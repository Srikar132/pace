package com.example.pace.services.focus

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.os.Binder
import android.os.Build
import android.util.Log
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.SurfaceControl
import android.view.SurfaceControlViewHost
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Cover shown over a blocked window (split pane, PiP, freeform) during a focus session.
 *
 * Two implementations, chosen per window:
 *
 * 1. **Attached (Android 14+, preferred).** The cover is a SurfaceControl attached to the blocked window
 *    itself with AccessibilityService.attachAccessibilityOverlayToWindow. The system then moves, grows
 *    and shrinks it together with the window, so there is no chasing, no lag, and the PiP's own menu
 *    (a separate, higher window) draws above it without the cover having to hide.
 * 2. **Floating overlay (fallback, below Android 14).** A TYPE_ACCESSIBILITY_OVERLAY window positioned over
 *    the window's bounds and re-positioned by a tracking loop. Slightly laggy, and hidden while the PiP
 *    menu is open so its buttons stay visible.
 *
 * Touch behaviour: PiP covers are visual only (touches reach the PiP so the system controls work); other
 * covers block touches in that window and offer "Back to Pace".
 *
 * [service] MUST be the AccessibilityService. Main thread only. Colors mirror AppColors in
 * lib/core/theme/app_theme.dart; this view cannot read the Dart theme, so keep the two in sync by hand.
 */
class FocusWindowCover(
    private val service: AccessibilityService,
    private val onBackToPace: () -> Unit,
) {
    private class Attached(val host: SurfaceControlViewHost, val sc: SurfaceControl)

    private class Entry(
        val root: View,
        val title: TextView,
        val compact: Boolean,
        val passTouches: Boolean,
        var appName: String,
        var bounds: WindowBounds,
        var scale: Float,
        val rescale: (Float) -> Unit,
        var hostWidth: Int,
        var hostHeight: Int,
        val attached: Attached? = null,
    )

    private val context: Context = service
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val density = context.resources.displayMetrics.density
    private val entries = mutableMapOf<Int, Entry>()
    private var pipMenuOpen = false

    private companion object {
        const val TAG = "FocusWindowCover"

        /**
         * Android 14+ window-attached overlay: the cover is a layer inside the blocked window itself, so
         * it follows, scales and clips with it and the system's window controls stay usable. Verified on a
         * device for floating windows (Android 15 / ColorOS). Below Android 14, or if attaching fails,
         * the floating overlay is used instead. Set false to force the floating overlay.
         */
        const val USE_ATTACHED_OVERLAY = true
        val BACKGROUND = Color.parseColor("#FF090A0C") // AppColors.background
        val TEXT_PRIMARY = Color.parseColor("#FFF4F5F6") // AppColors.textPrimary
        val TEXT_SECONDARY = Color.parseColor("#FF9298A0") // AppColors.textSecondary
        val BUTTON_FILL = Color.parseColor("#FFD7DCE1") // AppColors.buttonFill
    }

    /**
     * Shows the cover for [windowId], or resizes/repositions it if it is already up. [localWidth]/[localHeight]
     * are the window's own coordinate size (0 if unknown); a window-attached cover must use them, because
     * floating windows are drawn full size and scaled down on screen.
     */
    fun show(
        windowId: Int,
        appName: String,
        bounds: WindowBounds,
        passTouches: Boolean,
        localWidth: Int = 0,
        localHeight: Int = 0,
    ) {
        try {
            val canAttach = USE_ATTACHED_OVERLAY && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            val compact = CoverLayoutPolicy.isCompact(bounds.width, bounds.height, density)
            // Attached covers live in the window's own (unscaled) coordinates; floating ones in screen pixels.
            val scale = if (canAttach) CoverLayoutPolicy.contentScale(bounds.width, localWidth) else 1f
            val hostW = if (canAttach && localWidth > 0) localWidth else bounds.width
            val hostH = if (canAttach && localHeight > 0) localHeight else bounds.height
            val existing = entries[windowId]
            if (existing != null && existing.compact == compact && existing.passTouches == passTouches) {
                existing.appName = appName
                existing.title.text = titleText(appName, compact)
                // A rescale only changes sizes inside the same cover: no rebuild, so no uncovered frame.
                if (Math.abs(existing.scale - scale) >= 0.1f) {
                    existing.rescale(scale)
                    existing.scale = scale
                }
                applyBounds(existing, bounds, hostW, hostH)
                return
            }
            // New cover, or the window changed kind / crossed the compact threshold. Build and attach the
            // replacement FIRST and only then drop the old one, so the window is never left uncovered.
            var view = buildView(appName, compact, passTouches, scale)
            val attached = if (canAttach) tryAttach(windowId, view.root, hostW, hostH) else null
            // A failed attach leaves the first view owned by the released host: build a fresh one.
            var usedScale = scale
            if (canAttach && attached == null) {
                usedScale = 1f
                view = buildView(appName, compact, passTouches, usedScale)
            }
            val entry = Entry(
                view.root, view.title, compact, passTouches, appName, bounds,
                usedScale, view.rescale, hostW, hostH, attached,
            )
            if (attached == null) {
                applyMenuVisibility(entry)
                windowManager.addView(entry.root, layoutParams(bounds, passTouches))
            }
            entries[windowId] = entry
            existing?.let { detach(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error showing cover for window $windowId", e)
        }
    }

    /** Called by the tracking loop. Attached covers only need a resize; floating ones also move. */
    fun updateBounds(windowId: Int, bounds: WindowBounds) {
        val entry = entries[windowId] ?: return
        // An attached cover already follows its window; its size is refreshed from full snapshots.
        if (entry.attached != null) return
        try {
            if (CoverLayoutPolicy.isCompact(bounds.width, bounds.height, density) != entry.compact) {
                show(windowId, entry.appName, bounds, entry.passTouches)
            } else {
                applyBounds(entry, bounds, bounds.width, bounds.height)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating cover for window $windowId", e)
        }
    }

    /** Floating (fallback) PiP covers hide while the PiP's menu is open. Attached covers never need to. */
    fun setPipMenuOpen(open: Boolean) {
        if (pipMenuOpen == open) return
        pipMenuOpen = open
        entries.values.forEach { applyMenuVisibility(it) }
    }

    private fun applyMenuVisibility(entry: Entry) {
        if (entry.attached != null || !entry.passTouches) return
        entry.root.visibility = if (pipMenuOpen) View.INVISIBLE else View.VISIBLE
    }

    private fun applyBounds(entry: Entry, bounds: WindowBounds, hostWidth: Int, hostHeight: Int) {
        val moved = entry.bounds.left != bounds.left || entry.bounds.top != bounds.top
        val screenResized = entry.bounds.width != bounds.width || entry.bounds.height != bounds.height
        entry.bounds = bounds
        val attached = entry.attached
        if (attached != null) {
            // Position follows the window automatically; only the host surface size must be told.
            if (entry.hostWidth != hostWidth || entry.hostHeight != hostHeight) {
                entry.hostWidth = hostWidth
                entry.hostHeight = hostHeight
                attached.host.relayout(hostWidth, hostHeight)
            }
        } else if (moved || screenResized) {
            windowManager.updateViewLayout(entry.root, layoutParams(bounds, entry.passTouches))
        }
    }

    /** Removes every cover whose window is not in [windowIds] anymore. */
    fun retainOnly(windowIds: Set<Int>) {
        entries.keys.filter { it !in windowIds }.forEach { remove(it) }
    }

    fun hasCovers(): Boolean = entries.isNotEmpty()

    fun removeAll() {
        entries.keys.toList().forEach { remove(it) }
    }

    private fun remove(windowId: Int) {
        val entry = entries.remove(windowId) ?: return
        detach(entry)
    }

    private fun detach(entry: Entry) {
        try {
            val attached = entry.attached
            if (attached != null) {
                SurfaceControl.Transaction().reparent(attached.sc, null).apply()
                attached.host.release()
            } else {
                windowManager.removeViewImmediate(entry.root)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error removing cover", e)
        }
    }

    // ---- attached (Android 14+)

    /** Returns null if attaching is impossible so the caller falls back to the floating overlay. */
    private fun tryAttach(windowId: Int, view: View, width: Int, height: Int): Attached? {
        return try {
            val display = context.getSystemService(DisplayManager::class.java)
                .getDisplay(Display.DEFAULT_DISPLAY)
            val host = SurfaceControlViewHost(context, display, Binder())
            host.setView(view, width, height)
            val sc = host.surfacePackage?.surfaceControl
            if (sc == null) {
                host.release()
                Log.w(TAG, "No SurfaceControl from host, using floating overlay")
                null
            } else {
                service.attachAccessibilityOverlayToWindow(windowId, sc)
                // The root surface of a SurfaceControlViewHost starts hidden: attaching alone shows nothing.
                SurfaceControl.Transaction().setVisibility(sc, true).apply()
                Log.d(TAG, "Attached cover to window $windowId (host ${width}x$height)")
                Attached(host, sc)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Attach failed for window $windowId, using floating overlay", e)
            null
        }
    }

    // ---- floating overlay (fallback)

    private fun layoutParams(bounds: WindowBounds, passTouches: Boolean) = WindowManager.LayoutParams(
        bounds.width,
        bounds.height,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            (if (passTouches) WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE else 0),
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = bounds.left
        y = bounds.top
    }

    // ---- view

    private class BuiltView(val root: View, val title: TextView, val rescale: (Float) -> Unit)

    private fun titleText(appName: String, compact: Boolean) =
        if (compact) "$appName\nblocked" else "$appName is blocked"

    private fun buildView(appName: String, compact: Boolean, passTouches: Boolean, scale: Float): BuiltView {
        val title = TextView(context).apply {
            text = titleText(appName, compact)
            setTextColor(TEXT_PRIMARY)
            gravity = Gravity.CENTER
            if (compact) {
                maxLines = 3
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
                )
            }
        }
        var subtitle: TextView? = null
        var button: Button? = null
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(BACKGROUND)
            addView(title)
            if (!compact) {
                subtitle = TextView(context).apply {
                    text = "Focus session in progress"
                    setTextColor(TEXT_SECONDARY)
                    gravity = Gravity.CENTER
                }
                addView(subtitle)
                if (!passTouches) {
                    button = Button(context).apply {
                        text = "Back to Pace"
                        isAllCaps = false
                        setTextColor(BACKGROUND)
                        background = GradientDrawable().apply { setColor(BUTTON_FILL) }
                        setOnClickListener { onBackToPace() }
                    }
                    addView(button)
                }
            }
        }

        // All sizes are multiplied by [sc] so text stays readable when the window shrinks the cover.
        // Re-runnable in place, which lets a resize rescale the cover without ever rebuilding it.
        val rescale: (Float) -> Unit = { sc ->
            fun px(v: Int) = (dp(v) * sc).toInt()
            fun sp(v: Float) = v * sc
            val pad = if (compact) px(6) else px(16)
            root.setPadding(pad, pad, pad, pad)
            if (compact) {
                // Fill the tiny window and shrink the text to fit instead of clipping it.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    title.setAutoSizeTextTypeUniformWithConfiguration(
                        sp(8f).toInt().coerceAtLeast(1), sp(14f).toInt().coerceAtLeast(2), 1,
                        TypedValue.COMPLEX_UNIT_SP,
                    )
                } else {
                    title.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp(11f))
                }
            } else {
                title.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp(20f))
            }
            subtitle?.apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, sp(14f))
                setPadding(0, px(8), 0, if (passTouches) 0 else px(24))
            }
            button?.apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, sp(14f))
                (background as? GradientDrawable)?.cornerRadius = px(24).toFloat()
            }
        }
        rescale(scale)
        return BuiltView(root, title, rescale)
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics,
        ).toInt()
}
