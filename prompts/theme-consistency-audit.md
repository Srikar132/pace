# Theme consistency audit — remove hardcoded hex, route all color through AppTheme/AppColors

## Goal

`lib/core/theme/app_theme.dart` defines `AppTheme.darkTheme` + `AppColors`, but 357 raw
`Color(0x......)` literals across 27 files bypass it (different agent sessions hardcoded
their own hex over time). Result: near-duplicate shades drifting from the real palette, and
one whole surface (the overlay engine) rendering in indigo/purple instead of app's green.
Goal: single source of truth — every color in `lib/` resolves through `Theme.of(context)`
or `AppColors`, zero raw hex left except one documented third-party-brand exception.

## Skills / files read

- `lib/core/theme/app_theme.dart` — full read, `AppTheme.darkTheme` (ColorScheme + all
  component themes) + `AppColors` (20 raw constants).
- `lib/presentation/overlays/overlay_app.dart` — root cause of overlay off-brand colors:
  builds its own inline `ThemeData` with `primary: Color(0xFF6366F1)` / `secondary:
  Color(0xFF8B5CF6)` instead of importing `AppTheme.darkTheme`.
- Grepped all `Color(0x......)` literals in `lib/` (357 hits, 53 distinct values, 27 files)
  and inspected context of every non-obvious one: `active_focus_screen.dart` (session-type
  color switch), `group_screen.dart`/`group_detail_screen.dart` (avatar color list,
  byte-identical copy-paste between the two files), `lumo_voice_bot_screen.dart` (voice
  state color switch), `create_group_screen.dart` (WhatsApp share button),
  `focus_time_bottom_model.dart` (PRO badge), overlay screens' gradient backgrounds.
- No architecture/layout skill needed — this is a mechanical literal-to-token substitution,
  not a structural refactor.

## What's in scope vs not

- In scope: `Color(0xAARRGGBB)` / `Color(0xRRGGBB)` literals.
- Not in scope (separate concern, not asked for): raw `Colors.white`/`Colors.black54`/
  `Colors.transparent`/`Colors.grey[...]` usage. Leaving these — they're Flutter's own
  named constants, not drifted hex, and touching them would balloon the diff far beyond
  what was asked.

## Decisions (confirmed with user)

1. **Overlay engine matches main theme.** `OverlayApp` currently hand-rolls a second
   `ThemeData` instead of using `AppTheme.darkTheme`. Fix: `OverlayApp`'s
   `MaterialApp.router` uses `theme: AppTheme.darkTheme` directly — one definition, both
   Flutter engines, no future drift possible. The 4 blocked-overlay screens'
   gradient backgrounds (currently navy `0xFF1A1A2E→0xFF16213E`, maroon
   `0xFF1A1A1A→0xFF2D1B1B`/`0xFF2A1A2A`, near-black `0xFF000000→0xFF0D0D0D`, blue-black
   `0xFF0F1419→0xFF1A1F2E`) get re-themed to dark-green gradients built from
   `AppColors.background`/`surface`/`primaryGreen`/`darkGreen` so blocked screens read as
   the same app, not a different product.
2. **Near-duplicate drift shades consolidate into the existing token**, not kept separate:
   - `0xFF2D2D2D` (15× in group screens) → `AppColors.surfaceElevated` (`0xFF2A2A2A`)
   - `0xFFFF8C00` (2×, usage-stats dot/legend) → `AppColors.warning` (`0xFFFFB84D`)
   - `0xFFFFB800` (PRO badge) → `AppColors.proYellow` (`0xFFFFD700`)
   - `0xFF6BB84D` (profile gradient stop) → `AppColors.darkGreen` (`0xFF5CAF3C`) or
     `lightGreen` (`0xFF8FD66E`) — pick whichever renders closer in the actual gradient;
     verify visually, don't just nearest-hex-guess.
3. **"Semantic" palettes (avatar list, Lumo voice states, session-type colors) are not
   intentional design — confirmed by user as accidental cross-agent drift.** Reuse the
   *existing* `AppColors` tokens for these instead of inventing new ones or keeping the
   current ad hoc hues:
   - Group avatar list (`group_screen.dart` L11-20, byte-identical duplicate in
     `group_detail_screen.dart` L13-20): replace the 9 bespoke hues with a single shared
     `AppColors` list — cycle through `primaryGreen, lightGreen, darkGreen, success,
     warning, error, info, proYellow` (8 existing tokens) instead of 9 one-off hex values.
     Since it's duplicated verbatim in two files, extract to one constant (e.g.
     `AppColors.avatarColors`) so there's a single definition, not two copies to keep in
     sync.
   - `lumo_voice_bot_screen.dart` voice-state colors (ready/listening/processing/speaking,
     ~4 distinct hues + duplicated FF388E3C/FF00E676/FF4CAF50 across two switches): map to
     `AppColors.success`/`primaryGreen`/`warning` — collapse the near-duplicate greens
     (`0xFF388E3C`, `0xFF00E676`, `0xFF4CAF50`) rather than keeping three different greens
     for shades of "ready".
   - `active_focus_screen.dart` `_getProgressColor` (timer/stopwatch/pomodoro): map to
     `AppColors.success` (timer), `AppColors.info` (stopwatch), `AppColors.warning`
     (pomodoro) — drop the raw `0xFF4CAF50`/`0xFF2196F3`/`0xFFFF5722`.
4. **One documented exception, left alone:** `create_group_screen.dart:113`
   `Color(0xFF25D366)` is WhatsApp's own brand green on a "share to WhatsApp" button — this
   identifies a third-party app, not this app's UI, so it stays a literal. Add a one-line
   comment (`// WhatsApp brand color, not app theme`) so it doesn't get "fixed" again by a
   future pass.

## Mapping table (mechanical swaps — majority of the 357 hits)

| Hex | Token |
|---|---|
| `0xFF82D65D` | `Theme.of(context).colorScheme.primary` / `AppColors.primaryGreen` |
| `0xFF8FD66E` | `AppColors.lightGreen` |
| `0xFF5CAF3C` | `AppColors.darkGreen` |
| `0xFF7ED957` | `AppColors.success` |
| `0xFF1E1E1E` | `Theme.of(context).colorScheme.surface` / `AppColors.surface` |
| `0xFF2A2A2A` | `AppColors.surfaceElevated` |
| `0xFF1A1A1A` | `Theme.of(context).colorScheme.onPrimary` / `AppColors.background`-adjacent — check each call site, some mean "on-primary text", some mean "near-black bg" |
| `0xFF0F0F0F` | `AppColors.background` / `scaffoldBackgroundColor` |
| `0xFF3A3A3A` | `Theme.of(context).colorScheme.outline` / `AppColors.border` |
| `0xFFFF5252` | `Theme.of(context).colorScheme.error` / `AppColors.error` |
| `0xFF8A8A8A` | `AppColors.textMuted` |
| `0xFF6A6A6A` | `AppColors.textDisabled` |
| `0xFFB0B0B0` | `AppColors.textTertiary` |
| `0xFFE0E0E0` | `AppColors.textSecondary` |
| `0xFFFFFFFF` / `Colors.white` mixed in same file | `AppColors.textPrimary` (only where swapping literal-for-literal; don't touch existing `Colors.white`) |
| `0xFF64B5F6` | `AppColors.info` |
| `0xFFFFD700` | `AppColors.proYellow` |
| `0xFF000000` | `AppColors.background` or `Colors.black` per context — check, don't blind-swap |

Every distinct hex not in this table is covered by decisions 1-4 above. Before editing each
file, re-check the literal against this table/decisions — don't pattern-match on the hex
string alone, confirm the surrounding widget makes semantic sense with the chosen token
(e.g. a `0xFF1A1A1A` used as card background is `surface`-family, the same hex used as
"text on a light button" is `onPrimary`).

## Files to touch (27)

`presentation/screens/`: `blocks_screen.dart`, `group_detail_screen.dart`,
`profile_screen.dart`, `save_session_screen.dart`, `group_screen.dart`,
`create_group_screen.dart`, `usage_stats_screen.dart`, `lumo_voice_bot_screen.dart`,
`manage_blocked_apps_screen.dart`, `active_focus_screen.dart`, `splash_screen.dart`,
`onboarding/onboarding_screen.dart`
`presentation/widgets/`: `usage_stats_widgets.dart`
`widgets/`: `parental_control_dialogs.dart`, `focus_timer_widget.dart`
`models/`: `audio_bottom_model.dart`, `block_app_bottom_model.dart`,
`focus_time_bottom_model.dart`, `end_session_bottom_sheet.dart`
`presentation/overlays/`: `overlay_app.dart`, `overlays/widgets/focus_timer_widget.dart`,
`overlays/widgets/overlay_background.dart`, `overlays/screens/blocked_website_overlay.dart`,
`overlays/screens/blocked_applimit_overlay.dart`,
`overlays/screens/blocked_shorts_overlay.dart`, `overlays/screens/blocked_app_overlay.dart`
`main.dart`
`core/theme/app_theme.dart` — only if `AppColors.avatarColors` constant needs adding (new
list, no new hue values — built from existing constants above it in the same class).

No native/Kotlin/manifest files touched. Not on the AGENTS.md no-exceptions list, but
scope (27 files) warrants the written prompt anyway per section 2.

## Requirements

- No new hex values introduced anywhere (decision 3 — reuse existing `AppColors` tokens,
  don't invent replacements).
- `OverlayApp` theme comes from `AppTheme.darkTheme`, not a second inline `ThemeData`.
- Overlay screens' dark gradients rebuilt from `AppColors`/`AppTheme` tokens so blocked
  screens visually match the main app (calm dark theme, green accents — per AGENTS.md
  section 3 overlay-consistency rule).
- Group avatar color list de-duplicated into one shared constant, both call sites use it.
- `flutter analyze` clean, `dart format` applied, after all edits.
- Don't touch `Colors.white`/`Colors.transparent`/`Colors.grey`-family literals — out of
  scope per above.
- Don't touch the WhatsApp brand color beyond adding the explanatory comment.

## Security / privacy

None — pure visual/cosmetic change, no data flow, no native/permission code touched.

## Acceptance criteria

- `grep -rn "Color(0x" lib --include=*.dart | grep -v app_theme.dart` returns exactly one
  hit: the commented WhatsApp brand color.
- App still builds and runs; no screen goes visually blank/wrong-colored from a bad
  ColorScheme-slot guess.
- Overlay (blocked-website / blocked-app / blocked-shorts / blocked-app-limit screens) reads
  as the same app as the main UI — dark background, green accents, not indigo/navy/maroon.
- Group member avatars still visually distinguishable from each other (cycled palette, not
  all-green).
- `flutter analyze` — no new warnings/errors.

## Checks to run

- `flutter analyze`
- `dart format lib/` (or per-file) on every touched file
- `flutter test` (existing suite, to catch any accidental widget-test breakage)

## Manual test steps

1. Launch app, walk through: home/dashboard, profile screen, blocks screen, usage stats
   screen, group screen + group detail screen (create a test group, confirm avatar colors
   still vary member-to-member), save-session screen, active focus session screen (check
   timer/stopwatch/pomodoro each show a distinct color), Lumo voice screen (trigger
   ready/listening/processing/speaking states if feasible, confirm distinct but
   theme-consistent colors).
2. Trigger each overlay type on-device (block a site, exceed an app limit, hit shorts
   detection, hit a per-app block) and visually confirm all 4 read as dark-green-themed,
   not indigo/navy/maroon.
3. Open "create group" → confirm the WhatsApp share button is still WhatsApp-green (i.e.
   confirm it wasn't accidentally swapped).
4. Compare a few screens side-by-side against pre-change screenshots to catch any
   ColorScheme-slot mismatch (e.g. text becoming invisible against its background).
