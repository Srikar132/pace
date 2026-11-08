package com.example.pace.services.focus

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityWindowInfo

/**
 * Multi-window enforcement for focus sessions (issue #8). Owned by LockInAccessibilityService.
 *
 * On every window change it snapshots all interactive windows (split panes, PiP, freeform), finds the
 * ones showing a blocked app. PiP / split panes / floating windows get a cover (PiP: touch-through, so
 * the system controls keep working; panes: touch-blocking) and their media is paused. A normal full-screen
 * blocked app gets no cover and is sent back to Pace. An interruption is recorded once per attempt.
 * Reads only package names and bounds, never window content.
 *
 * State comes straight from [FocusSessionManager] (restored from prefs), so pause/resume/end and
 * process restarts are respected without depending on MainActivity or FocusMonitoringService.
 * Main thread only.
 */
class FocusWindowEnforcer(private val service: AccessibilityService) {

    private companion object {
        const val TAG = "FocusWindowEnforcer"
        const val THROTTLE_MS = 50L
        const val TRACK_MS = 50L
        const val HEARTBEAT_IDLE_MS = 3000L
        const val HEARTBEAT_COVERED_MS = 1000L
        const val EJECT_RETRY_MS = 1500L
        const val FULLSCREEN_CONFIRM_MS = 400L
        const val HEALTHY_WITHIN_MS = 6000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val sessionManager = FocusSessionManager.getInstance(service.applicationContext)
    private val cover = FocusWindowCover(
        service = service,
        onBackToPace = { bringPaceToForeground() },
    )
    private val mediaPauser = BlockedMediaPauser(service.applicationContext)
    private val attempts = AttemptTracker()
    private val fullScreenGate = StableFullScreenGate(FULLSCREEN_CONFIRM_MS)
    private val recordThrottle = RecordThrottle(2000L)
    private var recheckPending = false
    private val eventPackages = mutableMapOf<Int, String>() // windowId -> package, from window events
    private var lastEvaluationAt = 0L
    private var lastEjectAt = 0L
    private var lastSnapshotLog = ""
    private var running = false
    private var coverShowing = false

    // Ids of every window seen in the last full snapshot, and of the ones currently covered.
    private var knownWindowIds = emptySet<Int>()
    private val coveredIds = mutableSetOf<Int>()
    private var evalPending = false
    private var tracking = false

    private val evaluateRunnable = Runnable {
        evalPending = false
        evaluateNow()
    }

    // While a cover is up, re-read only window bounds so the cover follows a dragged/resized
    // PiP or floating window instead of waiting for the next full snapshot.
    private val trackRunnable = object : Runnable {
        override fun run() {
            if (!running || coveredIds.isEmpty()) {
                tracking = false
                return
            }
            trackBounds()
            if (tracking) handler.postDelayed(this, TRACK_MS)
        }
    }

    private val heartbeat = object : Runnable {
        override fun run() {
            if (!running) return
            evaluateNow()
            handler.postDelayed(this, if (coverShowing) HEARTBEAT_COVERED_MS else HEARTBEAT_IDLE_MS)
        }
    }

    fun start() {
        if (running) return
        running = true
        handler.postDelayed(heartbeat, HEARTBEAT_IDLE_MS)
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        cover.removeAll()
        attempts.reset()
        fullScreenGate.reset()
        recordThrottle.reset()
        recheckPending = false
        eventPackages.clear()
        coveredIds.clear()
        coverShowing = false
        evalPending = false
        tracking = false
    }

    /**
     * Called for window/state events. Throttled (leading edge): the first event schedules a snapshot
     * ~50 ms out and the rest of the burst is absorbed. A debounce would starve while a PiP window is
     * being dragged, since events keep arriving and would keep postponing the update.
     */
    fun requestEvaluation() {
        if (!running || evalPending) return
        evalPending = true
        handler.postDelayed(evaluateRunnable, THROTTLE_MS)
    }

    /** Package of a window, from a window-state event. Fallback when a window's root cannot be read. */
    fun onWindowEvent(windowId: Int, packageName: String) {
        if (windowId >= 0) eventPackages[windowId] = packageName
    }

    /**
     * True while the enforcer is demonstrably alive (it evaluated recently). FocusMonitoringService only
     * defers to the enforcer when this is true, so a broken or stalled enforcer can never switch off
     * the original full-screen blocking.
     */
    fun isHealthy(): Boolean =
        running && android.os.SystemClock.elapsedRealtime() - lastEvaluationAt < HEALTHY_WITHIN_MS

    /** Called when the session starts, pauses, resumes or ends: evaluate right away. */
    fun onSessionStateChanged() {
        if (!running) return
        handler.removeCallbacks(evaluateRunnable)
        evalPending = false
        handler.post(evaluateRunnable)
    }

    private fun startTracking() {
        if (tracking) return
        tracking = true
        handler.postDelayed(trackRunnable, TRACK_MS)
    }

    /** Light pass: bounds only, no node-tree access. Falls back to a full snapshot on any structural change. */
    private fun trackBounds() {
        try {
            if (!enforcing()) {
                evaluateNow()
                return
            }
            val windows = service.windows ?: return
            cover.setPipMenuOpen(windows.any { isPipMenu(it) })
            val byId = windows.associateBy { it.id }
            var needFull = byId.keys.any { it !in knownWindowIds }
            for (id in coveredIds.toList()) {
                val w = byId[id]
                if (w == null) {
                    needFull = true
                    continue
                }
                val r = android.graphics.Rect().also { w.getBoundsInScreen(it) }
                cover.updateBounds(id, WindowBounds(r.left, r.top, r.right, r.bottom))
            }
            if (needFull) evaluateNow()
        } catch (e: Exception) {
            Log.e(TAG, "Error tracking window bounds", e)
        }
    }

    private fun enforcing(): Boolean =
        sessionManager.isSessionActive() && !sessionManager.isSessionPaused()

    private fun evaluateNow() {
        try {
            if (!enforcing()) {
                clear()
                return
            }
            val blocked = sessionManager.getCurrentSession()?.blockedApps?.toSet().orEmpty()
            val snapshots = snapshotWindows()
            val violations = VisibleWindowEvaluator.violations(
                snapshots, blocked, service.applicationContext.packageName
            )
            val metrics = service.resources.displayMetrics
            val now = android.os.SystemClock.elapsedRealtime()
            val raw = violations.map {
                it to CoverPolicy.responseFor(it, metrics.widthPixels, metrics.heightPixels)
            }
            // "Full screen" is only believed after it has looked that way for a moment: a pane or PiP
            // animating in/out briefly has full-screen-looking bounds and must not be ejected.
            val lookingFull = raw.filter { it.second.eject }.mapNotNull { it.first.packageName }.toSet()
            val confirmedFull = fullScreenGate.update(now, lookingFull)
            val responses = raw.map { (v, r) ->
                if (r.eject && v.packageName !in confirmedFull) {
                    v to WindowResponse(cover = false, passTouches = false, eject = false)
                } else v to r
            }
            if (lookingFull.any { it !in confirmedFull }) scheduleRecheck()

            // Covers only for PiP / split pane / freeform. A normal full-screen app gets no cover.
            val covered = responses.filter { it.second.cover }
            covered.forEach { (v, r) ->
                cover.show(
                    v.id, appName(v.packageName!!), v.bounds, passTouches = r.passTouches,
                    localWidth = v.localWidth, localHeight = v.localHeight,
                )
            }
            cover.retainOnly(covered.map { it.first.id }.toSet())
            coveredIds.clear()
            coveredIds.addAll(covered.map { it.first.id })
            coverShowing = coveredIds.isNotEmpty()
            if (coverShowing) startTracking()

            // Stop the blocked apps' audio/video behind the scenes (media sessions only).
            mediaPauser.pause(violations.mapNotNull { it.packageName }.toSet())

            val result = attempts.update(responses)

            logSnapshotIfChanged(responses)

            // A blocked app is a new attempt when it first appears, and also when it later goes full
            // screen (expand from PiP / maximise a pane): that is a new eject even for the same package.
            (result.newAttempts + result.newEjects).filter { recordThrottle.shouldRecord(it, now) }.forEach { pkg ->
                Log.d(TAG, "🚫 Blocked app visible: $pkg")
                sessionManager.recordInterruption(
                    packageName = pkg,
                    appName = appName(pkg),
                    type = "app_opened",
                    wasBlocked = true
                )
            }
            // Only a full-screen blocked app is ejected (back to Pace). PiP and split panes are covered and
            // left in place so the user keeps the system controls / the other pane. If a full-screen
            // blocked app is STILL there after the cooldown, the last eject did not work: try again.
            val fullScreenStillThere = responses.any { it.second.eject }
            val shouldEject = result.newEjects.isNotEmpty() ||
                (fullScreenStillThere && now - lastEjectAt >= EJECT_RETRY_MS)
            if (shouldEject) {
                lastEjectAt = now
                bringPaceToForeground()
            }
            lastEvaluationAt = now
        } catch (e: Exception) {
            Log.e(TAG, "Error evaluating windows", e)
        }
    }

    /** Re-evaluate just after the full-screen confirmation delay so the decision is not left to the heartbeat. */
    private fun scheduleRecheck() {
        if (recheckPending) return
        recheckPending = true
        handler.postDelayed({
            recheckPending = false
            evaluateNow()
        }, FULLSCREEN_CONFIRM_MS + 30)
    }

    private fun clear() {
        if (coverShowing || cover.hasCovers()) cover.removeAll()
        attempts.reset()
        fullScreenGate.reset()
        recordThrottle.reset()
        coveredIds.clear()
        coverShowing = false
    }

    private fun snapshotWindows(): List<WindowSnapshot> {
        val windows = service.windows ?: return emptyList()
        knownWindowIds = windows.map { it.id }.toSet()
        eventPackages.keys.retainAll(knownWindowIds)
        cover.setPipMenuOpen(windows.any { isPipMenu(it) })
        return windows.mapNotNull { w ->
            val kind = when {
                isPip(w) -> WindowKind.PIP
                w.type == AccessibilityWindowInfo.TYPE_APPLICATION -> WindowKind.APPLICATION
                else -> WindowKind.OTHER
            }
            if (kind == WindowKind.OTHER) return@mapNotNull null
            val rect = android.graphics.Rect().also { w.getBoundsInScreen(it) }
            val root = w.root
            val pkg = root?.packageName?.toString() ?: eventPackages[w.id]
            var localW = 0
            var localH = 0
            if (root != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val local = android.graphics.Rect().also { root.getBoundsInWindow(it) }
                localW = local.width()
                localH = local.height()
            }
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) root?.recycle()
            WindowSnapshot(
                id = w.id,
                packageName = pkg,
                kind = kind,
                bounds = WindowBounds(rect.left, rect.top, rect.right, rect.bottom),
                localWidth = localW,
                localHeight = localH,
            )
        }
    }

    private fun isPip(w: AccessibilityWindowInfo): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && w.isInPictureInPictureMode

    /**
     * The system's PiP controls (expand / close / settings) are their own non-application window flagged
     * as PiP. Its title is localized, so detect it by those two properties instead.
     */
    private fun isPipMenu(w: AccessibilityWindowInfo): Boolean =
        isPip(w) && w.type != AccessibilityWindowInfo.TYPE_APPLICATION

    private fun bringPaceToForeground() {
        try {
            val intent = service.packageManager
                .getLaunchIntentForPackage(service.applicationContext.packageName)
                ?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                } ?: return
            service.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error bringing Pace to foreground", e)
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        }
    }

    /** One line per CHANGE of what is on screen, so a log shows exactly what the service saw. */
    private fun logSnapshotIfChanged(responses: List<Pair<WindowSnapshot, WindowResponse>>) {
        val line = responses.joinToString { (v, r) ->
            "${v.packageName}[${v.kind} ${v.bounds.left},${v.bounds.top}-${v.bounds.right},${v.bounds.bottom} " +
                "cover=${r.cover} blockTouch=${!r.passTouches} eject=${r.eject}]"
        }
        if (line != lastSnapshotLog) {
            lastSnapshotLog = line
            Log.d(TAG, "Blocked windows now: ${line.ifEmpty { "none" }}")
        }
    }

    private fun appName(packageName: String): String = try {
        val pm = service.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    } catch (e: Exception) {
        packageName
    }
}
