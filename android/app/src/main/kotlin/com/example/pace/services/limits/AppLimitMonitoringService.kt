package com.example.pace.services.limits

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import com.example.pace.services.overlay.OverlayLauncher

/**
 * AppLimitMonitoringService - ONLY monitors app limits (always-on)
 *
 * RESPONSIBILITIES:
 * - Runs as foreground service when app limits are active
 * - Checks current app usage against limits
 * - Shows overlay when limit is exceeded
 * - Independent of focus sessions
 *
 * DOES NOT HANDLE:
 * - Focus session blocking (that's FocusMonitoringService)
 * - Session management (that's FocusSessionManager)
 */
class AppLimitMonitoringService : Service() {

    companion object {
        private const val TAG = "AppLimitMonitoring"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "app_limit_monitoring"
        private const val CHECK_INTERVAL = 2000L // 2 seconds

        // Actions
        const val ACTION_START = "START_LIMIT_MONITORING"
        const val ACTION_STOP = "STOP_LIMIT_MONITORING"
        const val ACTION_UPDATE_LIMITS = "UPDATE_LIMITS"

        @RequiresApi(Build.VERSION_CODES.O)
        fun start(context: Context) {
            val intent = Intent(context, AppLimitMonitoringService::class.java).apply {
                action = ACTION_START
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AppLimitMonitoringService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun updateLimits(context: Context) {
            val intent = Intent(context, AppLimitMonitoringService::class.java).apply {
                action = ACTION_UPDATE_LIMITS
            }
            context.startService(intent)
        }
    }

    // Core components
    private lateinit var appLimitManager: AppLimitManager
    private lateinit var usageStatsManager: UsageStatsManager
    private lateinit var overlayLauncher: OverlayLauncher

    // Monitoring
    private val handler = Handler(Looper.getMainLooper())
    private var monitoringRunnable: Runnable? = null
    private var isMonitoring = false

    // App tracking
    private var lastCheckedApp = ""
    private var lastCheckTime = 0L
    private val limitedAppsCache = mutableMapOf<String, Int>() // packageName -> dailyLimitMinutes
    private val blockedAppsToday = mutableSetOf<String>() // Apps that exceeded limit today

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "📊 AppLimitMonitoringService created")

        appLimitManager = AppLimitManager(this)
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        overlayLauncher = OverlayLauncher.getInstance(this)

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startMonitoring()
            ACTION_STOP -> {
                stopMonitoring()
                stopSelf()
            }
            ACTION_UPDATE_LIMITS -> {
                updateLimitsCache()
                if (limitedAppsCache.isEmpty()) {
                    stopMonitoring()
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ==========================================
    // MONITORING
    // ==========================================

    private fun startMonitoring() {
        if (isMonitoring) {
            Log.d(TAG, "⚠️ Already monitoring")
            return
        }

        // Update limits cache
        updateLimitsCache()

        if (limitedAppsCache.isEmpty()) {
            Log.w(TAG, "⚠️ No app limits configured, stopping service")
            stopSelf()
            return
        }

        Log.d(TAG, "▶️ Starting app limit monitoring for ${limitedAppsCache.size} apps")

        // Start foreground
        startForeground(NOTIFICATION_ID, createNotification())

        // Start monitoring loop
        isMonitoring = true
        startMonitoringLoop()
    }

    private fun stopMonitoring() {
        Log.d(TAG, "⏹️ Stopping app limit monitoring")

        isMonitoring = false
        monitoringRunnable?.let {
            handler.removeCallbacks(it)
            monitoringRunnable = null
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun startMonitoringLoop() {
        monitoringRunnable = object : Runnable {
            override fun run() {
                if (isMonitoring) {
                    checkCurrentApp()
                    handler.postDelayed(this, CHECK_INTERVAL)
                }
            }
        }
        handler.post(monitoringRunnable!!)
    }

    @RequiresPermission(Manifest.permission.PACKAGE_USAGE_STATS)
    private fun checkCurrentApp() {
        try {
            val currentApp = getCurrentForegroundApp()

            if (currentApp.isNotEmpty() && currentApp != lastCheckedApp) {
                lastCheckedApp = currentApp
                lastCheckTime = System.currentTimeMillis()

                // Check if app has limit and if exceeded
                if (limitedAppsCache.containsKey(currentApp)) {
                    checkAppLimit(currentApp)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking current app", e)
        }
    }

    private fun getCurrentForegroundApp(): String {
        try {
            val endTime = System.currentTimeMillis()
            val beginTime = endTime - 3000 // Last 3 seconds

            val usageEvents = usageStatsManager.queryEvents(beginTime, endTime)
            var lastApp = ""

            while (usageEvents.hasNextEvent()) {
                val event = UsageEvents.Event()
                usageEvents.getNextEvent(event)

                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    lastApp = event.packageName
                }
            }

            return lastApp

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting foreground app", e)
            return ""
        }
    }

    private fun checkAppLimit(packageName: String) {
        try {
            // Don't block our own app
            if (packageName == applicationContext.packageName) {
                return
            }

            // Check if already blocked today
            if (blockedAppsToday.contains(packageName)) {
                handleLimitExceeded(packageName)
                return
            }

            // Get today's usage
            val usageMinutes = getTodayUsageMinutes(packageName)
            val limitMinutes = limitedAppsCache[packageName] ?: return

            if (usageMinutes >= limitMinutes) {
                Log.d(TAG, "🚫 App limit exceeded: $packageName ($usageMinutes/$limitMinutes min)")
                blockedAppsToday.add(packageName)
                handleLimitExceeded(packageName)
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking app limit", e)
        }
    }

    private fun getTodayUsageMinutes(packageName: String): Int {
        try {
            val calendar = java.util.Calendar.getInstance()
            calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
            calendar.set(java.util.Calendar.MINUTE, 0)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)
            val startOfDay = calendar.timeInMillis
            val endOfDay = System.currentTimeMillis()

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startOfDay,
                endOfDay
            )

            val appStats = stats.find { it.packageName == packageName }
            val totalTimeMs = appStats?.totalTimeInForeground ?: 0

            return (totalTimeMs / 60000).toInt()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting usage stats", e)
            return 0
        }
    }

    private fun handleLimitExceeded(packageName: String) {
        Log.d(TAG, "⏰ Handling limit exceeded for: $packageName")

        val appName = getAppName(packageName)
        val limitMinutes = limitedAppsCache[packageName] ?: 0

        // Show overlay
        overlayLauncher.showAppLimitOverlay(
            packageName = packageName,
            appName = appName,
            usedMinutes = getTodayUsageMinutes(packageName),
            limitMinutes = limitMinutes
        )
    }

    private fun updateLimitsCache() {
        limitedAppsCache.clear()
        // Get limits from AppLimitManager
        // Note: This would need to be implemented in AppLimitManager
        // For now, we'll load from SharedPreferences directly

        val prefs = getSharedPreferences("app_limits", Context.MODE_PRIVATE)
        val limitsJson = prefs.getString("app_limits_map", null)

        if (limitsJson != null) {
            try {
                val limitsMap = org.json.JSONObject(limitsJson)
                limitsMap.keys().forEach { packageName ->
                    val limitData = limitsMap.getJSONObject(packageName)
                    val dailyLimit = limitData.optInt("dailyLimit", 0)
                    if (dailyLimit > 0) {
                        limitedAppsCache[packageName] = dailyLimit
                    }
                }
                Log.d(TAG, "📋 Updated limits cache: ${limitedAppsCache.size} apps")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error parsing limits", e)
            }
        }

        // Reset blocked apps at start of new day
        checkAndResetDailyBlocks()
    }

    private fun checkAndResetDailyBlocks() {
        val prefs = getSharedPreferences("app_limit_monitoring", Context.MODE_PRIVATE)
        val lastResetDay = prefs.getLong("last_reset_day", 0)
        val currentDay = getCurrentDayTimestamp()

        if (lastResetDay != currentDay) {
            blockedAppsToday.clear()
            prefs.edit().putLong("last_reset_day", currentDay).apply()
            Log.d(TAG, "🔄 Reset daily blocks for new day")
        }
    }

    private fun getCurrentDayTimestamp(): Long {
        val calendar = java.util.Calendar.getInstance()
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    private fun getAppName(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    // ==========================================
    // NOTIFICATION
    // ==========================================

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "App Limit Monitoring",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Monitors app usage against daily limits"
            setShowBadge(false)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun createNotification(): android.app.Notification {
        val text = "Monitoring ${limitedAppsCache.size} apps"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App Limits Active")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopMonitoring()
        Log.d(TAG, "🔚 AppLimitMonitoringService destroyed")
    }
}