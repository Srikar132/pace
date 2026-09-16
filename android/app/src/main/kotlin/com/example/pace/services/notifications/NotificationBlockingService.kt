package com.example.pace.services.notifications
import android.annotation.SuppressLint
import android.app. Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content. IntentFilter
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.example.pace.services.focus.FocusSessionManager
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java. text.SimpleDateFormat
import java.util.*

/**
 * NotificationBlockingService - System notification listener for filtering distracting notifications
 * Blocks notifications during focus sessions while allowing critical ones
 */
class NotificationBlockingService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationBlockingService"
        private const val PREFS_NAME = "notification_blocks"
        private const val ACTION_UPDATE_BLOCKS = "com.lockin.focus.UPDATE_NOTIFICATION_BLOCKS"

        /**
         * Static methods for external control
         */
        fun updateBlocks(context: Context, blocks: Map<String, Any>): Boolean {
            return try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putString("blocks_config", JSONObject(blocks).toString())
                    apply()
                }

                // Send broadcast to update service
                val intent = Intent(ACTION_UPDATE_BLOCKS).apply {
                    putExtra("blocks", JSONObject(blocks).toString())
                }
                context.sendBroadcast(intent)

                Log.d(TAG, "Updated notification blocks configuration")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error updating notification blocks", e)
                false
            }
        }

        fun isServiceEnabled(context: Context): Boolean {
            val enabledListeners = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            )
            return enabledListeners?. contains(context.packageName) == true
        }

        fun openNotificationListenerSettings(context:  Context) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }

    // Core components
    private lateinit var sessionManager: FocusSessionManager
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Blocking configuration
    private var notificationBlocks = NotificationBlocks()

    // Statistics
    private var blockedNotificationsToday = 0
    private val blockedAppsCount = mutableMapOf<String, Int>()

    // Configuration receiver
    private val configReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_UPDATE_BLOCKS) {
                val blocksJson = intent.getStringExtra("blocks")
                if (blocksJson != null) {
                    updateBlocksFromJson(blocksJson)
                }
            }
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "NotificationBlockingService connected")

        try {
            // Initialize components
            sessionManager = FocusSessionManager.getInstance(this)

            // Load configuration
            loadBlockConfiguration()

            // Register configuration receiver
            registerReceiver(configReceiver, IntentFilter(ACTION_UPDATE_BLOCKS))

            // Load today's statistics
            loadTodayStatistics()

            Log.d(TAG, "Service initialized successfully")

        } catch (e: Exception) {
            Log.e(TAG, "Error initializing service", e)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "NotificationBlockingService destroyed")
        try {
            unregisterReceiver(configReceiver)
            scope.cancel()
            saveTodayStatistics()
        } catch (e:  Exception) {
            Log.e(TAG, "Error during cleanup", e)
        }
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Only block if session is active OR if persistent blocking is enabled
        if (!sessionManager.isSessionActive()) return

        try {
            val packageName = sbn.packageName

            // Don't process our own notifications
            if (packageName == this.packageName) return

            Log.v(TAG, "Notification posted: $packageName")

            // Check if we should block this notification
            if (shouldBlockNotification(sbn)) {
                blockNotification(sbn)
            }

        } catch (e:  Exception) {
            Log.e(TAG, "Error handling posted notification", e)
        }
    }

    override fun onNotificationRemoved(sbn:  StatusBarNotification) {
        // Handle notification removal if needed for statistics
        try {
            Log.v(TAG, "Notification removed: ${sbn.packageName}")
        } catch (e:  Exception) {
            Log.e(TAG, "Error handling removed notification", e)
        }
    }

    // ====================
    // BLOCKING LOGIC
    // ====================

    private fun shouldBlockNotification(sbn: StatusBarNotification): Boolean {
        try {
            val packageName = sbn.packageName
            val notification = sbn.notification

            // Check quiet hours first
            if (notificationBlocks.quietHours.enabled && isInQuietHours()) {
                return !isAllowedDuringQuietHours(sbn)
            }

            // If not blocking all during focus, only check specific rules
            if (!notificationBlocks.blockAllDuringFocus) {
                return false
            }

            // Allow explicitly allowed apps
            if (notificationBlocks. allowedApps.contains(packageName)) {
                Log.v(TAG, "Allowing notification from allowed app: $packageName")
                return false
            }

            // Allow calls if configured
            if (notificationBlocks.allowCalls && isCallNotification(notification)) {
                Log.v(TAG, "Allowing call notification: $packageName")
                return false
            }

            // Allow alarms if configured
            if (notificationBlocks.allowAlarms && isAlarmNotification(notification)) {
                Log.v(TAG, "Allowing alarm notification: $packageName")
                return false
            }

            // Allow system critical notifications
            if (isSystemCriticalNotification(sbn)) {
                Log.v(TAG, "Allowing system critical notification: $packageName")
                return false
            }

            // Allow emergency notifications
            if (isEmergencyNotification(sbn)) {
                Log.v(TAG, "Allowing emergency notification: $packageName")
                return false
            }

            // Block everything else during focus
            Log.v(TAG, "Blocking notification from: $packageName")
            return true

        } catch (e: Exception) {
            Log. e(TAG, "Error checking if notification should be blocked", e)
            return false // Default to allow on error
        }
    }

    private fun blockNotification(sbn: StatusBarNotification) {
        try {
            val packageName = sbn.packageName
            val appName = getAppName(packageName)

            // Cancel the notification
            cancelNotification(sbn.key)

            // Update statistics
            blockedNotificationsToday++
            blockedAppsCount[packageName] = (blockedAppsCount[packageName] ?: 0) + 1

            // Log the blocked notification
            logBlockedNotification(sbn)

            // Report interruption to session manager if session is active
            if (sessionManager.isSessionActive()) {
                sessionManager.recordInterruption(
                    packageName = packageName,
                    appName = appName,
                    type = "notification_blocked",
                    wasBlocked = true
                )
            }

            Log. d(TAG, "Blocked notification from $appName (total today: $blockedNotificationsToday)")

        } catch (e: Exception) {
            Log.e(TAG, "Error blocking notification", e)
        }
    }

    // ====================
    // NOTIFICATION TYPE DETECTION
    // ====================

    private fun isCallNotification(notification: Notification): Boolean {
        return try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP -> {
                    notification.category == Notification.CATEGORY_CALL
                }
                else -> {
                    // Fallback for older versions
                    val extras = notification.extras
                    val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                    val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

                    val callKeywords = listOf("call", "calling", "incoming", "missed", "phone")
                    callKeywords.any { keyword ->
                        title.contains(keyword, ignoreCase = true) ||
                                text.contains(keyword, ignoreCase = true)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting call notification", e)
            false
        }
    }

    private fun isAlarmNotification(notification: Notification): Boolean {
        return try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP -> {
                    notification. category == Notification.CATEGORY_ALARM ||
                            notification.category == Notification.CATEGORY_REMINDER
                }
                else -> {
                    val extras = notification.extras
                    val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                    val text = extras?.getCharSequence(Notification. EXTRA_TEXT)?.toString() ?: ""

                    val alarmKeywords = listOf("alarm", "reminder", "timer", "clock")
                    alarmKeywords.any { keyword ->
                        title.contains(keyword, ignoreCase = true) ||
                                text. contains(keyword, ignoreCase = true)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting alarm notification", e)
            false
        }
    }

    private fun isSystemCriticalNotification(sbn: StatusBarNotification): Boolean {
        try {
            val packageName = sbn.packageName
            val notification = sbn.notification

            // System packages
            val systemPackages = setOf(
                "android",
                "com.android.systemui",
                "com.android.phone",
                "com.android.settings",
                "com.google.android.gms"
            )

            if (systemPackages. contains(packageName)) return true

            // Check notification flags and categories
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // High priority notifications
                if (notification.priority >= Notification.PRIORITY_HIGH) return true

                // Critical categories
                val criticalCategories = setOf(
                    Notification.CATEGORY_SYSTEM,
                    Notification.CATEGORY_ALARM,
                    Notification.CATEGORY_CALL,
                    Notification.CATEGORY_REMINDER,
                    Notification.CATEGORY_ERROR
                )

                if (criticalCategories.contains(notification.category)) return true
            }

            // Ongoing notifications (like navigation, music)
            if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return true

            // No clear intent (system notifications often don't have actions)
            if (notification.flags and Notification.FLAG_NO_CLEAR != 0) return true

            return false

        } catch (e: Exception) {
            Log.e(TAG, "Error detecting system critical notification", e)
            return true // Default to allow on error
        }
    }

    private fun isEmergencyNotification(sbn: StatusBarNotification): Boolean {
        try {
            val packageName = sbn.packageName
            val notification = sbn.notification

            // Emergency services packages
            val emergencyPackages = setOf(
                "com.android.phone",
                "com.android.dialer",
                "com.google.android.dialer"
            )

            if (emergencyPackages.contains(packageName)) return true

            // Check for emergency keywords
            val extras = notification.extras
            val title = extras?.getCharSequence(Notification. EXTRA_TITLE)?.toString() ?: ""
            val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            val emergencyKeywords = listOf(
                "emergency", "911", "sos", "urgent", "critical",
                "ambulance", "police", "fire", "medical"
            )

            return emergencyKeywords. any { keyword ->
                title.contains(keyword, ignoreCase = true) ||
                        text.contains(keyword, ignoreCase = true)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error detecting emergency notification", e)
            return true // Default to allow on error for safety
        }
    }

    // ====================
    // QUIET HOURS LOGIC
    // ====================

    private fun isInQuietHours(): Boolean {
        if (!notificationBlocks.quietHours.enabled) return false

        try {
            val now = Calendar.getInstance()
            val currentHour = now.get(Calendar.HOUR_OF_DAY)
            val currentMinute = now.get(Calendar. MINUTE)
            val currentTime = currentHour * 60 + currentMinute

            val startParts = notificationBlocks.quietHours.startTime.split(":")
            val endParts = notificationBlocks.quietHours.endTime.split(":")

            val startTime = startParts[0]. toInt() * 60 + startParts[1].toInt()
            val endTime = endParts[0].toInt() * 60 + endParts[1].toInt()

            return if (startTime < endTime) {
                // Same day (e.g., 9:00 to 17:00)
                currentTime in startTime..endTime
            } else {
                // Crosses midnight (e.g., 22:00 to 08:00)
                currentTime >= startTime || currentTime <= endTime
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error checking quiet hours", e)
            return false
        }
    }

    private fun isAllowedDuringQuietHours(sbn: StatusBarNotification): Boolean {
        val notification = sbn.notification

        // Always allow calls, alarms, and emergencies during quiet hours
        return isCallNotification(notification) ||
                isAlarmNotification(notification) ||
                isSystemCriticalNotification(sbn) ||
                isEmergencyNotification(sbn)
    }

    // ====================
    // UTILITY METHODS
    // ====================

    private fun getAppName(packageName: String): String {
        return try {
            val packageManager = packageManager
            val appInfo = packageManager. getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private fun logBlockedNotification(sbn: StatusBarNotification) {
        scope.launch {
            try {
                val packageName = sbn.packageName
                val appName = getAppName(packageName)
                val title = sbn.notification.extras?.getCharSequence(Notification. EXTRA_TITLE)?.toString() ?: ""
                val text = sbn.notification.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

                val logData = mapOf(
                    "package_name" to packageName,
                    "app_name" to appName,
                    "title" to title,
                    "text" to text,
                    "timestamp" to System.currentTimeMillis(),
                    "session_id" to (sessionManager.getCurrentSession()?.sessionId ?: "")
                )

                // Save to local storage for analytics
                saveBlockedNotificationLog(logData)

            } catch (e: Exception) {
                Log.e(TAG, "Error logging blocked notification", e)
            }
        }
    }

    private fun saveBlockedNotificationLog(logData: Map<String, Any>) {
        try {
            val prefs = getSharedPreferences("notification_logs", Context. MODE_PRIVATE)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            val existingLogs = prefs. getString("logs_$today", "[]")
            val logsArray = JSONArray(existingLogs)

            logsArray. put(JSONObject(logData))

            prefs.edit().putString("logs_$today", logsArray.toString()).apply()

        } catch (e: Exception) {
            Log.e(TAG, "Error saving blocked notification log", e)
        }
    }

    // ====================
    // STATISTICS MANAGEMENT
    // ====================

    private fun loadTodayStatistics() {
        try {
            val prefs = getSharedPreferences("notification_stats", Context. MODE_PRIVATE)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

            blockedNotificationsToday = prefs. getInt("blocked_$today", 0)

            val appsJson = prefs.getString("blocked_apps_$today", "{}")
            if (!appsJson.isNullOrEmpty()) {
                val appsObject = JSONObject(appsJson)
                appsObject.keys().forEach { packageName ->
                    blockedAppsCount[packageName] = appsObject.getInt(packageName)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error loading today statistics", e)
        }
    }

    private fun saveTodayStatistics() {
        try {
            val prefs = getSharedPreferences("notification_stats", Context.MODE_PRIVATE)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

            prefs.edit().apply {
                putInt("blocked_$today", blockedNotificationsToday)

                val appsObject = JSONObject()
                blockedAppsCount.forEach { (packageName, count) ->
                    appsObject.put(packageName, count)
                }
                putString("blocked_apps_$today", appsObject.toString())

                apply()
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error saving today statistics", e)
        }
    }

    fun getTodayStatistics(): Map<String, Any> {
        return mapOf(
            "totalBlocked" to blockedNotificationsToday,
            "blockedByApp" to blockedAppsCount. toMap()
        )
    }

    // ====================
    // CONFIGURATION MANAGEMENT
    // ====================

    private fun loadBlockConfiguration() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val blocksJson = prefs. getString("blocks_config", "{}")
            if (!blocksJson.isNullOrEmpty()) {
                updateBlocksFromJson(blocksJson)
            }
        } catch (e:  Exception) {
            Log.e(TAG, "Error loading block configuration", e)
        }
    }

    private fun updateBlocksFromJson(json: String) {
        try {
            val jsonObject = JSONObject(json)

            val allowedApps = mutableListOf<String>()
            val allowedAppsArray = jsonObject.optJSONArray("allowedApps")
            if (allowedAppsArray != null) {
                for (i in 0 until allowedAppsArray.length()) {
                    allowedApps.add(allowedAppsArray.getString(i))
                }
            }

            val quietHoursObject = jsonObject.optJSONObject("quietHours")
            val quietHours = if (quietHoursObject != null) {
                QuietHours(
                    enabled = quietHoursObject.optBoolean("enabled", false),
                    startTime = quietHoursObject.optString("startTime", "22:00"),
                    endTime = quietHoursObject.optString("endTime", "08:00")
                )
            } else {
                QuietHours()
            }

            notificationBlocks = NotificationBlocks(
                blockAllDuringFocus = jsonObject.optBoolean("blockAllDuringFocus", false),
                allowedApps = allowedApps,
                allowCalls = jsonObject.optBoolean("allowCalls", true),
                allowAlarms = jsonObject. optBoolean("allowAlarms", true),
                quietHours = quietHours
            )

            Log.d(TAG, "Updated notification blocks configuration:  $notificationBlocks")

        } catch (e: Exception) {
            Log.e(TAG, "Error updating blocks from JSON", e)
        }
    }

    // ====================
    // DATA CLASSES
    // ====================

    data class NotificationBlocks(
        val blockAllDuringFocus: Boolean = false,
        val allowedApps: List<String> = emptyList(),
        val allowCalls: Boolean = true,
        val allowAlarms: Boolean = true,
        val quietHours: QuietHours = QuietHours()
    )

    data class QuietHours(
        val enabled: Boolean = false,
        val startTime: String = "22:00",
        val endTime: String = "08:00"
    )
}