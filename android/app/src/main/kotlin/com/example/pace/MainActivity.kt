package com.example.pace

import android.app.ComponentCaller
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import com.example.pace.permissions.PermissionManager
import com.example.pace.services.NotificationHelper
import com.example.pace.services.focus.FocusMonitoringService
import com.example.pace.services.focus.FocusSessionManager
import com.example.pace.services.limits.AppLimitManager
import com.example.pace.services.LockInAccessibilityService
import com.example.pace.services.shared.BlockingConfig
import com.example.pace.managers.ShortFormBlockManager
import com.example.pace.managers.WebsiteBlockManager
import com.example.pace.utils.AppUtils
import com.example.pace.utils.UsageStatsHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

class MainActivity: FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val METHOD_CHANNEL = "com.lockin.focus/native"
        private const val EVENT_CHANNEL = "com.lockin.focus/events"
    }

    // CORE MANAGERS
    private lateinit var permissionManager: PermissionManager
    private lateinit var sessionManager: FocusSessionManager
    private lateinit var appLimitManager: AppLimitManager
    private lateinit var blockingConfig: BlockingConfig
    private lateinit var shortFormBlockManager: ShortFormBlockManager
    private lateinit var websiteBlockManager: WebsiteBlockManager


    // Method channels
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var appLimitsChannel: MethodChannel
    private lateinit var limitEventsChannel: MethodChannel

    // Event sinks
    private var eventSink: EventChannel.EventSink? = null
    private val eventQueue = ConcurrentHashMap<String, Any>()

    // SCOPE
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity created")

        // Initialize notification channels
        NotificationHelper.createAllNotificationChannels(this)

        // Store app start time
        val prefs = getSharedPreferences("app_lifecycle", MODE_PRIVATE)
        if (!prefs.contains("app_start_time")) {
            prefs.edit().putLong("app_start_time", System.currentTimeMillis()).apply()
        }

        syncSessionIfActive()

    }



    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Update intent for the activity
        syncSessionIfActive()
    }

    private fun syncSessionIfActive() {
        scope.launch {
            // Ensure FocusSessionManager is initialized and check session
            if (sessionManager.isSessionActive()) {
                // Tell Flutter to force a re-route
                methodChannel.invokeMethod("force_sync_session", null)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            initializeManagers()
            setupMethodChannels(flutterEngine)
            setupEventChannels(flutterEngine)
        } catch (e: Exception) {
            Log.e(TAG, "ERROR CONFIGURING FLUTTER ENGINE", e)
        }
    }

    private fun initializeManagers() {
        try {
            permissionManager = PermissionManager(this)
            sessionManager = FocusSessionManager.getInstance(this)
            appLimitManager = AppLimitManager(this)
            blockingConfig = BlockingConfig.getInstance(this)
            shortFormBlockManager = ShortFormBlockManager.getInstance(this)
            websiteBlockManager = WebsiteBlockManager.getInstance(this)

            Log.d(TAG, "All managers initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing managers", e)
            throw e
        }
    }

    private fun setupMethodChannels(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            handleMainMethodCall(call.method, call.arguments, result)
        }
        
        // App Limits channel for managing limits
        appLimitsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lockin/app_limits")
        appLimitsChannel.setMethodCallHandler { call, result ->
            handleAppLimitsMethodCall(call.method, call.arguments, result)
        }
        
        // Limit Events channel for notifying Flutter when limits are reached
        limitEventsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lockin/app_limits_events")
        
        // Pass the channel to the AccessibilityService (with retry if service not ready)
        if (LockInAccessibilityService.getInstance() != null) {
            LockInAccessibilityService.getInstance()?.setLimitEventsChannel(limitEventsChannel)
            Log.d(TAG, "✅ Limit events channel set to AccessibilityService")
        } else {
            Log.w(TAG, "⚠️ AccessibilityService not ready, will retry setting channel")
            // Retry after a delay
            Handler(Looper.getMainLooper()).postDelayed({
                LockInAccessibilityService.getInstance()?.setLimitEventsChannel(limitEventsChannel)
                Log.d(TAG, "✅ Limit events channel set to AccessibilityService (retry)")
            }, 2000)
        }
        
        Log.d(TAG, "Method channels configured")
    }

    private fun setupEventChannels(flutterEngine: FlutterEngine) {
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                sessionManager.setEventSink(events)

                // Send queued events
                eventQueue.forEach { (event, data) ->
                    sendEventToFlutter(event, data)
                }
                eventQueue.clear()

                Log.d(TAG, "Event channel connected")
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                sessionManager.setEventSink(null)
                Log.d(TAG, "Event channel disconnected")
            }
        })
    }
    
    /**
     * Handle app limits method calls from Flutter
     */
    private fun handleAppLimitsMethodCall(
        method: String,
        arguments: Any?,
        result: MethodChannel.Result
    ) {
        scope.launch {
            try {
                when (method) {
                    "updateLimits" -> {
                        val limitsData = arguments as? Map<String, Any>
                        val limits = limitsData?.get("limits") as? List<Map<String, Any>>
                        
                        Log.d(TAG, "📥 Received updateLimits call from Flutter")
                        
                        if (limits != null) {
                            val limitsMap = mutableMapOf<String, Int>()
                            limits.forEach { limitItem ->
                                val pkg = limitItem["package"] as? String
                                val minutes = limitItem["limitMinutes"] as? Int
                                if (pkg != null && minutes != null) {
                                    limitsMap[pkg] = minutes
                                    Log.d(TAG, "  ➡️ Limit for $pkg: $minutes minutes")
                                }
                            }
                            
                            // Update native limits holder
                            Log.d(TAG, "Updating LockInNativeLimitsHolder with ${limitsMap.size} limits")
                            com.example.pace.services.limits.LockInNativeLimitsHolder.updateLimits(limitsMap)
                            Log.i(TAG, "✅ Successfully updated ${limitsMap.size} app limits from Flutter")
                            
                            withContext(Dispatchers.Main) {
                                result.success(true)
                            }
                        } else {
                            Log.e(TAG, "❌ Invalid limits data received from Flutter")
                            withContext(Dispatchers.Main) {
                                result.error("INVALID_ARGUMENT", "Limits list required", null)
                            }
                        }
                    }
                    
                    "getTodayUsage" -> {
                        val packageName = arguments as? String
                        if (packageName != null) {
                            val accessibilityService = LockInAccessibilityService.getInstance()
                            val usageMinutes = if (accessibilityService != null) {
                                val tracker = accessibilityService.getAppLimitTracker()
                                (tracker.getTodayUsageMs(packageName) / 60000).toInt()
                            } else {
                                0
                            }
                            
                            withContext(Dispatchers.Main) {
                                result.success(usageMinutes)
                            }
                        } else {
                            withContext(Dispatchers.Main) {
                                result.error("INVALID_ARGUMENT", "Package name required", null)
                            }
                        }
                    }
                    
                    "getAllUsageStats" -> {
                        val accessibilityService = LockInAccessibilityService.getInstance()
                        val stats = if (accessibilityService != null) {
                            accessibilityService.getAppLimitTracker().getAllUsageStats()
                        } else {
                            emptyMap<String, Map<String, Any>>()
                        }
                        
                        withContext(Dispatchers.Main) {
                            result.success(stats)
                        }
                    }
                    
                    "forceCheckLimits" -> {
                        val accessibilityService = LockInAccessibilityService.getInstance()
                        if (accessibilityService != null) {
                            val exceededPackages = accessibilityService.getAppLimitTracker().forceCheckAllLimits()
                            withContext(Dispatchers.Main) {
                                result.success(exceededPackages)
                            }
                        } else {
                            withContext(Dispatchers.Main) {
                                result.success(emptyList<String>())
                            }
                        }
                    }
                    
                    else -> {
                        withContext(Dispatchers.Main) {
                            result.notImplemented()
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling app limits method: $method", e)
                withContext(Dispatchers.Main) {
                    result.error("ERROR", e.message ?: "Unknown error", null)
                }
            }
        }
    }

    private fun handleMainMethodCall(
        method: String,
        arguments: Any?,
        result: MethodChannel.Result
    ) {
        scope.launch {
            try {
                Log.v(TAG, "Method call: $method")

                when (method) {
                    // ====================
                    // FOCUS SESSION METHODS
                    // ====================
                    "startFocusSession" -> {
                        val sessionData = arguments as? Map<String, Any>
                        if (sessionData != null) {
                            scope.launch {
                                try {
                                    Log.d(TAG, "Starting focus session with data: $sessionData")
                                    val success = sessionManager.startSession(sessionData)

                                    // Start monitoring service if session started successfully
                                    if (success) {
                                        FocusMonitoringService.start(this@MainActivity)
                                    }

                                    withContext(Dispatchers.Main) {
                                        result.success(success)
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Error starting focus session", e)
                                    withContext(Dispatchers.Main) {
                                        result.error("START_SESSION_ERROR", e.message, null)
                                    }
                                }
                            }
                        } else {
                            result.error("INVALID_ARGUMENT", "Session data is required", null)
                        }
                    }

                    "pauseFocusSession" -> {
                        scope.launch {
                            try {
                                val success = sessionManager.pauseSession()
                                withContext(Dispatchers.Main) {
                                    result.success(success)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error pausing session", e)
                                withContext(Dispatchers.Main) {
                                    result.error("PAUSE_SESSION_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    "resumeFocusSession" -> {
                        scope.launch {
                            try {
                                val success = sessionManager.resumeSession()
                                withContext(Dispatchers.Main) {
                                    result.success(success)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error resuming session", e)
                                withContext(Dispatchers.Main) {
                                    result.error("RESUME_SESSION_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    "endFocusSession" -> {
                        scope.launch {
                            try {
                                val success = sessionManager.endSession()

                                // Stop monitoring service when session ends
                                if (success) {
                                    FocusMonitoringService.stop(this@MainActivity)
                                }

                                withContext(Dispatchers.Main) {
                                    result.success(success)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error ending session", e)
                                withContext(Dispatchers.Main) {
                                    result.error("END_SESSION_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    "getCurrentSessionStatus" -> {
                        val status = sessionManager.getCurrentSessionStatus()
                        result.success(status)
                    }

                    // =======================
                    // PERMISSIONS
                    // =======================
                    "hasUsageStatsPermission" -> {
                        result.success(permissionManager.hasUsageStatsPermission())
                    }
                    "requestUsageStatsPermission" -> {
                        permissionManager.requestUsageStatsPermission()
                        result.success(null)
                    }
                    "hasAccessibilityPermission" -> {
                        result.success(permissionManager.hasAccessibilityPermission())
                    }
                    "requestAccessibilityPermission" -> {
                        permissionManager.requestAccessibilityPermission()
                        result.success(null)
                    }
                    "hasBackgroundPermission" -> {
                        result.success(permissionManager.hasBackgroundPermission())
                    }
                    "requestBackgroundPermission" -> {
                        permissionManager.requestBackgroundPermission()
                        result.success(null)
                    }
                    "hasOverlayPermission" -> {
                        result.success(permissionManager.hasOverlayPermission())
                    }
                    "requestOverlayPermission" -> {
                        permissionManager.requestOverlayPermission()
                        result.success(null)
                    }
                    "hasDisplayPopupPermission" -> {
                        result.success(permissionManager.hasDisplayPopupPermission())
                    }
                    "requestDisplayPopupPermission" -> {
                        permissionManager.requestDisplayPopupPermission()
                        result.success(null)
                    }
                    "hasNotificationPermission" -> {
                        result.success(permissionManager.hasNotificationPermission())
                    }
                    "requestNotificationPermission" -> {
                        permissionManager.requestNotificationPermission()
                        result.success(null)
                    }

                    // =============
                    // APP MANAGEMENT
                    // =============
                    "getInstalledApps" -> {
                        withContext(Dispatchers.IO) {
                            val apps = AppUtils.getInstalledApps(this@MainActivity)
                            withContext(Dispatchers.Main) {
                                result.success(apps)
                            }
                        }
                    }

                    "getAppUsageStats" -> {
                        val days = (arguments as? Map<String, Any>)?.get("days") as? Int ?: 7
                        withContext(Dispatchers.IO) {
                            val stats = UsageStatsHelper.getAppUsageStats(this@MainActivity, days)
                            withContext(Dispatchers.Main) {
                                result.success(stats)
                            }
                        }
                    }

                    "getTodayUsageStats" -> {
                        withContext(Dispatchers.IO) {
                            val stats = UsageStatsHelper.getTodayUsageStats(
                                this@MainActivity
                            )
                            withContext(Dispatchers.Main) {
                                result.success(stats)
                            }
                        }
                    }

                    "getTodayUsagePatterns" -> {
                        withContext(Dispatchers.IO) {
                            val patterns = UsageStatsHelper.getTodayUsagePatterns(
                                this@MainActivity
                            )
                            withContext(Dispatchers.Main) {
                                result.success(patterns)
                            }
                        }
                    }

                    "getAppSpecificUsage" -> {
                        val args = arguments as? Map<String, Any>
                        val packageName = args?.get("packageName") as? String
                        val days = args?.get("days") as? Int ?: 7

                        if (packageName != null) {
                            withContext(Dispatchers.IO) {
                                val usage = UsageStatsHelper.getAppSpecificUsage(
                                    this@MainActivity,
                                    packageName,
                                    days
                                )
                                withContext(Dispatchers.Main) {
                                    result.success(usage)
                                }
                            }
                        } else {
                            result.error("INVALID_ARGUMENT", "Package name is required", null)
                        }
                    }



                    "getAppIcon" -> {
                        val args = arguments as? Map<*, *>
                        val packageName = args?.get("packageName") as? String

                        if (packageName != null) {
                            scope.launch(Dispatchers.IO) {
                                val iconBytes = AppUtils.getAppIcon(
                                    this@MainActivity,
                                    packageName
                                )
                                withContext(Dispatchers.Main) {
                                    result.success(iconBytes)
                                }
                            }
                        } else {
                            result.error("INVALID_ARG", "Package name is null", null)
                        }
                    }

                    // ====================
                    // PERSISTENT (ALWAYS-ON) BLOCKING
                    // ====================

                    // App blocking
                    "setPersistentAppBlocking" -> {
                        val args = arguments as? Map<*, *>
                        val enabled = args?.get("enabled") as? Boolean ?: false
                        val apps = (args?.get("blockedApps") as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
                        blockingConfig.setPersistentAppBlocking(enabled)
                        blockingConfig.setPersistentBlockedApps(apps)
                        result.success(null)
                    }

                    "isPersistentAppBlockingEnabled" -> {
                        result.success(blockingConfig.isPersistentAppBlockingEnabled())
                    }

                    "getPersistentBlockedApps" -> {
                        result.success(blockingConfig.getPersistentBlockedApps())
                    }

                    // Website blocking
                    "setPersistentWebsiteBlocking" -> {
                        val args = arguments as? Map<*, *>
                        val enabled = args?.get("enabled") as? Boolean ?: false
                        val websites = (args?.get("blockedWebsites") as? List<*>)?.mapNotNull {
                            it as? Map<String, Any>
                        } ?: emptyList()
                        blockingConfig.setPersistentWebsiteBlocking(enabled)
                        blockingConfig.setPersistentBlockedWebsites(websites)
                        result.success(null)
                    }

                    "isPersistentWebsiteBlockingEnabled" -> {
                        result.success(blockingConfig.isPersistentWebsiteBlockingEnabled())
                    }

                    "getPersistentBlockedWebsites" -> {
                        result.success(blockingConfig.getPersistentBlockedWebsites())
                    }

                    // Individual website management (for WebsiteBlockManager)
                    "addBlockedWebsite" -> {
                        val args = arguments as? Map<*, *>
                        val url = args?.get("url") as? String
                        val name = args?.get("name") as? String
                        val isActive = args?.get("isActive") as? Boolean ?: true
                        
                        if (url != null && name != null) {
                            websiteBlockManager.addBlockedWebsite(url, name, isActive)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "url and name are required", null)
                        }
                    }

                    "removeBlockedWebsite" -> {
                        val args = arguments as? Map<*, *>
                        val url = args?.get("url") as? String
                        
                        if (url != null) {
                            websiteBlockManager.removeBlockedWebsite(url)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "url is required", null)
                        }
                    }

                    "getBlockedWebsites" -> {
                        val websites = websiteBlockManager.getBlockedWebsites().map { website ->
                            mapOf(
                                "url" to website.url,
                                "name" to website.name,
                                "isActive" to website.isActive
                            )
                        }
                        result.success(websites)
                    }

                    // Short-form content blocking
                    "setShortFormBlock" -> {
                        val args = arguments as? Map<*, *>
                        val platform = args?.get("platform") as? String
                        val feature = args?.get("feature") as? String
                        val isBlocked = args?.get("isBlocked") as? Boolean ?: false
                        
                        if (platform != null && feature != null) {
                            shortFormBlockManager.setShortFormBlock(platform, feature, isBlocked)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "platform and feature are required", null)
                        }
                    }

                    "getShortFormBlocks" -> {
                        val blocks = shortFormBlockManager.getAllBlocks().map { block ->
                            mapOf(
                                "platform" to block.platform,
                                "feature" to block.feature,
                                "isBlocked" to block.isBlocked
                            )
                        }
                        result.success(blocks)
                    }

                    "setPersistentShortFormBlocking" -> {
                        val args = arguments as? Map<*, *>
                        val enabled = args?.get("enabled") as? Boolean ?: false
                        val blocks = args?.get("shortFormBlocks") as? Map<String, Any> ?: emptyMap()
                        blockingConfig.setPersistentShortFormBlocking(enabled)
                        blockingConfig.setPersistentShortFormConfig(blocks)
                        result.success(null)
                    }

                    "isPersistentShortFormBlockingEnabled" -> {
                        result.success(blockingConfig.isPersistentShortFormBlockingEnabled())
                    }

                    "getPersistentShortFormBlocks" -> {
                        result.success(blockingConfig.getPersistentShortFormConfig())
                    }

                    // Notification blocking
                    "setPersistentNotificationBlocking" -> {
                        val args = arguments as? Map<*, *>
                        val enabled = args?.get("enabled") as? Boolean ?: false
                        val blocks = args?.get("notificationBlocks") as? Map<String, Any> ?: emptyMap()
                        blockingConfig.setPersistentNotificationBlocking(enabled)
                        blockingConfig.setPersistentNotificationConfig(blocks)
                        result.success(null)
                    }

                    "isPersistentNotificationBlockingEnabled" -> {
                        result.success(blockingConfig.isPersistentNotificationBlockingEnabled())
                    }

                    "getPersistentNotificationBlocks" -> {
                        result.success(blockingConfig.getPersistentNotificationConfig())
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling method call: $method", e)
                result.error("METHOD_ERROR", "Error: ${e.message}", mapOf(
                    "method" to method,
                    "error" to e.javaClass.simpleName,
                    "message" to (e.message ?: "Unknown error")
                ))
            }
        }
    }

    private fun sendEventToFlutter(event: String, data: Any) {
        try {
            val eventData = mapOf(
                "event" to event,
                "data" to data,
                "timestamp" to System.currentTimeMillis()
            )

            if (eventSink != null) {
                eventSink?.success(eventData)
            } else {
                eventQueue[event] = data
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending event to Flutter: $event", e)
        }
    }


    // ====================
    // ACTIVITY LIFECYCLE
    // ====================

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        caller: ComponentCaller
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        try {
            permissionManager.onActivityResult(requestCode, resultCode, data)

            // Send permission result to Flutter
            scope.launch {
                delay(500) // Small delay to ensure permission state is updated
                val permissions = permissionManager.checkAllPermissions()
                sendEventToFlutter("permissions_updated", permissions)
            }

        } catch (e:  Exception) {
            Log.e(TAG, "Error handling activity result", e)
        }
    }

    override fun onResume() {
        super.onResume()

        // Check for permission changes when app resumes
        scope.launch {
            try {

                if (sessionManager.isSessionActive()) {
                    // Notify Flutter to force a state refresh
                    methodChannel.invokeMethod("force_sync_session", null)
                }


                val permissions = permissionManager.checkAllPermissions()
                sendEventToFlutter("app_resumed", mapOf(
                    "permissions" to permissions,
                    "timestamp" to System.currentTimeMillis()
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Error handling onResume", e)
            }
        }
    }

    override fun onPause() {
        super.onPause()

        sendEventToFlutter("app_paused", mapOf(
            "timestamp" to System.currentTimeMillis()
        ))
    }

    override fun onDestroy() {
        try {
            // Cleanup
            scope.cancel()

                        eventSink = null
            eventQueue.clear()

            // Cleanup managers
            sessionManager.cleanup()
            permissionManager.cleanup()
            appLimitManager.cleanup()

            Log.d(TAG, "MainActivity destroyed and cleaned up")


        } catch (e:  Exception) {
            Log.e(TAG, "Error during cleanup", e)
        }

        super.onDestroy()
    }
}