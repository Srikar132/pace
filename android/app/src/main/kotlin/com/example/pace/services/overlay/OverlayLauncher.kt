package com.example.pace.services.overlay

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/**
 * OverlayLauncher - Single entry point for all block overlays
 *
 * RESPONSIBILITIES:
 * - Launch BlockOverlayActivity with appropriate data
 * - Handle overlay priority (Focus > Limits > Shorts > Websites)
 * - Debounce rapid overlay requests
 * - Manage Intent creation
 *
 * OVERLAY TYPES:
 * - blocked_app (Focus session)
 * - app_limit (Daily/weekly limit exceeded)
 * - blocked_shorts (Short-form content)
 * - blocked_website (Blocked website)
 * - blocked_notification (Notification blocked)
 */
class OverlayLauncher private constructor(private val context: Context) {

    companion object {
        private const val TAG = "OverlayLauncher"
        private const val DEBOUNCE_INTERVAL = 1500L // 1.5 seconds

        @Volatile
        private var INSTANCE: OverlayLauncher? = null

        fun getInstance(context: Context): OverlayLauncher {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: OverlayLauncher(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }

    // Debouncing
    private var lastOverlayTime = 0L
    private var lastOverlayPackage = ""

    // Priority levels (higher = more important)
    private val overlayPriority = mapOf(
        "blocked_app" to 100,        // Focus session - highest priority
        "app_limit" to 80,            // App limits
        "blocked_shorts" to 60,       // Short-form content
        "blocked_website" to 40,      // Websites
        "blocked_notification" to 20  // Notifications
    )

    // ==========================================
    // FOCUS SESSION BLOCKING
    // ==========================================

    fun showFocusBlockOverlay(
        packageName: String,
        appName: String,
        sessionData: Map<String, Any>?
    ) {
        if (shouldDebounce(packageName)) {
            Log.d(TAG, "⏭️ Debouncing overlay for $packageName")
            return
        }

        Log.d(TAG, "🚫 Showing focus block overlay for $appName")

        val intent = Intent(context, BlockOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            // Overlay type
            putExtra("overlayType", "blocked_app")

            // App data
            putExtra("packageName", packageName)
            putExtra("appName", appName)

            // Session data
            if (sessionData != null) {
                putExtra("sessionActive", sessionData["isActive"] as? Boolean ?: false)
                putExtra("sessionType", sessionData["sessionType"] as? String ?: "")
                putExtra("elapsedMinutes", sessionData["elapsedMinutes"] as? Int ?: 0)
                putExtra("plannedDuration", sessionData["plannedDuration"] as? Int ?: 0)
            }

            // Block reason
            putExtra("blockReason", "This app is blocked during your focus session")
            putExtra("blockType", "focus_session")
        }

        launchOverlay(intent, packageName)
    }

    // ==========================================
    // APP LIMIT BLOCKING
    // ==========================================

    fun showAppLimitOverlay(
        packageName: String,
        appName: String,
        usedMinutes: Int,
        limitMinutes: Int
    ) {
        if (shouldDebounce(packageName)) {
            Log.d(TAG, "⏭️ Debouncing overlay for $packageName")
            return
        }

        Log.d(TAG, "⏰ Showing app limit overlay for $appName")

        val intent = Intent(context, BlockOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            // Overlay type
            putExtra("overlayType", "app_limit")

            // App data - using snake_case keys to match BlockOverlayActivity parser
            putExtra("app_name", appName)
            putExtra("package_name", packageName)

            // Limit data
            putExtra("used_minutes", usedMinutes)
            putExtra("limit_minutes", limitMinutes)
            putExtra("usage_percentage", ((usedMinutes.toFloat() / limitMinutes) * 100).toInt())
            putExtra("limit_type", "daily")
            
            // Reset time calculation
            val hoursUntilReset = getHoursUntilMidnight()
            putExtra("time_until_reset", hoursUntilReset.toLong())
            putExtra("allow_override", false)
        }

        launchOverlay(intent, packageName)
    }

    // ==========================================
    // SHORT-FORM CONTENT BLOCKING
    // ==========================================

    fun showShortsBlockOverlay(
        packageName: String,
        appName: String,
        contentType: String = "shorts"
    ) {
        if (shouldDebounce(packageName)) {
            Log.d(TAG, "⏭️ Debouncing overlay for $packageName")
            return
        }

        Log.d(TAG, "📹 Showing shorts block overlay for $appName")

        val intent = Intent(context, BlockOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            // Overlay type
            putExtra("overlayType", "blocked_shorts")

            // App data - using snake_case keys to match BlockOverlayActivity parser
            putExtra("package_name", packageName)
            putExtra("content_type", contentType)
            
            // Platform detection based on package name
            val platform = when (packageName) {
                "com.google.android.youtube" -> "YouTube"
                "com.instagram.android" -> "Instagram"
                "com.zhiliaoapp.musically" -> "TikTok"
                "com.facebook.katana" -> "Facebook"
                else -> "Unknown"
            }
            putExtra("platform", platform)
            
            // Educational message based on content type
            val educationalMessage = when (contentType) {
                "shorts" -> "YouTube Shorts are designed to keep you scrolling. Take control of your time!"
                "reels" -> "Instagram Reels can be addictive. Focus on what truly matters!"
                "tiktok" -> "TikTok videos are made to hook you. Break free and stay focused!"
                else -> "Short-form content is distracting. You're doing great by staying focused!"
            }
            putExtra("educational_message", educationalMessage)
        }

        launchOverlay(intent, packageName)
    }

    // ==========================================
    // WEBSITE BLOCKING
    // ==========================================

    fun showWebsiteBlockOverlay(
        url: String,
        reason: String = "This website is blocked"
    ) {
        if (shouldDebounce(url)) {
            Log.d(TAG, "⏭️ Debouncing overlay for $url")
            return
        }

        Log.d(TAG, "🌐 Showing website block overlay for $url")

        val intent = Intent(context, BlockOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            // Overlay type
            putExtra("overlayType", "blocked_website")

            // Website data - using snake_case keys to match BlockOverlayActivity parser
            putExtra("domain", extractDomain(url))
            putExtra("full_url", url)
            putExtra("block_reason", reason)
            putExtra("suggestion", "Use this time for something more meaningful and productive")
        }

        launchOverlay(intent, url)
    }

    // ==========================================
    // NOTIFICATION BLOCKING
    // ==========================================

    fun showNotificationBlockOverlay(
        packageName: String,
        appName: String,
        notificationTitle: String
    ) {
        if (shouldDebounce(packageName)) {
            Log.d(TAG, "⏭️ Debouncing overlay for $packageName")
            return
        }

        Log.d(TAG, "🔔 Showing notification block overlay for $appName")

        val intent = Intent(context, BlockOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            // Overlay type
            putExtra("overlayType", "blocked_notification")

            // App data
            putExtra("packageName", packageName)
            putExtra("appName", appName)
            putExtra("notificationTitle", notificationTitle)

            // Block reason
            putExtra("blockReason", "Notifications from this app are blocked")
            putExtra("blockType", "notification")
        }

        launchOverlay(intent, packageName)
    }

    // ==========================================
    // OVERLAY MANAGEMENT
    // ==========================================

    private fun launchOverlay(intent: Intent, identifier: String) {
        try {
            context.startActivity(intent)
            updateDebounce(identifier)
            Log.d(TAG, "✅ Overlay launched successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error launching overlay", e)
        }
    }

    private fun shouldDebounce(identifier: String): Boolean {
        val currentTime = SystemClock.elapsedRealtime()
        val timeSinceLastOverlay = currentTime - lastOverlayTime

        return if (identifier == lastOverlayPackage && timeSinceLastOverlay < DEBOUNCE_INTERVAL) {
            true
        } else {
            false
        }
    }

    private fun updateDebounce(identifier: String) {
        lastOverlayTime = SystemClock.elapsedRealtime()
        lastOverlayPackage = identifier
    }

    // ==========================================
    // UTILITIES
    // ==========================================

    private fun getHoursUntilMidnight(): Int {
        val calendar = java.util.Calendar.getInstance()
        calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)

        val resetTime = calendar.timeInMillis
        val currentTime = System.currentTimeMillis()
        return ((resetTime - currentTime) / (1000 * 60 * 60)).toInt()
    }

    private fun getResetTimeText(): String {
        val hoursUntilReset = getHoursUntilMidnight()
        return "Resets in $hoursUntilReset hours"
    }

    private fun extractDomain(url: String): String {
        return try {
            val domain = url.replace(Regex("https?://"), "")
                .replace(Regex("/.*"), "")
                .replace("www.", "")
            domain
        } catch (e: Exception) {
            url
        }
    }

    /**
     * Check if overlay permission is granted
     */
    fun hasOverlayPermission(): Boolean {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /**
     * Open overlay permission settings
     */
    fun requestOverlayPermission() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val intent = Intent(
                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:${context.packageName}")
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }
}