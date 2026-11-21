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
- `flutter test` → **354/354 passing**
- `flutter build apk --debug` → succeeds
- Signed release: `flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/debug-info`
- Last installed on phone (wireless ADB `192.168.1.64:37655`): arm64 release 39.9 MB, 1.5.0 / code 2004, installed 2026-11-21 — **the latest UI-polish changes below are not yet rebuilt/reinstalled**.

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

## One-handed layout + gesture polish (latest)
- Additive pref `one_handed_mode` is **on by default** (one-time migration for older installs; Settings → Appearance can still turn it off and that explicit choice persists via `one_handed_choice_v1`).
- One-handed mode puts History Entries/Categories/Events tabs, Insights period bar and Lent's Lent/Borrowed + Pending/Settled/All toggles **just above the bottom navigation bar** (not mid-screen).
- **Removed** root-shell horizontal swipe between tabs; tab switching is NavigationBar/rail only.
- Home month paging: direction-aware slide (old label exits opposite the incoming one) with subtle scale, eased over 300 ms, reduced-motion aware; only the date text opens the picker.
- Home balance: magnitude only (no minus sign), tinted red when negative / green when positive; hidden state stays neutral.
- Home Events: on by default for new installs and migrated on for existing ones, so **every** tagged event this month gets its own group.
- Add screen: Account picker stays low; the Repeat suggestion section is removed; Receipts row has **Gallery only** — the Camera button no longer launches the camera.
- Lent summary amounts shrink to fit instead of overlapping the Borrowed/Lent button; pending amounts in loan headers are bounded too.

## Profile + Home chrome polish (latest)
- Home profile row sits slightly lower; scrolling past ~120 px reveals a compact avatar/name bar with a translucent blurred backdrop (`BackdropFilter`).
- Home Events filtering now uses the active calendar period, so tagged entries also show in BS mode.
- One-handed inset uses the real Material 3 NavigationBar height (80 dp) plus the system bottom inset, putting tab bars just above the nav bar.
- Greeting has a real night part (21:00–04:59 → "Good night").
- Settings no longer says "Shown in (the) home greeting"; username dialog label is just "Your name".
- Additive `avatar_style_v1` pref with **Minimal** (initial) / **Classic** (person glyph) choices in Settings → Appearance; applied everywhere ProfileAvatar is used.

## Round 3.1 — Step 1 (Insights)
- New pure `lib/insights.dart`: `computeHowYouPay` (expense-only account shares, archived included, top 5 + "Other accounts", legacy resolver) and `projectInsightsEndSpend`; covered by `test/insights_pay_test.dart`.
- `ExpenseStore.howYouPay(period)` memoizes on the same revision as `insights(period)`.
- Insights now shows **How you pay** (8 dp stacked bar, 3 dp gaps, tappable legend → History account filter), a quiet **Month-end forecast**, and paired spend/income bars in the trend card.
- `HistoryDayRequest.openAccount` carries an account filter into the already-mounted History tab; filter pill + Semantics included.
- Still missing from the Round 1 Insights spec (not implemented here): Biggest changes, Your week, Possible subscriptions, month heatmap.

## Round 3.1 — Step 2 (receipts)
- Edit sheet (`entry_actions.dart`) now has the same ReceiptField as Add: view/remove stored photos, add from Gallery, 3-photo cap. Captures attach only on successful save; removals apply only on save; cancel drops unattached captures without touching stored files.
- Pure helpers in `receipts.dart`: `planReceiptChanges`, `cleanupRemovedReceipts`, `cleanupCapturedPaths`, `isCapturedReceiptPath`, plus a test-only `debugOverride` seam.
- Immediate cleanup paths: Undo snackbar close without undo (`delete.dart`), sync tombstone applied in `_mergeAndApplyLocked`, and `eraseAll`. Startup orphan pass kept as safety net. User delete leaves files intact until the snackbar resolves so Undo restores them.
- 4 new tests in `test/receipts_lifecycle_test.dart`.

## Round 3.1 — Step 3 (Accounts completion)
- Accounts table already had a `color` column (verified in `app_db.dart`), so the colour feature needed no schema/migration change.
- Accounts screen: optional soft-swatch colour (`kColorChoices`) in the add/edit dialog, colour dot on account rows; the same colour is shown as the icon tint in Add chips and as the dot in the Insights "How you pay" legend.
- Hard delete for unused accounts with a confirm dialog; blocked with a calm "Has N entries: archive it or merge it" message when the account has history. Last active account cannot be archived or deleted.
- Archived section with Unarchive and Merge actions; archived accounts hidden from pickers except when editing an entry already using one (`store.accountsForPicker`).
- Store helpers: `accountEntryCount`, `accountsForPicker`. 4 new widget/unit tests.

## Round 3.1 — Step 4 (migration stress tests, tests only)
- New `test/migration_stress_test.dart` builds real file-backed v2 SQLite databases with raw SQL and opens them through `AppDb` so `onUpgrade(2,3)` runs. Covers: 5k entries across all four modes (counts, per-month totals, mode->account mapping, loans/topups/repayments/events untouched, timing); interrupted-then-resumed migration equals a clean one with no duplicate defaults; guarded migration re-run is a no-op; legacy v1 JSON and v2 snapshot imports into the migrated app; one-time safety copy exists and is readable; marker/budgets survive.
- Reported, not changed: the "throw inside the migration" interruption is simulated by pre-applying the guarded steps and resuming (production `onUpgrade` was not modified, per tests-only rule).

## Round 3.1 — Final QA (Step 5)
- Verified by commands run here: `flutter analyze --no-fatal-infos` clean; `flutter test` 354/354; `flutter build apk --debug` succeeds.
- Frozen files unchanged across all four Round 3.1 commits (`git diff c8616a8..HEAD`): `pubspec.yaml` (1.5.0+4), `lib/version.dart`, signing config, `assets/webapp/version.json` (still 1.4.0). No schema/migration/sync-payload changes in production code; no new packages; no network calls.
- Automated-only checks that passed (widget/unit tests, not on-device): Insights cards incl. How you pay + forecast; account filter into History; receipts add/remove/limit and cleanup pure-logic lifecycle; account colour/delete/archive/merge/last-account guard; migration stress (5k, resume, re-run, imports, safety copy); existing AD/BS layout, light/dark, 360 dp/1280 px and 1.3x text-scale widget tests.
- Not verified: on-device camera/gallery intents and real receipt files, Undo snackbar timing, actual visual appearance of the new cards/legend/chips, and How you pay with an active BS calendar (logic is BS-aware via `insights()`, but no BS-specific assertion was added). The phone stayed offline throughout Round 3.1.
- Known deviation: the receipt row exposes Gallery only (Camera was removed in the earlier one-handed round at the maintainer's request), so Edit matches Add; requirement (2.1) said camera/gallery.

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
