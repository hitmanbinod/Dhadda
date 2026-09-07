# Dhadda Snapshot v2 — Record-Level Sync (Phase 4)

Replaces whole-snapshot last-write-wins on every network path with
deterministic record-level merge. File export/import stays Snapshot v1.
Baseline record stays in `docs/BASELINE.md`.

## 1. The v1 weakness (what this fixes)

V1 compared device wall clocks (`updatedAt`) and replaced all four
collections with the "newer" snapshot (`store.dart` legacy path). Two devices
editing offline lost each other's records; equal timestamps diverged
silently. See `PROJECT_CONTEXT.md` §"Sync Conflict Analysis".

## 2. Snapshot v2 format

```json
{
  "format": 2,
  "deviceId": "<random uuid, already shared in v1>",
  "deviceName": "<display name>",
  "exportedAt": "<wall-clock ISO, informational only>",
  "records": [
    {"t": "txn|cat|proj|loan|topup|repay", "id": "...",
     "rev": 7, "by": "<deviceId>",
     "dead": true,                       // tombstones only
     "parent": "<loan id>",               // topup/repay only
     "d": {<v1-shaped content>}}
  ]
}
```

- Record content reuses v1 `toJson` shapes (no duplicated field definitions):
  categories additionally carry `sortOrder` (list position is merged state);
  loans carry scalar fields only (children are independent records).
- Detection: `format == 2` → v2; `version == 1`/snapshot-shaped → v1;
  anything else → malformed (existing friendly-error paths).
- Unknown record types, malformed entries, and unknown top-level fields are
  skipped/ignored (forward compatibility), counted, never adopted.

## 3. Record metadata (every field earns its place)

| Field | Purpose |
|---|---|
| `id` | stable identity across devices (existing uuids, preserved) |
| `rev` | per-record logical counter: 0 = unknown history (migrated/v1-ingested), +1 per local edit. No wall clock → immune to skew |
| `by` | authoring `deviceId` (existing random id, already shared; no hardware IDs). Tie-break only |
| `dead` | tombstone marker (separate from content so deletions converge) |
| `parent` | loan ownership for topup/repay (orphans are meaningless → dropped) |
| content hash | implicit final tie-break (larger canonical JSON wins; unreachable when writers bump correctly) |

## 4. Revision algorithm

- New record: rev 1 (recreation over a tombstone: tomb.rev + 1, tomb dropped).
- Local edit (content, budget, reminder, moved-txn, reorder position):
  rev = current + 1, `by` = local deviceId, persisted atomically with the row
  on native (same SQL statement) or alongside it on prefs/Web.
- Merge picks the max of a total order per `(type, id)`: higher rev wins;
  rev tie → lexicographically SMALLER `by` wins (arbitrary, fixed);
  full tie → deletion wins; identical live versions with divergent content →
  larger JSON wins (defensive).
- Same-record concurrent edits therefore converge deterministically
  (documented record-level LWW — the losing edit is outvoted, never merged
  field-by-field; no conflict UI in Phase 4).

## 5. Device identity

Reused: the existing random per-install `deviceId` (uuid v4, persisted in
`expense_meta_v1`, already sent in every v1 snapshot). No new identifier, no
hardware/account/advertising IDs. Reinstall = new identity (documented);
existing revs keep working (ordering only needs stable strings, not continuity).

## 6. Tombstones

- Created on every delete at `oldRev + 1`, saved before the row delete
  (crash in either order converges correctly).
- Live in `tombstones` table (native) / `expense_sync_tombs_v1` (prefs/Web),
  loaded at startup, survive restart/reload/sync.
- Never garbage-collected in Phase 4 (deferred: safe cleanup needs proof
  every peer has seen the deletion).
- Tombstone for category `other` is refused (pre-v2 UI invariant); a missing
  `other` after merge is re-seeded (rev 0) rather than running broken.

## 7. Merge rules (implemented in `lib/sync/sync_v2.dart`, pure function)

1. Record on one side only → taken. Tombstone on one side only → kept.
2. Same rev/by/content → no change (idempotence observable as "Already in sync").
3. Higher rev wins, either direction.
4. Rev tie → smaller `by` wins, either direction → same result.
5. Delete (higher rev) beats live; live (higher rev) beats tomb.
6. Exact rev+by tie live-vs-dead → deletion wins.
7. Equal rev+by divergent content → larger JSON wins (both directions agree).
8. Malformed/unknown-type entries → skipped + counted.
9. Unknown future envelope fields → ignored.
10. Duplicate IDs in one payload → max wins, extras counted.
11. No categories table entry survives without `other` (reseeded if missing).
12. Txn with unknown category → remapped to `other` (current display fallback).
13. Child with missing loan → dropped + counted (meaningless without parent).
14. Txn with unknown project → untagged (current delete-project behavior).
15. Category order = sort by `(sortOrder, id)`, `other` forced last.

Commutativity, associativity, and idempotence hold by construction (per-id
max over a total order + deterministic post-pass) and are proven by seeded
fuzz tests, not just asserted.

## 8. Convergence guarantees (v2 ↔ v2 scope; see §11 tiers for the rest)

- `merge(A,B) == merge(B,A)` (canonical-encoding tested, incl. fuzz).
- `merge(merge(A,B),C) == merge(A,merge(B,C))` (fuzz-tested triples).
- `merge(A,A) == A` and re-merging a converged peer reports no change, so a
  second sync round is always quiet (tested at engine and store level).
- 3-device A→B→C→A converges (tested with independent offline adds).

## 9. Conflict behavior (honest limits)

- Different records: always unioned — the headline data-loss class is gone.
- Same record, both edited: deterministic winner (rule §4); the loser is
  outvoted, visibly (counts in the sync message), but not preserved anywhere.
  No conflict UI exists; add one only if real-world need appears.
- Cross-version (v1 peer): v1 content enters as rev-0 records on the v2
  side; the v1 side keeps last-write-wins, so guarantees there are reduced
  (see §11 tiers).

## 10. Clock-skew behavior

No timestamp participates in any decision — tested with skewed `exportedAt`
and interleaved revs. `updatedAt` is still stamped after adopting changes so
v1 peers observe us as newer (compat visibility) and messages stay familiar.

## 11. v1 compatibility matrix

Guarantee tiers (do not overclaim beyond these):

- v2 ↔ v2: full record-level convergence guarantees
- v2 ↔ v1: backward-compatible, but guarantees are reduced on the legacy side
- v1 ↔ v1: original Snapshot v1 last-write-wins behavior remains

| Direction | Behavior |
|---|---|
| v1 file/backup → v2 app | Whole-replace (unchanged UX) + re-key: existing revs kept, new ids rev 0; force drops all tombstones; file drops tombstones for present ids; ambient keeps them (suppressed ids filtered from lists) |
| v2 app → v1 file | Export stays v1 (human format stable; existing fixtures/backups valid) |
| v1 network peer → v2 app | Content ingested as rev-0 records and merged on the v2 side; the v1 side keeps its own last-write-wins behavior, so guarantees there are reduced |
| v2 app → v1 network peer | v1 encoding served/sent (peer applies its legacy rules; reduced guarantees on that side) |
| v1-only relay in the middle | Drops `snapshotV2`; v2 sides fall back to v1-ingest merge while v1 sides keep last-write-wins (reduced guarantees wherever v1 decides) |
| Dead offer/answer flow | Frozen v1-only, no UI callers (documented, untouched) |

## 12. Protocol / QR impact

- QR/link outer formats UNCHANGED (`EXPENSESYNC::`, `EXPENSESYNC2::`, plain URL).
- Link slots gain optional `snapshotV2` (omitted when empty → old relays see
  byte-identical payloads; Node relay + phone host pass it through).
- Direct WiFi gains `GET /snapshot-v2` (404 = v1-only sender → fallback);
  v2 POSTs go only to senders that served v2 (old senders would misread v2
  through whole-replace import — never sent there by construction).
- No encryption/replay/rate-limit changes (Phase 5 territory, untouched).

## 13. Persistence changes

- Drift schema 1 → 2: `rev`/`rev_by` (NOT NULL DEFAULT) on all 6 domain
  tables + `tombstones(type, id, rev, rev_by)`; upgrade tested from a
  hand-built v1 database (data + budgets preserved, defaults applied).
- Web/prefs: `expense_sync_revs_v1`, `expense_sync_tombs_v1`,
  `expense_sync_v2_v1` marker. Existing Phase-2 rows init to rev 0 via column
  defaults — zero bulk writes, marker-gated, idempotent.
- Merge application is atomic (`applyV2`: 7 tables, one transaction) with
  Phase-2 revert discipline extended to rev/tomb maps; failures report
  through message channels, never phantom state.

## 14. Limitations / non-goals (Phase 4)

- No tombstone GC; no delta sync (full snapshots still travel); no conflict
  UI; same-record concurrent edits lose deterministically (see §9).
- Per-tap mutator failures revert visibly (entry disappears) with
  `lastPersistError` recorded; import/merge failures report via message.
- Real-device multi-device runs not yet performed (emulator procedure below).

## 15. Manual multi-device procedure (emulator + spare, synthetic data)

1. Fresh-install the Phase-4 build on A and B (separate devices/emulators).
2. Disconnect both from WiFi. On A: add txn A1, edit seeded txn X, delete
   seeded txn D. On B: add txn B1, edit the same X differently, add a loan
   repayment, leave D unchanged.
3. Reconnect (same WiFi, no VPN). Pair via link QR (or direct WiFi).
4. Verify: A1 and B1 on both; X converged identically on both (documented
   tie-break); D deleted on both; repayment present on both.
5. Sync again both directions: expect "Already in sync." / "Up to date."
   with zero logical changes.
