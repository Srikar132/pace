package com.example.pace.services


import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.example.pace.services.overlay.BlockOverlayActivity

/**
 * FlutterOverlayManager - Manages Flutter-based overlay activities for different block types
 * Provides beautiful, customizable blocking experiences using Flutter UI
 */
object FlutterOverlayManager {

    private const val TAG = "FlutterOverlayManager"

    // ====================
    // APP BLOCKING OVERLAYS
    // ====================

    /**
     * Show Flutter overlay when an app is blocked
     */
    fun showBlockedAppOverlay(
        context: Context,
        packageName: String,
        appName: String,
        focusTimeMinutes: Int,
        sessionType: String = "timer",
        sessionId: String = "",
        additionalData: Map<String, Any> = emptyMap()
    ) {
        try {
            Log.d(TAG, "Showing blocked app overlay for:  $appName ($packageName)")

            val intent = Intent(context, BlockOverlayActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                putExtra("overlay_type", "blocked_app")
                putExtra("package_name", packageName)
                putExtra("app_name", appName)
                putExtra("focus_time_minutes", focusTimeMinutes)
                putExtra("session_type", sessionType)
                putExtra("session_id", sessionId)

                // Add additional data as bundle
                if (additionalData.isNotEmpty()) {
                    val bundle = Bundle().apply {
                        additionalData.forEach { (key, value) ->
                            when (value) {
                                is String -> putString(key, value)
                                is Int -> putInt(key, value)
                                is Long -> putLong(key, value)
                                is Boolean -> putBoolean(key, value)
                                is Float -> putFloat(key, value)
                                is Double -> putDouble(key, value)
                                else -> putString(key, value.toString())
                            }
                        }
                    }
                    putExtra("additional_data", bundle)
                }
            }

            context.startActivity(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Error showing blocked app overlay", e)
        }
    }

    // ====================
    // SHORT-FORM CONTENT OVERLAYS
    // ====================

    /**
     * Show Flutter overlay when short-form content is blocked (reels, shorts, etc.)
     */
    fun showBlockedShortsOverlay(
        context: Context,
        contentType: String, // "YouTube Shorts", "Instagram Reels", "TikTok", etc.
        packageName: String,
        focusTimeMinutes:  Int,
        sessionType: String = "timer",
        sessionId: String = "",
        educationalMessage: String = ""
    ) {
        try {
            Log.d(TAG, "Showing blocked shorts overlay for: $contentType ($packageName)")

            val intent = Intent(context, BlockOverlayActivity:: class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent. FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("overlay_type", "blocked_shorts")
                putExtra("content_type", contentType)
                putExtra("package_name", packageName)
                putExtra("focus_time_minutes", focusTimeMinutes)
                putExtra("session_type", sessionType)
                putExtra("session_id", sessionId)
                putExtra("educational_message", educationalMessage.ifEmpty {
                    getDefaultShortsMessage(contentType)
                })
            }

            context.startActivity(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Error showing blocked shorts overlay", e)
        }
    }

    // ====================
    // WEBSITE BLOCKING OVERLAYS
    // ====================

    /**
     * Show Flutter overlay when a website is blocked
     */
    fun showBlockedWebsiteOverlay(
        context: Context,
        domain: String,
        fullUrl: String = "",
        focusTimeMinutes: Int,
        sessionType: String = "timer",
        sessionId: String = "",
        blockReason: String = "focus_session"
    ) {
        try {
            Log.d(TAG, "Showing blocked website overlay for:  $domain")

            val intent = Intent(context, BlockOverlayActivity:: class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("overlay_type", "blocked_website")
                putExtra("domain", domain)
                putExtra("full_url", fullUrl)
                putExtra("focus_time_minutes", focusTimeMinutes)
                putExtra("session_type", sessionType)
                putExtra("session_id", sessionId)
                putExtra("block_reason", blockReason)
                putExtra("suggestion", getWebsiteAlternativeSuggestion(domain))
            }

            context.startActivity(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Error showing blocked website overlay", e)
        }
    }

    // ====================
    // APP LIMIT OVERLAYS
    // ====================

    /**
     * Show Flutter overlay when daily app limit is exceeded
     */
    fun showAppLimitOverlay(
        context: Context,
        appName: String,
        packageName: String,
        limitMinutes: Int,
        usedMinutes: Int,
        limitType: String = "daily", // "daily", "weekly"
        timeUntilReset: Long = 0L, // milliseconds until limit resets
        allowOverride: Boolean = false
    ) {
        try {
            Log.d(TAG, "Showing app limit overlay for: $appName (${usedMinutes}/${limitMinutes} minutes)")

            val intent = Intent(context, BlockOverlayActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("overlay_type", "app_limit")
                putExtra("app_name", appName)
                putExtra("package_name", packageName)
                putExtra("limit_minutes", limitMinutes)
                putExtra("used_minutes", usedMinutes)
                putExtra("limit_type", limitType)
                putExtra("time_until_reset", timeUntilReset)
                putExtra("allow_override", allowOverride)
                putExtra("usage_percentage", (usedMinutes. toFloat() / limitMinutes * 100).toInt())
            }

            context.startActivity(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Error showing app limit overlay", e)
        }
    }

    // ====================
    // NOTIFICATION BLOCK OVERLAYS
    // ====================

    /**
     * Show Flutter overlay when notifications are being blocked (optional, for user awareness)
     */
    fun showNotificationBlockOverlay(
        context: Context,
        blockedAppName: String,
        notificationCount: Int,
        focusTimeMinutes: Int,
        sessionId: String = ""
    ) {
        try {
            Log.d(TAG, "Showing notification block overlay for: $blockedAppName ($notificationCount notifications)")

            val intent = Intent(context, BlockOverlayActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("overlay_type", "notification_block")
                putExtra("blocked_app_name", blockedAppName)
                putExtra("notification_count", notificationCount)
                putExtra("focus_time_minutes", focusTimeMinutes)
                putExtra("session_id", sessionId)
            }

            context.startActivity(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Error showing notification block overlay", e)
        }
    }

    // ====================
    // UTILITY METHODS
    // ====================

    /**
     * Get default educational message for different short-form content types
     */
    private fun getDefaultShortsMessage(contentType: String): String {
        return when (contentType. lowercase()) {
            "youtube shorts" -> "YouTube Shorts are designed to be addictive. Try watching educational videos or tutorials instead!"
            "instagram reels" -> "Instagram Reels can consume hours of your time. Consider checking your messages or creating content instead."
            "tiktok" -> "TikTok's algorithm is designed to keep you scrolling. Use this time for something more meaningful!"
            "facebook reels" -> "Facebook Reels can be a major distraction. Try connecting with friends or reading articles instead."
            "snapchat spotlight" -> "Snapchat Spotlight can break your focus. Consider sending messages to friends instead."
            else -> "Short-form content is designed to be addictive and can break your focus. Stay strong!"
        }
    }

    /**
     * Get alternative suggestions for blocked websites
     */
    private fun getWebsiteAlternativeSuggestion(domain: String): String {
        return when {
            domain.contains("facebook") -> "Try reading a book or calling a friend instead"
            domain.contains("twitter") || domain.contains("x.com") -> "Consider journaling or planning your day"
            domain.contains("instagram") -> "Take a walk or do some creative work"
            domain.contains("youtube") -> "Try listening to music or a podcast instead"
            domain.contains("reddit") -> "Read an article or learn something new"
            domain.contains("linkedin") -> "Focus on your current tasks first, then network"
            domain.contains("tiktok") -> "Do something creative or physical instead"
            domain.contains("netflix") || domain.contains("hulu") || domain.contains("prime") -> "Save entertainment for after your focus session"
            domain.contains("news") -> "Stay informed later - focus on your work now"
            domain.contains("shopping") || domain.contains("amazon") -> "Make a shopping list for later"
            else -> "Use this time to focus on your important tasks"
        }
    }

    /**
     * Check if overlays can be displayed
     */
    fun canShowOverlays(context: Context): Boolean {
        return if (android.os.Build. VERSION.SDK_INT >= android.os. Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /**
     * Get motivational message based on focus time
     */
    fun getMotivationalMessage(focusTimeMinutes: Int): String {
        return when {
            focusTimeMinutes < 5 -> "Every journey starts with a single step. Keep going!"
            focusTimeMinutes < 15 -> "Great start! You're building the habit of focus."
            focusTimeMinutes < 30 -> "Excellent! You're in the flow state now."
            focusTimeMinutes < 60 -> "Amazing focus! You're achieving great things."
            focusTimeMinutes < 120 -> "Incredible dedication! You're unstoppable."
            else -> "You're a focus champion! This level of dedication is extraordinary."
        }
    }
}