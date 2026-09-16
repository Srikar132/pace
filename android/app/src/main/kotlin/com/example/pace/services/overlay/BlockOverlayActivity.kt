package com.example.pace.services.overlay;


import android.Manifest
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.view.WindowManager
import androidx.annotation.RequiresPermission
// Ensure this matches your actual package structure
import com.lockin.focus.FocusModeManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * BlockOverlayActivity - Flutter activity for displaying beautiful block screens
 * Routes to different overlay types based on block reason
 */
class BlockOverlayActivity : FlutterActivity() {

    companion object {
        private const val TAG = "BlockOverlayActivity"
        private const val METHOD_CHANNEL = "com.lockin.focus/overlay_actions"
        private const val EVENT_CHANNEL = "com.lockin.focus/overlay_events"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Overlay data
    private var overlayType: String = "blocked_app"
    private var overlayData: Map<String, Any> = emptyMap()
    private var sessionData: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        configureOverlayWindow()
        
        // CRITICAL: Parse intent data BEFORE super.onCreate()
        // because getInitialRoute() is called during Flutter engine initialization
        parseIntentData()
        
        super.onCreate(savedInstanceState)

        Log.d(TAG, "BlockOverlayActivity created with type: $overlayType")

        // Load session data
        loadCurrentSessionData()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup method channel for overlay actions
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        )
        methodChannel. setMethodCallHandler { call, result ->
            handleMethodCall(call.method, call.arguments, result)
        }

        // Setup event channel for real-time updates
        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        )
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                sendInitialData()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun getDartEntrypointFunctionName(): String {
        return "overlayMain"
    }

    override fun getInitialRoute(): String {
        return when (overlayType) {
            "blocked_app" -> "/blocked-app"
            "blocked_shorts" -> "/blocked-shorts"
            "blocked_website" -> "/blocked-website"
            "app_limit" -> "/app-limit"
            "notification_block" -> "/notification-block"
            else -> "/blocked-app"
        }
    }

    // ====================
    // INTENT DATA PARSING
    // ====================

    private fun parseIntentData() {
        try {
            overlayType = intent.getStringExtra("overlayType") ?: "blocked_app"

            val baseData = when (overlayType) {
                "blocked_app" -> parseBlockedAppData()
                "blocked_shorts" -> parseBlockedShortsData()
                "blocked_website" -> parseBlockedWebsiteData()
                "app_limit" -> parseAppLimitData()
                "notification_block" -> parseNotificationBlockData()
                else -> emptyMap()
            }

            overlayData = baseData.toMutableMap().apply {
                put("overlayType", overlayType)
            }

            Log.d(TAG, "Parsed overlay data: type=$overlayType, data=$overlayData")

        } catch (e:  Exception) {
            Log.e(TAG, "Error parsing intent data", e)
            overlayData = emptyMap()
        }
    }

    private fun parseBlockedAppData(): Map<String, Any> {
        return mapOf(
            "packageName" to (intent.getStringExtra("packageName") ?: ""),
            "appName" to (intent.getStringExtra("appName") ?: ""),
            "focusTimeMinutes" to intent.getIntExtra("focusTimeMinutes", 0),
            "sessionType" to (intent.getStringExtra("sessionType") ?: "timer"),
            "sessionId" to (intent.getStringExtra("sessionId") ?: ""),
            "blockReason" to "focusSession",
            "motivationalMessage" to getMotivationalMessage()
        )
    }

    private fun parseBlockedShortsData(): Map<String, Any> {
        return mapOf(
            "contentType" to (intent.getStringExtra("content_type") ?: "Short Content"),
            "packageName" to (intent.getStringExtra("package_name") ?: ""),
            "focusTimeMinutes" to intent.getIntExtra("focus_time_minutes", 0),
            "sessionType" to (intent.getStringExtra("session_type") ?: "timer"),
            "sessionId" to (intent.getStringExtra("session_id") ?: ""),
            "educationalMessage" to (intent.getStringExtra("educational_message") ?: getDefaultShortsMessage()),
            "platform" to getPlatformFromPackage(intent.getStringExtra("package_name") ?: "")
        )
    }

    private fun parseBlockedWebsiteData(): Map<String, Any> {
        return mapOf(
            "domain" to (intent.getStringExtra("domain") ?: ""),
            "fullUrl" to (intent.getStringExtra("full_url") ?: ""),
            "focusTimeMinutes" to intent.getIntExtra("focus_time_minutes", 0),
            "sessionType" to (intent.getStringExtra("session_type") ?: "timer"),
            "sessionId" to (intent.getStringExtra("session_id") ?: ""),
            "blockReason" to (intent.getStringExtra("block_reason") ?: "focus_session"),
            "suggestion" to (intent.getStringExtra("suggestion") ?: getWebsiteSuggestion())
        )
    }

    private fun parseAppLimitData(): Map<String, Any> {
        return mapOf(
            "appName" to (intent.getStringExtra("app_name") ?: ""),
            "packageName" to (intent.getStringExtra("package_name") ?: ""),
            "limitMinutes" to intent. getIntExtra("limit_minutes", 0),
            "usedMinutes" to intent.getIntExtra("used_minutes", 0),
            "limitType" to (intent. getStringExtra("limit_type") ?: "daily"),
            "timeUntilReset" to intent. getLongExtra("time_until_reset", 0L),
            "allowOverride" to intent.getBooleanExtra("allow_override", false),
            "usagePercentage" to intent.getIntExtra("usage_percentage", 100)
        )
    }

    private fun parseNotificationBlockData(): Map<String, Any> {
        return mapOf(
            "blockedAppName" to (intent. getStringExtra("blocked_app_name") ?: ""),
            "notificationCount" to intent.getIntExtra("notification_count", 1),
            "focusTimeMinutes" to intent.getIntExtra("focus_time_minutes", 0),
            "sessionId" to (intent.getStringExtra("session_id") ?: "")
        )
    }

    // ====================
    // WINDOW CONFIGURATION
    // ====================

    private fun configureOverlayWindow() {
        try {
            window.apply {
                // 1. Force the screen to stay on and dismiss the keyguard (lock screen)
                addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)

                // 2. Comprehensive flags for showing over the lock screen and waking the device
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(true)
                    setTurnScreenOn(true)
                } else {
                    @Suppress("DEPRECATION")
                    addFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    )
                }

                // 3. CRITICAL: Set the layout to NOT be "touch modal" so it can capture focus
                // and use FLAG_LAYOUT_IN_SCREEN to ensure it covers system bars
                addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
                addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN)
                addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)

                // 4. Set the proper overlay type for modern Android
                // if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                //     setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
                // } else {
                //     @Suppress("DEPRECATION")
                //     setType(WindowManager.LayoutParams.TYPE_PHONE)
                // }

                // 5. Configure transparent system bars for a seamless look
                statusBarColor = Color.TRANSPARENT
                navigationBarColor = Color.TRANSPARENT

                // 6. Handle modern display cutouts (notches)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    attributes.layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }

            Log.d(TAG, "Overlay window configured with priority focus flags")

        } catch (e: Exception) {
            Log.e(TAG, "Error configuring overlay window", e)
        }
    }
    // ====================
    // SESSION DATA LOADING
    // ====================

    private fun loadCurrentSessionData() {
        scope.launch {
            try {
                val focusManager = FocusModeManager.getInstance(this@BlockOverlayActivity)
                sessionData = focusManager.getCurrentSessionStatus()

                // Send session data to Flutter if event sink is available
                sessionData?.let { data ->
                    sendEventToFlutter("session_data", data)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error loading session data", e)
            }
        }
    }

    // ====================
    // METHOD CHANNEL HANDLING
    // ====================

    private fun handleMethodCall(
        method: String,
        arguments:  Any?,
        result: MethodChannel.Result
    ) {
        scope.launch @androidx.annotation.RequiresPermission(android.Manifest.permission.VIBRATE) {
            try {
                when (method) {
                    "getOverlayData" -> {
                        result.success(overlayData)
                    }

                    "getSessionData" -> {
                        result.success(sessionData ?: emptyMap<String, Any>())
                    }

                    "goHome" -> {
                        goHome()
                        result.success(true)
                    }

                    "goBack" -> {
                        goBack()
                        result. success(true)
                    }

                    "endFocusSession" -> {
                        val success = endFocusSession()
                        result.success(success)
                    }

                    "pauseFocusSession" -> {
                        val success = pauseFocusSession()
                        result.success(success)
                    }

                    "resumeFocusSession" -> {
                        val success = resumeFocusSession()
                        result.success(success)
                    }

                    "closeOverlay" -> {
                        closeOverlay()
                        result.success(true)
                    }

                    "overrideAppLimit" -> {
                        val success = overrideAppLimit(arguments)
                        result.success(success)
                    }

                    "reportInteraction" -> {
                        reportUserInteraction(arguments)
                        result.success(true)
                    }

                    "vibrate" -> {
                        val pattern = arguments as? String ?: "single"
                        vibrateDevice(pattern)
                        result.success(true)
                    }

                    "showEducationalContent" -> {
                        showEducationalContent(arguments)
                        result.success(true)
                    }

                    else -> {
                        Log.w(TAG, "Unknown method: $method")
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling method call: $method", e)
                result.error("ERROR", "Method call failed: ${e.message}", null)
            }
        }
    }

    // ====================
    // OVERLAY ACTIONS
    // ====================

    private fun goHome() {
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent. CATEGORY_HOME)
                flags = Intent. FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(homeIntent)
            finish()
        } catch (e: Exception) {
            Log.e(TAG, "Error going home", e)
            finish()
        }
    }

    private fun goBack() {
        try {
            onBackPressed()
        } catch (e: Exception) {
            Log.e(TAG, "Error going back", e)
            goHome()
        }
    }

    private suspend fun endFocusSession(): Boolean {
        return try {
            val focusManager = FocusModeManager. getInstance(this@BlockOverlayActivity)
            val success = focusManager. endSession()

            if (success) {
                sendEventToFlutter("session_ended", mapOf("reason" to "user_request"))
                finish()
            }

            success
        } catch (e: Exception) {
            Log.e(TAG, "Error ending focus session", e)
            false
        }
    }

    private suspend fun pauseFocusSession(): Boolean {
        return try {
            val focusManager = FocusModeManager.getInstance(this@BlockOverlayActivity)
            val success = focusManager.pauseSession()

            if (success) {
                sendEventToFlutter("session_paused", mapOf("timestamp" to System.currentTimeMillis()))
            }

            success
        } catch (e: Exception) {
            Log.e(TAG, "Error pausing focus session", e)
            false
        }
    }

    private suspend fun resumeFocusSession(): Boolean {
        return try {
            val focusManager = FocusModeManager.getInstance(this@BlockOverlayActivity)
            val success = focusManager.resumeSession()

            if (success) {
                sendEventToFlutter("session_resumed", mapOf("timestamp" to System.currentTimeMillis()))
            }

            success
        } catch (e: Exception) {
            Log.e(TAG, "Error resuming focus session", e)
            false
        }
    }

    private fun closeOverlay() {
        try {
            finish()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing overlay", e)
        }
    }

    private suspend fun overrideAppLimit(arguments: Any?): Boolean {
        return try {
            val args = arguments as? Map<String, Any> ?: return false
            val packageName = args["packageName"] as?  String ?: return false
            val duration = args["overrideDurationMinutes"] as? Int ?: 15

            // Implement app limit override logic
            Log.d(TAG, "Overriding app limit for $packageName for $duration minutes")

            // This would integrate with AppLimitManager to temporarily override limits
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error overriding app limit", e)
            false
        }
    }

    // ====================
    // ANALYTICS & FEEDBACK
    // ====================

    private suspend fun reportUserInteraction(arguments: Any?) {
        try {
            val args = arguments as? Map<String, Any> ?: return
            val interactionType = args["type"] as? String ?: "unknown"
            val data = args["data"] as? Map<String, Any> ?:  emptyMap()

            val focusManager = FocusModeManager. getInstance(this@BlockOverlayActivity)
            focusManager.reportInterruption(
                packageName = overlayData["packageName"] as? String ?: "overlay",
                appName = overlayData["appName"] as? String ?: "Block Overlay",
                type = "overlay_interaction_$interactionType",
                wasBlocked = true
            )

            Log.d(TAG, "Reported user interaction: $interactionType")

        } catch (e: Exception) {
            Log.e(TAG, "Error reporting user interaction", e)
        }
    }

    @RequiresPermission(Manifest.permission.VIBRATE)
    private fun vibrateDevice(pattern: String) {
        try {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator

            val vibrationPattern = when (pattern) {
                "double" -> longArrayOf(0, 200, 100, 200)
                "triple" -> longArrayOf(0, 150, 100, 150, 100, 150)
                "long" -> longArrayOf(0, 500)
                else -> longArrayOf(0, 200) // single
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val amplitudes = IntArray(vibrationPattern.size) {
                    if (it % 2 == 0) 0 else 255
                }
                val vibrationEffect = VibrationEffect.createWaveform(vibrationPattern, amplitudes, -1)
                vibrator.vibrate(vibrationEffect)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(vibrationPattern, -1)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error vibrating device", e)
        }
    }

    private fun showEducationalContent(arguments: Any?) {
        try {
            val args = arguments as? Map<String, Any>
            val contentType = args?. get("contentType") as? String ?: overlayType

            // This could launch a separate educational activity or show content within the overlay
            Log.d(TAG, "Showing educational content for: $contentType")

            // For now, we'll just send the educational data to Flutter
            sendEventToFlutter("educational_content", mapOf(
                "contentType" to contentType,
                "message" to getEducationalMessage(contentType),
                "tips" to getEducationalTips(contentType)
            ))

        } catch (e: Exception) {
            Log. e(TAG, "Error showing educational content", e)
        }
    }

    // ====================
    // EVENT CHANNEL COMMUNICATION
    // ====================

    private fun sendInitialData() {
        sendEventToFlutter("initial_data", mapOf(
            "overlayType" to overlayType,
            "overlayData" to overlayData,
            "sessionData" to (sessionData ?: emptyMap<String, Any>()),
            "timestamp" to System.currentTimeMillis()
        ))
    }

    private fun sendEventToFlutter(event: String, data: Any) {
        try {
            val eventData = mapOf(
                "event" to event,
                "data" to data,
                "timestamp" to System.currentTimeMillis()
            )

            eventSink?.success(eventData)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending event to Flutter: $event", e)
        }
    }

    // ====================
    // UTILITY METHODS
    // ====================

    private fun getMotivationalMessage(): String {
        val messages = listOf(
            "Stay strong! Every moment of focus builds your willpower.",
            "You chose focus over distraction. That's the path to success.",
            "Great minds think about their goals, not their apps.",
            "This interruption is temporary, but your achievements are permanent.",
            "Focus is a muscle. You're making it stronger right now.",
            "The best time to plant a tree was 20 years ago. The second best time is now.",
            "Success is the sum of small efforts repeated day in and day out."
        )
        return messages.random()
    }

    private fun getDefaultShortsMessage(): String {
        return "Short-form content is designed to capture your attention and keep you scrolling. Break the cycle and focus on what truly matters!"
    }

    private fun getPlatformFromPackage(packageName: String): String {
        return when {
            packageName.contains("youtube") -> "YouTube"
            packageName.contains("instagram") -> "Instagram"
            packageName.contains("facebook") -> "Facebook"
            packageName.contains("tiktok") || packageName.contains("musically") -> "TikTok"
            packageName.contains("snapchat") -> "Snapchat"
            else -> "Unknown"
        }
    }

    private fun getWebsiteSuggestion(): String {
        val suggestions = listOf(
            "Try reading a book or article instead",
            "Consider doing some physical exercise",
            "Practice a skill or hobby you enjoy",
            "Connect with friends or family",
            "Work on your personal projects",
            "Learn something new online"
        )
        return suggestions.random()
    }

    private fun getEducationalMessage(contentType: String): String {
        return when (contentType.lowercase()) {
            "blocked_shorts" -> "Short-form videos trigger dopamine responses similar to gambling, making them highly addictive.  Studies show they can reduce attention span and increase anxiety."
            "blocked_app" -> "App blocking helps you build digital discipline.  Each time you resist the urge to check blocked apps, you strengthen your focus muscle."
            "blocked_website" -> "Website blocking during focus sessions helps maintain deep work states. It takes an average of 23 minutes to regain focus after a distraction."
            "app_limit" -> "Setting app limits helps you maintain a healthy relationship with technology.  Awareness of usage patterns is the first step to digital wellness."
            else -> "Taking control of your digital habits is one of the most important skills in the modern world."
        }
    }

    private fun getEducationalTips(contentType: String): List<String> {
        return when (contentType.lowercase()) {
            "blocked_shorts" -> listOf(
                "Replace short-form content with long-form educational videos",
                "Use the 'two-minute rule' - if it takes less than two minutes, do it now",
                "Practice mindful consumption - ask yourself 'Is this adding value?'",
                "Set specific times for entertainment content"
            )
            "blocked_app" -> listOf(
                "Use app timers to gradually reduce usage",
                "Replace checking apps with productive habits",
                "Practice delayed gratification exercises",
                "Find offline alternatives for your favorite apps"
            )
            "blocked_website" -> listOf(
                "Use website blockers during work hours",
                "Create a 'parking lot' for interesting links to check later",
                "Practice the Pomodoro technique for focused work",
                "Set up a dedicated workspace free from distractions"
            )
            "app_limit" -> listOf(
                "Start with generous limits and gradually reduce them",
                "Track your usage patterns to identify peak distraction times",
                "Use app limits as training wheels for self-control",
                "Reward yourself when you stay within limits"
            )
            else -> listOf(
                "Digital wellness is about intentional technology use",
                "Small consistent changes lead to big improvements",
                "Focus on what you want to do more of, not just what to avoid"
            )
        }
    }

    fun onBackPressedDispatcher() {
        // Prevent back button from closing overlay easily
        // Show confirmation or just go home
        goHome()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}