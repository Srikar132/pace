# Fix focus session Flutter↔Kotlin bridge bugs (complete, stop/continue)

## Goal

Fix six confirmed bugs in the focus-session pause/resume/complete flow, spanning the Dart↔Kotlin
method/event channel bridge (`com.lockin.focus/native`, `com.lockin.focus/events`). Two are
enforcement-breaking (native), the rest are data-integrity/UX (mostly Dart). No new features,
no refactor beyond what each fix needs.

## Skills read

- `flutter-apply-architecture-best-practices` — confirms provider/repository separation already
  in use (Notifier + Repository pattern); fixes below stay inside that shape, no layer changes.
- `dart-add-unit-test` — used to decide what's actually testable: pure Dart logic (repository
  batch payload, discard cleanup, race guard) gets unit tests; Kotlin service lifecycle and
  platform-channel behavior can't be unit tested (per AGENTS.md §13) and gets manual steps instead.
- `dart-run-static-analysis` / `dart-fix-runtime-errors` — checklist for the mandatory
  `dart analyze` / `dart fix --apply` / `dart format` pass after edits.

## Code inspected

- `lib/services/native_service.dart` — channel wrapper, all focus-session methods.
- `lib/presentation/providers/focus_session_provider.dart` — `FocusSessionNotifier`, event
  handling, local timer, save/discard flow.
- `lib/presentation/screens/active_focus_screen.dart`, `save_session_screen.dart`.
- `lib/data/repositories/focus_session_repository.dart`, `lib/data/models/focus_session_model.dart`.
- `android/app/src/main/kotlin/com/example/pace/MainActivity.kt` (method channel handlers,
  `syncSessionIfActive`).
- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusSessionManager.kt`
  (session lifecycle, timer, event emission).
- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusMonitoringService.kt`
  (foreground monitoring service, blocked-apps cache).
- `android/app/src/main/kotlin/com/example/pace/models/FocusSession.kt`.
- Confirmed `FocusModeManager.kt` / `PromodoroManager.kt` / `FocusActionReceiver.kt` are a
  separate legacy system (app-limit overlay related, wired through `AppLimitManager`/
  `UsageStatusJobService`/`BlockOverlayActivity`) — **not** touched by this fix, not part of the
  new `services/focus/` session architecture.

## Bugs and fixes

### 1. CRITICAL (native) — auto-complete leaves `FocusMonitoringService` stuck, breaks next session

**Where:** `FocusSessionManager.kt` timer `Runnable` (`startTimer`, "timer" branch) calls
`endSession()` directly when `remaining <= 0`. `FocusMonitoringService.stop()` is only invoked
from `MainActivity`'s `endFocusSession` method-channel handler — never reached on natural
completion.

**Effect:** `FocusMonitoringService.isMonitoring` stays `true` forever. The stale foreground
notification never clears. Worse: the next `startFocusSession` call invokes
`FocusMonitoringService.start()` → `startMonitoring()` sees `isMonitoring == true` → returns
early → `updateBlockedAppsCache()` never runs → the next session enforces the **previous**
session's blocked-apps list (or none).

**Fix:** Give `FocusSessionManager` a way to signal "session ended, stop monitoring" back out,
instead of only reacting to the method-channel call:
- Add a lightweight listener/callback interface on `FocusSessionManager`
  (e.g. `var onSessionEnded: (() -> Unit)? = null`, or reuse the existing `sendEvent` path) that
  `MainActivity` registers in `initializeManagers()`, calling
  `FocusMonitoringService.stop(this)` whenever it fires — covering both the manual
  `endFocusSession` path and the internal auto-complete path.
- In `endSession()`, invoke that callback right before/after clearing state, regardless of
  which caller triggered it.
- In `MainActivity`'s `endFocusSession` handler, keep calling `FocusMonitoringService.stop()`
  too is fine (idempotent — `stopMonitoring()`/`stopSelf()` already tolerate being called when
  already stopped), OR simplify by removing that direct call once the callback covers it —
  pick whichever keeps the diff smaller; do not leave both paths racing to double-stop in a way
  that throws.
- In `FocusMonitoringService.startMonitoring()`, don't treat "already monitoring" as fully safe
  to no-op — at minimum call `updateBlockedAppsCache()` on every `ACTION_START`, even if a stale
  loop is still marked running, so a new session never inherits a stale blocked-apps list. Better:
  fix root cause (bullet above) so `isMonitoring` is never stuck true, and keep the existing
  early-return as a genuine idempotency guard.

### 2. HIGH (native + Dart) — race: manual "Stop" pressed as native timer completes

**Where:** `FocusSessionNotifier.endSession()` sets `_isManuallyEnding = true` before calling
`NativeService.endFocusSession()`. If the native timer already self-completed a moment earlier,
`FocusSessionManager.endSession()` returns `false` (guard: `if (!isActive) return false`), so
Dart's call throws `Exception('Failed to end native session')`, landing in `FocusSessionStatus.error`
— the already-completed session's data is dropped (no save screen, no Firestore write), because
the earlier `session_completed` event was ignored (flag was already `true`).

**Fix (Dart side):** In `FocusSessionNotifier.endSession()`, when `NativeService.endFocusSession()`
returns `false`, don't immediately treat it as failure — call
`NativeService.getCurrentSessionStatus()` (or reuse `refreshSessionFromNative`) to check whether
the native side reports no active session (i.e. it already completed). If so, treat this as a
completed session using the best available data (`state.elapsedMinutes` /
`state.plannedDuration`) and route to `FocusSessionStatus.endingWithSave` exactly like the happy
path, instead of `error`. Only surface a real error if native genuinely couldn't process the
request for another reason.

### 3. HIGH (Dart) — native's authoritative duration is computed but never used

**Where:** `FocusSessionManager.kt.endSession()` computes real `actualDuration`/`completionRate`
from wall-clock `sessionStartTime` and sends it in the `session_completed` event payload.
`FocusSessionNotifier._saveCompletedSession()` and `.completeSessionWithNotes()` both ignore that
payload and use `state.elapsedMinutes`, which comes from the Dart-side `Timer.periodic` — subject
to drift if the Flutter engine is throttled/backgrounded while the native foreground-service timer
keeps ticking accurately.

**Fix:** Thread the native `actualDuration` through. Store the last `session_completed`/
`session_auto_completed` event's `data` on `FocusSessionState` (new nullable field, e.g.
`nativeCompletionData`), and prefer `data['actualDuration']` (native, minutes — verify unit;
native sends raw ms in `totalElapsed` and a pre-computed minute value in `actualDuration`, use the
latter) over `state.elapsedMinutes` when present, falling back to `elapsedMinutes` only if the
native event never arrived (e.g. the code path from bug #2's fallback).

### 4. MEDIUM (Dart) — `completionRate` hardcoded to 100% on save

**Where:** `FocusSessionRepository.completeSession()` always writes `'completionRate': 100.0`,
even for an early/partial manual stop.

**Fix:** Add a `completionRate` parameter to `completeSession(...)`, compute it in the provider as
`plannedDuration > 0 ? (actualDuration / plannedDuration * 100).clamp(0, 100) : 100.0` (mirroring
the native calc in `FocusSessionManager.kt.endSession()`), and pass it through instead of the
hardcoded literal.

### 5. MEDIUM (Dart) — discard leaves an orphaned `status: active` Firestore doc

**Where:** `FocusSessionNotifier.startSession()` creates a Firestore doc via
`sessionRepositoryProvider.createSession()` with `status: 'active'` immediately at session start.
`discardSession()` only resets local state — never touches that doc, so a discarded session stays
`active` in Firestore forever (pollutes `todaySessionsProvider` and any streak/insights query
filtering on status/date).

**Fix:** Add a `deleteSession(String sessionId)` method to `FocusSessionRepository` (simple
`_firestore.collection('focusSessions').doc(sessionId).delete()`), and call it from
`discardSession()` before resetting state, guarded by `state.sessionId != null`. Keep it
fire-and-forget with error logging (matches existing style in this file) — don't block the UI
reset on it.

### 6. LOW (native) — pause doesn't stop the monitoring loop/notification

**Where:** `FocusMonitoringService.checkCurrentApp()` returns early when
`sessionManager.isSessionPaused()`, but the 1.5s polling loop and the "Focus Session Active"
foreground notification keep running during a pause.

**Fix:** On `session_paused`, have `MainActivity` (or the callback from bug #1) call a new
`FocusMonitoringService.pause(context)` / `.resume(context)` pair that stops/restarts the
`handler.postDelayed` loop and swaps the notification text to reflect "Paused" (reuse
`createNotification()`, add a paused-state branch). Keep the service alive (don't `stopSelf()`)
so resume doesn't need `startForeground()` again. Wire `resumeFocusSession` in `MainActivity` to
call `.resume()`.

## Decisions and assumptions

- Fixing all 6, per user's "find complete end-to-end bugs" + explicit go-ahead, not just the two
  enforcement-breaking ones.
- Bug #1's fix uses a callback/listener rather than having `FocusMonitoringService` poll
  `FocusSessionManager.isSessionActive()` on a timer — keeps `services/focus/` responsibilities
  as documented (AGENTS.md §5: `FocusSessionManager` = session mgmt, `FocusMonitoringService` =
  monitoring only) without adding a new polling loop.
- Bug #3's `nativeCompletionData` field is additive to `FocusSessionState`, not a replacement for
  `elapsedSeconds`/`elapsedMinutes` — those stay as the real-time UI display driver; only the
  *final save* prefers native data.
- Not touching `FocusModeManager.kt`/`PromodoroManager.kt`/`FocusActionReceiver.kt` — confirmed
  separate legacy system, out of scope (AGENTS.md §11 legacy-≠-dead warning).
- Not addressing the dual-timer redundancy (Dart local `Timer.periodic` + native `timer_update`
  events both driving `elapsedSeconds`) — cosmetic overlap, not a correctness bug once #3 makes
  the *saved* duration authoritative from native; leaving the live countdown display as-is to
  keep the diff scoped.

## Files expected to touch

- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusSessionManager.kt`
- `android/app/src/main/kotlin/com/example/pace/services/focus/FocusMonitoringService.kt`
- `android/app/src/main/kotlin/com/example/pace/MainActivity.kt`
- `lib/presentation/providers/focus_session_provider.dart`
- `lib/data/repositories/focus_session_repository.dart`
- New: `test/data/repositories/focus_session_repository_test.dart` (or wherever `test/` mirrors
  the repo path) and/or `test/presentation/providers/focus_session_provider_test.dart` for the
  testable pieces (completionRate calc, discard-deletes-doc, bug #2's fallback branch) — exact
  scope depends on what's mockable without pulling in real Firestore/platform channels.

## Requirements

- No behavior change to session start, or to blocking logic inside `checkCurrentApp()` itself.
- `FocusMonitoringService` must never end up in a state where `isMonitoring == true` but no
  active session exists, across an arbitrary sequence of natural-complete → start → natural-complete.
- Pause/resume must not require the user to re-grant any permission or re-trigger
  `startForeground()` (avoid `ForegroundServiceStartNotAllowedException` on resume after pause).
- Firestore writes stay batched where they already are (`completeSession`'s `WriteBatch`) —
  don't split that into multiple round-trips.

## Security / privacy

- No new data leaves the device differently than before; `deleteSession` only removes the
  user's own session doc (already scoped by `sessionId` created client-side for that user).
- No permission or manifest changes required for any of the 6 fixes.

## Acceptance criteria

1. Let a short (~1 min) `timer`-type session run to natural completion. Immediately start a
   second session with a *different* blocked-apps list. Confirm the second session's monitoring
   notification and enforcement reflect the *new* list, not the first session's.
2. Confirm the foreground "Focus Session Active" notification disappears within ~1s of natural
   completion (not just on manual stop).
3. Start a `timer` session with a very short duration; tap "Stop focusing" within the same
   ~100–300ms window the timer would naturally complete (repeat a few times to hit the race).
   Confirm the app always lands on the save screen (or home) with correct data — never stuck on
   an error snackbar with the session silently lost.
4. Complete a session normally; confirm the saved `actualDuration` in Firestore matches native's
   wall-clock elapsed time even if the app was backgrounded for several seconds mid-session.
5. Start a session, manually stop it early (e.g. 5 of 25 planned minutes), save it. Confirm the
   Firestore doc's `completionRate` is ~20%, not 100%.
6. Start a session, discard it from the save screen. Confirm the Firestore doc created at session
   start no longer exists (or is deleted, per repository choice above) — not left as `status: active`.
7. Pause a session; confirm the monitoring notification updates to a paused state and CPU/battery
   polling stops (no more `checkCurrentApp` log lines while paused). Resume; confirm blocking
   resumes without any permission prompt or crash.

## Checks to run

- `dart analyze` and `dart fix --apply` (dry-run first) on all touched Dart files, then
  `dart format .`.
- `flutter test` (existing suite) plus any new tests added under Files above.
- Native/Kotlin changes: no automated check exists (AGENTS.md §13) — manual verification only,
  via the acceptance criteria above on a real device/emulator with usage-stats + accessibility
  + battery-optimization-exemption permissions already granted.

## Manual test steps (run on real device/emulator)

1. Grant all focus-session-relevant permissions (usage stats, accessibility, overlay, battery
   exemption) via the existing permission screens.
2. Set a `timer` session for 1 minute with 2–3 blocked apps (e.g. a browser + one game). Start it,
   background the app, open a blocked app — confirm it's still blocked/redirected.
3. Let the timer hit 0 without touching the app. Watch `adb logcat` for `FocusMonitoringService`
   and `FocusSessionManager` tags — confirm `stopMonitoring`/`STOP_FOREGROUND_REMOVE` fires, and
   the "Focus Session Active" notification clears.
4. Immediately start a new 1-minute session with a *different* single blocked app (not in the
   previous list). Open the app that was blocked in session 1 but not session 2 — confirm it is
   NOT blocked. Open the newly-blocked app — confirm it IS blocked. (Regression check for bug #1.)
5. Start another session; near the end, spam-tap "Stop focusing" repeatedly in the final second
   before natural completion. Confirm you land on the save/home screen with sane duration data,
   never an error snackbar. (Bug #2.)
6. Start a session, background the app for 30+ seconds (switch to another app without triggering
   the blocker, e.g. via notification shade), return, let it complete. Compare the saved duration
   to a stopwatch — should match native elapsed time within a couple seconds. (Bug #3.)
7. Start a 25-minute timer session, manually stop at ~5 minutes, save. Check the Firestore
   `focusSessions` doc — `completionRate` should be ~20%, `actualDuration` ~5. (Bug #4.)
8. Start a session, discard from save screen. Check Firestore — no lingering `status: active` doc
   for that `sessionId`. (Bug #5.)
9. Start a session, pause, wait 10s, check notification text changed and no new
   `checkCurrentApp` log lines appear, resume, open a blocked app — confirm blocking still works
   and no permission dialog/crash occurred. (Bug #6.)
