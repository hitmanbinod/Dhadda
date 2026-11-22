# SYNC_PROTOCOL.md — Dhadda cloud vault sync (v1)

Both sides (Flutter/Android and web-v2) implement this document exactly.
`sync/test-vectors.json` contains the shared conformance scenarios.

## 1. Scope

Synced tables (table names are the wire `t` values):

| `t` | Android table | Primary key |
|---|---|---|
| `categories` | `categories` | UUID string |
| `accounts` | `accounts` | UUID string |
| `entries` | `transactions` | UUID string |
| `events` | `projects` | UUID string |
| `people` | `loans` | UUID string |
| `lent_txns` | `loan_topups` ∪ `loan_repayments` | UUID string, `kind` field = `topup`/`repayment` |
| `settings` | `expense_meta_v1` (selected keys only) | key name as `id` |

Settings rows: `userName`, `currency`, `calendarSystem`, `homeLayout`,
`fiscalYearStart`. All other preferences stay per-device.

Not synced: receipts, SMS, reminders, theme/accent, PIN/biometric, widget
settings, deviceId, link state, derived totals/balances.

## 2. Record envelope (plaintext inside ciphertext)

```json
{
  "id": "<uuid string>",
  "t": "<table name>",
  "data": {
    "...all fields of the record...": "...",
    "updated_at": 1732200000123,
    "deleted": 0
  }
}
```

- Foreign keys are always UUID strings referencing another synced record
  (`categoryId`, `projectId`, `loanId`, `accountId`).
- Amounts are **integer minor units** (paisa): `minor = Math.round(amount * 100)`.
- Dates: `date` = canonical AD `YYYY-MM-DD`; `date_ms` = epoch ms UTC.
  BS is display-only and never sent.
- `updated_at` (`ua`) is epoch ms, `deleted` (`d`) is `0` or `1`.
- Settings rows carry `data = {"value": <json value>, ...}`.
- Derived fields (totals, pending, percentages) are never stored or sent.

## 3. Wire row (stored by the server)

```json
{"t":"entries","id":"uuid","ua":1732200000123,"d":0,
 "device_id":"dev-...","iv":"<base64 12 bytes>","ct":"<base64 AES-GCM ciphertext>","seq":42}
```

`device_id` is sent only for tie-breaking and is not decrypted. The server
never sees the data key. Plaintext metadata: `t`, `id`, `ua`, `d`, `iv`, `ct`.

## 4. Encryption

- One random 256-bit data key per vault, generated on the phone.
- AES-256-GCM, **fresh random 12-byte IV for every row**, no AAD.
- Key stored in app-private, platform-protected storage on Android, and as a
  non-extractable `CryptoKey` in IndexedDB on web.
- Key is never sent to the server. The pairing link carries it in the URL
  fragment (`#...&k=<base64url>`), which browsers do not send in requests.

## 5. Conflict resolution

1. For the same `(t, id)`: higher `ua` wins.
2. Tie on `ua`: lexicographically larger `device_id` string wins.
3. A tombstone (`d=1`) is just a row; rules 1-2 apply. A newer update beats an
   older tombstone; a newer tombstone beats an older update.
4. Settings rows are keyed by setting name and follow the same rules.
5. Push is idempotent: re-pushing an identical `(t,id,ua,d,device_id)` row is a
   no-op; the server returns the same `seq` it already assigned.
6. Hybrid clock: `ua = max(clockNowMs, lastSeenUa + 1)`; `lastSeenUa` is the
   maximum `ua` observed from the server. On pull, any row with
   `ua > clockNowMs + 86400000` is clamped to that bound, logged as a clock
   skew event, and then merged with the normal rules — never discarded.
7. Server tombstone retention: 180 days. Local tombstones are kept longer
   (Android keeps them indefinitely today) — this is safe.

## 6. Dependency order on apply

Apply pulled rows in this order within a batch:

1. `categories`, `events`, `people`, `settings`
2. `entries`, `lent_txns`, `accounts`

A row whose referenced UUID is missing is **parked** in a `pending` map keyed
by `(t,id)` and retried after the next pull. It is never dropped and never
crashes the apply. After two consecutive pulls with no progress, log a warning
with the missing parent ids (no data contents).

## 7. Cursor and batching

- The server assigns a strictly increasing integer `seq` to every accepted row.
- `GET /v1/pull?since=<seq>&limit<=500` returns rows with `seq > since`, ordered
  by `seq` ascending: `{rows, next:<last seq>, more:<bool>}`.
- Clients persist `last_seq` atomically with the applied rows.
- Push accepts ≤ 500 rows and ≤ 512 KB body. Responses may include
  `rejected_older` rows (the server's newest version) for LWW losers.

## 8. Initial sync and offline rules

- A new phone vault: push all local rows with `ua` = current clock.
- A new browser: pull from `since=0` until `more=false`, showing progress
  ("Syncing X of Y" where Y is the server's reported row count).
- Never delete local data because the server is empty or unreachable.
- Each side keeps an outbox of local changes; push retries with exponential
  backoff while offline, capped at 5 min.
- Status words on both sides: `Not connected` · `Connecting` · `Syncing…` ·
  `Synced just now` / `Synced 2 min ago` · `Offline, N changes waiting` ·
  `Sync error (tap for details)`.

## 9. Server API (`sync-server/`)

All JSON over HTTPS. `Authorization: Bearer <token>` on every route except
vault creation. Token stored server-side as SHA-256 and compared in constant
time; returned once at creation or rotation.

| Method | Path | Body / query | Response |
|---|---|---|---|
| POST | `/v1/vault` | `{}` | `{vault_id, token}` |
| POST | `/v1/push` | `{device_id, rows:[≤500]}` | `{accepted, rejected_older, server_seq}` |
| GET | `/v1/pull` | `since=<seq>&limit≤500` | `{rows, next, more, total}` |
| POST | `/v1/rotate` | `{}` | `{vault_id, token}` (old token dead) |
| DELETE | `/v1/vault` | `{}` | `{deleted:true}` |

Hardening: body ≤ 512 KB, ≤ 500 rows/push, per-vault rate limit, CORS only for
the Pages origin, no request-body logging, schema in `sync-server/schema.sql`,
`wrangler.toml` contains no secrets.

## 10. Pairing

Phone → Settings → Web access → Create link:
POST `/v1/vault`, generate key, build
`https://<pages>/#v=<vault_id>&t=<token>&k=<base64url key>`, show Copy/Share
(and QR only if the encoder fits the size budget), with the warning
"Anyone with this link can read your data. Do not post it."

Browser: read the fragment (never sent to server), import key as
non-extractable WebCrypto key, store credentials + key in IndexedDB, strip the
fragment with `history.replaceState`, then run first pull with progress.
If old localStorage data exists, back it up to IndexedDB `dhadda-prebackup`,
offer Download backup, and do not upload it silently.

## 11. Conformance

`sync/test-vectors.json` is the single source of test scenarios for both sides.
Scenario ids are stable; implementations must produce the documented `expect`
values. Phase 7 runs web `node --test`, Android unit tests, and a two-device
simulation against `wrangler dev`.
