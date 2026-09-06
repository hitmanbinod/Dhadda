# CHAT_HANDOFF.md — Dhadda Project Continuation Summary

> Use this file to continue the Dhadda project in a new ChatGPT conversation.
>
> Recommended uploads in the new chat:
>
> 1. `CHAT_HANDOFF.md`
> 2. `PROJECT_CONTEXT.md`
> 3. `DHADDA_SECURITY_EFFICIENCY_FDROID_ROADMAP.md`
>
> Then say:
>
> **"Read these files completely and continue from the current roadmap. We are starting/continuing Phase 0 only unless I explicitly say otherwise."**

---

# 1. Project

**Name:** Dhadda  
**Package / Android app ID:** `com.dhadda.expense`  
**Current inspected version:** `1.3.1+2`  
**Type:** Personal, open-source, offline-first expense tracker  
**Primary platform:** Android  
**Companion platform:** Flutter Web served locally from the phone / usable from desktop browser  
**Distribution target:** GitHub Releases + F-Droid  
**Google Play:** Not planned  
**Cloud/backend:** None required  
**Accounts:** None  
**Target operating cost:** $0

Dhadda is designed as a single-user personal finance app with local-only data, local network sync, SMS transaction import, backup/export, lent/borrowed tracking, projects/events, budgets, PIN/biometric lock, and a same-WiFi "Show on PC" web interface.

---

# 2. Current Verified Stack

The repository inspection documented the current stack as:

## Frontend / Android

- Flutter
- Dart
- Material 3
- Provider
- `ChangeNotifier`
- Navigator 1.0 / `MaterialPageRoute`
- `setState` for local UI state

## Persistence

Current critical data is stored as JSON in `SharedPreferences`.

Important current data includes:

- transactions
- categories
- budgets
- loans
- repayments
- top-ups
- projects/events
- metadata
- backups

There is currently **no real database engine**.

## Networking / Local Services

- `http`
- `shelf`
- `shelf_router`
- Direct WiFi sync
- Link/mailbox relay sync
- Phone-hosted HTTP server
- mDNS
- Node.js local PC relay

## Android-native bridge

Kotlin MethodChannels are used for:

- mDNS / Android `NsdManager`
- SMS inbox access
- camera/permission helpers

## Other important packages

- `fl_chart`
- `qr_flutter`
- `flutter_zxing`
- `local_auth`
- `dynamic_color`
- `flex_color_picker`
- `wakelock_plus`
- `flutter_local_notifications`
- `timezone`
- `flutter_timezone`
- `flutter_slidable`
- `file_picker`
- `share_plus`
- `uuid`
- `intl`
- `crypto`

## CI

- GitHub Actions
- Flutter analyze
- Flutter tests
- Flutter Web build
- APK build

---

# 3. Major Existing Features

Dhadda currently has:

- Home dashboard
- Expense/income entry
- History/search/filter
- CSV export
- Category customization/reordering
- Budgets
- Projects/events
- Lent/borrowed ledger
- Repayments
- Top-ups
- Reminders
- PIN lock
- Biometric unlock
- Theme controls
- Material You
- Currency selection
- File backup/export/import
- Five rolling local backups
- Direct WiFi sync
- Link/mailbox sync
- Phone-hosted "Show on PC"
- mDNS advertisement
- SMS import
- Automatic SMS import
- Local notifications
- GitHub CI
- 49 automated tests across 12 test files at the time of inspection

---

# 4. Important Architectural Conclusions From This Chat

## Keep Flutter

Do **not** rewrite Dhadda in native Kotlin/Jetpack Compose.

Reason:

Dhadda is not merely an Android UI app.

Flutter is useful because the same project supports:

- Android
- Flutter Web
- phone-hosted browser UI
- desktop access over LAN

A native Android rewrite would likely force a separate web frontend and substantially increase maintenance.

---

## Keep Provider

Do **not** migrate Provider/ChangeNotifier to Riverpod, Bloc, Redux, or another state system just because it is newer.

The current state system is not the primary problem.

Later, `ExpenseStore` can be split gradually into smaller responsibilities while continuing to use Provider.

---

## Do not add unnecessary cloud infrastructure

Do not add:

- Firebase
- Supabase
- hosted auth
- PostgreSQL server
- remote realtime DB
- GraphQL
- microservices
- analytics/tracking SDKs

unless a future requirement explicitly needs them.

Dhadda should remain:

- offline-first
- privacy-oriented
- local-first
- zero-backend-cost

---

# 5. Main Problems Identified

## 5.1 SharedPreferences is being used as the financial database

Critical financial data is stored as whole JSON values.

This creates several risks:

- entire history is rewritten on many mutations
- cost grows with history size
- no relational integrity
- no indexes
- no schema migration system
- harder recovery from partial/corrupt storage
- poor scaling to large histories
- plain local data is readable if storage is extracted

Future direction:

**Drift + SQLite**

SharedPreferences should eventually keep only non-critical small settings.

---

## 5.2 Sync can lose offline edits

Current sync behavior is whole-snapshot last-write-wins.

Example:

```text
Device A and Device B start equal.

A adds transaction X offline.
B adds transaction Y offline.

Later they sync.

Whichever snapshot is considered newer replaces the other entire state.
```

This means X or Y can disappear.

Equal timestamps / clock skew can also create divergence.

Future direction:

**Snapshot v2 + record-level merge**

with:

- per-record IDs
- per-record update metadata
- tombstones for deletion
- conflict handling
- deterministic convergence
- clock-skew-safe revisions

Important:

Do not change sync in the same phase as the database migration.

---

## 5.3 Financial data security can be improved

Current app PIN is a 4-digit PIN hashed locally.

Important conclusion:

The PIN should be treated as an **application privacy lock**, not encryption.

A 4-digit PIN has only 10,000 combinations.

Future security direction:

- PIN rate limiting
- progressive delay after repeated failures
- Android Keystore-backed secret storage for cryptographic keys
- explicit Android backup behavior
- optional database encryption after a separate design decision
- optional encrypted export format

Do **not** store the entire financial database in `flutter_secure_storage`.

If used, secure storage should store small high-value secrets such as:

- encryption keys
- wrapped key material

---

## 5.4 Android backup policy is currently implicit

Financial data and PIN-related state should not accidentally be included in Android cloud backup simply because default behavior is enabled.

Future action:

Explicitly define:

- backup exclusions
- data extraction rules
- whether database files are backed up
- whether security material is backed up

User-controlled Dhadda export/import should remain the intentional backup mechanism.

---

## 5.5 Embedded Flutter Web bundle can become stale

Current flow involves manually rebuilding and copying:

```text
build/web
→
assets/webapp
```

The inspected repository showed the embedded web app version lagging behind the Android app.

Future direction:

Automate embedded web build + copy + version verification.

---

## 5.6 Release signing needs improvement

The inspected Android release configuration used debug signing for release builds.

This must be replaced before publishing GitHub releases.

For GitHub/F-Droid:

- use proper maintainer release signing for GitHub APKs
- keep keystore private
- never commit passwords
- investigate reproducible upstream binaries / F-Droid signing strategy

---

# 6. Distribution Decision

The project will be distributed via:

## GitHub

Expected:

- public source
- tagged releases
- signed APKs
- checksums
- changelogs

## F-Droid

The project should remain F-Droid compatible.

This means prioritizing:

- FOSS dependencies
- public source
- FOSS license
- exact release tags
- source-buildability
- reproducible build investigation
- metadata under Fastlane/F-Droid-compatible structure
- avoiding proprietary SDK dependencies

Google Play is currently out of scope.

Do not add Google Play-specific work unless the project direction changes later.

---

# 7. Files Created During This Conversation

## `PROJECT_CONTEXT.md`

A complete project audit generated from the actual repository.

It documents:

- project overview
- features
- stack
- architecture
- folder structure
- important files
- navigation
- models
- persistence
- networking
- authentication
- state management
- dependencies
- config
- completed work
- known issues
- architecture rules
- build instructions
- tests
- technical status
- recommended next steps
- AI handoff
- persistence risks
- sync conflict analysis
- threat model
- release readiness
- embedded web build reproducibility
- architecture scaling
- future stack

This should remain the primary technical source of truth together with the repository.

---

## `DHADDA_SECURITY_EFFICIENCY_FDROID_ROADMAP.md`

A full phase-by-phase implementation roadmap created during this chat.

It is specifically designed for:

- security
- efficiency
- data integrity
- maintainability
- GitHub
- F-Droid
- open-source distribution

The roadmap explicitly says Muse should **not implement everything at once**.

---

# 8. Roadmap Summary

## Phase 0 — Freeze a known-good baseline

Goal:

Create a safe recovery point before risky changes.

Tasks include:

- Git checkpoint/tag
- current health verification
- export fixture
- synthetic test fixtures
- Snapshot v1 fixture
- legacy fixtures
- corruption fixtures
- behavior baseline
- backup/restore baseline
- baseline documentation

No architecture changes.

---

## Phase 1 — Build / GitHub / F-Droid foundation

Tasks:

- pin Flutter toolchain
- real release signing
- remove debug-signed releases
- automate embedded web build
- separate GitHub Pages build from phone-hosted embedded web build
- harden GitHub Actions
- FOSS dependency audit
- F-Droid metadata
- reproducible-build investigation
- explicit Android backup configuration

No database migration yet.

---

## Phase 2 — Real persistence layer

Primary direction:

**Drift + SQLite**

Tasks:

- introduce persistence abstraction
- database schema
- indexes
- safe SharedPreferences migration
- idempotent migration
- preserve old data until verification
- preserve Snapshot v1
- preserve backup import/export
- investigate Android + Web database strategy
- consider integer minor units for money

---

## Phase 3 — Security at rest

Tasks:

- explicit Android backup policy
- PIN rate limiting
- app-lock vs encryption separation
- secure key storage
- database encryption decision checkpoint
- optional encrypted backups
- no sensitive logging

---

## Phase 4 — Fix sync data loss

Tasks:

- Snapshot v2
- record-level merge
- tombstones
- per-record revisions
- conflict handling
- clock-skew-safe strategy
- legacy v1 compatibility
- extensive multi-device tests

Correctness before delta-sync optimization.

---

## Phase 5 — LAN security

Tasks:

- trusted-WiFi guidance
- secure random credentials
- wrong-PIN rate limiting
- body-size limits
- session TTLs
- safer request handling
- replay/integrity design investigation
- accurate HTTP threat documentation

Do not claim local HTTP is secure against hostile networks.

---

## Phase 6 — Performance / architecture cleanup

Tasks:

- gradually split `ExpenseStore`
- database-backed analytics
- pagination/windowed history
- narrower Provider rebuilds
- move heavy work off UI-critical paths
- benchmark 1k / 5k / 20k / 50k records

No state-management rewrite unless clearly necessary.

---

## Phase 7 — Integration and security testing

Tasks:

- add `integration_test/`
- migration tests
- sync integration tests
- real-device SMS tests
- mDNS tests
- reminder tests
- phone-host tests
- privacy-safe local diagnostics

---

## Phase 8 — GitHub / F-Droid release process

Tasks:

- choose/add open-source license
- release tagging
- changelog discipline
- signed GitHub APKs
- SHA256 checksums
- F-Droid metadata
- reproducibility
- FOSS dependency gate

---

# 9. Priority Order

Recommended execution order:

```text
Phase 0
↓
Phase 1
↓
Phase 2
↓
Phase 4
↓
Phase 3
↓
Phase 5
↓
Phase 7
↓
Phase 6
↓
Phase 8
```

Important exception:

Android backup-policy work should be pulled forward into Phase 1 because current data is plaintext.

---

# 10. Current Next Step

The next task is:

# PHASE 0 ONLY

Do not allow Muse to start:

- Drift
- SQLite
- Snapshot v2
- sync refactor
- encryption
- Provider migration
- UI redesign

until Phase 0 is complete and reviewed.

---

# 11. Phase 0 Prompt Prepared in This Chat

Use the following intent with Muse:

```text
Read PROJECT_CONTEXT.md and
DHADDA_SECURITY_EFFICIENCY_FDROID_ROADMAP.md completely.

Dhadda is distributed through GitHub and F-Droid only.
Google Play is not planned.

Start Phase 0 only.

Before changing anything:
- inspect the repository;
- verify the current baseline;
- compare it to PROJECT_CONTEXT.md;
- identify mismatches;
- show the Phase 0 implementation plan.

Then perform Phase 0 only.

Do not start Phase 1 automatically.
```

The detailed Phase 0 prompt from the previous ChatGPT conversation additionally asked Muse to:

- inspect Git state
- verify Flutter/Dart version
- verify current tests
- preserve current backup/export format
- create synthetic fixtures
- preserve Snapshot v1 fixture
- create legacy fixtures
- create corruption fixtures
- capture existing behavior
- verify export/import round-trip
- create `docs/BASELINE.md`
- run `flutter analyze`
- run `flutter test`
- report all changed files
- confirm no user-data format change
- confirm no sync-format change

---

# 12. Phase 0 Restrictions

During Phase 0, do NOT:

- add Drift
- add SQLite
- add SQLCipher
- add `flutter_secure_storage`
- change SharedPreferences keys
- migrate stored data
- change transaction models
- change monetary representation
- modify Snapshot format
- create Snapshot v2
- change sync behavior
- change QR formats
- modify LAN protocol
- migrate Provider
- refactor `ExpenseStore`
- change PIN hashing
- add encryption
- upgrade unrelated dependencies
- add Firebase
- add Supabase
- add analytics
- add Google Play work
- redesign UI

Phase 0 is only a baseline and safety phase.

---

# 13. Phase 0 Completion Report Expected From Muse

Ask Muse to return:

```text
PHASE:
Phase 0 — Freeze a Known-Good Baseline

STATUS:
COMPLETE / PARTIAL / FAILED

BASELINE VERSION:

GIT COMMIT:

BASELINE TAG:

WORKING TREE STATUS:

FLUTTER VERSION:

DART VERSION:

ANALYZE RESULT:

TEST RESULT:

TOTAL TESTS:

FIXTURES CREATED:

SNAPSHOT V1 FIXTURE:

LEGACY FIXTURES:

CORRUPTION FIXTURES:

BASELINE DOCUMENT:

FILES CHANGED:

APPLICATION CODE CHANGED:
YES / NO

USER DATA FORMAT CHANGED:
YES / NO

SYNC FORMAT CHANGED:
YES / NO

KNOWN PRE-EXISTING ISSUES:

MANUAL VERIFICATION STILL REQUIRED:

READY FOR PHASE 1:
YES / NO
```

---

# 14. Guidance for the Next ChatGPT Conversation

In the next ChatGPT chat:

1. Upload:
   - `CHAT_HANDOFF.md`
   - `PROJECT_CONTEXT.md`
   - `DHADDA_SECURITY_EFFICIENCY_FDROID_ROADMAP.md`

2. If Muse has already completed Phase 0, also paste/upload:
   - Muse's Phase 0 completion report
   - any changed files or diff if available

3. Ask ChatGPT to:
   - review whether Phase 0 was completed safely
   - detect scope creep
   - verify that no data/sync architecture changed
   - identify missing baseline fixtures/tests
   - decide whether the project is safe to enter Phase 1

Do not tell Muse to begin Phase 1 until the Phase 0 report has been reviewed.

---

# 15. High-Level Technical Direction

The desired long-term stack remains:

```text
Flutter + Dart
Material 3
Provider / ChangeNotifier

        ↓

Repositories / persistence abstractions

        ↓

Drift / SQLite
for financial/domain data

SharedPreferences
for small non-critical settings

Android Keystore-backed secure storage
for small cryptographic secrets

        ↓

Snapshot v2 record-level sync
with tombstones and conflict handling

        ↓

GitHub + F-Droid
open-source distribution
```

No native Android rewrite is currently recommended.

---

# 16. Final Context for a New AI

If an AI receives only this file, the most important facts are:

- Dhadda is already a working Flutter Android + Web expense tracker.
- It should remain Flutter.
- It should remain offline-first and cloud-free.
- Provider is not the problem.
- SharedPreferences-as-database is a real architectural weakness.
- Whole-snapshot sync can lose offline edits.
- Security should improve without pretending a 4-digit PIN is strong encryption.
- GitHub + F-Droid are the only current distribution targets.
- FOSS compatibility matters.
- Work must be done phase by phase.
- **Current task: Phase 0 only.**
- Do not start database/sync/security migrations until Phase 0 is safely completed.

---

*End of chat handoff.*
