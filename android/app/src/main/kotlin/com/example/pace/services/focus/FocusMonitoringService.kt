package com.example.pace.services.focus

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
 * FocusMonitoringService - ONLY monitors apps during active focus sessions
 *
 * RESPONSIBILITIES:
 * - Runs as foreground service during focus sessions
 * - Checks current app every 1.5 seconds
 * - Shows overlay when blocked app is detected
 * - Records interruptions via FocusSessionManager
 *
 * DOES NOT HANDLE:
 * - Persistent blocking (that's AppLimitMonitoringService)
 * - Session management (that's FocusSessionManager)
 */
class FocusMonitoringService : Service() {

    companion object {
        private const val TAG = "FocusMonitoringService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "focus_monitoring"
        private const val CHECK_INTERVAL = 1500L // 1.5 seconds

        // Actions
        const val ACTION_START = "START_FOCUS_MONITORING"
        const val ACTION_STOP = "STOP_FOCUS_MONITORING"

        @RequiresApi(Build.VERSION_CODES.O)
        fun start(context: Context) {
            val intent = Intent(context, FocusMonitoringService::class.java).apply {
                action = ACTION_START
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, FocusMonitoringService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    // Core components
    private lateinit var sessionManager: FocusSessionManager
    private lateinit var usageStatsManager: UsageStatsManager
    private lateinit var overlayLauncher: OverlayLauncher

    // Monitoring
    private val handler = Handler(Looper.getMainLooper())
    private var monitoringRunnable: Runnable? = null
    private var isMonitoring = false

    // App tracking
    private var lastCheckedApp = ""
    private var lastCheckTime = 0L
    private val blockedAppsCache = mutableSetOf<String>()

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🔍 FocusMonitoringService created")

        sessionManager = FocusSessionManager.getInstance(this)
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

        // Check if session is active
        if (!sessionManager.isSessionActive()) {
            Log.w(TAG, "⚠️ No active session, cannot start monitoring")
            stopSelf()
            return
        }

        Log.d(TAG, "▶️ Starting focus monitoring")

        // Update blocked apps cache
        updateBlockedAppsCache()

        // Start foreground
        startForeground(NOTIFICATION_ID, createNotification())

        // Start monitoring loop
        isMonitoring = true
        startMonitoringLoop()
    }

    private fun stopMonitoring() {
        Log.d(TAG, "⏹️ Stopping focus monitoring")

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
            // Verify session is still active
            if (!sessionManager.isSessionActive() || sessionManager.isSessionPaused()) {
                return
            }

            val currentApp = getCurrentForegroundApp()

            if (currentApp.isNotEmpty() && currentApp != lastCheckedApp) {
                lastCheckedApp = currentApp
                lastCheckTime = System.currentTimeMillis()

                // Check if app is blocked
                if (isAppBlocked(currentApp)) {
                    handleBlockedApp(currentApp)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking current app", e)
        }
    }

    private fun getCurrentForegroundApp(): String {
        try {
            val endTime = System.currentTimeMillis()
            val beginTime = endTime - 2000 // Last 2 seconds

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

    private fun isAppBlocked(packageName: String): Boolean {
        // Don't block our own app
        if (packageName == applicationContext.packageName) {
            return false
        }

        return blockedAppsCache.contains(packageName)
    }

    private fun handleBlockedApp(packageName: String) {
        Log.d(TAG, "🚫 Blocked app detected: $packageName")

        // Record interruption
        val appName = getAppName(packageName)
        sessionManager.recordInterruption(
            packageName = packageName,
            appName = appName,
            type = "app_opened",
            wasBlocked = true
        )



        // Show overlay
        /*overlayLauncher.showFocusBlockOverlay(
            packageName = packageName,
            appName = appName,
            sessionData = sessionManager.getCurrentSessionStatus()
        )*/

        bringAppToForeground()

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
                Log.d(FocusMonitoringService.Companion.TAG, "Successfully brought LockIn to foreground")
            }
        } catch (e: Exception) {
            sendToHomeScreen()
        }
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
            Log.e(FocusMonitoringService.Companion.TAG, "Error sending to home screen", e)
        }
    }

    private fun updateBlockedAppsCache() {
        blockedAppsCache.clear()
        sessionManager.getCurrentSession()?.let { session ->
            blockedAppsCache.addAll(session.blockedApps)
            Log.d(TAG, "📋 Updated blocked apps cache: ${blockedAppsCache.size} apps")
        }
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
            "Focus Session Monitoring",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Active focus session monitoring"
            setShowBadge(false)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun createNotification(): android.app.Notification {
        val session = sessionManager.getCurrentSession()
        val title = "Focus Session Active"
        val text = if (session != null) {
            "Blocking ${session.blockedApps.size} apps"
        } else {
            "Monitoring in progress"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopMonitoring()
        Log.d(TAG, "🔚 FocusMonitoringService destroyed")
    }
}