# Dhadda Persistence Architecture (Phase 2)

SQLite via Drift is the domain store on Android/desktop; SharedPreferences JSON
remains for small settings everywhere and for all domain data on Web. Snapshot
v1, sync semantics, and UI behavior are unchanged. Baseline record stays in
`docs/BASELINE.md`.

## 1. Layout: what lives where

| Data | Storage | Keys / location |
|---|---|---|
| transactions, categories (+order, budgets), loans (+top-ups, repayments, reminders), projects | SQLite (`dhadda.sqlite`, app documents dir) on native; prefs JSON on Web | tables below / `expense_{cats,txns,loans,projects}_v1` |
| device/link/settings/sync stamps (`expense_meta_v1`), 5 backups, SMS ids | SharedPreferences (all platforms) | unchanged keys |
| PIN hash, biometric flag | SharedPreferences (untouched) | `expense_pin_hash_v1`, `expense_biometric_v1` |
| migration state | SharedPreferences int | `expense_db_migrated_v1` = 1 when complete |
| legacy domain keys after migration | SharedPreferences (retained, stale) | original 4 keys, never deleted in Phase 2 |

## 2. Code map

- `lib/data/app_db.dart` — schema (source of truth) + `app_db.g.dart`
  (committed generated code; regenerate with
  `dart run build_runner build --delete-conflicting-outputs`).
- `lib/data/domain_store.dart` — `DomainData`, `DomainSummary` (verification
  fingerprint), the `DomainStore` interface, lenient legacy decoder.
- `lib/data/drift_domain_store.dart` — SQLite backend (transactional
  multi-writes, FK-safe ordering).
- `lib/data/prefs_domain_store.dart` — JSON backend (Web + degraded fallback).
- `lib/data/db_connection*.dart` — conditional native/stub connection: sqlite3
  bindings can never compile into the web bundle.
- `lib/data/test_env*.dart` — `isFlutterTest` gate (conditional, no dart:io on
  web): unit/widget tests always use prefs (drift's async machinery hangs in
  testWidgets' fake-async zone — verified empirically).
- `lib/store.dart` — selects backend in `load()`, runs migration, write-through
  in mutators. Still the single `ChangeNotifier`; no decomposition (later phase).

## 3. Schema (version 1) and field mapping

| Table | Columns (PK / FK / index) | Maps from |
|---|---|---|
| `categories` | `id` PK, `name`, `icon`, `color`, `budget` REAL, `sortOrder` (+) | Category + list position |
| `transactions` | `id` PK, `type`, `amount` REAL, `categoryId` → categories, `date`, `note`, `mode`, `projectId`; indexes `idx_transactions_date/category/project` | Txn 1:1 |
| `projects` | `id` PK, `name`, `note`, `created`, `icon`, `color` | Project 1:1 |
| `loans` | `id` PK, `person`, `kind`, `principal` ← `lent`, `dateLent`, `dueDate`?, `note`, `remindAt` | Loan 1:1 |
| `loan_topups` | `id` PK, `loanId` → loans CASCADE, `amount`, `date`, `note` | Topup + parent id |
| `loan_repayments` | same shape as topups | Repayment + parent id |

Money stays `double` (SQLite REAL round-trips bit-exact — proven by test;
integer minor units deferred: zero migration risk, Snapshot v1 untouched).
No tombstones/revisions (Phase 4). No encryption (Phase 3).

## 4. Migration algorithm (`ExpenseStore.load` + `_migrateLegacyToDb`)

States: **fresh** (no legacy keys, no marker) → seed in memory, migrate seeds;
**legacy** (keys, no marker) → legacy-load, migrate; **failed** (marker unset
after an attempt) → prefs fallback this launch, retry next; **done**
(marker = 1) → load from DB. Detection uses only the marker + backend type,
never "file exists" or row counts.

1. Read meta/settings (unchanged).
2. Pick backend: injected override (tests) ?? native SQLite (fails → prefs
   fallback, retry later) ?? prefs (always on Web).
3. Non-prefs backend + marker ≠ 1: legacy-load (seeds + fuel upgrade, today's
   exact behavior), then `replaceAll` in ONE drift transaction.
4. Verify by `DomainSummary` (counts + exact double sums + pendings + ID
   orders); mismatch throws → fallback, no marker.
5. Marker = 1 only after verification. Legacy keys never deleted.

`eraseAll` self-heals: `prefs.clear()` wipes the marker, so the next `load()`
re-seeds and re-migrates fresh state over the old rows.

## 5. Snapshot v1 compatibility

Export builds from in-memory lists (unchanged code); import assigns lists then
`replaceAll` into the backend (now `async` — 7 call sites updated with `await`).
Same bytes in/out, same newer-wins rule, same backups. No v2, no merge.

## 6. Web strategy

One interface, two backends: Web resolves the stub connection and always gets
`PrefsDomainStore` (identical JSON behavior to Phase 0/1, including legacy
keys). Drift-Web/WASM was evaluated and rejected for Phase 2: it needs
`sqlite3.wasm` + worker + MIME/hosting care for zero user gain while the domain
fits prefs semantics on browser. Revisit only with measured need. No cloud.

## 7. Recovery procedure (read carefully: two different cases)

### A. Initial-migration recovery (safe)

While investigating a FIRST migration problem — marker unset, or just set
with no meaningful post-migration writes yet — the legacy keys still equal
(or nearly equal) the database content. Safe steps: delete
`expense_db_migrated_v1` and restart to re-run migration from the intact
legacy keys; or delete `dhadda.sqlite` + marker for a fully clean
re-migration. No user data is at risk beyond the failed attempt itself,
because nothing newer exists anywhere else yet.

### B. Later rollback (UNSAFE via legacy keys — do not do this)

After the SQLite-backed version is in normal use, the preserved legacy keys
are a STALE snapshot of migration day. Deleting the marker then does NOT
"roll back" — it re-migrates the OLD data and silently discards every
transaction, loan change, and setting created since. Never recommend this.

The primary human recovery mechanism after normal use is the
user-controlled **Snapshot v1 export**: export before risky operations,
import (`force`) to restore. The 5 rolling auto-backups inside the app are
the second line. Legacy keys exist only as migration source + forensic
evidence, never as a restore path.

## 8. Write-failure semantics (persist-or-revert)

Every domain mutator snapshots memory before changing it and reverts on a
database failure: lists restored, `updatedAt` stamp restored (and re-saved so
prefs meta matches), `lastPersistError` set, listeners notified. The UI can
never show phantom-saved state. Import additionally refuses through its
message channel (`Could not save the import. Nothing was changed.`) instead
of claiming success. Corrupt/unwritable legacy input refuses migration the
same way the database refuses bad writes: no marker, bytes kept, retry later.

## 9. Known limitations / future cleanup

- Real user data: validate only on emulator/copies/test installs, never the
  primary phone; keep real exports outside Git.
- Write failures revert memory (lists + stamp), record `lastPersistError`,
  and — for imports — report through the message channel. Per-tap mutators
  keep their signatures; a future phase may add visible error surfaces.
- Legacy domain keys go stale on native after migration (retained deliberately;
  cleanup is a later-release decision after stability is proven).
- No per-record sync metadata yet (Phase 4); no encryption (Phase 3); store
  still notifies broadly (later performance work).
- sqlite3 v3 ships its own native libs via build hooks (no separate libs
  package); F-Droid native-binary provenance to be confirmed at submission.
