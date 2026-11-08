# Focus mode: enforce blocked apps in split-screen, PiP and floating windows (issue #8)

## Goal

During an active (not paused) focus session, no blocked app may stay visible in any
window: split-screen pane, picture-in-picture, freeform/floating window, or full screen.
Detection is event-driven and window-aware. A violation is ejected, and covered
fail-closed until the blocked window is gone. Full-screen blocking keeps working.

## Skills / docs read

- `AGENTS.md`. Native services are on the no-exceptions prompt-approval list (section 2).
  Enforcement stays in Kotlin (section 5). New-architecture packages are canonical (section 7).
- GitHub issue #8 (labels: bug). It has no comments.
- Android docs checked: `AccessibilityWindowInfo` (window types, `isInPictureInPictureMode`),
  `TYPE_WINDOWS_CHANGED` with `WINDOWS_CHANGE_*` flags, `UsageEvents.Event` (ACTIVITY_RESUMED/PAUSED/STOPPED
  replace the deprecated MOVE_TO_FOREGROUND/BACKGROUND, reported per activity), `TYPE_ACCESSIBILITY_OVERLAY`.

## Code inspected (and what it showed)

- `services/focus/FocusMonitoringService.kt`
  - Polls `UsageEvents` every 1.5 s and keeps one `lastApp` from the last `MOVE_TO_FOREGROUND`.
  - Acts only when the package differs from `lastCheckedApp`, so a blocked window that stays visible is never re-checked.
  - The Flutter overlay call is commented out. The only enforcement is `recordInterruption` + `bringAppToForeground()`.
    This does nothing for PiP and is ambiguous in split-screen.
  - `onStartCommand` ignores a null intent (`START_STICKY` restart). After process death the session is restored
    from prefs but nothing restarts monitoring. This is a real hole for the "service restart" criterion.
- `services/focus/FocusSessionManager.kt` is a singleton that restores `isActive`, `isPaused` and `blockedApps`
  from SharedPreferences. It is the right source of truth for the enforcer.
  `onSessionEnded/Paused/Resumed` callbacks are assigned only in `MainActivity.initializeManagers`
  (`MainActivity.kt:125-132`), so they stop working if the Activity is destroyed.
- `LockInAccessibilityService.kt` has no focus-session logic. `serviceInfo` is set in code (line ~180) with
  `FLAG_RETRIEVE_INTERACTIVE_WINDOWS` but without `TYPE_WINDOWS_CHANGED`. The code overrides the XML.
  It already calls `windows` elsewhere (YouTube navigation helper), so window access is already granted.
- `accessibility_service_config.xml` has `canRetrieveWindowContent=true` and `flagRetrieveInteractiveWindows`.
- `OverlayLauncher` / `BlockOverlayActivity`: Flutter overlay launched as a new task. Unreliable placement in
  split-screen/PiP, so it is kept for the full-screen path only.
- `AndroidManifest.xml` needs no changes. The accessibility permission is already required.
- No `android/app/src/test` directory and no unit-test dependency exist.

## Design (what changed vs the issue's proposal)

The issue suggests `ActivityManager` running tasks and extending the polling loop. I'm not doing that:

1. **Event-driven, not polled.** Add `TYPE_WINDOWS_CHANGED` to the accessibility event types. Window add/remove,
   PiP enter/exit, bounds and active-window changes all fire it. Coalesce events (~100 ms) and re-query `getWindows()`.
   This catches split-screen and PiP transitions that never produce a new usage event.
2. **Heartbeat backstop.** A slow safety check (3 s, only while a session is active and not paused) re-evaluates
   the snapshot, so a missed event never leaves a blocked window uncovered.
3. **Enforcer lives in the accessibility service.** The system rebinds it after a kill, and it reads
   `FocusSessionManager` directly. Pause, resume and end are respected with no dependency on `MainActivity`
   or on `FocusMonitoringService` being alive.
4. **Testable core.** A pure-Kotlin `VisibleWindowEvaluator` takes a list of `WindowSnapshot`
   (type, package, bounds, isPip, isActive) plus the blocked set and returns violating windows. It has no Android types, so JUnit can test it.
5. **Cover + eject, fail-closed (user choice).**
   - Eject: `GLOBAL_ACTION_HOME`.
   - Cover: a native `TYPE_ACCESSIBILITY_OVERLAY` view (needs no `SYSTEM_ALERT_WINDOW`). It is sized to the
     blocked window's bounds, blocks touches, and shows the app name plus a "Back to Pace" button.
     It is removed as soon as the window no longer appears in the snapshot or the session pauses or ends.
   - If a window's package can't be read, it is not blocked and is logged. It is never guessed.
6. **Interruptions: once per episode.** Record an interruption when a package goes from not visible to visible,
   not on every check.
7. **Use the new usage-event types.** The remaining `MOVE_TO_FOREGROUND` use in `FocusMonitoringService` moves to
   `ACTIVITY_RESUMED` (same value, current name). The service stays as the foreground-notification owner and a fallback for
   devices where the accessibility service is off.
8. **Fix the restart hole.** `FocusMonitoringService.onStartCommand` handles a null intent by restarting monitoring
   if `FocusSessionManager.isSessionActive()`.

Full-screen behaviour is unchanged. The existing foreground check and `bringAppToForeground()` path stay for it.

## Files expected to touch

- `android/app/src/main/kotlin/com/example/pace/services/focus/VisibleWindowEvaluator.kt` (new, pure Kotlin)
- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusWindowEnforcer.kt` (new: snapshot, evaluate,
  eject, cover, episode tracking)
- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusWindowCover.kt` (new: native cover view)
- `android/app/src/main/kotlin/com/example/pace/services/LockInAccessibilityService.kt` (add `TYPE_WINDOWS_CHANGED`,
  forward to enforcer, init/teardown. This is a large file, so changes are surgical and the shorts/websites/limits code is untouched.)
- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusMonitoringService.kt` (null-intent restart,
  `ACTIVITY_RESUMED`, hand off when the enforcer is active)
- `android/app/src/main/res/xml/accessibility_service_config.xml` (add `typeWindowsChanged` for consistency)
- `android/app/build.gradle.kts`: add `testImplementation("junit:junit:4.13.2")`
- `android/app/src/test/kotlin/com/example/pace/services/focus/VisibleWindowEvaluatorTest.kt` (new)

Not touched: `AndroidManifest.xml`, Firestore rules, platform channels, Dart. No bridge or method-name change, so
there is no silent channel mismatch risk. `FocusModeManager` / `AppMonitoringService` (legacy but live) are not edited.

## Requirements

- Violation = any APPLICATION or PiP window (not our own package, not system windows) whose package is in
  `session.blockedApps`, while the session is active and not paused.
- Split-screen: either pane. PiP: `isInPictureInPictureMode`. Freeform: any windowed application window.
- Pre-existing windows: evaluate once on session start, and on resume. Cover/eject immediately.
- Several blocked windows: one cover per window, one `GLOBAL_ACTION_HOME`. Eject is rate-limited (>= 1 s apart) to avoid loops.
- Pause or end: remove all covers, stop enforcement. Resume: evaluate immediately.
- Accessibility service disabled mid-session: the usage-event fallback keeps full-screen blocking.
  Do not claim multi-window coverage in that state.
- Covers must survive rotation, folding and display changes: recompute from the new bounds on every snapshot.

## Security / privacy

- Reads only each window's package name and bounds. Does not read window content or text.
  Do not traverse node trees; use `window.root?.packageName` only.
- Nothing leaves the device. No new permissions. No Firestore writes beyond the existing interruption events.
- Cover is touch-blocking only inside the blocked window's bounds, never full screen unless the window is full screen.
- Heads-up: the service already holds broad accessibility capability. This does not widen it.

## Acceptance criteria

(From the issue.) Blocked app can't remain visible in either split pane, in PiP/mini-player, or in a freeform window,
whether opened before or after the session starts. Switching panes, entering/exiting PiP, rotation, Recents and deep links
trigger a fresh check. Multiple blocked windows are handled. Full-screen blocking, interruption recording and
pause/resume/end behave as before. Ending or expiring a session removes covers and leaves no state for the next session.
Also: after killing the app process mid-session, enforcement resumes without opening Pace.

## Checks to run

- `flutter analyze` and `dart format` (no Dart changes expected, run to confirm).
- `cd android && ./gradlew :app:testDebugUnitTest` for `VisibleWindowEvaluatorTest`. Cases: one pane blocked, both panes blocked,
  PiP blocked, own package ignored, unknown package ignored, paused and ended produce no violations, episode dedupe.
- `./gradlew :app:assembleDebug` to confirm it compiles.

## Manual test steps (real device or emulator, Android 12+ phone; also a tablet or foldable if available)

1. Grant usage access, accessibility, overlay and battery exemption. Allow restricted settings if the APK is sideloaded.
2. Start a focus session blocking YouTube and Chrome.
3. Full screen: open YouTube. Expect it to be blocked as before, with one interruption.
4. Split-screen: put Chrome (allowed) in one pane and YouTube in the other, then swap panes. Expect eject plus a cover on the blocked pane, and no content visible.
5. PiP: play a YouTube video, press Home to enter PiP. Expect PiP covered or dismissed.
6. Freeform window (enable developer freeform): open YouTube in a window. Expect cover plus eject.
7. Start the session with YouTube already open in split-screen. Expect immediate enforcement.
8. Rotate the device while a cover is up. The cover should match the new bounds. Open YouTube from Recents and from a deep link.
9. Pause the session. Covers disappear and YouTube is usable. Resume. Enforcement returns immediately. End the session. Nothing remains.
10. Mid-session, kill the app from Recents / `adb shell am force-stop com.example.pace`. Open YouTube in split-screen. Enforcement still works once the accessibility service rebinds.
11. Check `adb logcat -s LockInAccessibilityService FocusWindowEnforcer` and confirm one interruption per attempt.

## Open risks (stated, not hidden)

- OEM split-screen/PiP/freeform behaviour varies. `GLOBAL_ACTION_HOME` may not exit split-screen on every OEM,
  so the cover is the guarantee, not the eject. Test at least one non-Pixel device.
- Some PiP windows may return a null root package. Those are logged and not blocked.
- Sideloaded APKs on Android 13+ need "Allow restricted settings" before the accessibility service can be enabled. This
  affects FYP demo setup, not the design.

## Addendum: PiP follow-up (device feedback)

Device test: enforcement works, but the cover stayed in place when the PiP window was dragged and the
tiny layout was cramped. Reference apps move the cover with the PiP and let the user close it.

- **Why it stuck:** `requestEvaluation()` was a trailing debounce, so events during a drag kept postponing the
  update. Now a leading-edge throttle (50 ms), plus a bounds-only tracking loop (50 ms, no node-tree access)
  that runs only while a cover is up. A structural change (window added or removed) falls back to a full snapshot.
- **Responsive cover:** `CoverLayoutPolicy.isCompact` (under 180 dp tall or 260 dp wide) picks the layout. The cover
  rebuilds when a resize crosses the threshold. Compact = auto-sizing label (8-14 sp) plus a small Close button.
- **Close (user-approved: gesture-based):** `PipDismisser` taps the PiP to reveal controls, taps the close X
  (top-right), then falls back to dragging to the bottom dismiss zone. The cover is touch-transparent
  (`FLAG_NOT_TOUCHABLE`) while gestures run but stays visible. Non-PiP windows' Close goes Home.
  If every step fails the cover stays up (fail-closed).
- **Config change:** `android:canPerformGestures="true"` in `accessibility_service_config.xml`.
  Android may ask the user to re-enable the accessibility service once.
- **New tests:** `CoverLayoutPolicyTest` (7), `PipDismissGeometryTest` (5). 33 JUnit tests in total.

Extra manual steps: drag the PiP around the screen (cover follows without lag), pinch-resize it
(layout switches), tap Close on the cover (PiP closes, or at worst the cover stays), and check that
the cover is removed once the PiP is gone.

## Addendum 2: device feedback round 2 (OPPO, Android 15)

Findings (checked against the phone's persisted prefs, `dumpsys accessibility`, and AOSP docs):

1. **No cover after closing Pace and opening YouTube.** `FocusSessionManager`'s `JSONObject.toMap()` was shallow,
   so a restored session had `blockedApps` as a `JSONArray` and `FocusSession.fromMap` read it as an empty list.
   Any restart of the process restored a session that blocked nothing. Fixed with the recursive
   `JsonConversion` (also used for `blockedWebsites`, `interruptions`, `pomodoroData`). Covered by `JsonConversionTest`.
2. **Close button "expanded YouTube".** The gesture dismiss tapped the PiP centre. AOSP's PiP tap behaviour
   (commit 352f35ddaf8c) resizes a PiP that is too small for its menu, so the follow-up blind tap hit the wrong
   target. Gestures removed, along with `canPerformGestures`, `PipDismisser` and the geometry tests.
   Close now launches the blocked app's launcher intent (same as tapping its icon: pulls it out of PiP)
   then sends the user to Pace after 350 ms. The cover keeps covering during the swap. Non-PiP windows go Home.
3. **Diagnostics:** cover logs `touch DOWN on cover`, `Close clicked`, and the enforcer logs `Close tapped`.
   This distinguishes "touches never reach the cover" from "handler ran and the action was wrong".

Not fixable in code: OPPO/ColorOS can stop an accessibility service when the app is swiped from Recents.
Mitigation is device settings (lock the app in Recents, allow auto-launch/background, unrestricted battery).

Manual: start a session, swipe Pace from Recents, open YouTube: cover/eject must still happen (watch
`adb logcat -s FocusWindowEnforcer FocusSessionManager`). Then PiP test: drag (cover follows), tap Close.

## Addendum 3: behaviour rules confirmed by the user (final)

- **Full-screen blocked app:** no cover. Record the interruption and bring Pace forward (original behaviour).
- **PiP:** cover is visual only (`FLAG_NOT_TOUCHABLE`). Touches pass through so the system's own controls
  (expand, close, drag, drag-to-bottom dismiss) work. Cover follows the window and hides while the PiP menu
  window is open so its buttons are visible. Never ejected, no Close button, no gestures.
- **Split pane / freeform:** cover that blocks touches inside that window only. NEVER press Home or exit
  split-screen: the allowed pane stays usable. (Earlier build pressed Home for non-full-screen windows, which ended
  split-screen and removed the cover immediately: the cause of "no cover appeared / split closed".)
- **Media:** the blocked app's media session is paused behind the cover (`BlockedMediaPauser`, only that app,
  only if playing/buffering, throttled to 0.7 s). Needs Pace notification access; without it, logs a warning once.
  Cannot pause apps with no media session (Android offers no way to freeze an arbitrary app).
- Removed: `PipDismisser`, `canPerformGestures`, Close button, expand-then-eject.
- Tests: 42 JUnit tests (policy per window kind, media-pause states, JSON restore, layout thresholds).

## Addendum 4: regression round (split-screen not detected, normal open not ejected)

Found by re-reading the code (phone was disconnected, so no logs):
1. Attempts were tracked per package. A blocked app seen first in a PiP/split pane (covered, no eject) and then
   going full screen is the same package continuously on screen, so the eject never fired. Fixed: `AttemptTracker`
   tracks "visible" and "full-screen" separately. Covered by `AttemptTrackerTest` (pane -> full, PiP -> full, reopen, reset).
2. `FocusMonitoringService` disabled its original full-screen blocking whenever the enforcer object existed.
   Now it defers only while `FocusWindowEnforcer.isHealthy()` (evaluated within 6 s), so a stalled enforcer can't
   switch off full-screen blocking.
3. A failed eject was never retried. Now retried every 1.5 s while a full-screen blocked window is still there.
4. The Android 14+ attached overlay had been made the default without ever being seen rendering on a device.
   It stays in the code behind `USE_ATTACHED_OVERLAY = false`; the floating overlay (verified on device) is the default.
5. Window package falls back to the last window-state event when `root.packageName` is unreadable.
6. One log line per change of blocked windows ("Blocked windows now: ...") so logs show what was seen.

Needs a device run: split-screen (allowed + blocked pane), PiP drag/menu, full-screen eject after each.

## Addendum 5: split-screen verified on device; Pace's own screen overflowed in a short window

- **Split-screen bug cause (from the device log):** a pane sliding in passed through `0,397-1080,2412` (83% of the
  screen height) for one frame. The 80% full-screen threshold treated it as a normal full-screen app and ejected to
  Pace, which replaced the pane and removed the cover. Fixed: threshold 90% plus `StableFullScreenGate` (a window must
  look full screen for 400 ms continuously before it counts). One interruption per attempt via `RecordThrottle` (2 s).
- **Device result after the fix:** Pace in the top pane, YouTube pane covered ("YouTube is blocked" + Back to Pace),
  no jump. Floating window covered at exact bounds. Full-screen open ejects to Pace about 0.4 s after launch, once.
- **Pace's focus screen overflowed ("BOTTOM OVERFLOWED BY 208 PIXELS") in a half-height pane.** `active_focus_screen.dart`
  stacked fixed-height blocks in a Column. Now wrapped in `LayoutBuilder` + `SingleChildScrollView` +
  `ConstrainedBox(minHeight)` + `IntrinsicHeight`, so full height is unchanged (Spacer expands) and short windows
  scroll. Verified by temporarily running `adb shell wm size 1080x1250`, then `wm size reset`.
- 62 JUnit tests pass; `flutter analyze` clean.
