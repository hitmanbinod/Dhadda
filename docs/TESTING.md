# Dhadda Testing Guide (Phase 7)

What is tested, how, and what still needs a human or a device.
Baseline record stays in `docs/BASELINE.md`.

## 1. Test architecture

| Layer | Where | How it runs | Device needed |
|---|---|---|---|
| Unit (pure Dart) | `test/*_test.dart` | `flutter test` (host, CI) | no |
| Widget (pump screens) | `test/*_test.dart` (`testWidgets`) | `flutter test` (host, CI) | no |
| Live localhost HTTP/DB | `test/*_test.dart` (shelf servers, file SQLite, spawned `node`) | `flutter test` (host, CI) | no |
| Device integration | `integration_test/app_flow_test.dart` | `flutter test integration_test` on emulator/device | YES |
| Host mirror of device flow | `test/app_journey_test.dart` | `flutter test` (host, CI) | no |
| Manual procedures | below | human + emulator/spare | YES |

`flutter test` runs `test/` only — `integration_test/` never runs in CI
by accident. No emulator CI is configured (deliberate: no fragile
device farm for a personal app; see §9).

## 2. Test matrix (verified this phase)

| Workflow | Automated unit | Automated integration | Real device | Manual fallback |
|---|---|---|---|---|
| fresh install | seeds (settings_test) | boot + seeded Home (journey/integration) | — | — |
| legacy migration | migration_test (13: empty/single/populated/bulk/unicode/legacy/corrupt/retry/idempotent) | restart + export checks (same file) | — | — |
| backup/export/import | fixtures round-trip | backup_integration (export→mutate→import→reload; encrypted + wrong-pw; unicode/budgets/loans) | — | — |
| encrypted backup | backup_crypto (8) | backup_integration encrypted test | — | — |
| app PIN throttle | pin_throttle (7) | lock_throttle widget (wait blocks, success resets) | — | — |
| biometric unlock | — (pigeon binary channel: not honestly mockable) | fallback path runs in every suite (no impl → caught, verified by smoke layout) | REQUIRED (success/cancel/fallback) | §7 |
| direct WiFi sync | wifi e2e + v2 e2e | session/token/throttle/limits over live HTTP (lan_security) | two-device procedure | §7 |
| link/mailbox sync | link/link_store/relay/v2 (30+) | live HTTP incl. Node relay + secrets | two-device procedure | §7 |
| v2 conflicts | sync_v2 (15 incl. fuzz) + store (19) | both-restart-quiet, 3-device | — | — |
| Show-on-PC | API (lan_security) | ping-no-data + stop/revoke + restart-fresh | browser procedure | §7 |
| SMS manual/auto | parser (8) + channel (4: contract, dedup, import flow, cap) | parse→store→dedupe chain | inbox procedure | §7 |
| mDNS discovery | mdns (3: contract, failure, unregister) | — (env-sensitive by nature) | discovery procedure | §7 |
| reminders | reminders_test (7: schedule/cancel wording/reschedule/failure + tz data) | store→plugin-fake chain | delivery procedure | §7 |
| diagnostics | diagnostics_test (privacy + fail-closed keys) | builder only; UI exposure deferred | — | — |
| failure injection | migration/merge/import/socket/malformed | notify-failure, SMS-denied, mDNS-failure paths | — | — |
| restart | migration/tombstone/backup | reload-after-reopen everywhere above | — | — |
| log privacy | log_privacy (store + phone-host zone capture) | — | logcat step | §7 |

## 3. Emulator / device requirements

- Android emulator (API 30+): integration runs, SMS/mDNS/notification/
  biometric manual paths, Show-on-PC browser check.
- Second device or emulator + PC on one WiFi (no VPN): two-device sync,
  direct WiFi, Show-on-PC, mDNS discovery.
- Real SIM/inbox: SMS procedures (emulator `adb emu sms send` is the
  optional path where legal/practical).
- Nothing here needs Play Services, accounts, or network beyond the LAN.

## 4. SMS procedure (manual, synthetic data only)

Manual import: install test build → grant SMS permission → populate a test
inbox (emulator `adb emu sms send <sender> <text>` with bank-like shapes
from `test/sms_parse_test.dart`, never real messages) → Menu → Scan SMS →
verify parsed rows → import → verify transactions → re-scan → verify zero
duplicates. Auto mode: enable in Menu → send another synthetic message →
background/foreground the app → verify silent import + snackbar → revoke
the permission → verify no crash and a permission prompt on next attempt.
Never commit real messages, names, or numbers.

## 5. mDNS procedure (manual, real network)

Phone A: Sync → Show on PC (note IP + `.local` name, if shown). PC/device
B on the same WiFi (no VPN, no AP isolation): resolve/open
`http://dhadda.local:<port>` — works where the OS has mDNS (most desktops
with Bonjour/Avahi; stock Windows Chrome often fails: use the IP, which is
the supported path). Stop on A → B must fail to resolve (disappearance).
VPN on either side breaks discovery (documented, not a bug).

## 6. Notification procedure (manual)

Synthetic loan → reminder 2–3 minutes out → background the app → wait →
verify the notification appears with the right title/amount → tap (opens
app, if wired) → repay in full → verify cancellation (no re-fire).
Reboot persistence is explicitly NOT promised (one-time alarms do not
survive reboot; schedules use exact-while-idle only when granted).

Exact-alarm access (Android 12+): reminders schedule with
`exactAllowWhileIdle` when the OS grants `SCHEDULE_EXACT_ALARM`, else
fall back to inexact (may arrive late). Android 14+ does NOT pre-grant
this on fresh installs: when a reminder is saved without access, the
app shows an in-context snackbar ("Alarms & reminders" → Open
settings). Without the grant, late delivery on restrictive OEM skins
(HyperOS verified) is expected OS behavior, not an app bug.
`USE_EXACT_ALARM` is deliberately not used.

## 7. Biometric, two-device sync, Show-on-PC procedures

- Biometric: device with enrolled biometrics → enable in Menu (fresh
  biometric required) → lock app → unlock via biometric → disable biometric
  → cancel path falls back to PIN → failed attempts never bypass the lock →
  throttle delays still apply per Phase 3 policy.
- Two-device sync: the Phase 4 scenario in `docs/SYNC_V2.md` §15 verbatim
  (A1/B1 union, same-record tie-break, deletion rule, repayment survival,
  second round quiet), plus one link-secret rotation (unpair/re-pair).
- Show-on-PC: phone serves → PC browser loads UI → pair via link code →
  data converges → Stop → browser refresh fails → re-serve gets a fresh
  URL (no stale auth).

## 8. Diagnostics privacy contract

`DiagnosticsReport` carries counts/versions/markers/statuses only
(allow-listed keys, fail-closed `format`). Forbidden: descriptions, notes,
amounts, names, SMS, PIN/hash, link/session/QR secrets, device IDs,
passwords, snapshot contents. Adding a field requires updating the
allow-list AND the privacy test. No analytics/telemetry/upload, ever. UI
exposure deferred (builder only) — no silent data surface later.

## 9. Release-gate checklist

`flutter analyze` clean · full `flutter test` green · `integration_test`
on emulator green (or documented skip with reason) · manual SMS/mDNS/
notification/biometric/two-device/Show-on-PC passes recorded · no
`integration_test`-only failures hidden · `docs/BASELINE.md` untouched ·
no secrets/fixtures with real data committed.

## 10. Known test gaps (honest)

- No real-inbox SMS run; no real biometric success run; no real OS
  notification delivery run (all manual-gated above).
- No Android-emulator CI (no device farm; host suite is the gate).
- `integration_test/` executes only on a connected device (verified by
  `analyze`; host mirror in `test/app_journey_test.dart` runs in CI).
- Performance: observation-only bounds, no benchmarks (Phase 6 territory).

## 11. Validation log (2026-09-08, Phase 7 WIP cleanup)

Host (this machine, Flutter 3.47.2 / Dart 3.13.2):

- `flutter analyze --no-fatal-infos`: clean.
- `flutter test`: 176/176 pass (Drift multi-`AppDb` debug warnings
  retained, not a defect).
- `flutter test test/app_journey_test.dart`: 2/2 pass (host mirror of
  the device app-flow journey).

Device `integration_test/` (NOT run — honestly blocked, not passed):

- `flutter test integration_test/app_flow_test.dart -d <device>`:
  BLOCKED. `dhadda-p7` emulator exists but won't boot: x86_64
  emulation requires hardware acceleration, hypervisor driver not
  installed. Windows fallback also blocked: plugin symlinks need
  Developer Mode plus VS toolchain (absent).
- `flutter test integration_test/sync_two_device_test.dart`:
  BLOCKED for the same reason (needs a real device/emulator plus
  `--dart-define` relay choreography; host localhost/Node-relay
  equivalents in `test/` stay green but are not a substitute).
- SMS real-inbox, notification delivery, mDNS discovery, Show-on-PC
  browser, biometric, two-device convergence: BLOCKED / NOT RUN on
  real hardware this session. Prior manual-gated procedures in
  §§4–7 stand; no pass claimed here.

## 12. Device validation actuals (2026-09-08, Xiaomi 23129RAA4G, Android 15 API 35)

Install notes: HyperOS needs per-install approval (`INSTALL_FAILED_USER_RESTRICTED`
until tapped). `flutter install --debug` once installed a stale
`flutter test` harness APK (black screen, engine alive, no frames);
fixed by deleting the stale `app-debug.apk` and rebuilding plain
(no repo change; build output only).

- App render on device: PASS (Home dashboard screenshot-verified).
- `integration_test/app_flow_test.dart` (inbox-free subset via `--name`):
  2/2 PASS on device (`fresh boot`, `add-expense journey`). Note:
  `--plain-name` is substring match; use `--name` for alternations.
- Real-inbox SMS tests: NOT RUN (needs explicit consent; inbox unscanned).
- Notification delivery: FAIL (see below). Permission granted, channel
  `loan_reminders` (MAX), alarm registered with the OS carrying the
  correct time/content/timezone — verified via `dumpsys alarm`,
  plugin cache, and `appops`. The inexact alarm sat overdue 4+ min
  (later 18+ min) with no `NotificationReceiver` trace and no active
  notification, while the app sat in standby bucket RARE (fresh
  sideloaded install, backgrounded). App-side schedule path
  (`Reminders.refresh`: `cancelAll` + per-loan `zonedSchedule`,
  stable ids, past/settled cancellation) reviewed correct; no code
  fix made. Retest path: HyperOS battery No-restrictions + Autostart,
  fresh reminder, Home-backgrounded (never swipe-killed), longer soak.
  Exact-alarm escalation (`SCHEDULE_EXACT_ALARM`) is a
  product/permission decision, NOT taken unilaterally here.
- 2026-09-08 follow-up: Autostart enabled + battery unrestricted
  retests still silent (fresh TestNotify2 reminder, bucket improved
  to EXEMPTED, alarm still queued overdue, receiver never observably
  ran). Status: BLOCKED-environmental (HyperOS inexact-alarm
  suppression). Exact-alarm decision parked with maintainer.
- 2026-09-08 fix: maintainer approved exact alarms. `Reminders` now
  schedules `exactAllowWhileIdle` when `canScheduleExactNotifications()`
  is true, with inexact fallback (plus retry-on-revoke) otherwise;
  manifest declares `SCHEDULE_EXACT_ALARM` (never `USE_EXACT_ALARM`);
  saving a reminder without access shows the in-context grant
  snackbar. Regression: 3 new `reminders_test` cases
  (exact-when-granted, inexact-fallback-kept, helpers-never-throw).
  Host suite 179/179, analyze clean. Device retest pending.
- 2026-09-08 exact retest: new build verified on device (manifest
  permission present, `scheduleMode:exactAllowWhileIdle` in plugin
  cache for a 09:43 reminder, no grant snackbar because the OS
  reported access allowed). Exact alarm FIRED on time (receiver wake
  at ~09:43), yet no notification displayed, no channel/history
  trace, no crash. Display suppressed by HyperOS past the
  app-controlled path. Status: BLOCKED-environmental; fix retained
  (exact+fallback is strictly better on stock Android), delivery
  validation closed on this device. Maintainer chose to move on to
  remaining Phase 7 checks (mDNS, Show-on-PC, biometric, sync).
- 2026-09-08 Show-on-PC/mDNS (Xiaomi phone + Windows PC, same WiFi):
  IP path PASS (`/api/ping` → `{"ok":true,…}`, `/` → 200);
  `dhadda.local` from stock Windows BLOCKED-environmental as
  documented (no Bonjour; IP is the supported path); Stop →
  connection refused, disappearance PASS.
- 2026-09-08 Biometric/PIN on device: PASS (biometric unlock and PIN
  both verified working on the Xiaomi phone).
- 2026-09-08 Link/relay transport phone→PC (one phone + Node relay
  on same WiFi): PASS. Phone joined a PC-created PIN box
  (Server/Code/PIN manual entry), reported synced; PC pull showed the
  phone's full snapshot incl. the `Phase7Sync` tracer txn, the Test
  loan, and a live Snapshot v2 record set. True two-device
  convergence (two writers) stays BLOCKED — single phone; merge
  logic covered by host `sync_v2` tests.
- 2026-09-08 Real-inbox SMS (Xiaomi phone, explicit consent,
  counts/status only, no contents recorded): native MethodChannel
  inbox access PASS; scan completes without crash PASS; candidates
  dialog displayed PASS (parseable bank/wallet rows exist);
  permission request→Allow observed PASS; import-tap reached the
  `Added` confirmation, but the automated rescan-empty assertion
  flaked on device (empty notice not visible at check time across
  repeats, incl. a 12s-settle retry that was reverted as ineffective).
  App-side dedup path (`SmsReader` same-key awaited prefs
  round-trip) reviewed sound and host `sms_channel_test` dedup stays
  green; prime suspects are test-side (rescan tap landing while the
  snackbar overlay covers the button, snackbar-queue timing), NOT
  proven app data loss. Denied path (revoke → rescan) NOT RUN.
  Open item: rerun rescan assertion with tap-target logging or a
  manual rescan confirm.
- 2026-09-08 Manual SMS close-out (same phone, consent, counts only):
  45 candidates imported in one tap; immediate rescan showed `No
  new bank/wallet SMS found.` → dedup PASS on a real inbox (the
  earlier harness rescan-flake was test-side). Revoke → rescan shows
  the graceful `SMS permission needed` notice, no crash/access/import
  → denied-path PASS.
- Device-process notes: `flutter test` and `flutter install --debug`
  share `build/app/outputs/flutter-apk/app-debug.apk`; a stale
  harness build installs as a black screen (engine alive, no
  frames) — always `flutter build apk --debug` fresh before a manual
  install. Fresh-install cold start on this phone takes 60–90s of
  black before first frame (dexopt + DB + shaders); not an app bug.
