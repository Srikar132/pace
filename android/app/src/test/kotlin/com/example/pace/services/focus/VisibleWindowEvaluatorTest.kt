package com.example.pace.services.focus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VisibleWindowEvaluatorTest {

    private val own = "dev.srikar.pace"
    private val youtube = "com.google.android.youtube"
    private val chrome = "com.android.chrome"
    private val blocked = setOf(youtube, "com.instagram.android")

    private val full = WindowBounds(0, 0, 1080, 2400)
    private val topPane = WindowBounds(0, 0, 1080, 1200)
    private val bottomPane = WindowBounds(0, 1200, 1080, 2400)
    private val pipBounds = WindowBounds(700, 1500, 1040, 1700)

    private fun win(
        id: Int,
        pkg: String?,
        kind: WindowKind = WindowKind.APPLICATION,
        bounds: WindowBounds = full,
    ) = WindowSnapshot(id, pkg, kind, bounds)

    private fun violations(vararg windows: WindowSnapshot, blockedSet: Set<String> = blocked) =
        VisibleWindowEvaluator.violations(windows.toList(), blockedSet, own)

    // ---- violations ----

    @Test
    fun fullScreenBlockedAppIsAViolation() {
        val result = violations(win(1, youtube))
        assertEquals(listOf(1), result.map { it.id })
    }

    @Test
    fun blockedAppInTopPaneOnlyIsAViolation() {
        val result = violations(win(1, youtube, bounds = topPane), win(2, chrome, bounds = bottomPane))
        assertEquals(listOf(1), result.map { it.id })
    }

    @Test
    fun blockedAppInBottomPaneOnlyIsAViolation() {
        val result = violations(win(1, chrome, bounds = topPane), win(2, youtube, bounds = bottomPane))
        assertEquals(listOf(2), result.map { it.id })
    }

    @Test
    fun bothPanesBlockedReturnsBothWindows() {
        val result = violations(
            win(1, youtube, bounds = topPane),
            win(2, "com.instagram.android", bounds = bottomPane),
        )
        assertEquals(listOf(1, 2), result.map { it.id })
    }

    @Test
    fun blockedAppInPipIsAViolationEvenWhenAllowedAppIsFullScreen() {
        val result = violations(
            win(1, chrome),
            win(2, youtube, kind = WindowKind.PIP, bounds = pipBounds),
        )
        assertEquals(listOf(2), result.map { it.id })
    }

    @Test
    fun allowedWindowsOnlyIsNotAViolation() {
        assertTrue(violations(win(1, chrome, bounds = topPane), win(2, "com.whatsapp", bounds = bottomPane)).isEmpty())
    }

    @Test
    fun ownPackageIsNeverBlockedEvenIfInBlockedSet() {
        assertTrue(violations(win(1, own), blockedSet = blocked + own).isEmpty())
    }

    @Test
    fun windowWithUnreadablePackageIsNotBlocked() {
        assertTrue(violations(win(1, null, kind = WindowKind.PIP, bounds = pipBounds)).isEmpty())
    }

    @Test
    fun nonApplicationWindowsAreIgnoredEvenWithBlockedPackage() {
        assertTrue(violations(win(1, youtube, kind = WindowKind.OTHER)).isEmpty())
    }

    @Test
    fun emptyBlockedSetProducesNoViolations() {
        assertTrue(violations(win(1, youtube), blockedSet = emptySet()).isEmpty())
    }

    @Test
    fun noWindowsProducesNoViolations() {
        assertTrue(violations().isEmpty())
    }

    // ---- isFullScreen ----

    @Test
    fun fullDisplayWindowIsFullScreen() {
        assertTrue(VisibleWindowEvaluator.isFullScreen(full, 1080, 2400))
    }

    @Test
    fun windowSlightlyShortOfDisplayForSystemBarsIsStillFullScreen() {
        assertTrue(VisibleWindowEvaluator.isFullScreen(WindowBounds(0, 80, 1080, 2300), 1080, 2400))
    }

    @Test
    fun splitPaneIsNotFullScreen() {
        assertFalse(VisibleWindowEvaluator.isFullScreen(topPane, 1080, 2400))
    }

    @Test
    fun pipIsNotFullScreen() {
        assertFalse(VisibleWindowEvaluator.isFullScreen(pipBounds, 1080, 2400))
    }

    @Test
    fun zeroSizedDisplayIsNeverFullScreen() {
        assertFalse(VisibleWindowEvaluator.isFullScreen(full, 0, 0))
    }
}

class ViolationEpisodeTrackerTest {

    @Test
    fun firstSightingStartsAnEpisode() {
        val tracker = ViolationEpisodeTracker()
        assertEquals(setOf("yt"), tracker.update(setOf("yt")))
    }

    @Test
    fun stillVisiblePackageDoesNotStartANewEpisode() {
        val tracker = ViolationEpisodeTracker()
        tracker.update(setOf("yt"))
        assertTrue(tracker.update(setOf("yt")).isEmpty())
    }

    @Test
    fun reopeningAfterItDisappearedStartsANewEpisode() {
        val tracker = ViolationEpisodeTracker()
        tracker.update(setOf("yt"))
        tracker.update(emptySet())
        assertEquals(setOf("yt"), tracker.update(setOf("yt")))
    }

    @Test
    fun secondBlockedAppWhileFirstRemainsOnlyReportsTheNewOne() {
        val tracker = ViolationEpisodeTracker()
        tracker.update(setOf("yt"))
        assertEquals(setOf("ig"), tracker.update(setOf("yt", "ig")))
    }

    @Test
    fun resetForgetsEverythingSoNextSessionStartsFresh() {
        val tracker = ViolationEpisodeTracker()
        tracker.update(setOf("yt"))
        tracker.reset()
        assertEquals(setOf("yt"), tracker.update(setOf("yt")))
    }
}

class CoverLayoutPolicyTest {
    private val density = 2.75f

    @Test
    fun typicalPipWindowIsCompact() {
        // ~124dp x 73dp
        assertTrue(CoverLayoutPolicy.isCompact(340, 200, density))
    }

    @Test
    fun splitPaneIsNotCompact() {
        assertFalse(CoverLayoutPolicy.isCompact(1080, 1200, density))
    }

    @Test
    fun fullScreenIsNotCompact() {
        assertFalse(CoverLayoutPolicy.isCompact(1080, 2400, density))
    }

    @Test
    fun narrowButTallWindowIsCompact() {
        // 200dp wide, 600dp tall: too narrow for the button layout
        assertTrue(CoverLayoutPolicy.isCompact(550, 1650, density))
    }

    @Test
    fun wideButShortWindowIsCompact() {
        // 600dp wide, 120dp tall
        assertTrue(CoverLayoutPolicy.isCompact(1650, 330, density))
    }

    @Test
    fun pipGrowingByPinchCrossesThresholdToFullLayout() {
        assertTrue(CoverLayoutPolicy.isCompact(600, 330, density))   // ~218 x 120dp
        assertFalse(CoverLayoutPolicy.isCompact(900, 600, density))  // ~327 x 218dp
    }

    @Test
    fun zeroDensityNeverCompact() {
        assertFalse(CoverLayoutPolicy.isCompact(340, 200, 0f))
    }
}

class CoverPolicyTest {
    private val sw = 1080
    private val sh = 2412
    private fun w(kind: WindowKind, b: WindowBounds) = WindowSnapshot(1, "p", kind, b)
    private fun r(kind: WindowKind, b: WindowBounds) = CoverPolicy.responseFor(w(kind, b), sw, sh)

    private val fullScreen = WindowBounds(0, 0, 1080, 2412)
    private val topPane = WindowBounds(0, 0, 1080, 1200)
    private val bottomPane = WindowBounds(0, 1212, 1080, 2412)
    private val landscapeLeftPane = WindowBounds(0, 0, 540, 2412)
    private val pip = WindowBounds(505, 1921, 1032, 2316)

    @Test
    fun fullScreenAppGetsNoCoverAndIsEjected() {
        val x = r(WindowKind.APPLICATION, fullScreen)
        assertFalse(x.cover)
        assertTrue(x.eject)
    }

    @Test
    fun pipIsCoveredWithTouchesPassingThroughAndNeverEjected() {
        val x = r(WindowKind.PIP, pip)
        assertTrue(x.cover)
        assertTrue(x.passTouches)
        assertFalse(x.eject)
    }

    @Test
    fun splitPanesAreCoveredBlockTouchesAndNeverEjected() {
        listOf(topPane, bottomPane, landscapeLeftPane).forEach { b ->
            val x = r(WindowKind.APPLICATION, b)
            assertTrue("pane $b should be covered", x.cover)
            assertFalse(x.passTouches)
            assertFalse("pane $b must not go Home", x.eject)
        }
    }

    @Test
    fun floatingWindowIsCoveredNotEjected() {
        val x = r(WindowKind.APPLICATION, WindowBounds(100, 400, 900, 1500))
        assertTrue(x.cover)
        assertFalse(x.eject)
    }

    @Test
    fun pipIsNeverTreatedAsFullScreenEvenIfItIsLarge() {
        val x = r(WindowKind.PIP, fullScreen)
        assertTrue(x.cover)
        assertFalse(x.eject)
    }
}

class MediaPausePolicyTest {
    @Test fun pausesPlaying() = assertTrue(MediaPausePolicy.shouldPause(android.media.session.PlaybackState.STATE_PLAYING))
    @Test fun pausesBuffering() = assertTrue(MediaPausePolicy.shouldPause(android.media.session.PlaybackState.STATE_BUFFERING))
    @Test fun leavesPausedAlone() = assertFalse(MediaPausePolicy.shouldPause(android.media.session.PlaybackState.STATE_PAUSED))
    @Test fun leavesStoppedAlone() = assertFalse(MediaPausePolicy.shouldPause(android.media.session.PlaybackState.STATE_STOPPED))
    @Test fun noPlaybackStateMeansNothingToPause() = assertFalse(MediaPausePolicy.shouldPause(null))
}

class AttemptTrackerTest {
    private val sw = 1080
    private val sh = 2412
    private val yt = "com.google.android.youtube"
    private val full = WindowBounds(0, 0, 1080, 2412)
    private val pane = WindowBounds(0, 1212, 1080, 2412)
    private val pip = WindowBounds(505, 1921, 1032, 2316)

    private fun resp(kind: WindowKind, b: WindowBounds, pkg: String = yt): Pair<WindowSnapshot, WindowResponse> {
        val w = WindowSnapshot(1, pkg, kind, b)
        return w to CoverPolicy.responseFor(w, sw, sh)
    }

    @Test
    fun paneThenFullScreenSamePackageStillFiresAnEject() {
        val t = AttemptTracker()
        val first = t.update(listOf(resp(WindowKind.APPLICATION, pane)))
        assertEquals(setOf(yt), first.newAttempts)
        assertTrue(first.newEjects.isEmpty()) // covered, never ejected
        val second = t.update(listOf(resp(WindowKind.APPLICATION, full)))
        assertTrue(second.newAttempts.isEmpty()) // same attempt...
        assertEquals(setOf(yt), second.newEjects) // ...but it must now be ejected
    }

    @Test
    fun pipExpandedToFullScreenFiresAnEject() {
        val t = AttemptTracker()
        assertTrue(t.update(listOf(resp(WindowKind.PIP, pip))).newEjects.isEmpty())
        assertEquals(setOf(yt), t.update(listOf(resp(WindowKind.APPLICATION, full))).newEjects)
    }

    @Test
    fun fullScreenStayingFullScreenDoesNotReEjectOnEveryCheck() {
        val t = AttemptTracker()
        assertEquals(setOf(yt), t.update(listOf(resp(WindowKind.APPLICATION, full))).newEjects)
        assertTrue(t.update(listOf(resp(WindowKind.APPLICATION, full))).newEjects.isEmpty())
    }

    @Test
    fun reopeningFullScreenAfterLeavingEjectsAgain() {
        val t = AttemptTracker()
        t.update(listOf(resp(WindowKind.APPLICATION, full)))
        t.update(emptyList()) // went back to Pace
        val again = t.update(listOf(resp(WindowKind.APPLICATION, full)))
        assertEquals(setOf(yt), again.newAttempts)
        assertEquals(setOf(yt), again.newEjects)
    }

    @Test
    fun paneUntouchedForALongTimeNeverEjects() {
        val t = AttemptTracker()
        repeat(5) { assertTrue(t.update(listOf(resp(WindowKind.APPLICATION, pane))).newEjects.isEmpty()) }
    }

    @Test
    fun resetForgetsEverythingSoNextSessionStartsFresh() {
        val t = AttemptTracker()
        t.update(listOf(resp(WindowKind.APPLICATION, full)))
        t.reset()
        assertEquals(setOf(yt), t.update(listOf(resp(WindowKind.APPLICATION, full))).newEjects)
    }

    @Test
    fun twoDifferentBlockedAppsTrackIndependently() {
        val t = AttemptTracker()
        t.update(listOf(resp(WindowKind.APPLICATION, full, "a")))
        val r = t.update(listOf(resp(WindowKind.APPLICATION, full, "a"), resp(WindowKind.APPLICATION, full, "b")))
        assertEquals(setOf("b"), r.newEjects)
    }
}

class StableFullScreenGateTest {
    private val ms = 400L

    @Test
    fun notConfirmedOnFirstSighting() {
        assertTrue(StableFullScreenGate(ms).update(1000, setOf("yt")).isEmpty())
    }

    @Test
    fun notConfirmedJustBeforeTheDelay() {
        val g = StableFullScreenGate(ms)
        g.update(1000, setOf("yt"))
        assertTrue(g.update(1399, setOf("yt")).isEmpty())
    }

    @Test
    fun confirmedOnceStableForTheDelay() {
        val g = StableFullScreenGate(ms)
        g.update(1000, setOf("yt"))
        assertEquals(setOf("yt"), g.update(1400, setOf("yt")))
    }

    @Test
    fun animatingPaneThatShrinksBeforeTheDelayIsNeverConfirmed() {
        // The device log: a pane looked full screen at 10:44:15.148 and was a pane again right after.
        val g = StableFullScreenGate(ms)
        g.update(1000, setOf("yt")) // full-screen-looking frame
        assertTrue(g.update(1250, emptySet()).isEmpty()) // now pane-sized: timer reset
        assertTrue(g.update(1500, setOf("yt")).isEmpty()) // looks full again briefly: starts over
        assertTrue(g.update(1700, setOf("yt")).isEmpty())
    }

    @Test
    fun packagesAreTrackedIndependently() {
        val g = StableFullScreenGate(ms)
        g.update(1000, setOf("a"))
        g.update(1300, setOf("a", "b"))
        assertEquals(setOf("a"), g.update(1450, setOf("a", "b")))
    }

    @Test
    fun resetForgetsPendingTimers() {
        val g = StableFullScreenGate(ms)
        g.update(1000, setOf("yt"))
        g.reset()
        assertTrue(g.update(1500, setOf("yt")).isEmpty())
    }
}

class FullScreenThresholdTest {
    @Test
    fun paneAnimatingAtEightyThreePercentHeightIsNotFullScreen() {
        // 0,397-1080,2412 on a 1080x2412 screen: the exact frame that caused the wrong eject.
        assertFalse(VisibleWindowEvaluator.isFullScreen(WindowBounds(0, 397, 1080, 2412), 1080, 2412))
    }

    @Test
    fun launchAnimationBoundsNearlyFullAreFullScreen() {
        assertTrue(VisibleWindowEvaluator.isFullScreen(WindowBounds(2, 5, 1078, 2407), 1080, 2412))
    }
}

class RecordThrottleTest {
    @Test
    fun firstSightingIsRecorded() = assertTrue(RecordThrottle(2000).shouldRecord("yt", 1000))

    @Test
    fun theDelayedConfirmationOfTheSameOpenIsNotRecordedTwice() {
        val t = RecordThrottle(2000)
        assertTrue(t.shouldRecord("yt", 1000))
        assertFalse(t.shouldRecord("yt", 1430))
    }

    @Test
    fun aLaterGenuineNewAttemptIsRecorded() {
        val t = RecordThrottle(2000)
        t.shouldRecord("yt", 1000)
        assertTrue(t.shouldRecord("yt", 3500))
    }

    @Test
    fun differentAppsAreIndependent() {
        val t = RecordThrottle(2000)
        t.shouldRecord("a", 1000)
        assertTrue(t.shouldRecord("b", 1100))
    }

    @Test
    fun resetStartsFresh() {
        val t = RecordThrottle(2000)
        t.shouldRecord("a", 1000)
        t.reset()
        assertTrue(t.shouldRecord("a", 1100))
    }
}

class ContentScaleTest {
    @Test
    fun floatingWindowShrunkToQuarterIsScaledUpFourTimes() {
        // On the device: a window shown 261 px wide is drawn ~1044 px wide in its own coordinates.
        assertEquals(4f, CoverLayoutPolicy.contentScale(261, 1044), 0.01f)
    }

    @Test
    fun unscaledWindowHasScaleOne() = assertEquals(1f, CoverLayoutPolicy.contentScale(1080, 1080), 0.001f)

    @Test
    fun unknownLocalSizeFallsBackToOne() {
        assertEquals(1f, CoverLayoutPolicy.contentScale(500, 0), 0.001f)
        assertEquals(1f, CoverLayoutPolicy.contentScale(0, 800), 0.001f)
    }

    @Test
    fun scaleNeverDropsBelowOneOrExplodes() {
        assertEquals(1f, CoverLayoutPolicy.contentScale(1000, 600), 0.001f)
        assertEquals(6f, CoverLayoutPolicy.contentScale(10, 5000), 0.001f)
    }
}
