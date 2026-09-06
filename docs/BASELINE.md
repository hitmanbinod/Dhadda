# Dhadda — Phase 0 Baseline (GitHub + F-Droid track)

> Captured 2026-09-06. Detail reference: `../PROJECT_CONTEXT.md` (not duplicated here).
> Baseline commit: the commit tagged `pre-security-storage-migration`
> (`git rev-list -n 1 pre-security-storage-migration`).
> Distribution target: **GitHub + F-Droid only. No Google Play plan.**

- Baseline version: `1.3.1+2` (`pubspec.yaml`), `kAppVersion 1.3.1`
  (`lib/version.dart`, stamp `2026-09-06 (hostfix)`).
- Toolchain: Flutter 3.47.2 stable, Dart 3.13.2, JDK 17, AGP 9.1.0, KGP 2.4.0.
- Analyzer: `flutter analyze` clean. Tests: **59/59 pass** (49 pre-existing in
  12 files + 10 new in `test/fixtures_test.dart`).
- Snapshot version: v1 (`kSnapshotVersion = 1`, `lib/models.dart`).
- Persistence: plain JSON in SharedPreferences, keys `expense_cats/txns/loans/
  projects/meta/backups_v1` + `expense_pin_hash_v1`, `expense_biometric_v1`,
  `expense_sms_ids_v1`. No DB engine. 5 rolling snapshot backups.
- Fixtures: `test/fixtures/phase0/` (index in its `README.md`); validity tests in
  `test/fixtures_test.dart`.
- Known risks (pre-existing, unchanged): debug-key release signing; stale
  `assets/webapp/` bundle (1.3.0 vs app 1.3.1); whole-snapshot last-write-wins can
  drop a slower device's offline edits; implicit Android Auto Backup of plaintext
  finances; mDNS best-effort only; stale debug-build `SmsBridge` override failure
  in old log.

## Expected current behavior (verify refactors against this)

| Flow | Expected | Code |
|---|---|---|
| Cold start | Seed 8 categories (Fuel before Other) on first run; `loaded` gates UI; PIN gate if set; LinkEngine starts; reminders refresh; auto-SMS if enabled | `lib/main.dart`, `lib/store.dart` (`load`) |
| PIN lock | 4-digit pad, auto-submit, SHA-256 verify; biometric-only shortcut when enabled | `lib/security.dart`, `lib/screens/lock_screen.dart` |
| Add txn | Strict amount (`123` or `123.45`), category required, date/time/mode/event optional; clears + snackbar + pop | `lib/screens/add_screen.dart`, `lib/format.dart` |
| Home | Month pager; Spent/Income/Balance/Lent-out; pie + legend; budget bars; recent 8; pull-to-refresh syncs | `lib/screens/home_screen.dart` |
| History | Debounced search; type/category/day filters; CSV export; swipe-delete + Undo; tap/long-press edit; category reorder; event totals | `lib/screens/history_screen.dart`, `lib/widgets/` |
| Projects | Tag txns; per-event totals; delete untags | `lib/store.dart` (`deleteProject`) |
| Categories | Rename/budget/icon/color/delete (Other protected, txns move to Other); reorder, Other last | `lib/store.dart` |
| Lent/borrowed | Principal + top-ups − repayments = pending; settled ≤ 0.005; one-time reminder schedules OS notification | `lib/screens/lent_screen.dart`, `lib/sync/reminders.dart` |
| File export/import | Share-sheet JSON out; picker JSON in; newer-`updatedAt` wins else "Already up to date"; 5 backups; restore force-imports | `lib/sync/file_sync.dart`, `lib/store.dart:862-894` |
| Direct WiFi | Sender QR `EXPENSESYNC::<url>::<pin>`; `GET /meta`, `GET /snapshot`, `POST /snapshot` with `x-sync-pin`; 403 wrong PIN; auto-close ~5 min | `lib/sync/wifi_host_io.dart`, `wifi_client.dart` |
| Link sync | QR `EXPENSESYNC2::<origin>::<code>::<pin>`; auto-sync on change (3 s), 15 s poll, on resume; newest peer wins; gone link clears local | `lib/sync/link_sync.dart`, `relay_client.dart`, `sync_screen.dart` |
| Show on PC | Serves bundled web UI + link API (8080 → random); `GET /api/ping` = `{ok:true}`; request counter; wakelock; stop closes | `lib/sync/phone_host_io.dart` |
| mDNS/IP | `http://dhadda.local:<port>` best-effort; IP URL always shown and primary | `lib/sync/mdns.dart`, `MdnsHelper.kt` |
| SMS manual | Mode + sender allowlist; permission prompt; inbox (90 d, ≤300); checkbox picker; dedup ≤500 IDs | `lib/screens/menu_screen.dart`, `lib/sync/sms*.dart`, `SmsBridge.kt` |
| SMS auto | Same parse path, silent import + snackbar on launch/resume | `lib/main.dart` (`_autoSms`) |
| Erase | Double-confirm; wipes domain + reseeds defaults | `lib/store.dart` (`eraseAll`) |

## Manual verification still required (cannot run here)

On-device export of a real dataset; debug APK build (old log shows a possible
pre-existing `SmsBridge` override failure); Show-on-PC phone-local then PC browser
path (`/api/ping` then app); mDNS on Windows; SMS/manual+auto on real inbox;
reminder fires; biometric unlock.
