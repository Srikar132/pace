# Fix: Block Apps sheet (installed-apps list) lag/stutter

## Goal

`BlockAppsSheet` (opened from Focus tab's "Blocked Apps" row, and from the
Blocks tab flow) freezes/stutters badly on open and while scrolling. Fix the
root cause on both the Dart and native side.

## Skills read

None of the listed skills matched this directly (it's a perf bug, not a
layout-constraint error — `flutter-fix-layout-issues` doesn't apply, checked
and ruled out earlier in this session). Diagnosed by reading the actual
widget tree and native call path instead.

## Code inspected

- `lib/models/block_app_bottom_model.dart` — `BlockAppsSheet`,
  `_CategorySection`, `_AppListTile`, `_AppIcon`.
- `lib/presentation/providers/app_management_provide.dart` —
  `installedAppsProvider`, `groupedAppsProvider`, `appIconProvider`.
- `lib/services/native_service.dart` — `getAppIcon`, `getInstalledApps`.
- `android/app/src/main/kotlin/com/example/pace/MainActivity.kt` —
  `getAppIcon` channel handler (around line 515-532).
- `android/app/src/main/kotlin/com/example/pace/utils/AppUtils.kt` —
  `AppUtils.getAppIcon` (line 178-193), the actual bitmap decode/encode.

## Root cause (two layers, compounding)

1. **Dart — `_CategorySection` (block_app_bottom_model.dart:149-333).**
   Each category section defaults `_isExpanded = true` and renders its apps
   via `Column(children: widget.apps.map((app) => _AppListTile(...)).toList())`
   inside an `AnimatedSize` — not virtualized. `ListView.builder` at the sheet
   level only lazily builds one *category section* per item, but most
   installed apps don't declare an Android PackageManager category, so they
   collapse into one large "Other" bucket — realistically 100-200+ apps on a
   real device. When that section is built, all ~100-200 `_AppListTile`s (and
   their icon fetches) build at once instead of only the visible ones.

2. **Native — `AppUtils.getAppIcon` (AppUtils.kt:178-193).** Every call
   decodes the launcher icon at full native resolution via
   `packageManager.getApplicationIcon(packageName).toBitmap()`, PNG-encodes
   it, and returns the raw bytes — no cache, no downscaling, despite the UI
   only ever rendering it at 24-48dp (`_AppIcon`/`_AppListTile`/`_AppIconCircle`
   all use small fixed sizes). Each of these also completes via
   `withContext(Dispatchers.Main)` in `MainActivity.kt`, hopping onto the
   Android main thread to deliver the byte array over the channel.

Combined: opening the sheet (or scrolling into the "Other" bucket) fires
100-200+ concurrent native calls, each doing a full-res bitmap decode +
lossless PNG encode + a main-thread channel delivery of a large byte array.
That's the freeze — not a widget-tree/layout problem.

## Decisions / assumptions

- Flatten the grouped `Map<String, List<InstalledApp>>` into a single flat
  row list (`header` / `app` rows) and drive `ListView.builder` off that flat
  list, instead of one non-virtualized `Column` per category. This is the
  standard fix for "sectioned list built as nested Column" jank — only
  on-screen rows build/fetch regardless of how lopsided the category sizes
  are.
- Expand/collapse state moves from `_CategorySectionState` (one bool per
  category widget) to a single `Set<String> _collapsedCategories` in
  `_BlockAppsSheetState`, since row flattening now happens at the sheet
  level. Default: all expanded (matches current behavior).
- Drop the `AnimatedSize` collapse animation — rows now enter/leave a
  virtualized list rather than a `Column` resizing, so the old animation
  approach doesn't carry over cleanly. A plain instant collapse is an
  acceptable tradeoff; this prompt is about fixing lag, not preserving that
  animation. (Flag if you want it kept — would need a different animation
  approach.)
- Native: add an in-memory `LruCache<String, ByteArray>` keyed by
  `packageName` (size-bounded, e.g. 300 entries) so repeat requests for the
  same package — which happen constantly as `ListView.builder` recycles
  rows and `appIconProvider` (not `.autoDispose`) gets re-watched — return
  instantly.
- Native: downscale the bitmap to a fixed small size (96x96px) before
  encoding via `Bitmap.createScaledBitmap`, since nothing in the app renders
  these above ~48dp even at 3x density. Note: PNG compression's "quality"
  argument is ignored by Android (PNG is lossless) — the real win here is
  the downscale, not the compress call.
- No new Dart dependencies. Flattening uses a small sealed class, no chart
  or list package needed.

## Files touched

- `lib/models/block_app_bottom_model.dart` — replace `_CategorySection`'s
  nested `Column` with flat-row `ListView.builder` state in
  `_BlockAppsSheetState`.
- `android/app/src/main/kotlin/com/example/pace/utils/AppUtils.kt` — add
  icon cache + downscale to `getAppIcon`.

No changes to `app_management_provide.dart` (providers stay the same shape;
`groupedAppsProvider` output is just consumed differently) or to
`focus_timer_widget.dart`/`focus_time_bottom_model.dart` (their 3-icon
previews already benefit automatically from the native cache).

## Requirements

- Preserve current behavior: search filtering, popular-apps-first sort,
  category grouping, block/unblock toggle per app and per-category "block
  all", parental-control PIN gate on unblock — none of that logic changes,
  only how rows are built and how icons are cached.
- `ListView.builder` must be the only widget doing app-row virtualization —
  no nested unbounded `Column` of app tiles left anywhere in this sheet.
- Icon cache must be bounded (LRU, not unbounded growth) — this runs for the
  life of the process.

## Security/privacy considerations

None — app icons are already fetched from the device's own PackageManager,
no new data leaves the device, no new permission required. The cache is
in-memory only (cleared on process death), not persisted to disk.

## Acceptance criteria

- Opening `BlockAppsSheet` on a device with 100+ installed apps does not
  freeze or drop many frames.
- Scrolling through the list, including into the "Other" category bucket, is
  smooth.
- Repeatedly opening/closing the sheet does not refetch icons already seen
  in this app session (native cache hit).
- Block/unblock toggles, search, and category "block all" switch still work
  identically to before.

## Checks to run

- `flutter analyze` and `dart format` on `block_app_bottom_model.dart`.
- No automated test exists for this widget; none added (per AGENTS.md, only
  add tests for new meaningful *logic* — this is a rendering/perf fix, not
  new business logic). Native Kotlin change has no automated check either.
- **Manual verification required** (native + perf changes, no CI):

## Manual test steps

1. On a real Android device/emulator with 80+ installed apps (an emulator
   with only a handful of apps won't reproduce the "Other" bucket size that
   causes the freeze — test on a real device if possible).
2. Open the Focus tab, tap "Blocked Apps" (or reach `BlockAppsSheet` via the
   Blocks tab flow) — sheet should open without a visible freeze/jank.
3. Scroll through the full list, including scrolling into whatever category
   has the most apps (likely "Other") — should stay smooth, no stutter.
4. Toggle block on/off for a couple of individual apps — confirm it still
   updates Firestore/blocked state correctly (check reflected in Blocks tab).
5. Toggle a whole category's switch on/off — confirm all apps in that
   category block/unblock together.
6. Search for an app by name — confirm filtering still works and the
   filtered list is also smooth.
7. Close and reopen the sheet a few times — icons should appear
   near-instantly on reopen (native cache hit), not re-spinner-load each
   time.
8. If parental control is enabled, confirm the PIN prompt still appears
   when unblocking.
