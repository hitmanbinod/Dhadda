# SYNC_PLAN.md — Phase 0 recon and plan (Prompt 2)

Branch `sync`, created from `web-v2`. Phase 0 only — no sync or Android code has
been changed. Stopping for the maintainer's `go` before Phase 1.

## 0. Decision needed before Phase 1

The brief says "use the HTTP client and background-work library the project
already has". The project has `http ^1.2.2` but **no WorkManager, no background
work library**. The only existing background scheduling is one-shot OS alarms
via `flutter_local_notifications ^22.3.0` + `timezone` in
`lib/sync/reminders.dart` (exact alarms with inexact fallback).

Recommended adaptation (no new Android dependency):
- schedule a **one-shot, network-constrained sync check** with the same
  notification/alarm pattern already used for loan reminders;
- debounce UI changes 5 s, push on foreground and on that scheduled check;
- no wake locks, no polling loop;
- Android size growth stays near zero (no new native code).

Approval needed: reuse the alarm pattern, or add `workmanager` (a new dependency
that would break the "no new dependency" intent). Please say which in your `go`.

## 1. Existing sync and web hosting (what actually exists today)

**Existing sync is substantial and working — it is LAN/relay based, not cloud.**

| Mechanism | File | What it does |
|---|---|---|
| Link mailbox relay | `lib/sync/link_sync.dart`, `link_store.dart`, `relay_client.dart` | Auto-syncs whole snapshots between devices via a PIN-gated mailbox on a LAN relay (Node `server/serve-expense.cjs` or the phone host). Polls ~3 s on change, 15 s idle, on resume. |
| Direct WiFi | `wifi_host_io.dart`, `wifi_client.dart` | Short-lived `shelf` server on the phone, `/snapshot` + `/snapshot-v2`, 6-digit PIN. |
| File export/import | `file_sync.dart` | Manual plaintext/encrypted JSON files, CSV export. |
| Snapshot v2 | `lib/sync/sync_v2.dart` | Per-record `(rev, by)` logical revisions + tombstones, deterministic LWW merge. **No wall-clock LWW** — better than the brief's `ua` tie-break for clock skew. |
| Sync icon | `lib/main.dart:361-364` | Pushes `SyncScreen(engine: _link)` — the LAN relay hub. |
| Web sidebar status | `web-v2/app.js` `shell()` | Hard-coded `Not connected` dot + text; the Sync icon shows a toast "Sync is a later task". |

**Verdict:** reuse the *concepts and stable UUIDs* (Snapshot v2's per-record
revision, tombstones, existing record IDs and category/event/account tables),
but **do not reuse the transport**: it is plaintext JSON over HTTP on a LAN,
PIN-in-body, whole-snapshot, and has no E2EE, no stable public URL, no offline
queue on the web. The new design is a per-row E2EE cloud channel. The existing
LAN sync stays intact and untouched, so nothing already working regresses.

**Web serving today:**
- Phone-hosted: `lib/sync/phone_host_io.dart:357` tries port **8080**, then a
  random fallback; serves `assets/webapp/` (SPA fallback, `no-cache`).
- PC relay: `node server/serve-expense.cjs build/web 8080`.
- Flutter dev: `flutter run -d edge --web-hostname 127.0.0.1 --web-port 8080`.
- web-v2 prototype: `python -m http.server 8099 --directory web-v2`.

**Are web files bundled in the APK?** Yes. `pubspec.yaml` declares
`assets/webapp/` (43.8 MB / 45 files); the release APK is 98,768,577 bytes and
contains that bundle. web-v2 is **not** bundled. Packaging/hosting stays as-is
in Phase 0.

## 2. Android data model (source: `lib/data/app_db.dart`, Drift + SQLite)

| Table | PK | Columns (abridged) | Notes |
|---|---|---|---|
| `accounts` | text `id` | name, type, color int, sortOrder, archived int, rev, revBy | no balance stored |
| `receipts` | text `id` | entryId, fileName, addedAt, width, height | **never synced** (file paths) |
| `categories` | text `id` | name, icon int, color int, budget **real**, sortOrder, rev, revBy | `other` protected/last |
| `transactions` | text `id` | type, amount **real**, `categoryId` FK→categories, accountId nullable, `date` **integer epoch ms**, note, mode, `projectId` (string, no FK), rev, revBy | indexes on date/category/project/account |
| `projects` (events) | text `id` | name, note, created int, icon, color, rev, revBy | |
| `loans` | text `id` | person, kind, principal **real**, dateLent int, dueDate nullable int, note, remindAt int, rev, revBy | |
| `loan_topups` | text `id` | loanId FK→loans `ON DELETE CASCADE`, amount real, date int, note, rev, revBy | |
| `loan_repayments` | same shape as topups | loanId FK cascade | |
| `tombstones` | (`type`,`recordId`) | rev, revBy | never GC'd today; cloud copy can keep 180 days |

- All domain IDs are already UUID strings — no integer-id back-fill is needed.
- Amounts are **REAL (double)**; the sync envelope converts to integer minor
  units (paisa) with `round(amount*100)`, and back on apply. Existing doubles
  stay untouched in the DB (additive columns only).
- Dates are integer epoch ms UTC; the wire uses canonical AD `YYYY-MM-DD` plus
  `date_ms`. BS is display-only (`app_dates.dart`, `calendar/bs_*`).
- Deletes are hard deletes plus a tombstone row written by the repository
  (`DriftDomainStore.delete*`), not SQL triggers today.
- Settings live in SharedPreferences JSON `expense_meta_v1` (`lib/store.dart:33`):
  currency, themeMode, accent, materialYou, userName, hideBalance,
  one_handed_mode/choice, calendarSystem, home_layout_v1, smsMode,
  deviceId/deviceName, link/session fields, updatedAt, lastSynced, backups.
  **There is no fiscal-year-start setting** — fiscal year is computed. The
  proposed setting would be new and additive (default = calendar's rule).

## 3. Web data layer (web-v2, Prompt 1)

`web-v2/app.js`: `localStorage` with the same Android-compatible keys
`expense_cats_v1`, `expense_txns_v1`, `expense_loans_v1`,
`expense_projects_v1`, `expense_meta_v1`. Demo mode (`?demo=1`) loads
`demo-data.js` into memory and never touches storage. Record shapes mirror
`models.dart` but amounts are plain JS numbers and dates epoch ms. There is no
outbox, no crypto, no IndexedDB, and no server calls. Prompt 2 must:
- back up the old localStorage JSON to IndexedDB `dhadda-prebackup`, offer
  Download backup, then switch reads/writes to the vault IndexedDB store;
- keep `web-v2/` screens unchanged (Presentation interface intact).

## 4. Baselines (measured today)

| Metric | Value |
|---|---|
| Release APK | **98,768,577 bytes** (`flutter build apk --release`, 2026-11-22) |
| Android diff `web-parity..sync -- android` | empty at Phase 0 |
| web JS+CSS gzip (production) | **16,514 bytes** |
| web JS+CSS gzip (with demo data) | 17,949 bytes |
| New Android dependencies | none at Phase 0 |
| Embedded legacy web bundle | 43.8 MB / 45 files (APK unchanged by web-v2) |

Budget: APK growth ≤ 150 KB after Phase 7; web ≤ 60 KB gzip.

## 5. Hosting facts (official docs, fetched 2026-11-22)

Cloudflare **Pages Free**: 500 builds/month, 1 concurrent build, 20 min build
timeout, 20,000 files, 25 MiB per asset, 100 `_headers` rules, 100 projects,
`*.pages.dev` stable URL. Pages function requests count toward Workers quota.

Cloudflare **Workers Free**: **100,000 requests/day**, **10 ms CPU/request**,
128 MB memory, 50 subrequests/request, 100 Workers/account. Our endpoints are
tiny JSON + one D1 query each; one user at ~2,000 sync requests/day (pull every
30 s while visible ≈ 2,880/day worst case) fits, but a 30 s browser poll at
100% duty is borderline — see risks/mitigations.

Cloudflare **D1 Free**: 10 databases/account, **500 MB per DB**, 5 GB total,
50 queries per Worker invocation, 2 MB max row, 7-day Time Travel. Ciphertext
rows of ~1 KB × 50k entries ≈ 50 MB — comfortable.

All three fit one user on free tiers. Sources:
`https://developers.cloudflare.com/workers/platform/limits/`,
`https://developers.cloudflare.com/d1/platform/limits/`,
`https://developers.cloudflare.com/pages/platform/limits/`.

## 6. Plan (adapted architecture)

Static PWA on Pages + one Worker + one D1. One vault, one bearer token,
one 256-bit AES-GCM data key generated on the phone and never sent to the
server. Server rows are `{t,id,ua,d,iv,ct,seq}` only. Android keeps its SQLite
DB and adds an outbox via repository hooks (SQLite triggers are possible but
the DB layer is Drift with repository-level delete helpers; hooks are the
lower-risk, testable choice — triggers would not fire for Drift's high-level
API consistently). The web keeps IndexedDB rows + outbox.

**Synced entities:** categories, accounts, transactions(entries), projects
(events), loans(lent people), loan_topups, loan_repayments.
**Synced settings (one row per key):** userName, currency, calendarSystem
(AD/BS), homeLayout (section order/visibility), fiscalYearStart (new, additive,
default from calendar rules).
**Per-device, never synced:** themeMode, accent, materialYou, hideBalance,
one_handed_mode, smsMode/senders, PIN/biometric, widget/notification settings,
deviceId, link/session state.
**Derived, never synced:** balances, totals, loan outstanding, budgets spent.
**Out of scope:** receipt photos/metadata, SMS, reminder scheduling.

**Android files expected to change (Phase 5):**
- `lib/data/app_db.dart` — additive `sync_outbox` + settings mirror tables,
  schema version bump (migration copies DB to `dhadda.db.pre-sync.bak` first);
- `lib/data/drift_domain_store.dart` — repository hooks writing outbox rows,
  `sync_applying` guard, apply-pulled-rows method;
- `lib/sync/cloud_sync_client.dart` (new) — http + AES-GCM via `cryptography`
  (already a dependency), token/key storage via platform Keystore-equivalent
  built-ins (Android Keystore through existing `security.dart` patterns);
- `lib/screens/web_access_screen.dart` (new) + `lib/screens/menu_screen.dart`
  (one entry) + `lib/main.dart` (alarm/schedule hook);
- `AGENTS.md` at Phase 8 with the new sync contract.

No Gradle/manifest/signing/applicationId changes. No new dependencies.

**Web files:** `web-v2/` store/crypto/sync modules + status line + pairing
screens; `webapp/` PWA shell, manifest, service worker, `_headers`;
`sync-server/` Worker + `schema.sql` + `wrangler.toml`; `sync/test-vectors.json`;
`scripts/deploy-web`, `scripts/deploy-sync`, `scripts/sync-simulate`.

## 7. Steps only the maintainer can do (exact commands)

1. Create a free Cloudflare account (https://dash.cloudflare.com/sign-up).
2. `npx wrangler login`
3. Choose unique names (record them in `PROJECT_GUIDE.md` at Phase 8):
   - Pages project: `dhadda-web` → URL `https://dhadda-web.pages.dev`
   - Worker: `dhadda-sync` → URL `https://dhadda-sync.<your-subdomain>.workers.dev`
   - D1 database: `dhadda-vault`
4. One-time D1 create: `npx wrangler d1 create dhadda-vault` (paste the returned
   `database_id` into `sync-server/wrangler.toml` — it is not a secret).
5. Apply schema locally/remote:
   `npx wrangler d1 execute dhadda-vault --local --file=sync-server/schema.sql`
   `npx wrangler d1 execute dhadda-vault --remote --file=sync-server/schema.sql`
6. Deploy worker: `npm run deploy:sync` (or `bash scripts/deploy-sync`).
7. Deploy web: `npm run deploy:web` (or `bash scripts/deploy-web`).
8. On the phone: Settings → Web access → Create link → open it once in the
   browser. Run `design/ON_DEVICE_CHECKLIST.md`.

Nothing above will be run by me: no deploy, no login, no device install.

## 8. Risks / mitigations

- **Link = access.** Anyone with the URL can decrypt. Mitigate: 256-bit key in
  fragment, warning text, rotate/revoke, no logging.
- **30 s web delay + 100k/day Worker cap.** Mitigate: push 2 s after local
  change; pull on load/focus/30 s while visible; stop polling when hidden;
  conditional requests via `seq` and short caching where safe.
- **Clock skew.** Keep Snapshot v2's `(rev, by)` logical ordering *inside* the
  envelope, and use `ua = max(now, lastSeenUa+1)` with 24 h future clamp on the
  wire as specified. Both must agree — this is the main protocol risk.
- **Additive migration safety.** Copy DB before migrating; test on a copy of a
  realistic DB; never clear/reseed; keep existing queries working.
- **No background-work library** (see §0) — decision needed.
- **Fiscal-year start** does not exist on Android — additive default needed.
- **D1 single-threaded** — fine for one user; batch up to 500 rows/push.
- **Tombstone retention 180 days** vs Android's current "never GC" — keep local
  tombstones, allow server GC only after 180 days; a resurrected old client is
  an accepted edge case.

## 9. Phase order (after `go`)

1 protocol doc + test vectors · 2 sync-server + `wrangler dev` · 3 web store/
crypto/engine/status · 4 web pairing + first-run · 5 Android migration/client/
Web access screen · 6 PWA/headers/deploy scripts · 7 tests/simulation/size
measurements · 8 docs + AGENTS.md sync contract. Commit after each; never
merge or push.
