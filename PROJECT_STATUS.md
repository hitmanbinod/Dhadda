# Dhadda — Current Status (AI handoff)

This is the live status file. Read it first, then `PROJECT_GUIDE.md` for the
historical phases. Update this file whenever code changes.

## Identity & version
- Package: `com.dhadda.expense` (never change; installed-app identity)
- Branch: `round2` (Rounds 1-3 committed locally; nothing pushed)
- Version: **1.5.0**, build **4** (`pubspec.yaml` → `1.5.0+4`)
- Stamp: `lib/version.dart` → `kAppVersion = '1.5.0'`, `kBuildStamp = '2026-11-20 (1.5.0+4)'`
- Changelogs: `fastlane/metadata/android/en-US/changelogs/4.txt`, `docs/CHANGELOG.md`
- **Split-APK version codes:** Flutter adds `1000 × ABI` to the build number.
  arm64 = **2004**, armeabi-v7a = **1004**, x86_64 = **3004**. The universal
  APK is **4**. This explains the old "2003" confusion; it is not a bug.

## Verification baseline
- `flutter analyze --no-fatal-infos` → clean
- `flutter test` → **321/321 passing**
- `flutter build apk --debug` → succeeds
- Signed release: `flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/debug-info`
- Last installed on phone (wireless ADB `192.168.1.64:37655`): arm64 release 39.9 MB, 1.4.0 / code 2003 — **must be rebuilt and reinstalled for 1.5.0**.

## What exists now
### Round 1 (UI foundation)
Material 3 "Quiet Ledger" tokens; 4-tab nav (Home / History / Insights /
Lent); pushed Settings with profile header; large titles; grouped cards;
customizable Home sections with hide-balance eye; Insights analytics and
screen; redesigned Add/History/Lent; four native RemoteViews widgets
(Today 2x2, Month 4x2, Quick-add 4x1, Lent 2x2).

### Round 2 (BS calendar)
- `lib/calendar/bs_data.dart` — VERBATIM maintainer table (2070-2086), never edit.
- `lib/calendar/bs_calendar.dart` — pure AD↔BS converter; exhaustive 6,209-day round-trip test.
- `lib/calendar/period.dart` + `bs_calendar_system.dart` — `Period`, `CalendarSystem`, Gregorian and BS systems.
- `lib/app_dates.dart` — central formatter + BS date picker dispatcher; AD output unchanged.
- Firmware-free `expense_meta_v1` keys: `calendarSystem`, `home_layout_v1`, `hideBalance`, `category_rules_v1`.
- Fiscal year: Shrawan 1 → last day of Asar, label `FY 2083/84`.
- Auto-category rules: pure Dart core, Add suggestion, learn-from-edit snackbar, SMS rule-first mapping, management screen.

### Round 3 (accounts + receipts)
- Drift schema **v3**: `accounts`, nullable `transactions.account_id`, local `receipts` index. One-time safety copy `dhadda.pre-round3.sqlite`; guarded idempotent migration.
- Deterministic default ids `acct_cash/bank/card/ewallet` so devices converge. Legacy `mode` preserved and derived from account type.
- Snapshot v1: additive `accounts` + per-txn `accountId`. Snapshot v2: additive `acct` records with standard `(rev, by)` + tombstone handling. Unknown fields ignored by old peers.
- CSV: six original columns unchanged, `account` appended last.
- Settings → Money → Accounts (reorder/edit/archive/merge/delete-if-unused); Add/Edit account pickers; History account search + captions.
- Receipts: native camera/gallery intents, ≤1600 px JPEG q80, EXIF stripped, app-private files only; Add-screen receipt row, viewer, History paperclip, Settings → Data usage + double-confirm clear, startup orphan cleanup.

## Untouched / frozen
Package name, PIN/security, QR prefixes, relay/LAN/PC protocol semantics,
`(rev, by)` ordering, tombstone rules, `parseAmount`, `other` category rule,
store write discipline, signing/keystore, embedded web bundle, `allowBackup=false`.

## Known gaps (honest)
- No on-device verification: phone was offline except for APK installs. Camera/gallery, FileProvider, widgets, sync with un-updated peer, lock-screen receipt privacy are **not verified**.
- Insights has no "How you pay" card in this codebase, so account grouping there was not applicable.
- Edit screen has no receipt row (Add does). Account UI has no color picker or "delete unused" button (store methods exist).
- Receipt orphan cleanup runs at app start, not instantly after delete.
- Embedded web bundle remains at 1.4.0; not rebuilt per instruction.

## How to continue
1. Read this file, `PROJECT_GUIDE.md`, `docs/ROUND3_PLAN.md`.
2. `flutter pub get --enforce-lockfile`; `flutter analyze --no-fatal-infos`; `flutter test`.
3. After any schema edit: `dart run build_runner build`.
4. Never push; commit locally with scoped paths; revert regenerated `windows/flutter/generated_*`.
5. To bump version: update `pubspec.yaml`, `lib/version.dart`, both changelogs, and this file together.
6. Install (wireless ADB already paired): `adb connect 192.168.1.64:37655` then `adb -s 192.168.1.64:37655 install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

## Next recommended work
- On-device QA of receipts, accounts, widgets, sync and lock.
- Wire receipts into Edit screen; add account color picker and unused-account deletion UI.
- Decide whether to rebuild the embedded web bundle for 1.5.0.
