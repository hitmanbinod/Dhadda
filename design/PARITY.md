# Android <-> Web design parity

Last synced Android commit: `86a74ee` (2026-11-21)

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
