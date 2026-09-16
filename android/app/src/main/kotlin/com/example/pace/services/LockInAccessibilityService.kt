package com.example.pace.services

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.example.pace.services.overlay.BlockOverlayActivity
import com.example.pace.services.overlay.OverlayLauncher
import com.example.pace.services.overlay.SimpleBlockOverlay
import com.example.pace.managers.WebsiteBlockManager
import com.example.pace.managers.ShortFormBlockManager
import com.example.pace.services.limits.AppLimitManager
import com.example.pace.services.limits.AppLimitTracker
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat

/**
 * LockInAccessibilityService - Enhanced accessibility service for content blocking
 * 
 * This service monitors:
 * 1. Browser URLs to block websites
 * 2. App content to detect and block short-form content (Shorts, Reels, etc.)
 * 3. App usage time to enforce daily limits
 */
class LockInAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "LockInAccessibilityService"
        var isServiceRunning = false
            private set
        
        // Singleton instance to access from MainActivity
        private var instance: LockInAccessibilityService? = null
        
        fun getInstance(): LockInAccessibilityService? = instance
        
        // Foreground service constants
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "lockin_accessibility_channel"
        private const val CHANNEL_NAME = "LockIn Protection Service"
        
        // Browser package names for URL monitoring
        val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "org.mozilla.firefox",
            "com.microsoft.emmx",
            "com.opera.browser",
            "com.brave.browser",
            "com.kiwibrowser.browser"
        )
        
        // Time tracking constants
        private const val USAGE_CHECK_INTERVAL_MS = 10000L // Check every 10 seconds
        private const val MIN_USAGE_INCREMENT_SECONDS = 10 // Minimum 10 seconds to count
        private const val URL_CHECK_DELAY_MS = 500L // Delay before checking URL to let UI settle
    }
    
    private lateinit var websiteBlockManager: WebsiteBlockManager
    private lateinit var shortFormBlockManager: ShortFormBlockManager
    private lateinit var appLimitManager: AppLimitManager
    private lateinit var appLimitTracker: AppLimitTracker
    private lateinit var overlayLauncher: OverlayLauncher
    private var lastCheckedUrl: String? = null
    private var lastBlockTime = 0L // Add cooldown tracking
    private val BLOCK_COOLDOWN_MS = 5000L // 5 second cooldown
    
    // MethodChannel for communicating limit reached events to Flutter
    private var limitEventsChannel: MethodChannel? = null
    
    // Periodic limit checking
    private val limitCheckHandler = Handler(Looper.getMainLooper())
    private var limitCheckRunnable: Runnable? = null
    private val LIMIT_CHECK_INTERVAL_MS = 5000L // Check every 5 seconds
    private var lastUserApp: String? = null // Track last non-system app
    
    // System packages to ignore (don't treat as app switches)
    private val SYSTEM_PACKAGES = setOf(
        "android",
        "com.android.systemui",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.android.vending",
        "com.google.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.google.android.inputmethod.latin", // Gboard
        "com.samsung.android.app.aodservice",
        "com.samsung.android.bixby.agent",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.vivo.upslide", // Vivo notification panel
        "com.bbk.launcher2", // Vivo launcher
        "com.oppo.launcher", // Oppo launcher
        "com.huawei.android.launcher", // Huawei launcher
        "com.miui.home" // Xiaomi launcher
    )
    
    // YouTube Shorts detection with delayed checks
    private val shortsDetectionHandler = Handler(Looper.getMainLooper())
    private val SHORTS_DETECTION_DELAY_MS = 500L // Delay for UI to settle after scroll
    private val SHORTS_CONFIRMATION_DELAY_MS = 1000L // Additional delay for confirmation
    private val SHORTS_GRACE_PERIOD_MS = 3000L // Grace period for user to navigate manually
    private val SHORTS_WARNING_DELAY_MS = 2000L // Show warning before forced navigation
    
    // YouTube Shorts specific node IDs and patterns
    private val YOUTUBE_SHORTS_NODE_IDS = setOf(
        "com.google.android.youtube:id/reel_watch_fragment_root",
        "com.google.android.youtube:id/reel_recycler",
        "com.google.android.youtube:id/shorts_player_fragment",
        "com.google.android.youtube:id/shorts_pivot_bar",
        "com.google.android.youtube:id/reel_watch_with_overlay_fragment_container"
    )
    
    // Instagram Reels specific node IDs and patterns - only for ACTIVE reels viewing
    private val INSTAGRAM_REELS_NODE_IDS = setOf(
        "com.instagram.android:id/clips_viewer_root", 
        "com.instagram.android:id/clips_viewer_fragment_container",
        "com.instagram.android:id/clips_viewer_layout",
        "com.instagram.android:id/reel_viewer_fragment",
        "com.instagram.android:id/clips_video_container",
        "com.instagram.android:id/clips_item_view_pager"
    )
    
    private val INSTAGRAM_REELS_TEXT_PATTERNS = setOf(
        "Double tap to like", "Add a comment", "Share this reel", "Send this reel"
    )
    
    // Instagram Home navigation node IDs
    private val INSTAGRAM_HOME_NODE_IDS = setOf(
        "com.instagram.android:id/tab_home",
        "com.instagram.android:id/feed_tab",
        "com.instagram.android:id/tab_feed", 
        "com.instagram.android:id/home_tab",
        "com.instagram.android:id/bottom_navigation",
        "com.instagram.android:id/tab_bar",
        "com.instagram.android:id/main_tab_bar"
    )
    
    // App limit tracking
    private var currentForegroundApp: String? = null
    private var lastUsageCheckTime: Long = 0
    private val usageCheckHandler = Handler(Looper.getMainLooper())
    private val usageCheckRunnable = object : Runnable {
        override fun run() {
            checkAndUpdateUsage()
            usageCheckHandler.postDelayed(this, USAGE_CHECK_INTERVAL_MS)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        isServiceRunning = true
        instance = this
        Log.d(TAG, "Accessibility Service Connected")
        
        // Initialize managers
        websiteBlockManager = WebsiteBlockManager.getInstance(applicationContext)
        shortFormBlockManager = ShortFormBlockManager.getInstance(applicationContext)
        appLimitManager = AppLimitManager(applicationContext)
        appLimitTracker = AppLimitTracker(applicationContext)
        overlayLauncher = OverlayLauncher.getInstance(applicationContext)
        
        // Start as foreground service for persistence
        startForegroundService()
        
        // Configure the accessibility service
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                        AccessibilityEvent.TYPE_VIEW_SCROLLED or
                        AccessibilityEvent.TYPE_VIEW_CLICKED
            
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                   AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                   AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY or
                   AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE
            
            notificationTimeout = 100
        }
        serviceInfo = info
        
        // Start usage tracking
        usageCheckHandler.postDelayed(usageCheckRunnable, USAGE_CHECK_INTERVAL_MS)
        Log.d(TAG, "Service configuration completed - running in foreground")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        try {
            val packageName = event.packageName?.toString() ?: return
            val eventType = event.eventType
            
            Log.d(TAG, "Event: ${AccessibilityEvent.eventTypeToString(eventType)} for $packageName")
            
            // Update current foreground app for usage tracking
            if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                // Ignore system packages and transient windows
                if (isSystemPackage(packageName)) {
                    Log.d(TAG, "Ignoring system package: $packageName (keeping tracking for ${lastUserApp ?: "none"})")
                    return
                }
                
                // Check if new package has limits - if not, it's likely a system overlay
                val hasLimit = com.example.pace.services.limits.LockInNativeLimitsHolder.hasLimit(packageName)
                
                // If switching to an app without limits while tracking another app, ignore it
                if (!hasLimit && lastUserApp != null) {
                    val lastAppHasLimit = com.example.pace.services.limits.LockInNativeLimitsHolder.hasLimit(lastUserApp!!)
                    if (lastAppHasLimit) {
                        Log.d(TAG, "Ignoring transient window: $packageName (keeping tracking for $lastUserApp)")
                        // Don't call onAppSwitched, keep tracking the last user app
                        return
                    }
                }
                
                // Only update if it's a different user app
                if (packageName != lastUserApp) {
                    Log.d(TAG, "User app switched: ${lastUserApp ?: "none"} → $packageName")
                    lastUserApp = packageName
                }
                
                currentForegroundApp = packageName
                // Handle app limit checking with new tracker
                val limitExceeded = appLimitTracker.onAppSwitched(packageName)
                if (limitExceeded) {
                    enforceAppLimit(packageName)
                    return // Don't process other events if limit exceeded
                }
                
                // Start periodic checking if this app has a limit
                startPeriodicLimitCheck(packageName)
            }
            
            // Debug logging for YouTube
            if (packageName == "com.google.android.youtube") {
                val activeBlocks = shortFormBlockManager.getActiveBlocks()
                val isBlocked = shortFormBlockManager.isPackageBlocked(packageName)
                Log.i(TAG, "📹 YouTube detected - Active blocks: ${activeBlocks.size}, Package blocked: $isBlocked")
                activeBlocks.forEach { block ->
                    Log.i(TAG, "  - ${block.platform} ${block.feature}: ${block.isBlocked}")
                }
            }
            
            // Handle short-form content blocking with enhanced detection
            if (shortFormBlockManager.getActiveBlocks().isNotEmpty() && 
                shortFormBlockManager.isPackageBlocked(packageName)) {
                
                // Add cooldown to prevent spam blocking
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastBlockTime < BLOCK_COOLDOWN_MS) {
                    return
                }
                
                when (packageName) {
                    "com.google.android.youtube" -> {
                        // Use delayed check for Shorts detection, especially after scroll events
                        if (eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
                            shortsDetectionHandler.postDelayed({
                                if (detectYouTubeShortsEnhanced()) {
                                    blockShortFormContent(packageName)
                                    lastBlockTime = System.currentTimeMillis()
                                }
                            }, SHORTS_DETECTION_DELAY_MS)
                        } else {
                            if (detectYouTubeShortsEnhanced()) {
                                blockShortFormContent(packageName)
                                lastBlockTime = currentTime
                            }
                        }
                    }
                    "com.instagram.android" -> {
                        // Use delayed check for Reels detection, especially after scroll events
                        if (eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED || 
                            eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
                            shortsDetectionHandler.postDelayed({
                                if (detectInstagramReels()) {
                                    blockShortFormContent(packageName)
                                    lastBlockTime = System.currentTimeMillis()
                                }
                            }, SHORTS_DETECTION_DELAY_MS)
                        } else {
                            if (detectInstagramReels()) {
                                blockShortFormContent(packageName)
                                lastBlockTime = currentTime
                            }
                        }
                    }
                    "com.zhiliaoapp.musically" -> { // TikTok
                        blockShortFormContent(packageName) // TikTok is entirely short-form
                        lastBlockTime = currentTime
                    }
                    "com.snapchat.android" -> {
                        if (detectSnapchatSpotlight()) {
                            blockShortFormContent(packageName)
                            lastBlockTime = currentTime
                        }
                    }
                }
            }
            
            // Handle browser events for both URL blocking and short-form content
            if (BROWSER_PACKAGES.contains(packageName)) {
                handleBrowserEvent(event)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error handling accessibility event", e)
        }
    }

    private fun handleBrowserEvent(event: AccessibilityEvent) {
        try {
            val rootNode = rootInActiveWindow
            val packageName = event.packageName?.toString()
            
            if (rootNode != null && packageName != null) {
                // URL checking logic for website blocking
                usageCheckHandler.postDelayed({
                    checkCurrentUrlDirect(packageName, rootNode)
                }, URL_CHECK_DELAY_MS)
                
                // Also check for short-form content in browsers
                usageCheckHandler.postDelayed({
                    checkBrowserForShortsContent(event)
                }, URL_CHECK_DELAY_MS)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling browser event", e)
        }
    }

    private fun checkCurrentUrlDirect(packageName: String, rootNode: AccessibilityNodeInfo) {
        try {
            val url = extractUrlFromBrowser(rootNode)
            
            if (url != null) {
                // Always check if URL is blocked, but only log URL changes to avoid spam
                if (url != lastCheckedUrl) {
                    lastCheckedUrl = url
                    Log.d(TAG, "Checking URL: $url")
                }
                
                if (websiteBlockManager.isUrlBlocked(url)) {
                    Log.i(TAG, "⚠️ Blocked website detected: $url")
                    
                    // Add delay for UI stability before blocking
                    usageCheckHandler.postDelayed({
                        blockWebsite(packageName, url, rootInActiveWindow)
                    }, URL_CHECK_DELAY_MS)
                    
                    // Send event to Flutter for user notification
                    sendWebsiteBlockEvent(url, packageName)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error checking URL directly", e)
        }
    }

    private fun blockWebsite(packageName: String, url: String, rootNode: AccessibilityNodeInfo?) {
        try {
            val currentTime = System.currentTimeMillis()
            
            // Send challenge_failed event for survival mode
            sendChallengeFailedEvent(packageName, "blocked_website", url)
            
            // Prevent spam blocking with cooldown
            if (currentTime - lastBlockTime < BLOCK_COOLDOWN_MS) {
                Log.d(TAG, "Website blocking on cooldown, skipping...")
                return
            }
            
            lastBlockTime = currentTime
            Log.i(TAG, "🚫 Blocking website: $url")
            
            // Show overlay first for immediate user feedback
            showWebsiteBlockOverlay(url, getAppName(packageName))
            
            // Try multiple blocking strategies
            val blockingSuccess = tryMultipleBlockingStrategies(packageName, rootNode)
            
            if (!blockingSuccess) {
                Log.w(TAG, "All blocking strategies failed for $url")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking website", e)
        }
    }

    private fun tryMultipleBlockingStrategies(packageName: String, rootNode: AccessibilityNodeInfo?): Boolean {
        var success = false
        
        try {
            // Strategy 1: Navigate back (most reliable)
            if (tryNavigateBack()) {
                success = true
                Log.d(TAG, "✅ Website blocked using BACK navigation")
            }
            
            // Strategy 2: Close current tab (for browsers that support it)
            if (!success && tryCloseCurrentTab(packageName, rootNode)) {
                success = true
                Log.d(TAG, "✅ Website blocked by closing tab")
            }
            
            // Strategy 3: Clear address bar (last resort)
            if (!success && tryClearAddressBar(packageName, rootNode)) {
                success = true
                Log.d(TAG, "✅ Website blocked by clearing address bar")
            }
            
            // Strategy 4: Navigate to safe homepage (fallback)
            if (!success && tryNavigateToHomepage(packageName, rootNode)) {
                success = true
                Log.d(TAG, "✅ Website blocked by navigating to homepage")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error executing blocking strategies", e)
        }
        
        return success
    }

    private fun tryNavigateBack(): Boolean {
        return try {
            performGlobalAction(GLOBAL_ACTION_BACK)
            true
        } catch (e: Exception) {
            Log.d(TAG, "BACK navigation failed: ${e.message}")
            false
        }
    }

    private fun tryCloseCurrentTab(packageName: String, rootNode: AccessibilityNodeInfo?): Boolean {
        if (rootNode == null) return false
        
        return try {
            val closeButtonIds = when (packageName) {
                "com.android.chrome" -> listOf(
                    "com.android.chrome:id/tab_close_button",
                    "com.android.chrome:id/close_tab",
                    "com.android.chrome:id/tab_close"
                )
                "org.mozilla.firefox" -> listOf(
                    "org.mozilla.firefox:id/mozac_browser_toolbar_menu",
                    "org.mozilla.firefox:id/close_tab"
                )
                "com.sec.android.app.sbrowser" -> listOf(
                    "com.sec.android.app.sbrowser:id/tab_close_button"
                )
                else -> emptyList()
            }

            for (buttonId in closeButtonIds) {
                val closeButtons = rootNode.findAccessibilityNodeInfosByViewId(buttonId)
                closeButtons?.forEach { button ->
                    if (button.isClickable) {
                        val clicked = button.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        button.recycle()
                        if (clicked) {
                            Log.d(TAG, "Successfully clicked close tab button: $buttonId")
                            return true
                        }
                    }
                    button.recycle()
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "Close tab failed: ${e.message}")
            false
        }
    }

    private fun tryClearAddressBar(packageName: String, rootNode: AccessibilityNodeInfo?): Boolean {
        if (rootNode == null) return false
        
        return try {
            val addressBarIds = when (packageName) {
                "com.android.chrome" -> listOf(
                    "com.android.chrome:id/url_bar",
                    "com.android.chrome:id/location_bar"
                )
                "org.mozilla.firefox" -> listOf(
                    "org.mozilla.firefox:id/mozac_browser_toolbar_url_view"
                )
                "com.sec.android.app.sbrowser" -> listOf(
                    "com.sec.android.app.sbrowser:id/location_bar"
                )
                else -> emptyList()
            }

            for (barId in addressBarIds) {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(barId)
                addressBars?.forEach { addressBar ->
                    if (addressBar.isEditable) {
                        // Try to clear by setting empty text
                        val arguments = Bundle()
                        arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
                        val cleared = addressBar.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                        addressBar.recycle()
                        if (cleared) {
                            Log.d(TAG, "Successfully cleared address bar: $barId")
                            return true
                        }
                    }
                    addressBar.recycle()
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "Clear address bar failed: ${e.message}")
            false
        }
    }

    private fun tryNavigateToHomepage(packageName: String, rootNode: AccessibilityNodeInfo?): Boolean {
        if (rootNode == null) return false
        
        return try {
            // Look for home button in browser UI
            val homeButtonIds = when (packageName) {
                "com.android.chrome" -> listOf(
                    "com.android.chrome:id/home_button",
                    "com.android.chrome:id/toolbar_home"
                )
                "org.mozilla.firefox" -> listOf(
                    "org.mozilla.firefox:id/home"
                )
                "com.sec.android.app.sbrowser" -> listOf(
                    "com.sec.android.app.sbrowser:id/home_button"
                )
                else -> emptyList()
            }

            for (buttonId in homeButtonIds) {
                val homeButtons = rootNode.findAccessibilityNodeInfosByViewId(buttonId)
                homeButtons?.forEach { button ->
                    if (button.isClickable) {
                        val clicked = button.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        button.recycle()
                        if (clicked) {
                            Log.d(TAG, "Successfully clicked home button: $buttonId")
                            return true
                        }
                    }
                    button.recycle()
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "Navigate to homepage failed: ${e.message}")
            false
        }
    }

    private fun sendWebsiteBlockEvent(url: String, packageName: String) {
        try {
            val appName = getAppName(packageName)
            val event = mapOf(
                "type" to "website_blocked",
                "url" to url,
                "package_name" to packageName,
                "app_name" to appName,
                "timestamp" to System.currentTimeMillis()
            )
            
            // Send to Flutter via existing event mechanism
            // This will be handled by the EventChannel in MainActivity
            sendEventToFlutter(event)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error sending website block event", e)
        }
    }

    private fun sendEventToFlutter(event: Map<String, Any>) {
        try {
            // If we had a direct reference to MainActivity's event sink, we'd use it
            // For now, we'll use Intent to notify MainActivity
            val intent = Intent("com.lockin.WEBSITE_BLOCKED").apply {
                putExtra("event_data", HashMap(event))
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending event to Flutter", e)
        }
    }
    
    /**
     * Send challenge_failed event to Flutter for Survival Mode
     * This is called when user attempts to access blocked content during a challenge
     */
    private fun sendChallengeFailedEvent(packageName: String, reason: String, url: String? = null) {
        try {
            val event = mutableMapOf<String, Any>(
                "type" to "challenge_failed",
                "package_name" to packageName,
                "reason" to reason,
                "timestamp" to System.currentTimeMillis()
            )
            
            if (url != null) {
                event["url"] = url
            }
            
            Log.i(TAG, "🚨 Challenge Failed Event: $reason for $packageName")
            
            // Send to Flutter via broadcast
            val intent = Intent("com.lockin.CHALLENGE_FAILED").apply {
                putExtra("event_data", HashMap(event))
            }
            sendBroadcast(intent)
            
            // Also send via the generic event mechanism
            sendEventToFlutter(event)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error sending challenge failed event", e)
        }
    }
    
    private fun checkBrowserForShortsContent(event: AccessibilityEvent) {
        try {
            val rootNode = rootInActiveWindow ?: return
            val url = extractUrlFromBrowser(rootNode)
            
            if (url != null) {
                // Check if URL matches YouTube Shorts patterns
                val isYouTubeShortsUrl = url.contains("youtube.com/shorts") || 
                                        url.contains("/shorts/") ||
                                        url.contains("youtu.be/shorts")
                
                if (isYouTubeShortsUrl && shortFormBlockManager.isPlatformBlocked("YouTube", "Shorts")) {
                    Log.d(TAG, "YouTube Shorts detected in browser: $url")
                    blockBrowserShortsContent(event.packageName.toString(), url)
                }
                
                // Check for other short-form content URLs
                checkOtherShortFormUrls(url, event.packageName.toString())
            }
            
            rootNode.recycle()
        } catch (e: Exception) {
            Log.e(TAG, "Error checking browser for shorts content", e)
        }
    }
    
    private fun checkOtherShortFormUrls(url: String, packageName: String) {
        try {
            // Instagram Reels
            if ((url.contains("instagram.com/reel") || url.contains("instagram.com/reels")) &&
                shortFormBlockManager.isPlatformBlocked("Instagram", "Reels")) {
                blockBrowserShortsContent(packageName, url)
                return
            }
            
            // TikTok
            if ((url.contains("tiktok.com") || url.contains("vm.tiktok.com")) &&
                shortFormBlockManager.isPlatformBlocked("TikTok", "Videos")) {
                blockBrowserShortsContent(packageName, url)
                return
            }
            
            // Facebook Reels
            if ((url.contains("facebook.com/reel") || url.contains("fb.watch/reel")) &&
                shortFormBlockManager.isPlatformBlocked("Facebook", "Reels")) {
                blockBrowserShortsContent(packageName, url)
                return
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error checking other short-form URLs", e)
        }
    }
    
    private fun blockBrowserShortsContent(packageName: String, url: String) {
        try {
            Log.d(TAG, "Blocking short-form content in browser: $url")
            
            // Show overlay first
            showBrowserShortsBlockOverlay(packageName, url)
            
            // Try to navigate back or block scrolling
            performGlobalAction(GLOBAL_ACTION_BACK)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking browser shorts content", e)
        }
    }

    private fun extractUrlFromBrowser(rootNode: AccessibilityNodeInfo): String? {
        try {
            val packageName = rootNode.packageName?.toString() ?: return null
            Log.d(TAG, "Extracting URL from browser: $packageName")

            // Browser-specific URL extraction using view IDs
            val url = when (packageName) {
                "com.android.chrome" -> extractUrlFromChrome(rootNode)
                "org.mozilla.firefox" -> extractUrlFromFirefox(rootNode)
                "com.sec.android.app.sbrowser" -> extractUrlFromSamsungBrowser(rootNode)
                "com.microsoft.emmx" -> extractUrlFromEdge(rootNode)
                "com.opera.browser" -> extractUrlFromOpera(rootNode)
                "com.brave.browser" -> extractUrlFromBrave(rootNode)
                else -> findUrlInNodeGeneric(rootNode) // Fallback for other browsers
            }

            if (url != null) {
                Log.d(TAG, "Successfully extracted URL: $url")
                return url
            }

            // Fallback: try generic URL extraction
            return findUrlInNodeGeneric(rootNode)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting URL from browser", e)
            return null
        }
    }

    private fun extractUrlFromChrome(rootNode: AccessibilityNodeInfo): String? {
        val chromeAddressBarIds = listOf(
            "com.android.chrome:id/url_bar",
            "com.android.chrome:id/location_bar",
            "com.android.chrome:id/location_bar_status",
            "com.android.chrome:id/omnibox",
            "com.android.chrome:id/toolbar_container"
        )

        for (viewId in chromeAddressBarIds) {
            try {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                addressBars?.forEach { node ->
                    val text = node.text?.toString()
                    node.recycle()
                    if (isValidUrl(text)) {
                        return text
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to find Chrome URL with view ID: $viewId")
            }
        }

        // Fallback: look for nodes with "Address bar" content description
        try {
            val addressBars = rootNode.findAccessibilityNodeInfosByText("Address bar")
            addressBars?.forEach { node ->
                val text = node.text?.toString()
                node.recycle()
                if (isValidUrl(text)) {
                    return text
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "Chrome address bar fallback failed")
        }

        return null
    }

    private fun extractUrlFromFirefox(rootNode: AccessibilityNodeInfo): String? {
        val firefoxAddressBarIds = listOf(
            "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            "org.mozilla.firefox:id/url_bar_title",
            "org.mozilla.firefox:id/toolbar"
        )

        for (viewId in firefoxAddressBarIds) {
            try {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                addressBars?.forEach { node ->
                    val text = node.text?.toString()
                    node.recycle()
                    if (isValidUrl(text)) {
                        return text
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to find Firefox URL with view ID: $viewId")
            }
        }

        return null
    }

    private fun extractUrlFromSamsungBrowser(rootNode: AccessibilityNodeInfo): String? {
        val samsungAddressBarIds = listOf(
            "com.sec.android.app.sbrowser:id/location_bar",
            "com.sec.android.app.sbrowser:id/url_bar",
            "com.sec.android.app.sbrowser:id/location_bar_edit_text"
        )

        for (viewId in samsungAddressBarIds) {
            try {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                addressBars?.forEach { node ->
                    val text = node.text?.toString()
                    node.recycle()
                    if (isValidUrl(text)) {
                        return text
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to find Samsung Browser URL with view ID: $viewId")
            }
        }

        return null
    }

    private fun extractUrlFromEdge(rootNode: AccessibilityNodeInfo): String? {
        val edgeAddressBarIds = listOf(
            "com.microsoft.emmx:id/url_bar",
            "com.microsoft.emmx:id/location_bar"
        )

        for (viewId in edgeAddressBarIds) {
            try {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                addressBars?.forEach { node ->
                    val text = node.text?.toString()
                    node.recycle()
                    if (isValidUrl(text)) {
                        return text
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to find Edge URL with view ID: $viewId")
            }
        }

        return null
    }

    private fun extractUrlFromOpera(rootNode: AccessibilityNodeInfo): String? {
        val operaAddressBarIds = listOf(
            "com.opera.browser:id/url_field",
            "com.opera.browser:id/location_bar"
        )

        for (viewId in operaAddressBarIds) {
            try {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                addressBars?.forEach { node ->
                    val text = node.text?.toString()
                    node.recycle()
                    if (isValidUrl(text)) {
                        return text
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to find Opera URL with view ID: $viewId")
            }
        }

        return null
    }

    private fun extractUrlFromBrave(rootNode: AccessibilityNodeInfo): String? {
        // Brave browser typically uses Chrome-like view IDs
        val braveAddressBarIds = listOf(
            "com.brave.browser:id/url_bar",
            "com.brave.browser:id/location_bar"
        )

        for (viewId in braveAddressBarIds) {
            try {
                val addressBars = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                addressBars?.forEach { node ->
                    val text = node.text?.toString()
                    node.recycle()
                    if (isValidUrl(text)) {
                        return text
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to find Brave URL with view ID: $viewId")
            }
        }

        return null
    }

    private fun findUrlInNodeGeneric(node: AccessibilityNodeInfo): String? {
        try {
            // Check if this node contains a URL
            val text = node.text?.toString()
            if (isValidUrl(text)) {
                return text
            }
            
            // Check content description
            val contentDesc = node.contentDescription?.toString()
            if (isValidUrl(contentDesc)) {
                return contentDesc
            }
            
            // Check child nodes recursively
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    val url = findUrlInNodeGeneric(child)
                    child.recycle()
                    if (url != null) return url
                }
            }
            
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Error finding URL in node generically", e)
            return null
        }
    }

    private fun isValidUrl(text: String?): Boolean {
        if (text.isNullOrBlank()) return false
        
        val trimmedText = text.trim()
        return (trimmedText.startsWith("http://") || 
                trimmedText.startsWith("https://") ||
                (trimmedText.contains(".") && !trimmedText.contains(" ") && trimmedText.length > 3))
    }

    /**
     * Check if a package should be ignored (system/background services)
     */
    private fun isSystemPackage(packageName: String): Boolean {
        return SYSTEM_PACKAGES.contains(packageName) ||
               packageName.startsWith("com.android.") ||
               packageName.startsWith("com.google.android.") ||
               packageName.startsWith("com.samsung.android.") ||
               packageName.startsWith("com.vivo.") ||
               packageName.startsWith("com.oppo.") ||
               packageName.startsWith("com.bbk.") ||
               packageName.startsWith("com.huawei.") ||
               packageName.startsWith("com.xiaomi.") ||
               packageName.startsWith("com.miui.")
    }
    
    /**
     * Start periodic checking for app limits while app is in use
     */
    private fun startPeriodicLimitCheck(packageName: String) {
        // Stop any existing periodic check
        stopPeriodicLimitCheck()
        
        // Only start periodic check if app has a limit
        if (!com.example.pace.services.limits.LockInNativeLimitsHolder.hasLimit(packageName)) {
            Log.d(TAG, "No limit for $packageName, skipping periodic check")
            return
        }
        
        Log.d(TAG, "⏰ Starting periodic limit check for $packageName every ${LIMIT_CHECK_INTERVAL_MS/1000}s")
        
        limitCheckRunnable = object : Runnable {
            override fun run() {
                // Check if still on the same user app (ignore system overlays)
                if (lastUserApp == packageName) {
                    Log.d(TAG, "⏱️ Periodic check: Checking limit for $packageName")
                    val limitExceeded = appLimitTracker.checkLimit(packageName)
                    if (limitExceeded) {
                        Log.w(TAG, "⏱️ Periodic check: LIMIT EXCEEDED during active use!")
                        enforceAppLimit(packageName)
                        stopPeriodicLimitCheck() // Stop checking after enforcement
                    } else {
                        // Schedule next check
                        limitCheckHandler.postDelayed(this, LIMIT_CHECK_INTERVAL_MS)
                    }
                } else {
                    Log.d(TAG, "⏱️ User app switched away from $packageName, stopping periodic check")
                    stopPeriodicLimitCheck()
                }
            }
        }
        
        // Start the periodic checking
        limitCheckHandler.postDelayed(limitCheckRunnable!!, LIMIT_CHECK_INTERVAL_MS)
    }
    
    /**
     * Stop periodic limit checking
     */
    private fun stopPeriodicLimitCheck() {
        limitCheckRunnable?.let {
            limitCheckHandler.removeCallbacks(it)
            limitCheckRunnable = null
            Log.d(TAG, "⏰ Stopped periodic limit check")
        }
    }
    
    /**
     * Enforce app limit by navigating back and notifying Flutter
     */
    private fun enforceAppLimit(packageName: String) {
        try {
            Log.w(TAG, "⚠️⚠️⚠️ ENFORCING APP LIMIT FOR $packageName ⚠️⚠️⚠️")
            
            // Stop periodic checking
            stopPeriodicLimitCheck()
            
            // Strategy 1: Multiple BACK actions
            Log.d(TAG, "Strategy 1: Attempting BACK actions...")
            performGlobalAction(GLOBAL_ACTION_BACK)
            Thread.sleep(100)
            performGlobalAction(GLOBAL_ACTION_BACK)
            Thread.sleep(100)
            performGlobalAction(GLOBAL_ACTION_BACK)
            
            // Strategy 2: HOME action (more reliable)
            Handler(Looper.getMainLooper()).postDelayed({
                Log.d(TAG, "Strategy 2: Performing HOME action")
                val homeSuccess = performGlobalAction(GLOBAL_ACTION_HOME)
                Log.d(TAG, "HOME action result: $homeSuccess")
                
                // Strategy 3: Show blocking overlay
                Handler(Looper.getMainLooper()).postDelayed({
                    Log.d(TAG, "Strategy 3: Showing app limit overlay")
                    showAppLimitExceededOverlay(packageName)
                }, 300)
            }, 500)
            
            // Notify Flutter
            Log.d(TAG, "Sending limit reached event to Flutter for $packageName")
            sendLimitReachedToFlutter(packageName)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error enforcing app limit for $packageName", e)
        }
    }
    
    /**
     * Send limit reached event to Flutter via MethodChannel
     */
    private fun sendLimitReachedToFlutter(packageName: String) {
        try {
            if (limitEventsChannel == null) {
                Log.e(TAG, "❌ limitEventsChannel is NULL - cannot send event!")
                return
            }
            
            Log.d(TAG, "Invoking limitReached on channel for $packageName")
            limitEventsChannel?.invokeMethod("limitReached", mapOf(
                "package" to packageName
            ))
            Log.d(TAG, "✅ Successfully sent limit reached event to Flutter")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending limit reached event to Flutter", e)
        }
    }

    private fun checkAndUpdateUsage() {
        // This is now handled by AppLimitTracker automatically
        // Keep method for backward compatibility but it's no longer needed
    }

    private fun detectYouTubeShortsEnhanced(): Boolean {
        try {
            val rootNode = rootInActiveWindow ?: return false
            
            // Primary detection: Look for specific Shorts node IDs
            val shortsNodeDetected = detectShortsNodeIds(rootNode)
            
            // Secondary detection: Multi-stage detection for better accuracy
            val activeShortsTab = checkForActiveShortsTab(rootNode)
            val shortsActionButtons = checkForShortsActionButtons(rootNode)
            val shortsUIElements = checkForShortsUIElements(rootNode)
            
            rootNode.recycle()
            
            // If specific node IDs are found, that's primary confirmation
            if (shortsNodeDetected) {
                Log.d(TAG, "YouTube Shorts detected via node IDs")
                return true
            }
            
            // Fallback: Require at least 2 indicators to confirm we're in Shorts
            val confirmationCount = listOf(activeShortsTab, shortsActionButtons, shortsUIElements).count { it }
            val isShorts = confirmationCount >= 2
            
            if (isShorts) {
                Log.d(TAG, "YouTube Shorts detected via UI analysis ($confirmationCount/3 indicators)")
            }
            
            return isShorts
            
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting YouTube Shorts", e)
            return false
        }
    }
    
    private fun detectShortsNodeIds(node: AccessibilityNodeInfo): Boolean {
        try {
            // Check for specific YouTube Shorts node IDs using findAccessibilityNodeInfosByViewId
            for (nodeId in YOUTUBE_SHORTS_NODE_IDS) {
                val shortsNodes = node.findAccessibilityNodeInfosByViewId(nodeId)
                if (shortsNodes.isNotEmpty()) {
                    Log.d(TAG, "Found YouTube Shorts node ID: $nodeId")
                    // Recycle found nodes
                    shortsNodes.forEach { it.recycle() }
                    return true
                }
            }
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting Shorts node IDs", e)
            return false
        }
    }

    private fun checkForActiveShortsTab(node: AccessibilityNodeInfo, depth: Int = 0): Boolean {
        try {
            if (depth > 8) return false
            
            val nodeText = node.text?.toString() ?: ""
            val contentDescription = node.contentDescription?.toString() ?: ""
            val isSelected = node.isSelected
            val isFocused = node.isFocused
            
            // Look for "Shorts" that's selected or focused
            if (nodeText.equals("Shorts", ignoreCase = true) && (isSelected || isFocused)) {
                Log.d(TAG, "Found active Shorts tab - selected: $isSelected, focused: $isFocused")
                return true
            }
            
            // Check child nodes
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    if (checkForActiveShortsTab(child, depth + 1)) {
                        child.recycle()
                        return true
                    }
                    child.recycle()
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking for active Shorts tab", e)
            return false
        }
    }

    private fun checkForShortsActionButtons(node: AccessibilityNodeInfo, depth: Int = 0): Boolean {
        try {
            if (depth > 8) return false
            
            val nodeText = node.text?.toString() ?: ""
            val contentDescription = node.contentDescription?.toString() ?: ""
            
            // Look for Shorts-specific action buttons
            val shortsButtons = listOf("Subscribe", "Share", "Dislike", "Like")
            var foundButtons = 0
            
            for (button in shortsButtons) {
                if (nodeText.contains(button, ignoreCase = true) ||
                    contentDescription.contains(button, ignoreCase = true)) {
                    foundButtons++
                }
            }
            
            // If we find multiple action buttons, likely in Shorts
            if (foundButtons >= 2) {
                Log.d(TAG, "Found $foundButtons Shorts action buttons")
                return true
            }
            
            // Check child nodes
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    if (checkForShortsActionButtons(child, depth + 1)) {
                        child.recycle()
                        return true
                    }
                    child.recycle()
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking for Shorts action buttons", e)
            return false
        }
    }

    private fun checkForShortsUIElements(node: AccessibilityNodeInfo, depth: Int = 0): Boolean {
        try {
            if (depth > 8) return false
            
            val contentDescription = node.contentDescription?.toString() ?: ""
            val className = node.className?.toString() ?: ""
            
            // Look for Shorts-specific UI patterns
            val shortsIndicators = listOf(
                "shorts",
                "vertical video",
                "swipe up",
                "next video"
            )
            
            for (indicator in shortsIndicators) {
                if (contentDescription.contains(indicator, ignoreCase = true)) {
                    Log.d(TAG, "Found Shorts UI element: $indicator")
                    return true
                }
            }
            
            // Check for vertical video layout characteristics
            if (className.contains("RecyclerView", ignoreCase = true) &&
                node.childCount > 0) {
                
                // Check if children have video-like properties
                for (i in 0 until node.childCount) {
                    val child = node.getChild(i)
                    if (child != null) {
                        val childDesc = child.contentDescription?.toString() ?: ""
                        if (childDesc.contains("video", ignoreCase = true) ||
                            childDesc.contains("play", ignoreCase = true)) {
                            child.recycle()
                            Log.d(TAG, "Found video-like element in RecyclerView")
                            return true
                        }
                        child.recycle()
                    }
                }
            }
            
            // Check child nodes
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    if (checkForShortsUIElements(child, depth + 1)) {
                        child.recycle()
                        return true
                    }
                    child.recycle()
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking for Shorts UI elements", e)
            return false
        }
    }

    private fun detectInstagramReels(): Boolean {
        try {
            val root = rootInActiveWindow ?: return false
            
            Log.d(TAG, "🔍 Instagram Reels Detection Started - checking for ACTIVE reels viewing")
            
            // Method 1: Check for ACTIVE reels viewer containers (most specific)
            val activeReelsNodes = root.findAccessibilityNodeInfosByViewId("com.instagram.android:id/clips_viewer_root") +
                                  root.findAccessibilityNodeInfosByViewId("com.instagram.android:id/clips_viewer_fragment_container")
            
            if (activeReelsNodes.isNotEmpty()) {
                Log.d(TAG, "✅ Instagram Reels detected via active clips viewer")
                activeReelsNodes.forEach { it.recycle() }
                root.recycle()
                return true
            }
            
            // Method 2: Check for vertical video player with Reels-specific UI (scroll-based detection)
            if (detectActiveReelsVideoPlayer(root)) {
                Log.d(TAG, "✅ Instagram Reels detected via active video player")
                root.recycle()
                return true
            }
            
            // Method 3: Check for Reels interaction UI (like, comment, share buttons in vertical context)
            if (detectReelsInteractionUI(root)) {
                Log.d(TAG, "✅ Instagram Reels detected via interaction UI")
                root.recycle()
                return true
            }
            
            root.recycle()
            Log.d(TAG, "❌ Instagram Reels not detected - user is in main feed or other Instagram section")
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting Instagram Reels", e)
            return false
        }
    }
    
    private fun detectActiveReelsVideoPlayer(root: AccessibilityNodeInfo): Boolean {
        try {
            // Look for video players that are in portrait mode with typical Reels layout
            return findActiveVideoPlayers(root, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting active video player", e)
            return false
        }
    }
    
    private fun findActiveVideoPlayers(node: AccessibilityNodeInfo, depth: Int): Boolean {
        if (depth > 8) return false
        
        try {
            val className = node.className?.toString() ?: ""
            val viewId = node.viewIdResourceName ?: ""
            
            // Look for video surface that's likely a reel
            if ((className.contains("Video") || className.contains("Surface") || 
                 className.contains("TextureView") || viewId.contains("video")) && 
                 node.isVisibleToUser) {
                
                // Check if it's in portrait orientation (typical for reels)
                val bounds = android.graphics.Rect()
                node.getBoundsInScreen(bounds)
                if (bounds.height() > bounds.width() * 1.3) { // Portrait aspect ratio
                    
                    // Verify it's in a reels context by checking parent containers
                    val parent = node.parent
                    if (parent != null) {
                        val parentViewId = parent.viewIdResourceName ?: ""
                        val isInReelsContext = parentViewId.contains("clips") || 
                                             parentViewId.contains("reel") ||
                                             hasReelsParentContainer(parent)
                        parent.recycle()
                        if (isInReelsContext) {
                            return true
                        }
                    }
                }
            }
            
            // Check children
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    val found = findActiveVideoPlayers(child, depth + 1)
                    child.recycle()
                    if (found) return true
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error in active video player search", e)
            return false
        }
    }
    
    private fun hasReelsParentContainer(node: AccessibilityNodeInfo): Boolean {
        try {
            var current = node.parent
            var depth = 0
            
            while (current != null && depth < 5) {
                val viewId = current.viewIdResourceName ?: ""
                val className = current.className?.toString() ?: ""
                
                if (viewId.contains("clips_viewer") || 
                    viewId.contains("reel_viewer") ||
                    (className.contains("ViewPager") && viewId.contains("clips"))) {
                    current.recycle()
                    return true
                }
                
                val next = current.parent
                current.recycle()
                current = next
                depth++
            }
            current?.recycle()
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking parent containers", e)
            return false
        }
    }
    
    private fun detectReelsInteractionUI(root: AccessibilityNodeInfo): Boolean {
        try {
            // Look for the specific interaction buttons that appear when viewing reels
            val likeButtons = root.findAccessibilityNodeInfosByText("Like") + 
                             root.findAccessibilityNodeInfosByText("Unlike")
            val shareButtons = root.findAccessibilityNodeInfosByText("Share") +
                              root.findAccessibilityNodeInfosByText("Send")
            
            // Only consider it reels if we have interaction UI AND it's in a vertical layout
            if (likeButtons.isNotEmpty() && shareButtons.isNotEmpty()) {
                // Check if these buttons are arranged vertically (typical for reels)
                var hasVerticalLayout = false
                
                for (button in likeButtons + shareButtons) {
                    if (isInVerticalReelsLayout(button)) {
                        hasVerticalLayout = true
                        break
                    }
                }
                
                // Clean up
                (likeButtons + shareButtons).forEach { it.recycle() }
                
                return hasVerticalLayout
            }
            
            (likeButtons + shareButtons).forEach { it.recycle() }
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting interaction UI", e)
            return false
        }
    }
    
    private fun isInVerticalReelsLayout(node: AccessibilityNodeInfo): Boolean {
        try {
            // Check if the button is positioned in the typical right-side vertical layout of reels
            val bounds = android.graphics.Rect()
            node.getBoundsInScreen(bounds)
            
            // Get screen dimensions (approximate)
            val screenHeight = 2400 // Typical phone screen height
            val screenWidth = 1080   // Typical phone screen width
            
            // Check if button is positioned on the right side and in the middle-to-bottom area
            val isRightSide = bounds.centerX() > screenWidth * 0.7  // Right 30% of screen
            val isMiddleToBottom = bounds.centerY() > screenHeight * 0.4 && 
                                   bounds.centerY() < screenHeight * 0.9
            
            return isRightSide && isMiddleToBottom
            
        } catch (e: Exception) {
            Log.e(TAG, "Error checking vertical layout", e)
            return false
        }
    }

    private fun detectSnapchatSpotlight(): Boolean {
        // Similar detection logic for Snapchat Spotlight
        return false // Placeholder
    }

    private fun blockShortFormContent(packageName: String) {
        try {
            Log.d(TAG, "Short-form content detected for $packageName - showing blocking overlay")
            
            // Send challenge_failed event for survival mode
            sendChallengeFailedEvent(packageName, "short_form_content")
            
            when (packageName) {
                "com.google.android.youtube" -> {
                    blockYouTubeShortsWithOverlay()
                }
                "com.instagram.android" -> {
                    Log.d(TAG, "📸 Instagram Reels detected - blocking with navigation")
                    blockInstagramReelsWithOverlay()
                }
                "com.zhiliaoapp.musically" -> { // TikTok
                    // For TikTok, show overlay (entire app is short-form)
                    showShortFormBlockOverlay(packageName)
                }
                else -> {
                    // For other apps, just show overlay
                    showShortFormBlockOverlay(packageName)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking short-form content", e)
        }
    }
    
    private fun blockYouTubeShortsWithOverlay() {
        try {
            Log.d(TAG, "🎯 YouTube Shorts detected - showing overlay and navigating to Home")
            
            // STEP 1: Navigate to YouTube Home immediately
            navigateToYouTubeHomeImmediate()
            
            // STEP 2: Show simple native overlay (5 second duration with auto-dismiss)
            Handler(Looper.getMainLooper()).postDelayed({
                SimpleBlockOverlay.show(
                    context = applicationContext,
                    platform = "YouTube",
                    contentType = "shorts",
                    onDismiss = {
                        Log.d(TAG, "✅ Overlay dismissed, user is on YouTube Home")
                    }
                )
            }, 200) // Brief delay to let navigation complete
            
        } catch (e: Exception) {
            Log.e(TAG, "Error showing YouTube Shorts overlay", e)
        }
    }
    
    private fun showShortsBlockingOverlay() {
        try {
            overlayLauncher.showShortsBlockOverlay(
                packageName = "com.google.android.youtube",
                appName = "YouTube",
                contentType = "shorts"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing Shorts blocking overlay", e)
        }
    }

    private fun clickYouTubeHomeTab(): Boolean {
        try {
            val rootNode = rootInActiveWindow ?: return false
            val success = findAndClickHomeTab(rootNode)
            rootNode.recycle()
            return success
        } catch (e: Exception) {
            Log.e(TAG, "Error clicking YouTube Home tab", e)
            return false
        }
    }

    private fun findAndClickHomeTab(node: AccessibilityNodeInfo, depth: Int = 0): Boolean {
        try {
            if (depth > 6) return false
            
            val nodeText = node.text?.toString() ?: ""
            val contentDescription = node.contentDescription?.toString() ?: ""
            
            // Look for Home tab indicators
            if ((nodeText.equals("Home", ignoreCase = true) ||
                 contentDescription.contains("Home", ignoreCase = true)) &&
                node.isClickable) {
                
                Log.d(TAG, "Found Home tab, attempting click")
                return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            
            // Check child nodes
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    if (findAndClickHomeTab(child, depth + 1)) {
                        child.recycle()
                        return true
                    }
                    child.recycle()
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error finding Home tab at depth $depth", e)
            return false
        }
    }

    private fun showWebsiteBlockOverlay(url: String, appName: String) {
        try {
            Log.d(TAG, "🌐 Showing website block overlay for: $url in $appName")
            SimpleBlockOverlay.showWebsite(
                context = applicationContext,
                url = url,
                reason = "This website is blocked by your focus settings"
            ) {
                Log.d(TAG, "✅ Website block overlay dismissed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing website block overlay", e)
        }
    }

    private fun showShortFormBlockOverlay(packageName: String) {
        try {
            val appName = getAppName(packageName)
            val contentType = when (packageName) {
                "com.google.android.youtube" -> "shorts"
                "com.instagram.android" -> "reels"
                "com.zhiliaoapp.musically" -> "tiktok"
                "com.facebook.katana" -> "reels"
                else -> "shorts"
            }
            overlayLauncher.showShortsBlockOverlay(
                packageName = packageName,
                appName = appName,
                contentType = contentType
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing short-form block overlay", e)
        }
    }
    
    private fun showBrowserShortsBlockOverlay(packageName: String, url: String) {
        try {
            Log.d(TAG, "🌐 Showing browser shorts block overlay for: $url in $packageName")
            SimpleBlockOverlay.showWebsite(
                context = applicationContext,
                url = url,
                reason = "Short-form content blocked to help you stay focused"
            ) {
                Log.d(TAG, "✅ Browser shorts block overlay dismissed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing browser shorts block overlay", e)
        }
    }

    private fun showAutoClosingShortsOverlay() {
        try {
            // Use OverlayLauncher to show shorts block overlay
            overlayLauncher.showShortsBlockOverlay(
                packageName = "com.google.android.youtube",
                appName = "YouTube",
                contentType = "shorts"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing auto-closing Shorts overlay", e)
        }
    }

    private fun navigateToYouTubeHomeWithContext() {
        try {
            Log.d(TAG, "🏠 Attempting to navigate to YouTube Home tab with context awareness")
            
            // Try immediate navigation first
            var success = attemptYouTubeNavigation()
            
            if (!success) {
                // If failed, try dismissing overlay and then navigate
                Log.d(TAG, "🔄 Initial navigation failed, trying alternative approach...")
                
                // Use back action to potentially dismiss overlay
                performGlobalAction(GLOBAL_ACTION_BACK)
                
                // Wait a bit for overlay to dismiss and YouTube to be visible
                Handler(Looper.getMainLooper()).postDelayed({
                    success = attemptYouTubeNavigation()
                    
                    if (!success) {
                        Log.w(TAG, "⚠️ All navigation methods failed, using fallback")
                        // Fallback: Multiple back actions to try to get to YouTube home
                        performGlobalAction(GLOBAL_ACTION_BACK)
                        Handler(Looper.getMainLooper()).postDelayed({
                            performGlobalAction(GLOBAL_ACTION_BACK)
                        }, 200)
                    }
                }, 500)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during contextual navigation", e)
        }
    }

    private fun attemptYouTubeNavigation(): Boolean {
        try {
            // Method 1: Try to get YouTube-specific window nodes
            val windows = windows
            Log.d(TAG, "🔍 Found ${windows?.size ?: 0} accessibility windows")
            
            windows?.forEach { window ->
                val packageName = window.root?.packageName?.toString()
                Log.d(TAG, "   📱 Window: $packageName")
                
                if (packageName == "com.google.android.youtube") {
                    Log.d(TAG, "   🎯 Found YouTube window, attempting navigation...")
                    val rootNode = window.root
                    if (rootNode != null) {
                        val success = findAndClickHomeTabEnhanced(rootNode)
                        if (success) {
                            Log.d(TAG, "   ✅ Successfully navigated via YouTube window")
                            return true
                        }
                    }
                }
            }
            
            // Method 2: Try regular root node approach
            Log.d(TAG, "🔍 Trying regular root node approach...")
            val rootNode = rootInActiveWindow
            if (rootNode != null) {
                val packageName = rootNode.packageName?.toString()
                Log.d(TAG, "   📱 Root package: $packageName")
                
                if (packageName == "com.google.android.youtube") {
                    val success = findAndClickHomeTabEnhanced(rootNode)
                    rootNode.recycle()
                    return success
                } else {
                    Log.w(TAG, "   ⚠️ Root node is not YouTube (it's $packageName)")
                    rootNode.recycle()
                }
            }
            
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in YouTube navigation attempt", e)
            return false
        }
    }

    private fun attemptHomeNavigation(): Boolean {
        try {
            val rootNode = rootInActiveWindow ?: run {
                Log.w(TAG, "❌ No root node available for navigation")
                return false
            }
            
            val packageName = rootNode.packageName?.toString()
            Log.d(TAG, "🔍 Root node package: $packageName")
            
            if (packageName != "com.google.android.youtube") {
                Log.w(TAG, "❌ Root node is not YouTube, it's $packageName")
                rootNode.recycle()
                return false
            }
            
            Log.d(TAG, "🔍 Root node found for YouTube, searching for Home tab...")
            
            // Try multiple methods to find and click Home tab
            val success = findAndClickHomeTabEnhanced(rootNode)
            
            rootNode.recycle()
            return success
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in home navigation attempt", e)
            return false
        }
    }

    private fun findAndClickHomeTabEnhanced(rootNode: AccessibilityNodeInfo): Boolean {
        try {
            Log.d(TAG, "🔍 Starting enhanced Home tab search with immediate access...")
            
            // Method 1: Find bottom navigation container by common YouTube IDs
            val bottomNavIds = listOf(
                "com.google.android.youtube:id/bottom_navigation_container",
                "com.google.android.youtube:id/tab_layout",
                "com.google.android.youtube:id/navigation_bar",
                "com.google.android.youtube:id/bottom_navigation",
                "com.google.android.youtube:id/bottom_bar_container",
                "com.google.android.youtube:id/navigation_panel"
            )
            
            Log.d(TAG, "🔍 Method 1: Searching for bottom navigation containers...")
            for (navId in bottomNavIds) {
                Log.d(TAG, "   🔎 Trying navigation ID: $navId")
                val navContainers = rootNode.findAccessibilityNodeInfosByViewId(navId)
                Log.d(TAG, "   📊 Found ${navContainers.size} containers for $navId")
                
                for (container in navContainers) {
                    if (clickHomeInContainer(container)) {
                        Log.d(TAG, "   ✅ Successfully clicked Home via container $navId")
                        container.recycle()
                        navContainers.forEach { it.recycle() }
                        return true
                    }
                    container.recycle()
                }
                navContainers.forEach { it.recycle() }
            }
            
            // Method 2: Search for Home button by specific YouTube Home tab IDs
            Log.d(TAG, "🔍 Method 2: Searching for specific Home tab IDs...")
            val homeTabIds = listOf(
                "com.google.android.youtube:id/tab_home",
                "com.google.android.youtube:id/home_tab",
                "com.google.android.youtube:id/bottom_navigation_home",
                "com.google.android.youtube:id/pivot_home",
                "com.google.android.youtube:id/tab_activity_home"
            )
            
            for (homeId in homeTabIds) {
                Log.d(TAG, "   🔎 Trying home tab ID: $homeId")
                val homeNodes = rootNode.findAccessibilityNodeInfosByViewId(homeId)
                Log.d(TAG, "   📊 Found ${homeNodes.size} nodes for $homeId")
                
                for (homeNode in homeNodes) {
                    if (homeNode.isClickable && homeNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                        Log.d(TAG, "   ✅ Clicked Home tab using ID: $homeId")
                        homeNode.recycle()
                        homeNodes.forEach { it.recycle() }
                        return true
                    }
                    homeNode.recycle()
                }
                homeNodes.forEach { it.recycle() }
            }
            
            // Method 3: Search for Home button by text/content description
            Log.d(TAG, "🔍 Method 3: Searching for Home button by text...")
            if (findAndClickByText(rootNode, listOf("Home", "홈", "Início", "Accueil", "Inicio", "Beranda"))) {
                Log.d(TAG, "   ✅ Successfully clicked Home by text")
                return true
            }
            
            // Method 4: Aggressive debug - let's see what's actually available
            Log.d(TAG, "🔍 Method 4: Debug analysis of available nodes...")
            debugAvailableNodes(rootNode, 0, 4) // Deeper search since we have access
            
            Log.w(TAG, "❌ All Home tab search methods failed")
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in enhanced Home tab search", e)
            return false
        }
    }

    private fun clickHomeInContainer(container: AccessibilityNodeInfo): Boolean {
        try {
            Log.d(TAG, "🔍 Analyzing container for Home button...")
            // Look for Home button within this container
            for (i in 0 until container.childCount) {
                val child = container.getChild(i)
                if (child != null) {
                    val text = child.text?.toString() ?: ""
                    val contentDesc = child.contentDescription?.toString() ?: ""
                    val className = child.className?.toString() ?: ""
                    val viewId = child.viewIdResourceName ?: ""
                    
                    Log.d(TAG, "   🔎 Child $i: text='$text', desc='$contentDesc', class='$className', id='$viewId', clickable=${child.isClickable}")
                    
                    // Check if this child is the Home button
                    if ((text.equals("Home", ignoreCase = true) || 
                         contentDesc.contains("Home", ignoreCase = true) ||
                         contentDesc.contains("홈", ignoreCase = true)) && // Korean
                        child.isClickable) {
                        
                        Log.d(TAG, "   🎯 Found potential Home button, attempting click...")
                        if (child.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                            Log.d(TAG, "   ✅ Clicked Home tab in bottom navigation")
                            child.recycle()
                            return true
                        }
                    }
                    
                    // Recursively check child nodes
                    if (clickHomeInContainer(child)) {
                        child.recycle()
                        return true
                    }
                    
                    child.recycle()
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error clicking Home in container", e)
            return false
        }
    }

    private fun findAndClickByText(node: AccessibilityNodeInfo, searchTexts: List<String>, depth: Int = 0): Boolean {
        try {
            if (depth > 6) return false // Limit search depth
            
            val nodeText = node.text?.toString() ?: ""
            val contentDesc = node.contentDescription?.toString() ?: ""
            
            // Check if current node matches any search text
            for (searchText in searchTexts) {
                if ((nodeText.equals(searchText, ignoreCase = true) || 
                     contentDesc.contains(searchText, ignoreCase = true)) &&
                    node.isClickable) {
                    
                    if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                        Log.d(TAG, "✅ Clicked Home tab by text: $searchText")
                        return true
                    }
                }
            }
            
            // Search child nodes
            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    if (findAndClickByText(child, searchTexts, depth + 1)) {
                        child.recycle()
                        return true
                    }
                    child.recycle()
                }
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error searching by text", e)
            return false
        }
    }

    private fun debugAvailableNodes(node: AccessibilityNodeInfo, depth: Int = 0, maxDepth: Int = 3) {
        try {
            if (depth > maxDepth) return
            
            val indent = "  ".repeat(depth)
            val className = node.className?.toString() ?: "null"
            val text = node.text?.toString() ?: ""
            val contentDesc = node.contentDescription?.toString() ?: ""
            val viewId = node.viewIdResourceName ?: ""
            val isClickable = node.isClickable
            val packageName = node.packageName?.toString() ?: ""
            
            // Log ALL nodes at top level, and interesting nodes at deeper levels
            if (depth == 0) {
                Log.d(TAG, "${indent}🔍 ROOT Node: package=$packageName, class=$className, text='$text', desc='$contentDesc', id='$viewId', clickable=$isClickable")
            } else if (text.isNotEmpty() || contentDesc.isNotEmpty() || viewId.contains("nav") || 
                viewId.contains("tab") || viewId.contains("bottom") || className.contains("Tab") ||
                text.contains("Home", ignoreCase = true) || contentDesc.contains("Home", ignoreCase = true) ||
                viewId.contains("home") || isClickable) {
                
                Log.d(TAG, "${indent}🔍 Node: class=$className, text='$text', desc='$contentDesc', id='$viewId', clickable=$isClickable")
            }
            
            // Show more nodes if we're not finding what we expect
            if (depth <= 1) {
                for (i in 0 until minOf(node.childCount, 10)) { // Limit to first 10 children
                    val child = node.getChild(i)
                    if (child != null) {
                        debugAvailableNodes(child, depth + 1, maxDepth)
                        child.recycle()
                    }
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in debug node analysis at depth $depth", e)
        }
    }

    private fun navigateToYouTubeHomeImmediate(): Boolean {
        try {
            Log.d(TAG, "🏠 Immediate navigation attempt to YouTube Home (while YouTube is accessible)")
            
            // Try to get YouTube accessibility tree immediately
            val rootNode = rootInActiveWindow
            if (rootNode != null) {
                val packageName = rootNode.packageName?.toString()
                Log.d(TAG, "🔍 Current root package: $packageName")
                
                if (packageName == "com.google.android.youtube") {
                    Log.d(TAG, "✅ YouTube is accessible, attempting navigation...")
                    val success = findAndClickHomeTabEnhanced(rootNode)
                    rootNode.recycle()
                    
                    if (success) {
                        Log.d(TAG, "✅ Successfully navigated to Home before overlay")
                        return true
                    } else {
                        Log.w(TAG, "⚠️ Navigation failed but YouTube was accessible")
                    }
                } else {
                    Log.w(TAG, "⚠️ YouTube not accessible yet (package: $packageName)")
                    rootNode.recycle()
                }
            } else {
                Log.w(TAG, "❌ No root node available")
            }
            
            // Fallback: Try using windows method
            val windows = windows
            if (windows != null) {
                for (window in windows) {
                    val windowPackage = window.root?.packageName?.toString()
                    if (windowPackage == "com.google.android.youtube") {
                        Log.d(TAG, "🎯 Found YouTube window, trying navigation...")
                        val rootNode = window.root
                        if (rootNode != null) {
                            val success = findAndClickHomeTabEnhanced(rootNode)
                            if (success) {
                                Log.d(TAG, "✅ Successfully navigated via YouTube window")
                                return true
                            }
                        }
                    }
                }
            }
            
            Log.w(TAG, "❌ Immediate navigation failed - YouTube not accessible")
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in immediate YouTube navigation", e)
            return false
        }
    }

    private fun showSuccessNavigationOverlay() {
        try {
            // Use OverlayLauncher to show shorts block overlay
            overlayLauncher.showShortsBlockOverlay(
                packageName = "com.google.android.youtube",
                appName = "YouTube",
                contentType = "shorts"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing success navigation overlay", e)
        }
    }

    private fun showAppLimitExceededOverlay(packageName: String) {
        try {
            val appName = getAppName(packageName)
            val limitMs = com.example.pace.services.limits.LockInNativeLimitsHolder.getLimitMs(packageName)
            
            if (limitMs == null || limitMs <= 0) {
                Log.w(TAG, "No limit found for $packageName")
                return
            }
            
            val limitMinutes = (limitMs / 60_000).toInt()
            
            Log.d(TAG, "📱 Showing app limit overlay for $appName ($limitMinutes min limit)")
            
            // Show simple native overlay with 5 second countdown
            SimpleBlockOverlay.show(
                context = applicationContext,
                platform = appName,
                contentType = "Time limit exceeded",
                message = "⏰ Daily Limit: $limitMinutes minutes",
                durationSeconds = 5,
                onDismiss = {
                    Log.d(TAG, "✅ App limit overlay dismissed")
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing app limit overlay", e)
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

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility Service Interrupted")
    }
    
    /**
     * Set the MethodChannel for sending limit reached events to Flutter
     * Called from MainActivity after Flutter engine is ready
     */
    fun setLimitEventsChannel(channel: MethodChannel) {
        this.limitEventsChannel = channel
        Log.d(TAG, "Limit events channel set")
    }
    
    /**
     * Get the AppLimitTracker instance for usage queries from MainActivity
     */
    fun getAppLimitTracker(): AppLimitTracker {
        return appLimitTracker
    }

    override fun onUnbind(intent: Intent?): Boolean {
        isServiceRunning = false
        instance = null
        lastCheckedUrl = null
        currentForegroundApp = null
        lastUserApp = null
        
        // Cleanup tracker
        appLimitTracker.cleanup()
        
        // Stop periodic limit checking
        stopPeriodicLimitCheck()
        
        // Stop usage tracking
        usageCheckHandler.removeCallbacks(usageCheckRunnable)
        
        // Stop shorts detection handler
        shortsDetectionHandler.removeCallbacksAndMessages(null)
        
        // Stop foreground service
        try {
            stopForeground(true)
            Log.d(TAG, "✅ Foreground service stopped")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping foreground service", e)
        }
        
        Log.d(TAG, "Accessibility Service Disconnected")
        
        // Return true to indicate we want to be restarted if killed
        return true
    }
    
    private fun blockInstagramReelsWithOverlay() {
        try {
            Log.d(TAG, "📸 Instagram Reels detected - showing overlay and navigating to Home")
            
            // STEP 1: Navigate to Instagram Home immediately
            navigateToInstagramHomeImmediate()
            
            // STEP 2: Show simple native overlay (5 second duration with auto-dismiss)
            Handler(Looper.getMainLooper()).postDelayed({
                SimpleBlockOverlay.show(
                    context = applicationContext,
                    platform = "Instagram",
                    contentType = "reels",
                    onDismiss = {
                        Log.d(TAG, "✅ Overlay dismissed, user is on Instagram Home")
                    }
                )
            }, 200) // Brief delay to let navigation complete
            
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking Instagram Reels", e)
            // Fallback to regular overlay
            showShortFormBlockOverlay("com.instagram.android")
        }
    }
    
    private fun navigateToInstagramHomeImmediate(): Boolean {
        try {
            Log.d(TAG, "🔄 Attempting immediate Instagram Home navigation...")
            
            val root = rootInActiveWindow
            if (root == null) {
                Log.e(TAG, "❌ No root window available for Instagram navigation")
                return false
            }
            
            // Check if Instagram is accessible
            if (root.packageName != "com.instagram.android") {
                Log.e(TAG, "❌ Instagram is not accessible for navigation")
                root.recycle()
                return false
            }
            
            Log.d(TAG, "✅ Instagram is accessible, attempting navigation...")
            
            // Find and click Home tab
            val navigationSuccess = findAndClickInstagramHome(root)
            
            root.recycle()
            
            if (navigationSuccess) {
                Log.d(TAG, "✅ Successfully navigated to Instagram Home before overlay")
            } else {
                Log.e(TAG, "❌ Failed to find Instagram Home tab")
            }
            
            return navigationSuccess
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in Instagram Home navigation", e)
            return false
        }
    }
    
    private fun findAndClickInstagramHome(root: AccessibilityNodeInfo): Boolean {
        try {
            Log.d(TAG, "🔍 Searching for Instagram Home tab...")
            
            // Method 1: Try specific Home tab node IDs
            for (nodeId in INSTAGRAM_HOME_NODE_IDS) {
                val homeNodes = root.findAccessibilityNodeInfosByViewId(nodeId)
                if (homeNodes.isNotEmpty()) {
                    for (node in homeNodes) {
                        if (node.isClickable && node.isEnabled) {
                            Log.d(TAG, "✅ Found clickable Home tab via $nodeId")
                            val clicked = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            node.recycle()
                            homeNodes.forEach { it.recycle() }
                            if (clicked) {
                                Log.d(TAG, "✅ Successfully clicked Instagram Home tab")
                                return true
                            }
                        } else {
                            node.recycle()
                        }
                    }
                    homeNodes.forEach { it.recycle() }
                }
            }
            
            // Method 2: Look for Home text/content description
            val homeTextNodes = root.findAccessibilityNodeInfosByText("Home") +
                               root.findAccessibilityNodeInfosByText("🏠") // Home emoji
            
            for (node in homeTextNodes) {
                if (node.isClickable && node.isEnabled) {
                    Log.d(TAG, "✅ Found Home tab via text: ${node.text}")
                    val clicked = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    node.recycle()
                    homeTextNodes.forEach { it.recycle() }
                    if (clicked) {
                        Log.d(TAG, "✅ Successfully clicked Instagram Home via text")
                        return true
                    }
                } else {
                    node.recycle()
                }
            }
            homeTextNodes.forEach { it.recycle() }
            
            // Method 3: Find bottom navigation and look for first tab (usually Home)
            val navNodes = root.findAccessibilityNodeInfosByViewId("com.instagram.android:id/bottom_navigation") +
                          root.findAccessibilityNodeInfosByViewId("com.instagram.android:id/tab_bar")
            
            for (navNode in navNodes) {
                // Look for first clickable child (usually Home)
                for (i in 0 until navNode.childCount) {
                    val child = navNode.getChild(i)
                    if (child != null && child.isClickable && child.isEnabled) {
                        Log.d(TAG, "✅ Found first tab in navigation (likely Home)")
                        val clicked = child.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        child.recycle()
                        navNodes.forEach { it.recycle() }
                        if (clicked) {
                            Log.d(TAG, "✅ Successfully clicked first navigation tab")
                            return true
                        }
                    }
                    child?.recycle()
                }
                navNode.recycle()
            }
            
            Log.e(TAG, "❌ Could not find Instagram Home tab with any method")
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error finding Instagram Home tab", e)
            return false
        }
    }
    
    private fun showSuccessInstagramNavigationOverlay() {
        try {
            // Use OverlayLauncher to show reels block overlay
            overlayLauncher.showShortsBlockOverlay(
                packageName = "com.instagram.android",
                appName = "Instagram",
                contentType = "reels"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing Instagram success overlay", e)
        }
    }
    
    private fun showAutoClosingInstagramOverlay() {
        try {
            // Use OverlayLauncher to show reels block overlay
            overlayLauncher.showShortsBlockOverlay(
                packageName = "com.instagram.android",
                appName = "Instagram",
                contentType = "reels"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing Instagram auto-closing overlay", e)
        }
    }
    
    private fun startForegroundService() {
        try {
            createNotificationChannel()
            val notification = createPersistentNotification()
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            
            Log.d(TAG, "✅ Accessibility service started as foreground service")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting foreground service", e)
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "LockIn protection service running in background"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }
    
    private fun createPersistentNotification(): Notification {
        try {
            // Create intent to open main app when notification is tapped
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent, 
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )
            
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("LockIn Protection Active")
                .setContentText("Blocking distracting content in the background")
                .setSmallIcon(android.R.drawable.ic_menu_view) // Use system icon for now
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setShowWhen(false)
                .setAutoCancel(false)
                .setSilent(true)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "Error creating notification", e)
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("LockIn Protection Active")
                .setContentText("Blocking distracting content")
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .build()
        }
    }
}