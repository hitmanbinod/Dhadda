# Dhadda — Latest design status (living document)

> **For AI models and maintainers:** this is the canonical, short-lived design
> status. Update it in the **same commit** as any UI/layout/theme/navigation
> change, and mark anything you did not actually run as **not verified**.
> Detailed background lives in `docs/REPORT_ONE_HANDED_MODE.md` and
> `docs/REPORT_APP_DESIGN.md`; this file is the current snapshot, not history.

Last updated: 2026-11-21 (HEAD `dcf20b4`, branch `web-parity`; latest UI work in the working tree).

---

## 1. Design system (stable)

- Material 3, one Flutter codebase for Android + Web (`com.dhadda.expense`,
  label **Dhadda**, 1.5.0+4).
- Tokens in `lib/theme/tokens.dart`: spacing 4/8/12/16/24/32, radii
  (card 16, segmented 10, field 12, sheet 24, pill 999), 48 dp min tap,
  150/200/300 ms motion with reduced-motion zeroing.
- `AppColors` ThemeExtension roles (`expense` red, `income` green, `accent`,
  `card`, `field`, `hairline`, `textPrimary/Secondary`), 12 accents + Material
  You on Android (`lib/theme/palette.dart`, `app_theme.dart`).
- Typography names in `lib/theme/typography.dart` (`largeTitle`, `heroAmount`,
  `statValue`, `title`, `body`, `caption`, `amount`) — amounts tabular.
- Reusable widgets in `lib/widgets/` keep grouped cards, segmented controls,
  48 dp targets and Semantics labels consistent.

## 2. Surfaces

| Surface | Status | Notes |
|---|---|---|
| Android app | current | 4 tabs (Home/History/Insights/Lent) in `NavigationBar`; `NavigationRail` > 900 dp; pushed Settings; PIN/biometric gate. |
| Standalone web | current, with gaps | Same widget tree; rail on wide screens; no native camera/gallery bridge (not verified). Dev server: `flutter run -d edge --web-hostname 127.0.0.1 --web-port 8080`. |
| Embedded `assets/webapp/` | in sync at 1.5.0+4 | Rebuild with `dart tool/build_embedded_web.dart`; gate with `--check`. Served by the Android phone host over LAN. |
| Phone-hosted "Show on PC" | current | `shelf` on 8080 (random fallback), assets + `/api/sync/*` + `/api/ping`, mDNS `dhadda.local`, plain HTTP LAN-only. |

## 3. Latest design changes (most recent first)

| When | Change | Commit |
|---|---|---|
| 2026-11-22 | Home By category: removed duplicated featured header, added interactive proportional pill bar with selection glow/dim synced to rows (tap again clears), selected-row pill uses surface2; header action icons spaced 8dp | working tree |
| 2026-11-22 | Widgets redesign + picker previews: Month/Today/Lent/Quick layouts with light-night colors, 24dp surfaces, 3 bento tiles, tinted mini-cards and action pills; grouped currency formatting; `previewImage` + `previewLayout` bound on all four providers. Insights one-handed bar opaque; Home action icons spaced | working tree |
| 2026-11-22 | Add/Income restyle: accent-bound Expense/Income pill, 20dp hero amount card, 3-column categories + 4-column accounts with contrasting selected icon/label, one Details card (64/36 date/time), dashed-to-solid receipt card with cached 128px thumbnails and off-isolate downscaling, sticky Save pill | working tree |
| 2026-11-21 | Home polish: collapsible ~52dp One-UI top reach zone, tinted 36dp header/eye actions, 20dp card token + uniform badges, tight By-category list with inset divider, 90dp FAB scroll tail; Insights period bar pinned in one-handed mode; reliable receipt thumbnails + View receipt action | working tree |
| 2026-11-21 | Settings restyled to Home's language: titled cards (16/20 dp gaps), tinted 36 dp icon badges with inset dividers, accent-bound pills and switches, single Account & avatar sheet, concise row copy | working tree |
| 2026-11-21 | Camera restored in receipt row beside Gallery; native FileProvider root-path + `<queries>` + error reporting; web bundle rebuilt to 1.5.0+4 | `af9aceb` |
| 2026-11-21 | Lent summary button made compact to fix narrow-web RenderFlex overflow; 320 dp regression test | `484ee77` |
| 2026-11-21 | Round 3.1: Insights How-you-pay + forecast + account legend, Edit receipts + cleanup, Accounts colour/delete/archive/merge, migration stress tests, final QA | `c82ebf5` … `dc1b0d3` |
| 2026-11-21 | Home profile row lowered; blurred compact bar on scroll; Minimal/Classic avatars; night greeting | `c8616a8` |
| 2026-11-21 | One-handed on by default; tab swipe removed; smooth month paging; bars just above nav bar; magnitude-only balance colours; Home Events on | `18bbf99` |
| 2026-11-20 | One-handed mode introduced (off by default) | `2ed8d92` |

## 4. One-handed mode (current behaviour)

- Per-device pref `one_handed_mode`, **off by default**; an explicit toggle at
  `settings-one-handed` in `lib/screens/menu_screen.dart` persists via
  `one_handed_choice_v1` (`lib/store.dart`). Legacy values without an explicit
  choice are ignored.
- History / Insights / Lent segmented controls move from the header to just
  above the bottom nav (`oneHandedBottomPadding` in `lib/widgets/page.dart`).
  The Scaffold body already ends at the nav bar, so the helper adds only a
  small gap — do not add the nav-bar height here.
- Home header lowered; `AnimatedSwitcher` blur bar after 120 px scroll.
- Root-shell tab swiping removed; month paging direction-aware and animated.
- Full details: `docs/REPORT_ONE_HANDED_MODE.md` (historical report of the
  original `round2` work; the behaviour above is current).

## 4b. Settings screen anatomy (current)

- `lib/widgets/settings_row.dart` is the shared kit: `SettingsSectionTitle`
  (17 sp bold, `textPrimary`, outside each card), `SettingsCard` (AppCard with
  16 dp inner padding and dividers inset to the row text), `SettingsIconBadge`
  (36 dp / 10 dp radius soft-tinted square), `SettingsRow`,
  `SettingsSwitchRow`, `SettingsChevron` and `PillSegments`.
- Every row uses 16 dp horizontal padding, a 36 dp badge, a 12 dp gap and the
  same trailing-control alignment; destructive rows use the `expense` tint.
- Active pills and switches bind to `colors.accent` / `colors.onAccent` (never
  a hardcoded red); tracks use `colors.surface2` / `colors.track`.
- The account card, avatar and pencil open one **Account & avatar** sheet for
  name + Minimal/Classic style; the standalone Appearance chips are gone.
- Calendar shows the BS-only estimate note only when BS is selected; accent,
  currency and PIN are navigation rows that open pickers/dialogs.

## 5. Open design issues (do not lose)

1. `web/index.html` is still stock: `<title>expense</title>`, description
   "A new Flutter project." (`web/manifest.json` is correctly Dhadda). Fix
   branding when touching web packaging.
2. Web uses `--pwa-strategy none` — no service worker; not an offline PWA.
3. Web has no camera/gallery MethodChannel implementation; receipt buttons on
   web are **not verified**.
4. One-handed mode on wide screens (>900 dp) moves controls to the bottom even
   though there is no bottom NavigationBar — ergonomics worth reviewing.
5. Sticky-bar scroll threshold is a hard-coded 120 px; large text scales may
   shift the ideal point.
6. All on-device ergonomics/blur/camera behaviour is **not verified**; only
   automated widget tests and code evidence exist.

## 6. Maintenance rules for models

When you change UI, layout, theme, navigation, or web packaging:

1. Update this file in the **same commit**: add a row to §3, adjust §2/§4, and
   move or close any item in §5 that your change resolves.
2. Update `PROJECT_STATUS.md` (live handoff) and the detailed
   `docs/REPORT_APP_DESIGN.md` / `docs/REPORT_ONE_HANDED_MODE.md` when the
   change is substantial enough to alter their descriptions.
3. If you touch `assets/webapp/`, rerun `dart tool/build_embedded_web.dart`
   and `--check` so the embedded bundle version matches `pubspec.yaml`.
4. Run `flutter analyze --no-fatal-infos` + `flutter test`; report the count
   and mark anything unrun as **not verified**.
5. Never mutate `pubspec.yaml`, signing, PIN/security, sync semantics or the
   schema for a design-only change; revert regenerated
   `windows/flutter/generated_*`.
