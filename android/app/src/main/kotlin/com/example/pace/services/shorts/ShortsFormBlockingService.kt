package com.example.pace.services.shorts

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import com.example.pace.R
import com.example.pace.services.overlay.BlockOverlayActivity
import com.example.pace.services.shared.BlockingConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Enhanced service that reads configuration directly from BlockingConfig
 * and triggers BlockOverlayActivity with correct parameters.
 */
class ShortsBlockingService : AccessibilityService() {

    companion object {
        private const val TAG = "EnhancedShortFormService"
        const val NOTIFICATION_ID = 12345
        const val CHANNEL_ID = "short_form_blocking_channel"
        private const val ACTION_UPDATE_BLOCKS = "com.example.pace.UPDATE_SHORT_FORM_BLOCKS"

        // Platform Selectors for precise detection
        private val YOUTUBE_SHORTS_SELECTORS = listOf(
            "com.google.android.youtube:id/reel_player_page_container",
            "com.google.android.youtube:id/reel_watch_fragment_root",
            "com.google.android.youtube:id/reel_recycler"
        )
        private val INSTAGRAM_REELS_SELECTORS = listOf(
            "com.instagram.android:id/clips_viewer_root",
            "com.instagram.android:id/clips_viewer_fragment_container",
            "com.instagram.android:id/clips_media_view"
        )
        private val FACEBOOK_REELS_SELECTORS = listOf(
            "com.facebook.katana:id/video_player_container",
            "com.facebook.katana:id/reels_viewer"
        )
        
        /**
         * Update short-form blocking configuration
         */
        fun updateBlocks(context: Context, blocks: Map<String, Any>) {
            try {
                Log.d(TAG, "Updating short-form blocks: $blocks")
                // Store the blocks in BlockingConfig using instance method
                val blockingConfig = BlockingConfig.getInstance(context)
                blockingConfig.setPersistentShortFormConfig(blocks)
                
                // Send broadcast to update the service if it's running
                val intent = Intent(ACTION_UPDATE_BLOCKS).setPackage(/* TODO: provide the application ID. For example: */
                    ""
                )
                context.sendBroadcast(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Error updating short-form blocks", e)
            }
        }
    }

    private lateinit var blockingConfig: BlockingConfig
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private var lastDetectionTime = 0L
    private val detectionCooldown = 3000L

    // Receiver to handle real-time updates from MainActivity
    private val configReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d(TAG, "Blocking configuration updated in MainActivity")
            // BlockingConfig reads from SharedPreferences, so it's always fresh.
        }
    }

    //@SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun onServiceConnected() {
        super.onServiceConnected()
        blockingConfig = BlockingConfig.getInstance(this)

        startForeground(NOTIFICATION_ID, createPersistentNotification())
        configureAccessibilityService()

        val filter = IntentFilter(ACTION_UPDATE_BLOCKS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(configReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(configReceiver, filter)
        }
        Log.d(TAG, "Service connected and synchronized with BlockingConfig")
    }

    /**
     * Checks the source of truth (BlockingConfig) for the specific platform
     */
    private fun isPlatformBlocked(platformKey: String): Boolean {
        if (!blockingConfig.isPersistentShortFormBlockingEnabled()) return false

        val configMap = blockingConfig.getPersistentShortFormConfig()
        // platformKey matches the keys used in Flutter: 'youtube_shorts', 'instagram_reels', etc.
        return configMap[platformKey] == true
    }

    @RequiresPermission(Manifest.permission.VIBRATE)
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return

        // Global cooldown to prevent multiple overlays for the same scroll
        if (System.currentTimeMillis() - lastDetectionTime < detectionCooldown) return

        when (packageName) {
            "com.google.android.youtube" -> {
                if (isPlatformBlocked("youtube_shorts")) checkYouTube(event)
            }
            "com.instagram.android" -> {
                if (isPlatformBlocked("instagram_reels")) checkInstagram(event)
            }
            "com.facebook.katana" -> {
                if (isPlatformBlocked("facebook_reels")) checkFacebook(event)
            }
            "com.zhiliaoapp.musically" -> {
                if (isPlatformBlocked("tiktok_videos")) {
                    scope.launch { triggerBlock("TikTok", packageName, "TikTok is blocked!", "home") }
                }
            }
        }
    }

    private fun checkYouTube(event: AccessibilityEvent) {
        handler.postDelayed({
            val root = rootInActiveWindow ?: return@postDelayed
            if (hasTargetNode(root, YOUTUBE_SHORTS_SELECTORS)) {
                scope.launch {
                    triggerBlock("YouTube Shorts", "com.google.android.youtube", "Focus on your goals, not the scroll!", "back")
                }
            }
            root.recycle()
        }, 300)
    }

    private fun checkInstagram(event: AccessibilityEvent) {
        handler.postDelayed({
            val root = rootInActiveWindow ?: return@postDelayed
            if (hasTargetNode(root, INSTAGRAM_REELS_SELECTORS)) {
                scope.launch {
                    triggerBlock("Instagram Reels", "com.instagram.android", "Reels are designed to distract you.", "back")
                }
            }
            root.recycle()
        }, 300)
    }

    private fun checkFacebook(event: AccessibilityEvent) {
        val root = rootInActiveWindow ?: return
        if (hasTargetNode(root, FACEBOOK_REELS_SELECTORS)) {
            scope.launch {
                triggerBlock("Facebook Reels", "com.facebook.katana", "Back to work!", "back")
            }
        }
        root.recycle()
    }

    private fun hasTargetNode(root: AccessibilityNodeInfo, selectors: List<String>): Boolean {
        for (selector in selectors) {
            val nodes = root.findAccessibilityNodeInfosByViewId(selector)
            if (nodes.isNotEmpty()) {
                nodes.forEach { it.recycle() }
                return true
            }
        }
        return false
    }

    @RequiresPermission(Manifest.permission.VIBRATE)
    private suspend fun triggerBlock(title: String, pkg: String, msg: String, action: String) {
        lastDetectionTime = System.currentTimeMillis()

        withContext(Dispatchers.Main) {
            vibrateDevice()

            // Construct intent specifically for BlockOverlayActivity.parseBlockedShortsData()
            val intent = Intent(this@ShortsBlockingService, BlockOverlayActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION

                // Set the type for Flutter routing
                putExtra("overlayType", "blocked_shorts")

                // Map to the keys used in your parseBlockedShortsData()
                putExtra("content_type", title)
                putExtra("package_name", pkg)
                putExtra("educational_message", msg)
                putExtra("session_type", "persistent")
            }
            startActivity(intent)

            // Brief delay so user sees the app before it switches/closes
            delay(150)
            if (action == "home") performGlobalAction(GLOBAL_ACTION_HOME)
            else performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    private fun vibrateDevice() {
        val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 150, 100, 150), -1))
        } else {
            vibrator.vibrate(300)
        }
    }

    private fun createPersistentNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(CHANNEL_ID, "LockIn Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(chan)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Short-form Blocking Active")
            .setContentText("LockIn is protecting your focus.")
            .setSmallIcon(R.drawable.ic_shield) // Ensure this exists (Step 2)
            .setOngoing(true) // This should now resolve with proper import
            .build()
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        try { unregisterReceiver(configReceiver) } catch (e: Exception) {}
        scope.cancel()
        super.onDestroy()
    }

    private fun configureAccessibilityService() {
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            packageNames = arrayOf(
                "com.google.android.youtube",
                "com.instagram.android",
                "com.facebook.katana",
                "com.zhiliaoapp.musically"
            )
            notificationTimeout = 100
        }
        this.serviceInfo = info
    }
}