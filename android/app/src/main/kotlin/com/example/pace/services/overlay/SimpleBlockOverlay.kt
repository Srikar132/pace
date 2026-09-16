package com.example.pace.services.overlay

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import com.example.pace.R
import com.example.pace.MainActivity

/**
 * SimpleBlockOverlay - Native Android overlay that displays on top of apps
 * 
 * Shows a blocking message with a countdown timer bar
 * Auto-dismisses after 5 seconds
 */
class SimpleBlockOverlay(private val context: Context) {

    companion object {
        private const val TAG = "SimpleBlockOverlay"
        private const val DISPLAY_DURATION_MS = 5000L // 5 seconds
        
        @Volatile
        private var currentOverlay: SimpleBlockOverlay? = null
        
        fun show(
            context: Context,
            platform: String,
            contentType: String,
            message: String? = null,
            durationSeconds: Int = 5,
            onDismiss: (() -> Unit)? = null
        ) {
            // Dismiss any existing overlay first
            currentOverlay?.dismiss()
            
            val overlay = SimpleBlockOverlay(context)
            overlay.showOverlay(platform, contentType, message, durationSeconds, onDismiss)
            currentOverlay = overlay
        }
        
        fun showWebsite(
            context: Context,
            url: String,
            reason: String,
            onDismiss: (() -> Unit)? = null
        ) {
            // Dismiss any existing overlay first
            currentOverlay?.dismiss()
            
            val overlay = SimpleBlockOverlay(context)
            overlay.showWebsiteOverlay(url, reason, onDismiss)
            currentOverlay = overlay
        }
    }

    private val windowManager: WindowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var dismissRunnable: Runnable? = null
    private var displayDurationMs: Long = DISPLAY_DURATION_MS

    fun showOverlay(
        platform: String, 
        contentType: String, 
        customMessage: String? = null,
        durationSeconds: Int = 5,
        onDismiss: (() -> Unit)? = null
    ) {
        try {
            displayDurationMs = durationSeconds * 1000L
            
            // Inflate the overlay layout
            overlayView = LayoutInflater.from(context).inflate(R.layout.overlay_block_shorts, null)

            // Configure window parameters
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                },
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
            }

            // Set up the UI
            setupOverlayUI(platform, contentType, customMessage)

            // Add overlay to window
            windowManager.addView(overlayView, params)
            Log.d(TAG, "✅ Overlay displayed for $platform $contentType")

            // Start countdown animation
            startCountdown()

            // Auto-dismiss after duration
            dismissRunnable = Runnable {
                dismiss()
                onDismiss?.invoke()
            }
            handler.postDelayed(dismissRunnable!!, displayDurationMs)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing overlay", e)
        }
    }

    private fun showWebsiteOverlay(url: String, reason: String, onDismiss: (() -> Unit)?) {
        try {
            Log.d(TAG, "🌐 Showing website blocking overlay for: $url")
            
            // Inflate the website overlay layout
            overlayView = LayoutInflater.from(context).inflate(R.layout.overlay_block_website, null)
            
            // Configure overlay window parameters
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                android.graphics.PixelFormat.TRANSLUCENT
            )
            
            // Add overlay to window manager
            windowManager.addView(overlayView, params)
            
            // Setup website-specific UI
            setupWebsiteOverlayUI(url, reason)
            
            // Handle tap to dismiss
            overlayView?.setOnClickListener {
                Log.d(TAG, "👆 Overlay tapped, dismissing...")
                dismiss()
                onDismiss?.invoke()
            }
            
            // No countdown for website overlay - manual dismiss only via Close Tab button or tap
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing website overlay", e)
        }
    }

    private fun setupOverlayUI(platform: String, contentType: String, customMessage: String? = null) {
        overlayView?.apply {
            // Set platform-specific title and progress bar color
            val titleText = findViewById<TextView>(R.id.blockTitle)
            val progressBar = findViewById<ProgressBar>(R.id.countdownProgress)
            val settingsButton = findViewById<View>(R.id.settingsButton)

            // Use custom message if provided, otherwise use default
            if (customMessage != null) {
                // Show custom message in title
                titleText?.text = customMessage.split("\n").firstOrNull() ?: "Time Limit Reached"
                progressBar?.progressTintList = android.content.res.ColorStateList.valueOf(0xFFFF3B30.toInt()) // Red for limit
            } else {
                when (platform.lowercase()) {
                    "youtube" -> {
                        titleText?.text = "YouTube Shorts is Blocked!"
                        progressBar?.progressTintList = android.content.res.ColorStateList.valueOf(0xFFFF6B35.toInt()) // Orange
                    }
                    "instagram" -> {
                        titleText?.text = "Instagram Reels is Blocked!"
                        progressBar?.progressTintList = android.content.res.ColorStateList.valueOf(0xFFE1306C.toInt()) // Instagram pink
                    }
                    "tiktok" -> {
                        titleText?.text = "TikTok is Blocked!"
                        progressBar?.progressTintList = android.content.res.ColorStateList.valueOf(0xFF00F2EA.toInt()) // TikTok cyan
                    }
                    else -> {
                        titleText?.text = "Content Blocked!"
                        progressBar?.progressTintList = android.content.res.ColorStateList.valueOf(0xFFFF6B35.toInt()) // Default orange
                    }
                }
            }

            // Settings button click - open Pace app on block apps tab
            settingsButton?.setOnClickListener {
                openLockInAppSettings()
            }

            // Make overlay dismissible on tap (but not on settings button)
            setOnClickListener {
                dismiss()
            }
        }
    }

    private fun setupWebsiteOverlayUI(url: String, reason: String) {
        overlayView?.apply {
            // Set URL in the blocked message
            val urlText = findViewById<TextView>(R.id.urlText)
            val settingsButton = findViewById<View>(R.id.settingsButton)
            val closeTabButton = findViewById<Button>(R.id.closeTabButton)

            // Format: "discord.com is blocked!"
            urlText?.text = "$url is blocked!"

            // Settings button click - open Pace app
            settingsButton?.setOnClickListener {
                openLockInAppSettings()
            }

            // Close Tab button - dismiss overlay
            closeTabButton?.setOnClickListener {
                Log.d(TAG, "🚪 Close Tab clicked")
                dismiss()
            }

            // Make overlay dismissible on tap anywhere
            setOnClickListener {
                dismiss()
            }
        }
    }

    private fun openLockInAppSettings() {
        try {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                // Add extra to navigate to block apps tab
                putExtra("navigate_to", "block_apps")
            }
            context.startActivity(intent)
            dismiss()
            Log.d(TAG, "✅ Navigating to Pace app settings")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error opening Pace app", e)
        }
    }

    private fun startCountdown(isWebsite: Boolean = false) {
        val progressBar = overlayView?.findViewById<ProgressBar>(R.id.countdownProgress)
        progressBar?.max = 100

        // Animate progress bar from 100 to 0
        val animator = ValueAnimator.ofInt(100, 0).apply {
            duration = displayDurationMs
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Int
                progressBar?.progress = progress
            }
        }
        animator.start()
    }

    fun dismiss() {
        try {
            dismissRunnable?.let { handler.removeCallbacks(it) }
            overlayView?.let { view ->
                windowManager.removeView(view)
                overlayView = null
            }
            if (currentOverlay == this) {
                currentOverlay = null
            }
            Log.d(TAG, "✅ Overlay dismissed")
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing overlay", e)
        }
    }

    fun isShowing(): Boolean = overlayView != null
}
