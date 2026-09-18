# Go Router migration for app entry flow

## Goal

Replace the current "one widget swaps between screens depending on what it watches" pattern in `SplashScreen` with real `go_router` routes, so that:
- Auth/onboarding/permission/active-session gating logic lives in a `redirect` function, not inside a View's `build()`.
- The primary app flow (Entry → Onboarding → Permissions → Home / ActiveSession) has real routes instead of conditional widget returns.
- The unused `go_router` dependency (already in `pubspec.yaml`) actually gets used.

This directly fixes the root cause of the permission-check-flood bug fixed earlier this session (patched with a one-shot flag in `SplashScreen`, but the underlying design — routing decisions mixed into a View that also watches a ticking provider — is unchanged and can regress the same way again).

## Skills read

- `flutter-apply-architecture-best-practices` — View/ViewModel separation; routing/gating decisions are business logic, not UI logic.
- `flutter-setup-declarative-routing` — `go_router` core concepts, `redirect`, `GoRoute`, programmatic navigation via `context.go`/`context.push`.

## Code inspected

- `lib/main.dart` — `MaterialApp(home: SplashScreen(), routes: {'/manage-blocked-apps': ...})`. Global `ErrorWidget.builder` "Restart App" button does `pushAndRemoveUntil(... SplashScreen)`.
- `lib/presentation/screens/splash_screen.dart` — full file. `_SplashScreenState`:
  - `initState()` calls `_checkActiveSession()`: waits 100ms, calls `NativeService.getCurrentSessionStatus()`, if active syncs via `focusSessionProvider.notifier.refreshSessionFromNative()`, then sets `_hasCheckedSession = true`.
  - `build()` watches `isAuthenticatedProvider`, `currentUserProvider`, `authLoadingProvider`, `authErrorProvider`, `focusSessionProvider`, and (nested, inside the authenticated+onboarded branch) `permissionProvider`. Returns, in order: `_LoadingScreen` (while loading / `!_hasCheckedSession`) → `_ErrorScreen` (auth error) → `EntryScreen` (not authenticated / null user) → `OnboardingScreen` (`!user.hasCompletedOnboarding`) → `PermissionScreen` (`!permissionState.allGranted`) → `ActiveFocusScreen(sessionId, plannedDuration, sessionType)` (`focusSession.isActive`) → `HomeScreen` (else).
  - Already has a `_hasCheckedPermissions` one-shot flag (added this session) gating the permission-check `Future.microtask`.
- `lib/presentation/screens/entry_screen.dart` — stateless, no navigation calls itself (auth handled via a bottom sheet, `AuthActionsBottomModel`).
- `lib/presentation/screens/onboarding/onboarding_screen.dart` — internal step nav via `IndexedStack` keyed on `onboardingProvider.currentPage`. Not part of this migration's scope (intra-screen nav, already correct pattern).
- `lib/presentation/screens/onboarding/procrastination_screen.dart:129` — `Navigator.of(context).pushReplacementNamed('/')` after onboarding completes.
- `lib/presentation/screens/permission_screen.dart:182` — `Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false)` after permissions completed.
- `lib/presentation/screens/home_screen.dart` — `StatefulWidget`, local `_selectedIndex` + `NavigationBar` for its 5 tabs (Focus/Groups/Blocks/Usage/Insights). Not part of this migration's scope (intra-screen nav).
- `lib/presentation/screens/focus_screen.dart:123-131` — `Navigator.of(context).push(MaterialPageRoute(builder: (context) => ActiveFocusScreen(sessionId: ..., plannedDuration: ..., sessionType: ...)))` — **second, independent construction site for `ActiveFocusScreen`**, used when the user manually starts a session from the Focus tab (as opposed to `SplashScreen` picking it up on cold start because a session was already active).
- `lib/presentation/screens/active_focus_screen.dart`:
  - `_navigateToHome()` (lines ~200-219): `if (Navigator.of(context).canPop()) { Navigator.of(context).pop(); }` with **no else** — relies on the old implicit behavior where, if `ActiveFocusScreen` was swapped in by `SplashScreen` (not pushed), `canPop()` is false and nothing happens; "going home" only actually happens because the Riverpod state change makes `SplashScreen.build()` rerun and return `HomeScreen` instead.
  - `_navigateToSaveScreen()` (lines ~160-197): `Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => SaveSessionScreen(sessionData: sessionData)))`, where `sessionData` is a `Map<String, dynamic>` from `focusSessionProvider.notifier.getCurrentSessionData()`.
- `lib/presentation/screens/save_session_screen.dart:114-117` and `:188-193` — both `Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (route) => false)`, after successful save and after discard, respectively.
- Grep confirmed: no other call site constructs `EntryScreen`, `OnboardingScreen`, `PermissionScreen`, or `HomeScreen` directly; `'/manage-blocked-apps'` is currently unreferenced by any `pushNamed` call anywhere in `lib/` (dead route, flagged, out of scope — left alone).

## Decisions and assumptions

1. **New route table:**
   - `/splash` — bootstrap/loading gate. `initialLocation`. Shows a loading indicator while auth/session-check is in flight; otherwise `redirect` immediately routes away from it. This becomes the *only* place gating logic runs.
   - `/welcome` — `WelcomeScreen` (renamed from `EntryScreen`/`entry_screen.dart` before wiring routes — "Entry" was ambiguous with "app entry point"; this is the pre-login landing/CTA page, so `WelcomeScreen` matches what it actually is. `kEntryBackgroundImage` also renamed to `kWelcomeBackgroundImage` in `lib/core/constants/images.dart` for consistency; the underlying asset file path is unchanged.)
   - `/onboarding` — `OnboardingScreen`
   - `/permissions` — `PermissionScreen`
   - `/home` — `HomeScreen`
   - `/active-session` — `ActiveFocusScreen`, reads `sessionId`/`plannedDuration`/`sessionType` from `extra` (a small record/map; not URL query params, since these are internal session values, not deep-linkable state)
   - `/save-session` — `SaveSessionScreen`, reads `sessionData` (`Map<String, dynamic>`) from `extra`
   - `/manage-blocked-apps` — carried over as-is (currently unused, kept for parity, zero behavior change)
2. **Bootstrap logic moves out of the View.** Replace `_SplashScreenState`'s `initState`/`_checkActiveSession`/`_hasCheckedSession` with a small `appBootstrapProvider` (`FutureProvider<void>` or similar) that does the same `NativeService.getCurrentSessionStatus()` + `refreshSessionFromNative()` work once. `/splash`'s widget and the `redirect` function both read this provider's state — this is the "pull business logic out of the View" fix from the architecture skill, and it's what makes `redirect` a pure function of provider state instead of needing local `State` flags.
3. **`redirect` replaces `SplashScreen.build()`'s if/else chain, in the same precedence order:** bootstrap loading → auth error → not authenticated → not onboarded → permissions not granted → active session → else allow (go home). Critically, `redirect` only *forces* the active-session and default-home destinations when the current location is `/splash` (i.e., only steers the initial "where do I land" decision) — it must not fight explicit in-app navigation like `focus_screen.dart` pushing `/active-session` on top of `/home`, or a user legitimately sitting on `/home` momentarily. (Auth/onboarding/permission checks are safe to enforce on *every* navigation, since you should never be allowed onto `/home` etc. without them — only the "active session ⇒ jump to session screen" rule is initial-landing-only.)
4. **`ActiveFocusScreen`'s dual entry paths get distinct exits:**
   - Reached via `redirect` from `/splash` (cold start, session already active) → going home calls `context.go('/home')` (no back-stack to pop).
   - Reached via `context.push('/active-session', ...)` from `FocusScreen` → going home calls `context.pop()` (returns to Focus tab).
   - `_navigateToHome()` becomes: `if (context.canPop()) { context.pop(); } else { context.go('/home'); }` — this is the explicit version of what used to happen implicitly.
5. **The two `pushNamedAndRemoveUntil('/')` / `pushReplacementNamed('/')` call sites** (`permission_screen.dart:182`, `procrastination_screen.dart:129`) become `context.go('/splash')` — routes back through the same bootstrap/redirect gate rather than duplicating the "where should I actually land" logic at each call site. This is intentional: single source of truth for the gate decision.
6. **`save_session_screen.dart`'s two `pushAndRemoveUntil(SplashScreen)` calls** become `context.go('/splash')` for the same reason (consistency > shaving one redirect hop).
7. **`main.dart`'s crash-recovery button** (`ErrorWidget.builder`, "Restart App") becomes `context.go('/splash')` — needs verifying this context still has router access at the point `ErrorWidget` is built (it's inside `MaterialApp.builder`, so it should, but flagged as a specific manual test case below since a broken crash-recovery path is bad to ship silently).
8. **No change** to `onboarding_screen.dart`'s internal `IndexedStack` step nav or `home_screen.dart`'s bottom-nav tab switching — both are correct, intra-screen patterns already.
9. **`web` platform / deep linking is out of scope.** This app is Android-only per `AGENTS.md`; skipping the routing skill's URL-strategy/deep-linking workflow entirely (no `usePathUrlStrategy()`, no `AndroidManifest.xml` intent-filter changes).

## Files expected to touch

- `lib/main.dart` — `MaterialApp` → `MaterialApp.router`
- New: `lib/core/router/app_router.dart` — `GoRouter` config + `redirect`
- New: `lib/presentation/providers/app_bootstrap_provider.dart` (or similar) — extracted bootstrap logic
- `lib/presentation/screens/splash_screen.dart` — trimmed to a pure loading-indicator widget; all branching logic removed
- `lib/presentation/screens/permission_screen.dart` — 1 call site
- `lib/presentation/screens/onboarding/procrastination_screen.dart` — 1 call site
- `lib/presentation/screens/focus_screen.dart` — 1 call site
- `lib/presentation/screens/active_focus_screen.dart` — 2 call sites (`_navigateToHome`, `_navigateToSaveScreen`)
- `lib/presentation/screens/save_session_screen.dart` — 2 call sites

No native/Kotlin files, no `AndroidManifest.xml`, no permission-handling logic, no Firestore rules — pure Flutter/Dart routing refactor. Not on AGENTS.md's no-exceptions list, but written up as a prompt anyway per the standard workflow given the size and the fact that it changes app-wide navigation behavior.

## Requirements

- Every existing gating rule (auth → onboarding → permissions → active-session → home) must be preserved exactly — this is a structural refactor, not a behavior change.
- No regression on the dual `ActiveFocusScreen` entry paths (cold-start-into-active-session vs. manually-started-from-Focus-tab) — both must still work, with correct "go back" behavior for each.
- `flutter analyze` clean, `dart format` applied.
- Existing debounce/one-shot fixes from earlier this session (permission-check flood, no-op status-change logging) must survive the refactor — the bootstrap provider must not reintroduce a per-rebuild permission sweep.

## Security/privacy considerations

None beyond what already exists — this is a client-side navigation refactor. No new data exposure, no new permissions requested, no change to what's persisted or transmitted.

## Acceptance criteria

- Fresh install → Entry screen → sign up → Onboarding → Permissions → Home, each transition correct, no back-button regressions introduced (back-stack behavior may reasonably be *new* — e.g., pressing back on `/onboarding` now might pop to `/entry` where today it does nothing — call this out in the report as a UX change, not silently absorb it).
- Kill and relaunch app mid-active-session → lands directly on `/active-session`, no flash of Home/Splash.
- Start a session manually from the Focus tab while already on Home → pushes `/active-session`, and completing/discarding it correctly returns to the Focus tab (not Home, not Splash).
- Complete permissions from `PermissionScreen` → correctly lands on Home (or wherever the redirect chain now says, e.g. back to active session if one exists).
- Force a Flutter error → crash screen's "Restart App" button works.
- `flutter analyze`: 0 issues.

## Checks to run

- `flutter analyze` and `dart format` on every changed file.
- No automated test suite exists for this app (per `AGENTS.md` §13) — this is Dart/UI-only so no native manual-test requirement, but navigation flows must be manually walked end-to-end (see below) since routing bugs won't show up in static analysis.

## Manual test steps

1. Fresh app state (sign out or fresh install): confirm `/entry` shows, sign in, confirm routed to `/onboarding` (if new user) or `/home`.
2. Complete onboarding, confirm routed to `/permissions`.
3. Grant all permissions, confirm routed to `/home`.
4. From Focus tab, start a focus session, confirm `/active-session` is pushed (not a full replace), let it run, end it, confirm it returns to the Focus tab (not Home).
5. Start another session, force-kill the app (not just background), relaunch, confirm it lands directly on `/active-session` showing the still-running session.
6. Save a completed session, confirm it routes correctly afterward (was: back to `SplashScreen` → re-evaluated to Home; should still net out at Home).
7. Discard a session from the save screen, same check.
8. Trigger a Flutter error deliberately (e.g. temporarily throw in a widget), confirm the red crash screen's "Restart App" button actually restarts to `/splash` and re-resolves correctly.
9. Android back button at each of: `/entry`, `/onboarding`, `/permissions`, `/home` — note and report actual behavior (this may differ from today's "does nothing" since these are now real routes with a back-stack; flag anything that looks wrong, e.g. backing out of `/entry` to a blank screen or closing the app unexpectedly).
