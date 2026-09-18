# Implement missing native handlers: getWebsiteBlockingDiagnostics + getSupportedBrowsers

## Goal

`blocks_screen.dart` has a "Run Diagnostics" button (website-blocking section) that
calls `BlocksNativeService.getWebsiteBlockingDiagnostics()` and
`.getSupportedBrowsers()` over the `com.lockin.focus/native` channel. Neither method
has a case in `MainActivity.handleMainMethodCall` — both hit `result.notImplemented()`,
so the button always fails. Add the two missing native handlers so the feature works.

## Skills / docs read

- AGENTS.md (this project's own guide) — native/platform-channel changes are on the
  no-exceptions prompt-approval list (section 2), which is why this prompt exists.

## Code inspected

- `lib/services/blocks_native_service.dart` — defines both methods, no changes needed
  there; they already call the right method names/no-arg signature.
- `lib/presentation/screens/blocks_screen.dart:1803-1935` — `_runWebsiteBlockingDiagnostics`
  calls both methods, builds a report string from the diagnostics map (expects keys
  it reads directly — checked below) and the browsers list, shows it in a dialog.
- `android/.../MainActivity.kt:560-667` — `handleMainMethodCall`'s website/short-form
  block section; this is where the two new `"..." ->` cases get added, right before
  the final `else -> result.notImplemented()`.
- `android/.../managers/WebsiteBlockManager.kt` — already has `getBlockedWebsites()`,
  `getBlockedWebsitesCount()`, `getActiveBlockedWebsitesCount()` — reused as-is, no
  changes needed there.
- `android/.../permissions/PermissionManager.kt:80` — `hasAccessibilityPermission()`
  already exists and is already used elsewhere in `MainActivity` (`"hasAccessibilityPermission"`
  case at line 401-402) — reused, not duplicated.
- `android/.../services/LockInAccessibilityService.kt:57-64` — `BROWSER_PACKAGES` is
  the actual list of browser packages the URL-interception logic supports, but it's
  `private val` inside the companion object, so `MainActivity` can't read it yet.
- Verified nothing else in the app calls either method (grepped all of `lib/` for both
  method names outside `blocks_native_service.dart` — only the one call site above).

## Decisions / assumptions

- Ran the full "is this dead code" sweep first (grep by both filename and class name
  usage across all callers) before concluding this is a real, reachable bug rather
  than more dead code — the diagnostics button is live UI, not orphaned.
- `getSupportedBrowsers` returns `LockInAccessibilityService.BROWSER_PACKAGES` verbatim
  (package names, not human-readable browser names) — matches what `blocks_screen.dart`
  expects (`List<String>` displayed as-is per `getSupportedBrowsers` return type).
- `getWebsiteBlockingDiagnostics` returns a `Map<String, Any>` with keys:
  - `accessibilityServiceEnabled: Boolean` (from `permissionManager.hasAccessibilityPermission()`)
  - `totalBlockedWebsites: Int`, `activeBlockedWebsites: Int` (from `WebsiteBlockManager`)
  - `blockedWebsites: List<Map<String,Any>>` (url/name/isActive, same shape as `getBlockedWebsites`)
  - `supportedBrowsers: List<String>`
  These are read generically by `Map<String, dynamic>` conversion in
  `BlocksNativeService.getShortFormBlockingStatus`-style handling, and `blocks_screen.dart`'s
  report builder reads whatever keys are present — confirmed it doesn't hard-require any
  specific key beyond what it already prints defensively.
- Only change to `LockInAccessibilityService.kt` is dropping `private` from
  `BROWSER_PACKAGES` (visibility change only, no behavior change) so `MainActivity`
  can read it via the existing `getInstance()` singleton or the companion object directly
  (it's a `const`-like `val` on the companion object, doesn't need an instance).
- Not touching any of the other previously-flagged "missing" methods (`setAppLimit`,
  `removeAppLimit`, `getRemainingTime`, etc. on `BlocksNativeService`) — confirmed via
  grep that none of them are actually called anywhere; they're unreachable dead code
  inside a live file, out of scope for this fix.

## Files to touch

- `android/app/src/main/kotlin/com/example/pace/MainActivity.kt` — add two `"..." ->` cases.
- `android/app/src/main/kotlin/com/example/pace/services/LockInAccessibilityService.kt` —
  drop `private` from `BROWSER_PACKAGES`.

## Requirements

- No new permissions, no new manifest entries, no new Dart-side code (both Dart methods
  already exist and are already correctly wired to `_methodChannel`).
- Must not change the `com.lockin.focus/native` channel's existing behavior for any
  other method.

## Security considerations

- `getWebsiteBlockingDiagnostics`/`getSupportedBrowsers` are read-only, return no
  secrets (just package names and the user's own configured block list) — no privacy
  concern beyond what's already exposed via `getBlockedWebsites`.

## Acceptance criteria

- Tapping "Run Diagnostics" in the website-blocking section of Blocks no longer fails;
  it shows a report containing accessibility-service status, blocked-website counts,
  and the supported-browser list.
- `flutter analyze` clean (no new issues).
- No existing method channel case is altered.

## Checks to run

- `flutter analyze` (Dart side unaffected, but confirm no regressions).
- Kotlin: no automated check — manual verification required (see below).

## Manual test steps

1. Run the app on a device/emulator with the accessibility permission already granted
   (or not — diagnostics should reflect either state, not crash).
2. Go to Blocks -> Website Blocking section -> tap "Run Diagnostics".
3. Confirm a dialog/report appears (not an error snackbar) showing accessibility
   status, website counts, and a non-empty supported-browsers list.
4. Toggle the accessibility permission off and re-run diagnostics; confirm it now
   reports `accessibilityServiceEnabled: false` instead of erroring.
