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
Reboot persistence and exact-timing guarantees are explicitly NOT promised
(schedules use `inexactAllowWhileIdle`).

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
