package com.example.pace.services.focus

/**
 * Pure (no Android types) logic for deciding which visible windows break a focus session.
 * Kept framework-free so it can be unit tested on the JVM.
 */

enum class WindowKind { APPLICATION, PIP, OTHER }

data class WindowBounds(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
}

/** One window as reported by the accessibility service. [packageName] is null when unreadable. */
data class WindowSnapshot(
    val id: Int,
    val packageName: String?,
    val kind: WindowKind,
    /** Where the window is on screen (what the user sees, after any scaling). */
    val bounds: WindowBounds,
    /**
     * The window's own coordinate size (root node boundsInWindow), or 0 if unknown. Floating windows and PiP
     * are drawn at full size and scaled down, so this is larger than [bounds] and is what a window-attached
     * overlay must be sized to.
     */
    val localWidth: Int = 0,
    val localHeight: Int = 0,
)

object VisibleWindowEvaluator {

    /**
     * Windows that show a blocked package. Only APPLICATION and PIP windows count. Windows with an
     * unreadable package are never treated as blocked (logged by the caller, never guessed).
     */
    fun violations(
        windows: List<WindowSnapshot>,
        blockedPackages: Set<String>,
        ownPackage: String,
    ): List<WindowSnapshot> {
        if (blockedPackages.isEmpty()) return emptyList()
        return windows.filter { w ->
            val pkg = w.packageName
            pkg != null &&
                w.kind != WindowKind.OTHER &&
                pkg != ownPackage &&
                pkg in blockedPackages
        }
    }

    /** True when [bounds] covers (nearly) the whole display, i.e. a normal full-screen app. */
    fun isFullScreen(bounds: WindowBounds, screenWidth: Int, screenHeight: Int): Boolean {
        if (screenWidth <= 0 || screenHeight <= 0) return false
        return bounds.width >= screenWidth * 0.95 && bounds.height >= screenHeight * 0.9
    }
}

/** What to do about one violating window. */
data class WindowResponse(
    /** Draw a cover over the window. */
    val cover: Boolean,
    /** Cover lets touches through (PiP), so the system's own PiP controls keep working. */
    val passTouches: Boolean,
    /** Send the user back to Pace (normal full-screen blocking, as before). */
    val eject: Boolean,
)

/** Per-window decision. Pure so it is unit tested. */
object CoverPolicy {
    /**
     * - Full-screen app: no cover, just send the user to Pace (the original behaviour).
     * - PiP: cover only, touches pass through, never ejected. The user moves/closes it with the system controls.
     * - Split pane / freeform: cover only, touches blocked, never ejected (no Home), so the other pane stays usable.
     */
    fun responseFor(w: WindowSnapshot, screenWidth: Int, screenHeight: Int): WindowResponse = when {
        w.kind == WindowKind.PIP -> WindowResponse(cover = true, passTouches = true, eject = false)
        VisibleWindowEvaluator.isFullScreen(w.bounds, screenWidth, screenHeight) ->
            WindowResponse(cover = false, passTouches = false, eject = true)
        else -> WindowResponse(cover = true, passTouches = false, eject = false)
    }
}

/** Decides which cover layout fits a window. Pure so the thresholds are unit tested. */
object CoverLayoutPolicy {
    /**
     * How much a window is shrunk on screen: local width / on-screen width (1 when unknown or not shrunk).
     * A window-attached cover is drawn in local coordinates, so its text and padding are multiplied by this
     * to stay readable after the window scales it down.
     */
    fun contentScale(screenWidth: Int, localWidth: Int): Float {
        if (screenWidth <= 0 || localWidth <= 0) return 1f
        return (localWidth.toFloat() / screenWidth).coerceIn(1f, 6f)
    }

    private const val COMPACT_MAX_HEIGHT_DP = 180
    private const val COMPACT_MAX_WIDTH_DP = 260

    /** Compact = PiP-sized window: one auto-sized label, no subtitle or button. */
    fun isCompact(widthPx: Int, heightPx: Int, density: Float): Boolean {
        if (density <= 0f) return false
        return heightPx / density < COMPACT_MAX_HEIGHT_DP || widthPx / density < COMPACT_MAX_WIDTH_DP
    }
}

/**
 * Tracks which blocked packages are currently "in violation" so an interruption is recorded and the
 * eject action fires once per attempt (package goes from not visible to visible), not on every check.
 */
class ViolationEpisodeTracker {
    private val active = mutableSetOf<String>()

    /** Updates the tracker with the packages visible now and returns the ones that just appeared. */
    fun update(currentlyViolating: Set<String>): Set<String> {
        val started = currentlyViolating - active
        active.retainAll(currentlyViolating)
        active.addAll(currentlyViolating)
        return started
    }

    fun reset() = active.clear()
}

/**
 * Decides when a blocked app counts as a NEW attempt and when it needs a NEW eject.
 *
 * They are tracked separately on purpose. An app seen in a PiP/split pane (covered, no eject) and then
 * expanded to full screen is the same package continuously on screen, so a package-only "episode" would
 * never fire the eject and the blocked app would stay usable. Full-screen visibility has its own episode.
 */
class AttemptTracker {
    data class Result(val newAttempts: Set<String>, val newEjects: Set<String>)

    private val visible = ViolationEpisodeTracker()
    private val fullScreen = ViolationEpisodeTracker()

    fun update(responses: List<Pair<WindowSnapshot, WindowResponse>>): Result {
        val all = responses.mapNotNull { it.first.packageName }.toSet()
        val ejecting = responses.filter { it.second.eject }.mapNotNull { it.first.packageName }.toSet()
        return Result(visible.update(all), fullScreen.update(ejecting))
    }

    fun reset() {
        visible.reset()
        fullScreen.reset()
    }
}

/**
 * A window only counts as a normal full-screen app once it has LOOKED full screen continuously for
 * [minStableMs]. A split pane or PiP animating in or out passes through full-screen-looking bounds for a
 * moment (seen on device: a pane sliding in hit 83% of the screen height for one frame and was ejected as
 * if it were a normal app). Packages are tracked independently; any frame where a package does not look
 * full screen resets its timer.
 */
class StableFullScreenGate(private val minStableMs: Long) {
    private val since = mutableMapOf<String, Long>()

    /** [lookingFull] = packages that look full screen right now. Returns the ones that have been for long enough. */
    fun update(nowMs: Long, lookingFull: Set<String>): Set<String> {
        since.keys.retainAll(lookingFull)
        lookingFull.forEach { since.putIfAbsent(it, nowMs) }
        return since.filterValues { nowMs - it >= minStableMs }.keys
    }

    fun reset() = since.clear()
}

/**
 * One interruption per attempt. A single open is seen twice (first sighting, then the delayed full-screen
 * confirmation), so repeats of the same app within [windowMs] count as the same attempt.
 */
class RecordThrottle(private val windowMs: Long) {
    private val last = mutableMapOf<String, Long>()

    fun shouldRecord(key: String, nowMs: Long): Boolean {
        val prev = last[key]
        if (prev != null && nowMs - prev < windowMs) return false
        last[key] = nowMs
        return true
    }

    fun reset() = last.clear()
}
