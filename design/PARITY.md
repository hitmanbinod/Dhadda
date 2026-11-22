# Android <-> Web design parity

**Prompt 2 sync (branch `sync`):** the new PWA lives in `webapp/` (copy of
web-v2 plus manifest/service worker), served from Cloudflare Pages
`https://dhadda-web.pages.dev`; the sync Worker is
`https://dhadda-sync.<subdomain>.workers.dev` with D1 `dhadda-vault`.
`web-v2/` is now only the presentation source. Both sides use
`design/SYNC_PROTOCOL.md`; the phone creates the vault/key in Settings →
Web access. Existing LAN sync and the embedded Flutter-web bundle are unchanged.


Last synced Android commit: `61d78b1` (2026-11-22)

**`web-v2` experiment:** this branch adds a separate lightweight web app under
`web-v2/` (plain JS/CSS, no framework, ~17 KB gzip including demo data). It
does **not** change Android or the existing Flutter-web build. The legacy rows
below still describe the shipped Flutter-web path. See
`design/WEB_V2_PHASE0.md` and `design/WEB_V2_REPORT.md`.

Both platforms are one Flutter codebase. "Android file" and "Web file" are
often the same file; that is expected and listed under Intentional differences.

| Screen / component | Android file(s) | Web file(s) | Status |
|---|---|---|---|
| Design tokens | `lib/theme/{tokens,palette,typography,app_theme}.dart` | same + `design/tokens.json` -> `lib/theme/tokens.g.dart`, `design/tokens.css` | ✅ synced |
| App shell / nav | `lib/main.dart` | same (sidebar >=900, tab bar <900) | ✅ synced |
| Top bar, desktop Add, shortcuts | `lib/main.dart` | same | ✅ synced |
| Home | `lib/screens/home_screen.dart`, `lib/home_layout.dart` | same | ✅ synced |
| Home amount treatment | `lib/widgets/money_text.dart` | same | ✅ synced |
| History | `lib/screens/history_screen.dart` | same | ✅ synced |
| Insights (all sections incl. How you pay) | `lib/screens/insights_screen.dart`, `lib/insights.dart`, `lib/analytics.dart` | same | ✅ synced |
| Lent | `lib/screens/lent_screen.dart` | same | ✅ synced |
| Settings | `lib/screens/settings_screen.dart`, `menu_screen.dart` | same (pushed from avatar) | ✅ synced |
| Add / Edit sheet | `lib/screens/add_screen.dart`, `lib/widgets/entry_actions.dart`, `receipt_field.dart` | same | ✅ synced |
| Toasts / sheets | `lib/widgets/app_snack_bar.dart`, theme | same | ✅ synced |
| Embedded bundle | `lib/sync/phone_host_io.dart` | `assets/webapp/` (rebuild with `dart tool/build_embedded_web.dart`) | ✅ synced 1.5.0+4 |

Latest UI changes (both platforms share the same Flutter files): Home's By
category card dropped its duplicated featured header for a proportional,
tappable pill segment bar with glow/dim highlight synced to row selection;
tapping the active category clears back to the overview. all four Android
home-screen widgets were redesigned with light/dark surfaces, 24dp corners,
grouped comma-formatted currency and zero dead space; each provider now has a
real `previewImage` drawable and `previewLayout` so HyperOS/MIUI and Android 12+
show widget thumbnails. Insights' pinned one-handed bar is opaque; Home's
Edit Home and Sync actions have more breathing room. one-handed mode
is off by default, pinned bars sit just above the bottom nav, the AI-ish
title/helper captions were removed from History, Insights and Lent, Settings was
restyled to Home's surface language, Home has a collapsible One-UI top reach
zone and uniform 20dp cards/badges, and Insights pins its period bar to the
viewport bottom in one-handed mode. Add/Income now uses an accent-bound pill
track, hero amount card, 3-column category grid, 4-column account tiles, a
consolidated details card, dashed/solid receipt card with cached 128px
thumbnails, and a sticky Save pill. Receipt downscaling runs on a background
isolate; thumbnails never decode full-resolution images in the form. Tokens
gained `cardLarge` (20) and were re-synced.

## Intentional differences

- Android home-screen widgets are N/A on web.
- Desktop uses a sidebar + top bar; phone uses a bottom tab bar + FAB.
- Sheets are centred modals on desktop, bottom sheets on phone.
- Avatar opens Settings; desktop also has an avatar in the topbar.
- Web camera/gallery receipt capture has no platform implementation (not verified).
- Mock-only features deliberately not ported: daily-allowance ring, budgets
  card, cash-flow card, saved views, Sync & Devices, restore sample data,
  PIN/PBKDF2 demo, device list. (Budgets/Events/Today/Rhythm/Forecast exist on
  Android as optional Home sections and are reached through Edit Home.)

## Sync procedure ("sync web")

1. Read "Last synced Android commit" above.
2. `git log --oneline <hash>..HEAD -- lib/theme lib/screens lib/widgets lib/main.dart lib/analytics.dart lib/insights.dart lib/home_layout.dart`
3. `git diff <hash>..HEAD -- <same paths>`
4. Apply every UI change to the matching web file (usually the same file).
5. If tokens changed, edit `design/tokens.json` and run
   `python3 scripts/sync_tokens.py --check` (and regenerate if needed).
6. Update this table and set "Last synced Android commit" to the new HEAD.
7. Run `flutter analyze --no-fatal-infos` and `flutter test`.
