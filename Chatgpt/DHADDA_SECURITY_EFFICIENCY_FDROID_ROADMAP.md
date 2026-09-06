# DHADDA SECURITY, EFFICIENCY & F-DROID ROADMAP

> **Purpose:** A phase-by-phase implementation plan for improving Dhadda without turning the project into a rewrite.
>
> **Primary source of truth:** `PROJECT_CONTEXT.md` and the actual repository.
>
> **Distribution target:** GitHub Releases + F-Droid only.
>
> **Product direction:** Open-source, personal, offline-first expense tracking. No Google Play requirement. No hosted backend requirement. No accounts, Firebase, Supabase, analytics SDKs, or cloud dependency unless a future product requirement explicitly changes this.
>
> **Execution rule for Muse:** Do **not** implement this entire roadmap in one pass. Work one phase at a time, run the required tests, report results, and only then continue when explicitly instructed.

---

## 1. Product Goals

Dhadda should become:

1. **More secure**
   - Financial records should not remain easy-to-read plaintext application state.
   - Android backup behavior must be explicit.
   - App-lock behavior should resist casual brute-force attempts.
   - LAN sync should clearly communicate its trust assumptions.
   - Sensitive exports and sync credentials should be treated as secrets.

2. **More reliable**
   - No normal cross-device sync scenario should silently delete an independently-created transaction.
   - Storage should survive crashes and partial writes better than monolithic JSON values.
   - Migrations must preserve existing users' data.

3. **More efficient**
   - Adding one transaction should not require serializing and rewriting the entire history.
   - Large histories should not require scanning every record for common queries.
   - UI rebuilds should become more targeted where measurable.
   - Sync should eventually avoid unnecessary whole-dataset work.

4. **More maintainable**
   - Keep Flutter and the current user experience.
   - Keep Provider/ChangeNotifier unless a real technical limitation appears.
   - Separate persistence, sync, settings, analytics, and UI responsibilities gradually.
   - Preserve the single-codebase Android + Web advantage.

5. **Open-source and reproducible**
   - GitHub releases should be traceable to source tags.
   - F-Droid should be able to build the app from source with FOSS dependencies.
   - Build versions and embedded web assets must be reproducible.
   - No proprietary SDK should be introduced without an explicit decision.

---

## 2. Verified Current Baseline

Before modifying anything, Muse must re-check these facts against the repository. `PROJECT_CONTEXT.md` currently reports:

- Flutter + Dart + Material 3.
- Provider + `ChangeNotifier`.
- `ExpenseStore` as the main global state object.
- Financial/domain data stored as JSON in `SharedPreferences`.
- Five full snapshot backups.
- No database engine.
- Snapshot-based sync using whole-state last-write-wins.
- Four sync/transport paths sharing the snapshot model.
- Android-native Kotlin bridges for mDNS, SMS, and camera permission.
- Phone-hosted Flutter Web application.
- Optional zero-dependency Node LAN relay.
- Plain HTTP LAN APIs protected by PIN/link information.
- Optional 4-digit application PIN hashed with SHA-256 plus a static domain string.
- Biometric unlock through `local_auth`.
- No hosted backend.
- No cloud analytics or crash-reporting SDK.
- GitHub Actions for web and APK builds.
- Release configuration currently using debug signing.
- Embedded `assets/webapp/` build can lag behind the Android app.
- No `integration_test/` suite.
- Current automated suite: 49 tests across 12 files.
- Current version in the inspected snapshot: `1.3.1+2`.

Important source files include:

- `lib/store.dart`
- `lib/models.dart`
- `lib/security.dart`
- `lib/main.dart`
- `lib/sync/link_sync.dart`
- `lib/sync/link_store.dart`
- `lib/sync/relay_client.dart`
- `lib/sync/wifi_host_io.dart`
- `lib/sync/phone_host_io.dart`
- `lib/sync/file_sync.dart`
- `lib/sync/sms.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `.github/workflows/build.yml`
- `server/serve-expense.cjs`
- `pubspec.yaml`
- `test/`

If the repository no longer matches these facts, update the plan for the actual repository rather than forcing old assumptions.

---

## 3. Architectural Decisions to Preserve

Unless a later phase explicitly changes one of these with migration support:

### Keep

- Flutter.
- Dart.
- Material 3.
- Provider/ChangeNotifier.
- Offline-first behavior.
- Android + Flutter Web from one codebase.
- No mandatory hosted backend.
- No mandatory account system.
- Existing package/application ID.
- Existing transaction/category/project/loan IDs.
- Existing QR formats until a versioned replacement exists.
- Existing Snapshot v1 import capability.
- Existing file backup/import capability.
- Existing SMS import concept.
- Existing mDNS + IP fallback concept.
- GitHub and F-Droid distribution.
- FOSS-only dependency preference.

### Do not introduce merely for fashion

- Riverpod migration.
- Bloc migration.
- Redux.
- Firebase.
- Supabase.
- GraphQL.
- Kubernetes.
- Microservices.
- Hosted authentication.
- Remote realtime databases.
- A native Kotlin/Compose rewrite.

---

# 4. Target Architecture

The desired long-term architecture is:

```text
Flutter UI
│
├── Home / History / Add / Lent / Menu / Sync
│
├── Feature-facing state / view models
│      │
│      └── Provider / ChangeNotifier
│
├── Domain layer
│      ├── Transaction
│      ├── Category
│      ├── Project
│      ├── Loan
│      ├── Repayment
│      └── Sync metadata
│
├── Repositories
│      ├── TransactionRepository
│      ├── LoanRepository
│      ├── ProjectRepository
│      ├── SettingsRepository
│      └── SyncRepository
│
├── Persistence
│      ├── Drift / SQLite for domain records
│      ├── SharedPreferences for non-critical settings only
│      └── Secure storage for small secret/key material only
│
├── Sync
│      ├── Snapshot v1 compatibility
│      ├── Snapshot v2 record merge
│      ├── tombstones
│      ├── conflict handling
│      └── optional future delta/change-log sync
│
├── Local services
│      ├── SMS import
│      ├── reminders
│      ├── mDNS
│      ├── file backup
│      └── phone-hosted web app
│
└── Native Android bridge
       ├── SMS
       ├── mDNS
       └── permission/platform helpers
```

This architecture must be reached incrementally.

---

# 5. Mandatory Execution Protocol for Muse

For every phase:

1. Read `PROJECT_CONTEXT.md`.
2. Inspect every file named by that phase.
3. Create a short implementation plan.
4. Identify backward-compatibility risks.
5. Add or update tests **before or alongside** risky logic.
6. Make the smallest coherent change.
7. Run:
   - `flutter analyze`
   - `flutter test`
8. Run any phase-specific build/integration checks.
9. Report every changed file.
10. Report any unverified assumptions.
11. Do not continue to the next phase automatically.

At the end of every phase, output:

```text
PHASE:
STATUS:

CHANGED FILES:

BEHAVIOR CHANGES:

DATA MIGRATION:
NONE / DESCRIPTION

BACKWARD COMPATIBILITY:

SECURITY IMPACT:

PERFORMANCE IMPACT:

ANALYZE:

TESTS:

BUILD:

MANUAL VERIFICATION STILL REQUIRED:

KNOWN RISKS:

NEXT RECOMMENDED PHASE:
```

---

# PHASE 0 — Freeze a Known-Good Baseline

## Objective

Create a recoverable baseline before architecture/security work begins.

## Tasks

### 0.1 Create a source-control checkpoint

Before changing application code:

- Ensure the working tree is understood.
- Commit the current known-good version.
- Create a version tag or clearly named baseline tag.
- Do not include generated secrets, keystores, or local config.

Suggested semantic name:

```text
pre-security-storage-migration
```

The exact tag may follow the project's release convention.

### 0.2 Export real test data

Using the current app:

- Create a representative dataset.
- Include:
  - expenses
  - income
  - categories
  - budgets
  - projects
  - lent entries
  - borrowed entries
  - repayments
  - top-ups
  - reminder timestamps
  - settings
- Export a Snapshot/file backup.

Keep this fixture for migration tests.

### 0.3 Create edge-case fixtures

Create sanitized test fixtures containing:

- Empty dataset.
- One transaction.
- Hundreds of transactions.
- Loans with repayments/top-ups.
- Deleted/reassigned categories if supported.
- Projects with transactions.
- Unicode notes.
- Nepali currency formatting.
- Legacy data shapes that existing migrations support.
- Corrupt JSON.
- Missing optional fields.

### 0.4 Capture current behavior

Document:

- Cold-start behavior.
- Add transaction behavior.
- Search/filter behavior.
- Backup export/import.
- Direct WiFi sync.
- Link sync.
- Show on PC.
- SMS manual import.
- SMS auto import.
- reminders.
- PIN/biometric flow.

## Acceptance criteria

- Current app builds.
- Current 49+ tests pass.
- `flutter analyze` is clean.
- A baseline tag exists.
- A known-good export fixture exists.
- No architecture changes yet.

---

# PHASE 1 — Build, Release, GitHub & F-Droid Reproducibility

## Objective

Make builds deterministic enough that future security/storage changes are testable and F-Droid packaging is realistic.

This phase replaces the earlier Google Play work. **Do not add Play Store tasks.**

---

## 1.1 Pin the Flutter toolchain

Current `PROJECT_CONTEXT.md` reports Flutter 3.47.2 as observed but not pinned.

Change the project so CI and contributors can determine the intended Flutter version.

Possible approaches:

- a documented exact Flutter version;
- `.fvmrc` / FVM if appropriate;
- another simple version file;
- explicit `flutter-version` in GitHub Actions.

Do not rely on `stable` alone for release builds.

### Acceptance

A fresh environment can identify the exact Flutter/Dart toolchain expected for a release.

---

## 1.2 Fix release signing for GitHub builds

Current release signing must stop falling back to debug signing.

Requirements:

- Release builds use a maintainer-owned release key.
- Keystore is never committed.
- Passwords are never committed.
- Local signing configuration comes from ignored files/environment.
- GitHub secrets are used only in protected tag/release workflows if automated signing is enabled.
- Debug builds continue to use debug signing.
- A missing release key must produce a clear release-build failure, not a debug-signed "release".

### Key handling

Document:

- where the key is stored;
- how it is backed up securely;
- how recovery works;
- who has access;
- fingerprint of the public certificate;
- how to verify a GitHub APK signature.

Do not place private key material in documentation.

---

## 1.3 Decide GitHub/F-Droid signing compatibility

This requires an explicit distribution decision.

### Option A — Different signatures

- GitHub release APK is signed by the maintainer.
- Official F-Droid build is signed by F-Droid.

Consequence:

- Users generally cannot seamlessly switch between the two installed variants under the same package ID.

### Option B — Reproducible upstream binary verification

Long-term preferred if feasible:

- GitHub publishes the maintainer-signed APK.
- The corresponding F-Droid source build is byte-for-byte reproducible.
- F-Droid verifies the upstream binary and can use the upstream-signed binary through its reproducible-build workflow.

Muse should **research and document** which approach is feasible for the current Flutter build before changing signatures/package IDs.

Do not create separate package IDs unless there is a clear distribution reason.

---

## 1.4 Automate the embedded web bundle

Eliminate:

```text
flutter build web
manual copy
build/web → assets/webapp
```

Create one deterministic tool, for example:

```text
tool/build_embedded_web.dart
```

or an equivalent shell/PowerShell script.

It must:

1. Read the canonical app version.
2. Build Flutter Web using the exact required flags.
3. Not use the GitHub Pages `base-href` for the embedded bundle.
4. Use the intended PWA strategy.
5. Remove stale files from `assets/webapp/`.
6. Copy the new build.
7. Verify embedded version equals app version.
8. Verify required files exist.
9. Exit non-zero on mismatch.

Also ensure `phone_host_io.dart` serves any new required MIME types, including `application/wasm` if Drift Web is introduced later.

---

## 1.5 Separate GitHub Pages web build from embedded web build

They are different artifacts.

### GitHub Pages build

May need:

```text
--base-href /repository-name/
```

### Embedded phone-host build

Must be root-relative to the phone-host URL and must not accidentally inherit the Pages base path.

CI must build/validate them independently.

---

## 1.6 Harden GitHub Actions

Review `.github/workflows/build.yml`.

Target:

- least-privilege `permissions:`;
- pin critical third-party actions to immutable commit SHAs where practical;
- exact Flutter version;
- no secret access on untrusted pull requests;
- analyze;
- tests;
- embedded web verification;
- Android APK build;
- release signing only on trusted tags;
- SHA-256 checksums for released APKs;
- optional SBOM/dependency inventory;
- no debug-key release artifact.

---

## 1.7 Prepare F-Droid source-build requirements

F-Droid-facing repository should include:

- Public Git repository.
- FOSS license file.
- FOSS-only runtime/build dependencies.
- Upstream metadata.
- Tagged releases.
- Changelog per version.
- Reproducible command-line build instructions.

Current F-Droid guidance expects upstream metadata such as:

```text
fastlane/metadata/android/en-US/
├── short_description.txt
├── full_description.txt
├── images/icon.png
├── images/phoneScreenshots/
└── changelogs/<versionCode>.txt
```

The project already has some Fastlane metadata; complete and verify it rather than inventing a second metadata system.

---

## 1.8 Dependency license audit

Before F-Droid submission, generate an audit of every direct and important transitive dependency.

For each:

```text
package
version
license
source repository
contains native binaries?
contains Google/Firebase/GMS dependency?
network service dependency?
F-Droid concern?
```

Reject proprietary dependencies unless an explicit F-Droid-compatible flavor excludes them.

Keep `flutter_zxing` unless a technical issue requires replacement; avoiding Play Services is consistent with the project direction.

---

## 1.9 Reproducible-build investigation

Flutter builds can contain absolute/embedded paths or native artifacts that reduce reproducibility.

Muse should create a reproducibility test:

1. Build the same tagged source twice in clean environments.
2. Normalize only documented non-semantic container metadata if required by the official verification method.
3. Compare outputs.
4. Identify non-deterministic files.
5. Record exact toolchain paths/versions.
6. Fix reproducibility issues incrementally.

Do not claim reproducibility until independently verified.

---

## Phase 1 acceptance criteria

- No release build uses debug signing.
- Toolchain version is pinned.
- Embedded web bundle is automatically reproducible and version-checked.
- CI checks analyze + tests + embedded bundle.
- GitHub release process is documented.
- F-Droid dependency/license audit exists.
- F-Droid metadata is complete enough for packaging work.
- Build reproducibility has at least been tested and documented.
- No Google Play work added.

---

# PHASE 2 — Introduce a Real Persistence Layer

## Objective

Stop storing critical financial/domain history as monolithic JSON values in SharedPreferences.

## Recommended database

**Drift + SQLite** is the preferred starting point.

Reasons:

- Flutter/Dart-native architecture.
- Relational integrity.
- Transactions.
- Indexes.
- Migrations.
- Query streams.
- Android support.
- Web support through Drift/WASM when configured correctly.
- Open-source ecosystem.

Do not use `flutter_secure_storage` as the primary transaction database.

Use secure storage only for small secrets/key material.

---

## 2.1 Create a persistence abstraction first

Before migrating data, introduce an interface such as:

```text
ExpenseRepository
CategoryRepository
LoanRepository
ProjectRepository
SettingsRepository
```

or a smaller initial gateway if that better fits the existing app.

Goal:

```text
ExpenseStore
    ↓
PersistenceGateway
    ↓
SharedPreferences implementation
```

At this step the behavior may remain exactly the same.

This creates a seam for replacing persistence without rewriting UI code.

---

## 2.2 Design the database schema

Suggested logical tables:

### transactions

```text
id TEXT PRIMARY KEY
type
amount
category_id
date
note
mode
project_id nullable
created_at
updated_at
updated_by
deleted_at nullable
```

### categories

```text
id TEXT PRIMARY KEY
name
icon
color
budget
sort_order
created_at
updated_at
updated_by
deleted_at nullable
```

### projects

```text
id TEXT PRIMARY KEY
name
note
created
icon
color
updated_at
updated_by
deleted_at nullable
```

### loans

```text
id TEXT PRIMARY KEY
person
kind
principal
date_lent
due_date nullable
note
remind_at
created_at
updated_at
updated_by
deleted_at nullable
```

### loan_topups

```text
id TEXT PRIMARY KEY
loan_id
amount
date
note
created_at
updated_at
updated_by
deleted_at nullable
```

### loan_repayments

```text
id TEXT PRIMARY KEY
loan_id
amount
date
note
created_at
updated_at
updated_by
deleted_at nullable
```

### sync_metadata

Potential fields:

```text
device_id
device_name
schema_version
snapshot_version
last_sync
local_logical_counter
```

### settings

Most settings may stay in SharedPreferences initially.

---

## 2.3 Add indexes

At minimum evaluate indexes for:

- `transactions(date)`
- `transactions(category_id, date)`
- `transactions(project_id, date)`
- `transactions(type, date)`
- loans by status/due date
- tombstone/update fields used by sync

Only add indexes justified by actual queries.

---

## 2.4 Keep money representation safe

Do not blindly continue storing currency values as unconstrained binary floating point.

Before schema finalization, evaluate switching monetary values to integer minor units:

```text
NPR 123.45
→
12345
```

or a clearly defined decimal representation.

Migration must preserve existing values exactly enough that totals do not change.

If changing numeric representation creates unacceptable compatibility risk, document it and defer.

---

## 2.5 SharedPreferences migration

Create a one-time migration:

```text
old SharedPreferences JSON
        ↓
validate
        ↓
single DB transaction
        ↓
verify counts/totals/IDs
        ↓
mark migration complete
```

Rules:

- Never delete old keys before verification.
- Backup before migration.
- Migration must be idempotent.
- If migration fails, old app data remains recoverable.
- Do not reseed defaults over failed user data.
- Log a safe local diagnostic reason.
- Do not expose financial data in logs.

---

## 2.6 Preserve Snapshot v1

During this phase:

- Database changes.
- Sync contract does **not** change yet.
- File backup JSON remains importable/exportable.
- Existing peers can still sync with Snapshot v1 behavior.
- QR formats remain unchanged.

This keeps persistence migration separate from sync migration.

---

## 2.7 Web persistence

Drift supports Flutter Web using SQLite/WASM.

Before enabling it for the phone-hosted browser app, verify:

- `sqlite3.wasm` is included.
- Drift worker is included.
- correct MIME type is served;
- browser fallback behavior works;
- phone-hosted HTTP environment works;
- GitHub Pages build works;
- no service-worker caching regression;
- browser persistence survives reload;
- cross-origin headers are not accidentally required for baseline operation.

If Drift Web causes disproportionate risk, use a platform persistence adapter temporarily:

```text
Android → Drift/SQLite
Web     → current browser persistence
```

while keeping the same domain/repository API.

Do not break Show on PC simply to make storage uniform.

---

## 2.8 Database tests

Add tests for:

- fresh DB creation;
- schema version;
- migration from real v1 fixtures;
- idempotent migration;
- corrupt old JSON;
- duplicate IDs;
- foreign-key behavior;
- category deletion behavior;
- project deletion/untagging behavior;
- loan relationships;
- transaction rollback;
- database reopen;
- backup/export round trip.

---

## Phase 2 acceptance criteria

- Android domain data is stored in a transactional database.
- SharedPreferences no longer stores full transaction/loan/project collections after successful migration.
- Existing users migrate automatically.
- Snapshot v1 remains compatible.
- Existing backups import.
- App totals match pre-migration fixtures.
- Analyze/tests clean.
- Show on PC still works.

---

# PHASE 3 — Security at Rest and Local App Lock

## Objective

Protect financial data better without pretending a 4-digit PIN is strong encryption.

---

## 3.1 Make Android backup behavior explicit immediately

Because Dhadda already has deliberate export/backups, do not rely on Android's default automatic cloud backup for plaintext financial state.

Muse should inspect the current Android version behavior and implement explicit backup/data-extraction rules.

Preferred privacy posture:

- Financial database is excluded from unintended cloud backup.
- Security key material is excluded.
- SharedPreferences security state is excluded where appropriate.
- The app's explicit export/import flow remains the user-controlled backup mechanism.

Document any impact on Android device-to-device migration.

---

## 3.2 Separate app lock from encryption

Current PIN should be described as:

```text
application privacy gate
```

not:

```text
database encryption password
```

The four-digit PIN has only 10,000 combinations.

Do not directly derive the primary database encryption key from the 4-digit PIN.

---

## 3.3 Add brute-force resistance to app PIN

Without changing PIN UX unnecessarily:

- rate-limit repeated failures;
- introduce progressive delay;
- reset failure counter after successful biometric/PIN unlock;
- do not log entered PINs;
- prevent accidental PIN visibility;
- use constant-time hash comparison where practical;
- consider requiring device authentication for sensitive security-setting changes.

Example policy to evaluate:

```text
0–4 failures: normal
5 failures: short delay
additional failures: progressively longer delay
```

Avoid destructive wipe-on-failure behavior.

---

## 3.4 Secure small secret material

If cryptographic key material is introduced:

Use an Android Keystore-backed storage mechanism.

A package such as `flutter_secure_storage` can be evaluated because it is designed for small encrypted values and is FOSS-licensed, but Muse must verify:

- exact current package version;
- license;
- Android implementation;
- F-Droid buildability;
- backup behavior;
- behavior across reinstall/device transfer.

Use secure storage for:

- a random database encryption key;
- key-wrapping material;
- long-lived local secret tokens if ever needed.

Do **not** store all transaction JSON in secure storage.

---

## 3.5 Database encryption decision checkpoint

Do not automatically add SQLCipher.

Before implementation, create a short decision record comparing:

### Option A — normal SQLite + explicit Android backup exclusion

Pros:

- simpler;
- highly reproducible;
- fewer native crypto dependencies;
- strong integrity/performance improvement.

Cons:

- rooted/offline filesystem extraction can read DB.

### Option B — encrypted SQLite / SQLCipher-compatible approach

Pros:

- financial DB encrypted at rest.

Cons:

- additional native/build complexity;
- F-Droid reproducibility must be verified;
- key management becomes critical.

If Option B is chosen:

- use a random high-entropy DB key;
- store/wrap that key using Android Keystore-backed storage;
- never use the 4-digit PIN directly as the DB key;
- test key loss/reinstall scenarios;
- document recovery limitations;
- verify every crypto dependency is FOSS and reproducibly buildable.

Do not use obsolete packages merely because an old tutorial recommends them.

---

## 3.6 Encrypted export format

Current JSON/CSV exports are plaintext.

Add an **optional** encrypted backup format after database migration is stable.

Possible design:

```text
Dhadda encrypted backup
├── format version
├── KDF parameters
├── salt
├── nonce
└── authenticated ciphertext
```

Requirements:

- modern authenticated encryption;
- vetted KDF for user passphrases;
- no custom cryptography;
- wrong password fails safely;
- corruption detected;
- plaintext export can remain available only if clearly labeled;
- user receives an explicit warning that plaintext exports are sensitive.

Do not include cryptographic secrets in QR/logs/backups.

---

## Phase 3 acceptance criteria

- Android backup policy is explicit.
- PIN attempts are rate-limited.
- PIN is never described as encryption.
- Secret/key material is stored in an appropriate secure store.
- If DB encryption is enabled, recovery and F-Droid buildability are tested.
- Export sensitivity is clearly communicated.
- No sensitive values appear in logs.

---

# PHASE 4 — Fix Sync Data Loss

## Objective

Eliminate the current whole-snapshot clobber behavior for normal independent edits.

This is the highest data-integrity architecture phase.

Do not start until Phase 2 storage is stable.

---

## 4.1 Preserve Snapshot v1 compatibility

Keep the existing v1 decoder/importer.

Introduce a new version rather than mutating v1 semantics invisibly.

Example:

```text
Snapshot v1
→ legacy whole-state replacement

Snapshot v2
→ record-aware merge
```

---

## 4.2 Add record metadata

For every syncable entity add:

```text
id
createdAt
updatedAt
updatedBy
deletedAt?
```

For nested entities such as repayments/top-ups, make sure each already-stable ID remains independently mergeable.

---

## 4.3 Replace hard delete with tombstones for syncable records

Instead of immediately forgetting that a record existed:

```text
deletedAt = timestamp
updatedBy = deviceId
```

Tombstones prevent another offline device from resurrecting deleted records.

Do not physically purge tombstones until a documented safe-retention policy exists.

---

## 4.4 Merge behavior

For Snapshot v2:

### Different record IDs

Union them.

```text
A adds X
B adds Y
→
X + Y
```

### Same ID, one unchanged

Use changed record.

### Same ID, both changed

Detect conflict.

Do not silently overwrite without recording the decision.

Initial deterministic policy may use:

```text
revision ordering
then deviceId tie-break
```

but Muse must document clock-skew implications.

---

## 4.5 Logical revision strategy

Wall-clock time alone is not enough.

Before coding, compare:

- monotonic per-device counter + device ID;
- Hybrid Logical Clock;
- vector-clock-style conflict detection.

For Dhadda's personal/small-device-count scope, choose the simplest mechanism that:

- avoids same-millisecond ties;
- tolerates local clock moving backward;
- deterministically converges;
- can identify genuine concurrent edits to the same record where possible.

Create tests before committing to the algorithm.

---

## 4.6 Conflict handling

For rare same-record concurrent edits, preferred behavior:

1. Never lose the losing version silently.
2. Store conflict metadata or a recoverable copy.
3. Apply a deterministic visible winner for normal UI.
4. Optionally expose a future "sync conflicts" screen if real-world need appears.

Do not build a complex conflict UI unless necessary.

---

## 4.7 Keep full snapshots as bootstrap

Do not immediately build incremental sync.

Snapshot v2 can still exchange the full dataset while performing record-level merge.

This gets correctness first.

```text
full v2 snapshot
        ↓
record merge
        ↓
safe convergence
```

Later optimization can exchange deltas.

---

## 4.8 Legacy peer behavior

When a v2 app encounters a v1 peer:

- detect protocol version;
- do not pretend record merge is available;
- preserve v1 compatibility if safe;
- display/record a clear legacy-sync warning if data-loss semantics remain;
- encourage both devices to upgrade.

Never silently downgrade v2 data in a way that destroys tombstones/revision metadata.

---

## 4.9 Sync tests

Mandatory tests:

- A and B independently add different transactions.
- A and B independently add loans.
- A edits X while B adds Y.
- A deletes X while B is offline.
- A deletes X while B edits X.
- same-record concurrent edits.
- identical wall-clock timestamp.
- clock moves backward.
- device clock far ahead.
- repeated sync is idempotent.
- sync A→B→A converges.
- three devices converge.
- tombstone prevents resurrection.
- v1 import still works.
- backup restore followed by sync.
- network retry does not duplicate records.

---

## Phase 4 acceptance criteria

The following scenario must pass:

```text
A and B begin equal.
A adds transaction X offline.
B adds transaction Y offline.
They reconnect and sync.
Both devices end with X and Y.
```

No manual backup restore should be required.

---

# PHASE 5 — LAN / Sync Transport Hardening

## Objective

Reduce avoidable exposure while keeping local-network simplicity.

Current LAN transport should continue to be described as **trusted-LAN oriented** unless real transport authentication/encryption is added.

---

## 5.1 Improve user-facing trust guidance

Show concise guidance:

- Use sync on trusted home/private Wi-Fi.
- Avoid public/hotel/coffee-shop Wi-Fi.
- Do not forward sync QR screenshots/codes.
- Stop hosting when finished.
- IP/mDNS URLs expose a local service while active.

---

## 5.2 Make session credentials cryptographically random

Verify all PIN/code/token generation.

Use a cryptographically secure random source for:

- session identifiers;
- link secrets;
- pairing tokens.

Human-entered short PINs may remain for usability, but should not be the only high-entropy secret if stronger application-layer authentication is introduced.

---

## 5.3 Add rate limits and request constraints

LAN servers should enforce:

- wrong-PIN rate limiting;
- maximum request-body size;
- maximum snapshot size;
- bounded concurrent requests;
- bounded session creation;
- TTLs;
- safe JSON parsing;
- no raw exception leakage;
- no financial data in debug logs.

---

## 5.4 Review CORS and browser routes

`CORS *` is not itself a protection against LAN attackers.

Muse should determine exactly which browser flows require cross-origin access and reduce permissiveness where possible without breaking Show on PC.

Do not claim a CORS change encrypts or authenticates LAN traffic.

---

## 5.5 Replay/integrity protection

For state-changing sync requests, consider:

- request nonce;
- session sequence number;
- message authentication code;
- replay cache/window.

Only implement after defining a versioned protocol.

---

## 5.6 Transport encryption research checkpoint

Do not casually bolt on self-signed HTTPS and call the browser path secure.

The phone-hosted Flutter Web bundle itself is currently served over LAN HTTP, so a hostile network attacker capable of modifying that JavaScript could undermine application-layer secrets.

Before attempting end-to-end LAN confidentiality, create a design note comparing:

- trusted-LAN-only model;
- HTTPS with local certificates and certificate trust UX;
- certificate fingerprint/pinning for native clients;
- application-layer AEAD for native-to-native sync;
- limitations of browser clients receiving code over HTTP.

The product may reasonably keep the trusted-home-LAN model if the complexity of secure browser transport is disproportionate.

The important requirement is to state the boundary accurately.

---

## Phase 5 acceptance criteria

- No secrets/data logged.
- Auth failure is rate-limited.
- Request sizes are bounded.
- Credentials are generated safely.
- Host UI clearly communicates trusted-LAN assumption.
- Security documentation does not overclaim HTTPS-like confidentiality.

---

# PHASE 6 — Performance and Architecture Cleanup

## Objective

Improve measurable bottlenecks without replacing working frameworks.

---

## 6.1 Split `ExpenseStore` gradually

Potential seams:

```text
SettingsStore
SyncState
TransactionRepository
LoanRepository
ProjectRepository
AnalyticsService
PersistenceGateway
```

Keep Provider.

Do not change every screen in one commit.

---

## 6.2 Move derived financial calculations into efficient queries

Candidates:

- month spend;
- month income;
- category totals;
- project totals;
- recent transactions;
- date-range queries;
- loan totals.

Use indexed database queries instead of repeatedly scanning every transaction where profiling shows benefit.

---

## 6.3 Add pagination/windowed history

For very large histories:

- query pages or date windows;
- keep search/filter indexed where possible;
- avoid loading tens of thousands of rows merely to display the first screen.

Do not add pagination if it makes the small-data UX worse; test both.

---

## 6.4 Reduce broad UI rebuilds

Profile before changing.

Possible tools/patterns:

- `Selector`;
- smaller `Consumer` scopes;
- feature-specific notifiers;
- derived immutable view state;
- memoized/DB-backed aggregates.

Do not migrate state libraries.

---

## 6.5 Move expensive IO away from UI-critical work

Database work should use Drift's appropriate execution model.

Large:

- imports;
- exports;
- migrations;
- snapshot encoding;
- CSV generation;

should not visibly freeze the UI.

---

## 6.6 Performance benchmarks

Create repeatable datasets:

```text
1,000 transactions
5,000 transactions
20,000 transactions
50,000 transactions
```

Measure:

- cold start;
- add transaction;
- history opening;
- search;
- monthly dashboard;
- export;
- import;
- sync encode/merge;
- DB size;
- memory where practical.

Do not optimize based on guesses.

---

## Phase 6 acceptance criteria

- Large-history operations have measured before/after results.
- Normal UI behavior is unchanged.
- Provider remains unless a documented blocker exists.
- No broad refactor without tests.

---

# PHASE 7 — Integration Testing, Security Testing & Diagnostics

## Objective

Cover the failure modes that unit/widget tests cannot prove.

---

## 7.1 Add `integration_test/`

At minimum automate:

```text
launch
→ unlock if configured
→ add transaction
→ verify Home
→ verify History
→ edit
→ export/backup
```

---

## 7.2 Migration integration test

Test upgrade:

```text
old prefs fixture
→ app startup
→ migration
→ database
→ identical totals/IDs
→ restart
→ no second destructive migration
```

---

## 7.3 Sync integration tests

Where possible use real shelf/http on localhost for:

- v2 merge;
- retries;
- wrong PIN;
- malformed payload;
- request-size limit;
- tombstone flow.

---

## 7.4 On-device manual test matrix

Maintain a checklist for real Android devices:

### SMS

- permission denied;
- manual mode;
- auto mode;
- known bank sender;
- unknown sender;
- duplicate SMS;
- OTP-like non-transaction SMS.

### mDNS

- Android host + Android client;
- Windows Chrome/Edge;
- IP fallback;
- AP isolation;
- VPN enabled;
- host stop/restart.

### Notifications

- exact reminder;
- reboot;
- permission denied;
- timezone change.

### Hosting

- phone browser;
- PC browser;
- wrong PIN;
- host stopped;
- app backgrounded;
- network changed.

---

## 7.5 Local diagnostic diary

Add privacy-preserving diagnostics without an analytics vendor.

Store only the last N operational events such as:

```text
sync started
transport selected
peer version
merge result counts
backup created
migration completed
host started/stopped
error class
```

Never record:

- amounts;
- notes;
- names;
- full snapshot JSON;
- SMS bodies;
- PINs;
- QR secrets.

Allow explicit user export of diagnostics.

---

## Phase 7 acceptance criteria

- Core user path has integration coverage.
- Migration has integration coverage.
- Sync correctness has automated coverage.
- A real-device checklist exists.
- Diagnostics are useful without exposing financial content.

---

# PHASE 8 — GitHub and F-Droid Release Process

## Objective

Make every public release auditable, reproducible, and easy to maintain.

---

## 8.1 Choose an open-source license

If not already present, choose and add a real license.

Examples often used by FOSS apps include:

- GPL-3.0-or-later
- AGPL-3.0
- Apache-2.0
- MIT

The maintainer must choose based on desired redistribution/derivative terms.

Muse must not choose a license on the maintainer's behalf without instruction.

---

## 8.2 Release tagging

Every release should have:

- unique monotonically increasing version code;
- version name;
- Git commit;
- release tag;
- changelog;
- matching embedded web version.

Example:

```text
v1.4.0
```

Tag naming must stay consistent.

---

## 8.3 GitHub release assets

Recommended assets:

```text
Dhadda-<version>-universal.apk
Dhadda-<version>-arm64-v8a.apk   (optional)
SHA256SUMS
source tag / GitHub generated source archive
```

Only publish signed release APKs.

Do not publish the keystore.

---

## 8.4 F-Droid metadata

Prepare/submit the F-Droid metadata for:

- application ID;
- source URL;
- issue tracker;
- license;
- summary;
- description;
- changelog;
- build recipe;
- version detection;
- release commit;
- screenshots/icons.

F-Droid build metadata should point to exact release commits, not a moving branch.

---

## 8.5 F-Droid reproducibility

Long-term target:

```text
source tag
    ↓
clean F-Droid build
    ↓
reproducible binary
    ↓
verified relation to upstream GitHub release
```

Pay special attention to Flutter's embedded build paths and native artifacts.

---

## 8.6 FOSS dependency gate

CI should fail or warn on newly introduced dependencies until their license/source status has been reviewed.

Keep a file such as:

```text
docs/DEPENDENCIES.md
```

with important direct dependencies and licenses.

---

# 9. Recommended Priority Order

Do the work in this order:

```text
P0  Phase 0 — baseline
P0  Phase 1 — reproducible build/release foundation
P0  Phase 2 — transactional database migration
P0  Phase 4 — sync data-loss fix
P1  Phase 3 — at-rest security hardening
P1  Phase 5 — LAN hardening
P1  Phase 7 — integration/security testing
P2  Phase 6 — performance/architecture cleanup
P2  Phase 8 — F-Droid release polish/submission
```

One exception:

**Android backup exclusion from Phase 3 should be pulled forward into Phase 1** because current financial data is plaintext and backup behavior is currently implicit.

---

# 10. What Must Not Happen During the Roadmap

Muse must never:

- Rewrite the app in Kotlin.
- Replace Flutter.
- Replace Provider solely for style.
- Add Firebase/Supabase.
- Add analytics SDKs without explicit approval.
- Upload user financial data anywhere.
- Rename the application ID casually.
- Delete SharedPreferences data before migration verification.
- Break Snapshot v1 import.
- Change QR formats without versioning.
- Use a 4-digit PIN directly as an encryption key.
- Implement custom cryptographic algorithms.
- Introduce a proprietary dependency that blocks F-Droid.
- Publish a debug-signed release.
- Commit a keystore/password/token.
- Claim LAN HTTP is secure against hostile networks.
- Run a database + sync + state-management rewrite in one phase.
- Continue to the next phase after a failed test/build.
- silently "fix" user data by dropping malformed records.

---

# 11. Security Threat Model to Maintain

At minimum consider:

## Device attacker

Someone with:

- physical access;
- unlocked phone;
- rooted phone;
- extracted app storage;
- Android backup;
- exported backup.

## LAN attacker

Someone on the same Wi-Fi who can:

- scan ports;
- read traffic;
- attempt PINs;
- replay requests;
- modify traffic;
- capture QR screenshots.

## Supply-chain attacker

Risk from:

- compromised package dependency;
- compromised GitHub Action;
- unpinned build tool;
- tampered release binary;
- leaked signing key.

## Accidental failure

- crash mid-write;
- corrupt JSON;
- disk full;
- device clock incorrect;
- interrupted migration;
- two offline devices editing independently;
- stale embedded web build;
- old app version syncing with new version.

Every security feature should state which threat it actually addresses.

---

# 12. Target Storage Model

After Phase 2/3:

```text
DOMAIN DATA
    ↓
Drift / SQLite
    ↓
optional encryption layer if approved

SETTINGS
    ↓
SharedPreferences
    ↓
theme, currency, UI preferences, non-secret flags

SECRET MATERIAL
    ↓
Android Keystore-backed secure storage
    ↓
database key / key wrapping / sensitive local tokens

BACKUPS
    ↓
explicit user export
    ├── plaintext with warning
    └── encrypted format preferred for sensitive archival
```

---

# 13. Target Sync Model

Short-term:

```text
Snapshot v2
full dataset
record-level merge
tombstones
deterministic conflict handling
```

Long-term optional optimization:

```text
local change log
        ↓
changes since peer checkpoint
        ↓
merge
        ↓
acknowledgement
        ↓
safe compaction
```

Do not build delta sync until full-snapshot record merge is proven correct.

---

# 14. Target Release Model

```text
Git commit
   ↓
version + changelog
   ↓
tag
   ↓
CI
   ├── analyze
   ├── tests
   ├── integration checks
   ├── embedded-web build
   ├── reproducibility checks
   └── signed APK
   ↓
GitHub Release
   ↓
F-Droid source build / verification
```

---

# 15. Documentation Files to Maintain

By the end of the roadmap, the repository should contain useful human/AI documentation such as:

```text
README.md
LICENSE
PROJECT_CONTEXT.md
SECURITY.md
PRIVACY.md
CONTRIBUTING.md
docs/
├── ARCHITECTURE.md
├── DATA_MODEL.md
├── SYNC_PROTOCOL.md
├── BACKUP_FORMAT.md
├── RELEASE.md
├── FDROID.md
├── DEPENDENCIES.md
├── THREAT_MODEL.md
└── MIGRATIONS.md
```

Keep these concise and current rather than generating documentation nobody maintains.

---

# 16. Privacy Policy Direction

Even outside Google Play, an expense tracker should clearly state:

- Data is stored locally.
- No account is required.
- No hosted backend is required.
- SMS reading is opt-in.
- SMS parsing happens on device.
- Which data can be exposed during LAN sync.
- Exported backup files contain financial data.
- Whether diagnostics exist and what they contain.
- Whether any network calls leave the local network.
- What GitHub/F-Droid update mechanisms do.

If any future feature changes these facts, update the policy before release.

---

# 17. First Prompt to Give Muse

After uploading this roadmap and `PROJECT_CONTEXT.md`, use:

```text
Read PROJECT_CONTEXT.md and DHADDA_SECURITY_EFFICIENCY_FDROID_ROADMAP.md completely.

Treat the repository as the final source of truth.

We are NOT publishing to Google Play. Dhadda will be open-source and distributed through GitHub and F-Droid.

Do not implement the full roadmap.

Start with PHASE 0 only.

Before making any changes:
1. inspect the repository;
2. verify the Phase 0 assumptions;
3. show me the exact Phase 0 implementation/checkpoint plan;
4. identify any risk or mismatch with PROJECT_CONTEXT.md.

Then perform only Phase 0.

Run all required checks and give the phase completion report in the format defined by the roadmap.

Do not begin Phase 1 until I explicitly ask.
```

---

# 18. Prompt for Starting Any Later Phase

Use:

```text
Read PROJECT_CONTEXT.md and DHADDA_SECURITY_EFFICIENCY_FDROID_ROADMAP.md.

We have completed the previous phases.

Start PHASE <N> only.

First verify that the acceptance criteria of all prerequisite phases still hold.

Before coding:
- inspect the relevant source files;
- show the implementation plan;
- identify migration/backward-compatibility risks;
- identify tests that must exist before the change.

Then implement only this phase.

Do not perform unrelated cleanup.
Do not start the next phase automatically.

At completion:
- run flutter analyze;
- run flutter test;
- run all phase-specific checks;
- list changed files;
- report migration/security/performance impact;
- report manual verification still required.
```

---

# 19. External Technical Notes for Muse

These are planning references, not substitutes for inspecting the repo.

## F-Droid

Official F-Droid guidance currently emphasizes:

- public source;
- FOSS license;
- FOSS dependencies;
- upstream metadata;
- source-buildable releases;
- exact release commits/build metadata.

Flutter reproducible builds can require extra attention because build paths/native artifacts may become embedded.

References:

- https://f-droid.org/docs/Submitting_to_F-Droid_Quick_Start_Guide/
- https://f-droid.org/docs/Reproducible_Builds/
- https://f-droid.org/docs/Build_Metadata_Reference/
- https://f-droid.org/docs/Signing_Process/

## Drift

Drift currently supports Android and Flutter Web. Web uses SQLite through WebAssembly and may require `sqlite3.wasm`, a Drift worker, correct MIME handling, and browser-specific fallback behavior.

References:

- https://drift.simonbinder.eu/platforms/
- https://drift.simonbinder.eu/platforms/web/
- https://pub.dev/packages/drift

## Secure storage

Secure key-value storage should be considered for small cryptographic secrets, not as the main financial-record database.

Reference:

- https://pub.dev/packages/flutter_secure_storage

---

# 20. Final Definition of Success

Dhadda is ready for a stable open-source release when:

## Data integrity

- A crash does not normally threaten an entire monolithic history value.
- Existing user data migrates safely.
- Two devices adding different transactions offline converge without losing either transaction.
- Deletes do not resurrect during sync.
- Old backup files remain importable.

## Security

- Financial DB storage has an explicit at-rest security decision.
- Android automatic backup behavior is explicit.
- PIN brute-force attempts are rate-limited.
- Secret key material uses secure storage.
- Exports are clearly identified as sensitive, with encrypted export available if implemented.
- LAN security boundaries are accurately documented.
- No sensitive data appears in logs.

## Efficiency

- Adding one transaction does not rewrite the entire transaction history.
- Common dashboard/history queries use database/index support.
- Large-history performance has been measured.
- UI remains responsive during imports/exports/migrations.

## Maintainability

- Persistence and sync are separated from UI state.
- Provider remains unless a real limitation exists.
- Sync protocol is documented/versioned.
- Migration tests exist.
- Integration tests cover core flow.

## Open source / distribution

- Repository has a FOSS license.
- Dependencies pass a FOSS audit.
- Release toolchain is pinned.
- GitHub APK is release-signed.
- Embedded web bundle matches the app version automatically.
- Tags/changelogs are consistent.
- F-Droid can build the app from source or reproducibility blockers are explicitly documented.
- Release binaries have checksums and trace back to source.

---

# 21. Immediate Next Action

**Do not start with Drift or sync yet.**

Start with:

```text
PHASE 0
→ known-good baseline
→ fixtures
→ backups
→ current tests
```

Then:

```text
PHASE 1
→ deterministic build
→ safe signing
→ web-bundle automation
→ explicit Android backup policy
→ F-Droid readiness
```

Only after that should storage migration begin.

---

*End of Dhadda Security, Efficiency & F-Droid Roadmap.*
