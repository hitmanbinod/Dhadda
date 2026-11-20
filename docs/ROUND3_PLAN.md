# Round 3 plan — user accounts + local receipts

Status: PLAN (written before code, per the brief). Proceeding with implementation
under the user's explicit "complete every step at once" instruction.

## 1. Current data model — where `mode` lives

| Where | File:line | Role |
|---|---|---|
| `Txn.mode` (`cash\|bank\|card\|ewallet`) | `lib/models.dart:172,182,196,210` | Single source of truth today |
| Drift `Transactions.mode` column | `lib/data/app_db.dart:42`; generated `lib/data/app_db.g.dart:559-1079` | Persistence |
| Drift mapping | `lib/data/drift_domain_store.dart:82,95` | `Txn` ↔ row |
| Store write path | `lib/store.dart:988,1000,1022,1038,1196,1651` | `addTransaction`, `updateTransaction`, snapshot v1/v2 export |
| Snapshot v1 | `lib/models.dart:414-476` | `toJson` includes every `Txn` (with `mode`) |
| Snapshot v2 record decode | `lib/store.dart:2283` | Rebuilds `Txn.mode` from record data |
| `SyncType.known` | `lib/sync/sync_v2.dart:19-27` | Whitelist; unknown record types are skipped by old apps |
| CSV | `lib/sync/file_sync.dart:87-90` | Header `date,type,amount,category,mode,note` |
| SMS candidate mode | `lib/sync/sms_parse.dart:14,180` | `bank\|ewallet\|cash` from sender |
| SMS import writes | `lib/screens/menu_screen.dart:1076`, `lib/main.dart:214` | `mode: c.mode` |
| Add / Edit mode picker | `lib/screens/add_screen.dart:514`, `lib/widgets/entry_actions.dart:25,120,130` | Dropdown |
| History search/caption | `lib/screens/history_screen.dart:557,714-715,792` | Searches and displays `mode` |
| Other captions | `lib/screens/home_screen.dart:1534`, `lib/screens/category_entries_screen.dart:93`, `lib/widgets/event_branch_group.dart:144` | `t.mode.toUpperCase()` |
| Repeat chips | `lib/repeat_suggestions.dart:8,17,59,69,88,100,109` | Carry `mode` as a grouping field |
| Widgets data writer | `android/.../WidgetData.kt` | Reads SQLite directly; no mode usage (no impact expected) |
| Lent | `lib/screens/lent_screen.dart` | Loans have **no** mode — no change |

## 2. Proposed schema (additive, one transaction, idempotent)

- `Accounts` table (`accounts`): `id TEXT PK`, `name TEXT`, `type TEXT`, `color INTEGER NOT NULL DEFAULT 0`, `sort_order INTEGER NOT NULL DEFAULT 0`, `archived INTEGER NOT NULL DEFAULT 0`, plus v2 sync columns `rev INTEGER DEFAULT 0`, `rev_by TEXT DEFAULT ''`. No balance column.
- `Transactions.account_id TEXT NULL` — nullable so old rows stay valid. Index `idx_transactions_account (account_id)`.
- `Receipts` table (`receipts`, local-only, never synced/backed up): `id TEXT PK`, `entry_id TEXT NOT NULL`, `file_name TEXT NOT NULL`, `added_at INTEGER NOT NULL`, `width INTEGER`, `height INTEGER`. Index `idx_receipts_entry (entry_id)`.

Migration, run **once** in `onUpgrade` (schemaVersion 2 → 3) inside a single Drift transaction:
1. Before opening the upgrade, copy `dhadda.sqlite` to `dhadda.pre-round3.bak.<timestamp>` in the same app-private directory (best-effort; failure aborts the migration with the existing `DatabaseProblemScreen` path).
2. `CREATE TABLE accounts ...`, `ALTER TABLE transactions ADD COLUMN account_id TEXT`, create both indexes, `CREATE TABLE receipts ...`.
3. Insert four deterministic default accounts **only if absent**: `acct_cash / acct_bank / acct_card / acct_ewallet`, names `Cash / Bank / Card / E-wallet`, types `cash / bank / card / wallet`, `sort_order 0..3`, `rev 0`. `INSERT OR IGNORE` by id makes this idempotent.
4. `UPDATE transactions SET account_id = 'acct_' || CASE mode ... END WHERE account_id IS NULL` with the four known modes; unknown/empty modes fall back to `acct_cash`. `mode` itself is **never rewritten**.
5. Guard every step: check `sqlite_master` / `PRAGMA table_info` before creating/adding (same pattern as the v1→v2 `_ensureColumns`). Drift writes `user_version` only after `onUpgrade` returns, so an interrupted run resumes safely.

Idempotency and no-data-loss are proved by a migration test from `test/fixtures/phase0/snapshot_populated.json`: entry count, sum, category and date of every entry identical before/after; `mode` unchanged; deterministic account ids; re-running the migration adds no duplicates.

## 3. Snapshot & sync changes

- `Txn.accountId` (optional, default `''`) added to v1 JSON and v2 record `data`. Old apps ignore unknown JSON keys (verified by existing decode code — `fromJson` reads named keys only), so new payloads into old apps keep working; old payloads into new apps produce `accountId == ''` and the new app derives the account from `mode` via the deterministic map at display/merge time.
- `Account` model with `toJson/fromJson`; `Snapshot.accounts` additive list (default empty). Old apps ignore it; new apps seed the four defaults when absent.
- `SyncType.acct = 'acct'` added to the v2 whitelist. Old apps skip unknown record types (`SyncRecord.tryParse` line 69) — they neither crash nor drop the records they understand. New apps merge accounts with the same `(rev, by)` total order and tombstone rules as categories/projects.
- Deterministic ids mean two devices migrating independently converge; no duplicate-account conflict on first sync.
- Compatibility matrix (relay, direct WiFi, phone-hosted PC relay, file import, encrypted backup): v1 old↔new works via ignored unknown fields; v2 old peer skips `acct` records and `accountId` fields, new peer accepts old records and backfills accounts from modes. Encrypted backup wraps the same JSON, so behaviour matches file import exactly. Tests will cover both directions for all five transports at payload level (transport code itself is unchanged).

## 4. CSV

Keep all six existing columns and their meanings in the same order; append a seventh column `account` at the END with the active account name. Old readers still see the original six columns first. `FileSync.buildCsv` gains an optional account-name resolver so callers that do not pass one keep the old six-column output.

## 5. UI changes by file

- `lib/screens/settings_screen.dart` / `menu_screen.dart`: Money → **Accounts** row.
- New `lib/screens/accounts_screen.dart`: grouped list, drag reorder, add/edit (name, type icon, optional color), archive, merge, delete-if-unused, clear explanations, ≥48 dp targets, Semantics.
- `lib/screens/add_screen.dart` + `lib/widgets/entry_actions.dart`: mode dropdown → wrapping account chips; remembers last used; stores both `accountId` and derived `mode`.
- `lib/screens/history_screen.dart`: account filter; captions `Category · Account`.
- `lib/screens/insights_screen.dart`: "How you pay" grouped by account (fall back to mode label when no account).
- `lib/repeat_suggestions.dart`: suggestions carry `accountId` + `mode`.
- SMS mapping: rules first (unchanged), then account type from parsed mode → first active account of that type, graceful fallback to `acct_cash` / first active.
- Home/Lent/Event captions: show account name when available, else legacy mode. Widgets: no mode usage — expected no change; verified by build + tests.

## 6. Receipts

- Files in `app_flutter/receipts/<entryId>/<uuid>.jpg` (app-private, never in DB blobs, never synced/backed up). UI states this explicitly.
- Native `expense/media` MethodChannel: `takePhoto` → camera intent, `pickImages` → `ACTION_OPEN_DOCUMENT`/photo picker (max 3). Both return app-private copies; no runtime permission requested (intent-based). Manifest: `<queries>` for camera/image intents if needed; no new permission.
- Shrink in Kotlin: decode with `BitmapFactory` in-sample size to ≤1600 px long edge, re-encode JPEG q80 **without copying EXIF**, save under app-private directory; return relative file name.
- Viewer uses `InteractiveViewer` pinch-zoom + delete; paperclip marker on History rows with receipts.
- Orphan cleanup on app start, after permanent delete, after undo, and after sync removal: delete files whose `entry_id` no longer exists. Settings → Data shows "Receipts: N photos, X MB" and a double-confirm "Clear all receipts".
- Privacy: thumbnails/viewer sit behind the existing app lock (same navigator as other screens); no receipts in backups/sync.

## 7. Test plan

Migration from the old fixture (counts/sums/modes identical, deterministic accounts), migration idempotency, schema-level account CRUD (rename/archived/merge/delete-if-unused, at least one active), v1/v2 snapshot round trips with accounts, old-snapshot import, new→old and old→new compatibility payload tests for all five transports, merge/tombstone behaviour for accounts, duplicate-default prevention, CSV trailing column, SMS mapping, and receipt lifecycle + orphan cleanup (filesystem mocked/fake channel in widget tests).

## 8. Risks, rollback, open questions

- **Drift cannot downgrade.** Protection: the pre-migration safety copy, additive-only columns, `INSERT OR IGNORE` defaults, and the existing `DatabaseProblemScreen` quarantine path. Recovery is manual restore of that copy.
- Old apps that receive new v2 snapshots will not see accounts and may keep using `mode`; that is expected and data-preserving.
- Accounts are display/grouping only — no balances, no recategorisation of past entries beyond the one-time deterministic `account_id` backfill.

**Open questions for the maintainer:** (1) Should archived accounts still appear in Insights history totals? (plan: yes). (2) Is `other` allowed as an account type when the built-in keyword map finds no match? (plan: yes, `acct_cash` fallback). (3) Receipt size cap confirm 1600 px / q80. (4) Should merged accounts keep their `rev` tombstone forever? (plan: yes, standard tombstone rules).
