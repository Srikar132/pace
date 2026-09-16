package com.example.pace.services

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import com.example.pace.models.AppLimitStatus
import com.example.pace.models.LimitStatusType
import com.example.pace.services.limits.AppLimitManager
import com.lockin.focus.FocusModeManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.Locale

/**
 * AppMonitoringService - Foreground service that continuously monitors apps Provides bulletproof
 * app blocking that survives app closure and system kills
 */
class AppMonitoringService : Service() {

    companion object {
        private const val TAG = "AppMonitoringService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "focus_monitoring"
        private const val CHECK_INTERVAL = 1500L // 1.5 seconds

        // Action constants
        const val ACTION_START_MONITORING = "START_MONITORING"
        const val ACTION_STOP_MONITORING = "STOP_MONITORING"
        const val ACTION_UPDATE_BLOCKED_APPS = "UPDATE_BLOCKED_APPS"
    }

    // Core components
    private lateinit var focusManager: FocusModeManager
    private lateinit var appLimitManager: AppLimitManager
    private lateinit var usageStatsManager: UsageStatsManager

    // Monitoring state
    private val handler = Handler(Looper.getMainLooper())
    private var monitoringRunnable: Runnable? = null
    private var isMonitoring = false
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // App tracking
    private var lastCheckedApp = ""
    private var lastCheckTime = 0L
    private var sessionStartTime = 0L

    // Blocked apps cache
    private val blockedApps = mutableSetOf<String>()
    private val temporaryBlocks = mutableSetOf<String>() // Apps blocked due to limits

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AppMonitoringService created")

        // Initialize components
        focusManager = FocusModeManager.getInstance(this)
        appLimitManager = AppLimitManager(this)
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // Create notification channel
        createNotificationChannel()
    }

    @RequiresPermission(Manifest.permission.VIBRATE)
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")

        when (intent?.action) {
            ACTION_START_MONITORING -> {
                val sessionData = intent.getStringExtra("session_data")
                startMonitoring(sessionData)
            }
            ACTION_STOP_MONITORING -> {
                stopMonitoring()
                stopSelf()
            }
            ACTION_UPDATE_BLOCKED_APPS -> {
                val blockedAppsList = intent.getStringArrayListExtra("blocked_apps")
                updateBlockedApps(blockedAppsList ?: emptyList())
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action}")
            }
        }

        // Return START_STICKY for auto-restart
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "AppMonitoringService destroyed")
        stopMonitoring()
        scope.cancel()
        super.onDestroy()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "Task removed - restarting service if session active")

        // If session is active or any persistent blocking is enabled, restart the service
        try {
            if (focusManager.isSessionActive() || focusManager.isBlockingActive()) {
                val restartIntent =
                    Intent(this, AppMonitoringService::class.java).apply {
                        action = ACTION_START_MONITORING
                    }
                startForegroundService(restartIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error while handling task removed restart logic", e)
        }
    }

    // ====================
    // NOTIFICATION SETUP
    // ====================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    "Focus Mode Monitoring",
                    NotificationManager.IMPORTANCE_LOW
                )
                    .apply {
                        description = "Monitors and blocks apps during focus sessions"
                        setShowBadge(false)
                        setSound(null, null)
                        enableLights(false)
                        enableVibration(false)
                    }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundService() {
        val session = focusManager.getCurrentSession()
        val elapsedMinutes = ((System.currentTimeMillis() - sessionStartTime) / 60000).toInt()

        // Capitalize session type properly
        val sessionTypeName =
            session?.sessionType?.replaceFirstChar {
                if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
            }
                ?: "Focus"

        val notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Focus Mode Active")
                .setContentText(
                    "$sessionTypeName • ${elapsedMinutes}min • ${blockedApps.size} apps blocked"
                )
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setSilent(true)
                .setShowWhen(false)
                .addAction(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    createActionPendingIntent("PAUSE_SESSION")
                )
                .addAction(
                    android.R.drawable.ic_delete,
                    "End",
                    createActionPendingIntent("END_SESSION")
                )
                .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createActionPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, FocusActionReceiver::class.java).apply { this.action = action }
        return PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // ====================
    // MONITORING CONTROL
    // ====================

    @RequiresPermission(Manifest.permission.VIBRATE)
    private fun startMonitoring(sessionDataJson: String?) {
        try {
            Log.d(TAG, "====== START MONITORING ======")
            Log.d(TAG, "📥 Session JSON received: $sessionDataJson")

            if (isMonitoring) {
                Log.w(TAG, "Already monitoring")
                return
            }

            // CRITICAL FIX 1: Clear any stale data
            blockedApps.clear()
            temporaryBlocks.clear()

            // CRITICAL FIX 2: Get session from FocusManager FIRST (most reliable source)
            val session = focusManager.getCurrentSession()
            if (session != null) {
                Log.d(TAG, "✅ Got session from FocusManager")
                Log.d(TAG, "📱 Session.blockedApps = ${session.blockedApps}")

                if (session.blockedApps.isNotEmpty()) {
                    blockedApps.addAll(session.blockedApps)
                    Log.d(TAG, "✅ Added ${session.blockedApps.size} apps from session")
                } else {
                    Log.w(TAG, "⚠️ Session has empty blockedApps!")
                }
            } else {
                Log.e(TAG, "⚠️ getCurrentSession() returned NULL!")
            }

            // BACKUP FIX 3: Also try parsing from JSON (secondary source)
            if (!sessionDataJson.isNullOrEmpty()) {
                try {
                    parseSessionData(sessionDataJson)
                    Log.d(TAG, "📱 After JSON parse: ${blockedApps.size} apps")
                } catch (e: Exception) {
                    Log.e(TAG, "Error parsing JSON, but we have session data", e)
                }
            }

            // FINAL FIX 4: Load persistent blocks if enabled
            try {
                if (focusManager.isPersistentAppBlockingEnabled()) {
                    val persistentApps = focusManager.getPersistentBlockedApps()
                    if (persistentApps.isNotEmpty()) {
                        blockedApps.addAll(persistentApps)
                        Log.d(TAG, "📱 Added ${persistentApps.size} persistent apps")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error loading persistent apps", e)
            }

            // VERIFICATION
            Log.d(TAG, "📋 FINAL RESULT:")
            Log.d(TAG, "  ├─ Total blocked apps: ${blockedApps.size}")
            Log.d(TAG, "  └─ Apps: ${blockedApps.joinToString()}")

            if (blockedApps.isEmpty()) {
                Log.e(TAG, "🚨 CRITICAL ERROR: No blocked apps loaded!")
                Log.e(TAG, "🚨 Session data: $sessionDataJson")
                Log.e(TAG, "🚨 Session object: $session")
            } else {
                Log.d(TAG, "✅ Successfully loaded blocked apps")
            }

            sessionStartTime = focusManager.getSessionStartTime()
            isMonitoring = true

            // Start foreground service
            startForegroundService()

            // Start monitoring loop
            startMonitoringLoop()

            Log.d(TAG, "✅ Monitoring started successfully")
            Log.d(TAG, "====== END START MONITORING ======")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting monitoring", e)
            e.printStackTrace()
            isMonitoring = false
        }
    }

    private fun stopMonitoring() {
        try {
            Log.d(TAG, "Stopping app monitoring")
            isMonitoring = false

            // Stop monitoring loop
            monitoringRunnable?.let { handler.removeCallbacks(it) }
            monitoringRunnable = null

            // Clear blocked apps
            blockedApps.clear()
            temporaryBlocks.clear()

            Log.d(TAG, "App monitoring stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping monitoring", e)
        }
    }

    @RequiresPermission(Manifest.permission.VIBRATE)
    private fun startMonitoringLoop() {
        monitoringRunnable =
            object : Runnable {
                override fun run() {
                    // Continue monitoring while either a focus session is active or any
                    // persistent blocking is enabled OR we have blocked apps to monitor
                    val sessionActive = focusManager.isSessionActive()
                    val blockingActive = focusManager.isBlockingActive()
                    val hasBlockedApps = blockedApps.isNotEmpty()

                    if (isMonitoring && (sessionActive || blockingActive || hasBlockedApps)) {
                        scope.launch {
                            try {
                                checkCurrentApp()
                                checkAppLimits()
                                updateNotification()
                            } catch (e: Exception) {
                                Log.e(TAG, "Error in monitoring loop", e)
                            }
                        }

                        // Schedule next check
                        handler.postDelayed(this, CHECK_INTERVAL)
                    } else {
                        Log.d(
                            TAG,
                            "🛑 Monitoring loop stopped - sessionActive: $sessionActive, blockingActive: $blockingActive, hasBlockedApps: $hasBlockedApps"
                        )
                    }
                }
            }
        handler.post(monitoringRunnable!!)
    }

    // ====================
    // APP MONITORING LOGIC
    // ====================

    @RequiresPermission(Manifest.permission.VIBRATE)
    private suspend fun checkCurrentApp() {
        withContext(Dispatchers.IO) {
            try {
                val currentApp = getCurrentForegroundApp()
                val currentTime = System.currentTimeMillis()

                if (currentApp != null && currentApp != lastCheckedApp) {
                    Log.v(TAG, "App changed: $lastCheckedApp -> $currentApp")
                    lastCheckedApp = currentApp
                    lastCheckTime = currentTime

                    // Check if app should be blocked
                    if (shouldBlockApp(currentApp)) {
                        blockApp(currentApp)
                    }

                    // Update session stats
                    updateSessionStats(currentApp)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking current app", e)
            }
        }
    }

    private fun getCurrentForegroundApp(): String? {
        return try {
            val currentTime = System.currentTimeMillis()
            val queryTime = 10000L // Last 10 seconds

            val usageStats =
                usageStatsManager.queryUsageStats(
                    UsageStatsManager.INTERVAL_DAILY,
                    currentTime - queryTime,
                    currentTime
                )

            // Find the most recently used app
            usageStats?.maxByOrNull { it.lastTimeUsed }?.packageName
        } catch (e: Exception) {
            Log.e(TAG, "Error getting foreground app", e)
            null
        }
    }


    @RequiresPermission(Manifest.permission.VIBRATE)
    private suspend fun blockApp(packageName: String) {
        withContext(Dispatchers.Main) {
            try {
                val appName = getAppName(packageName)
                val focusTimeMinutes = getFocusTimeMinutes()

                Log.d(TAG, "Blocking app: $appName ($packageName)")
                
                bringAppToForeground()

                
                // Show Flutter overlay
                FlutterOverlayManager.showBlockedAppOverlay(
                    context = this@AppMonitoringService,
                    packageName = packageName,
                    appName = appName,
                    focusTimeMinutes = focusTimeMinutes,
                    sessionType = focusManager.getCurrentSession()?.sessionType ?: "timer",
                    sessionId = focusManager.getCurrentSession()?.sessionId ?: ""
                )

                // Send user to home screen
                //sendToHomeScreen()

                // Report interruption
                focusManager.reportInterruption(
                    packageName = packageName,
                    appName = appName,
                    type = "app_opened",
                    wasBlocked = true
                )

                // Show block notification
                showBlockNotification(appName)

                // Vibrate device
                vibrateDevice()

                Log.d(TAG, "Successfully blocked app: $appName")
            } catch (e: Exception) {
                Log.e(TAG, "Error blocking app: $packageName", e)
            }
        }
    }

    // ====================
    // APP LIMIT CHECKING
    // ====================

    private suspend fun checkAppLimits() {
        withContext(Dispatchers.IO) {
            try {
                val limitStatuses = appLimitManager.checkAllAppLimits()

                limitStatuses.forEach { status ->
                    when (status.status) {
                        LimitStatusType.EXCEEDED -> {
                            if (status.actionOnExceed == "block") {
                                // Add to temporary blocks
                                temporaryBlocks.add(status.packageName)

                                // If this app is currently foreground, block it
                                if (lastCheckedApp == status.packageName) {
                                    blockAppForLimit(status)
                                }
                            }
                        }
                        LimitStatusType.WARNING_75, LimitStatusType.WARNING_90 -> {
                            // Warnings are handled by AppLimitManager
                        }
                        else -> {
                            // Remove from temporary blocks if limit is no longer exceeded
                            temporaryBlocks.remove(status.packageName)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking app limits", e)
            }
        }
    }

    private suspend fun blockAppForLimit(status: AppLimitStatus) {
        withContext(Dispatchers.Main) {
            try {
                Log.d(TAG, "Blocking app for limit: ${status.appName}")

                // Show app limit overlay
                FlutterOverlayManager.showAppLimitOverlay(
                    context = this@AppMonitoringService,
                    appName = status.appName,
                    packageName = status.packageName,
                    limitMinutes = status.limitMinutes,
                    usedMinutes = status.usedMinutes,
                    limitType = "daily",
                    timeUntilReset = status.timeUntilReset,
                    allowOverride = status.actionOnExceed == "warn"
                )

                // Send to home screen
                sendToHomeScreen()

                // Report interruption
                focusManager.reportInterruption(
                    packageName = status.packageName,
                    appName = status.appName,
                    type = "app_limit_exceeded",
                    wasBlocked = true
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error blocking app for limit: ${status.packageName}", e)
            }
        }
    }

    // ====================
    // UTILITY METHODS
    // ====================

    private fun parseSessionData(sessionDataJson: String) {
        try {
            val sessionData = JSONObject(sessionDataJson)

            // Try multiple possible keys for blocked apps
            val possibleKeys = listOf("blockedApps", "blocked_apps", "apps")
            var blockedAppsArray: org.json.JSONArray? = null

            for (key in possibleKeys) {
                if (sessionData.has(key)) {
                    blockedAppsArray = sessionData.optJSONArray(key)
                    if (blockedAppsArray != null) {
                        Log.d(TAG, "📱 Found apps under key: '$key'")
                        break
                    }
                }
            }

            if (blockedAppsArray == null) {
                Log.w(TAG, "⚠️ No blocked apps array found in JSON")
                Log.d(TAG, "Available keys: ${sessionData.keys().asSequence().toList()}")
                return
            }

            val sessionBlockedApps = mutableListOf<String>()
            for (i in 0 until blockedAppsArray.length()) {
                val packageName = blockedAppsArray.getString(i)
                sessionBlockedApps.add(packageName)
            }

            if (sessionBlockedApps.isNotEmpty()) {
                val sizeBefore = blockedApps.size
                blockedApps.addAll(sessionBlockedApps)
                Log.d(TAG, "📱 JSON parse added: ${blockedApps.size - sizeBefore} new apps")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing session data JSON", e)
        }
    }

    private fun shouldBlockApp(packageName: String): Boolean {
        return try {
            if (isSystemApp(packageName) || packageName == this.packageName) return false

            // CHANGE: If the service is running and has apps in the list,
            // it should consider blocking active by default.
            val isServiceActive = isMonitoring && blockedApps.isNotEmpty()

            val isInLocalList = blockedApps.contains(packageName)
            val isTemporaryBlocked = temporaryBlocks.contains(packageName)

            // Log for debugging
            if (isInLocalList || isTemporaryBlocked) {
                Log.d(TAG, "🔍 Checking: $packageName | ServiceActive: $isServiceActive | InList: $isInLocalList")
            }

            // Fix: Don't just rely on focusManager.isBlockingActive()
            // because the Manager state might lag behind the Service state
            if (isServiceActive && isInLocalList) {
                Log.i(TAG, "🚫 BLOCKING: $packageName")
                return true
            }

            if (isTemporaryBlocked) return true

            false
        } catch (e: Exception) {
            false
        }
    }
    // OPTIONAL: Add this method to manually refresh blocked apps if needed
    fun refreshBlockedApps() {
        try {
            Log.d(TAG, "🔄 Refreshing blocked apps")
            val session = focusManager.getCurrentSession()

            if (session != null && session.blockedApps.isNotEmpty()) {
                blockedApps.clear()
                blockedApps.addAll(session.blockedApps)

                if (focusManager.isPersistentAppBlockingEnabled()) {
                    blockedApps.addAll(focusManager.getPersistentBlockedApps())
                }

                Log.d(TAG, "✅ Refreshed: ${blockedApps.size} apps")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error refreshing blocked apps", e)
        }
    }

    private fun updateBlockedApps(newBlockedApps: List<String>) {
        try {
            blockedApps.clear()
            blockedApps.addAll(newBlockedApps)
            Log.d(TAG, "Updated blocked apps: ${blockedApps.size} apps")
        } catch (e: Exception) {
            Log.e(TAG, "Error updating blocked apps", e)
        }
    }

    private fun isSystemApp(packageName: String): Boolean {
        val systemApps =
            setOf(
                "com.android.systemui",
                "android",
                "com.android.phone",
                "com.android.settings",
                "com.google.android.dialer",
                "com.android.launcher",
                "com.android.launcher3"
            )

        return systemApps.contains(packageName) ||
                packageName.startsWith("com.android.") ||
                packageName.startsWith("com.google.android.gms")
    }

    private fun getAppName(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            Log.w(TAG, "Could not get app name for $packageName", e)
            packageName
        }
    }

    private fun getFocusTimeMinutes(): Int {
        return try {
            val elapsed = System.currentTimeMillis() - sessionStartTime
            (elapsed / 60000).toInt()
        } catch (e: Exception) {
            0
        }
    }

    private fun updateSessionStats(packageName: String) {
        // Update session statistics - could be sent to Firebase Analytics
        // This is a placeholder for future analytics implementation
    }

    private fun sendToHomeScreen() {
        try {
            val homeIntent =
                Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            startActivity(homeIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending to home screen", e)
        }
    }

    /**
     * Forcefully brings com.example.pace to the foreground
     */
    private fun bringAppToForeground() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(this.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED) // Helps when app was killed
            }
            if (intent != null) {
                startActivity(intent)
                Log.d(TAG, "Successfully brought LockIn to foreground")
            }
        } catch (e: Exception) {
            sendToHomeScreen()
        }
    }

    private fun showBlockNotification(appName: String) {
        try {
            val notificationManager = getSystemService(NotificationManager::class.java)
            val notification =
                NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("App Blocked")
                    .setContentText("$appName was blocked during focus session")
                    .setSmallIcon(android.R.drawable.ic_delete)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setAutoCancel(true)
                    .setSilent(false)
                    .build()

            notificationManager.notify(
                "block_${System.currentTimeMillis()}".hashCode(),
                notification
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing block notification", e)
        }
    }

    @RequiresPermission(Manifest.permission.VIBRATE)
    private fun vibrateDevice() {
        try {
            val vibrator =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager =
                        getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as
                                VibratorManager
                    vibratorManager.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrationEffect =
                    VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE)
                vibrator.vibrate(vibrationEffect)
            } else {
                @Suppress("DEPRECATION") vibrator.vibrate(200)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error vibrating device", e)
        }
    }

    private fun updateNotification() {
        try {
            if (isMonitoring) {
                startForegroundService() // This updates the notification
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating notification", e)
        }
    }
}