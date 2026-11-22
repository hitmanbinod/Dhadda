# Prompt 2 final report — cloud sync and web access

## 1. Branch and commits

Branch `sync` from `web-v2`. Nothing merged, nothing pushed.

| Commit | Phase |
|---|---|
| `8f9f44e` | 0 recon + SYNC_PLAN (stopped for `go`) |
| `82ae82c` | 1 protocol doc + 10 shared test vectors |
| `e0a2e70` | 2 Cloudflare Worker + D1 schema, local `wrangler dev` verified |
| `d0125e1` | 3-4 web IndexedDB store, WebCrypto, engine, status, pairing |
| `30fb336` | 5 Android sync client, Web access screen, additive store merge |
| final | 6-8 PWA/headers/deploy scripts, tests/simulation/size, docs |

## 2. Reused vs replaced

Reused the existing UUID record ids, Drift/SQLite domain model, `http` package,
`cryptography` (already a direct dependency) and the existing alarm pattern
concept. Replaced the **transport**: the LAN snapshot relay stays intact and
untouched; the new cloud channel is per-row AES-256-GCM ciphertext through one
Worker + D1. No existing sync code was deleted or rewritten.

## 3. Sizes and dependencies

| Metric | Before | After |
|---|---:|---:|
| Release APK | 98,768,577 B | 98,981,785 B (**+213,208 B**) |
| Web JS+CSS gzip | 16,514 B | 24,028 B (budget 60 KB — OK) |
| New Android dependencies | — | **none** |

APK growth is **over the 150 KB target by ~60 KB** (new Dart sync client and
Web access screen plus two extra Material icon glyphs). It is reported, not
hidden; no native code, Gradle, signing or applicationId changed.

## 4. Tests

- Web conformance: `node --test sync/test-web.mjs` — **10/10 pass**.
- Android conformance: `flutter test test/cloud_sync_test.dart` — **11/11 pass**;
  full host suite `flutter test` — **360/360 pass**; analyzer clean.
- Simulation: `node scripts/sync-simulate` against local `wrangler dev` —
  two devices, initial pull, edits on both sides, offline period, delete
  propagation, token rotation and cloud deletion — **SIMULATION PASSED**.
- Browser pairing: Playwright opened a real pairing link against local Worker;
  fragment stripped, ciphertext verified on server, second browser pulled the
  same entry — passed.
- Migration/deviation: no DB schema migration was performed. The outbox and
  per-record ua map are additive SharedPreferences keys; a pre-sync snapshot is
  saved to `expense_cloud_prebackup_v1` before vault creation. Existing queries
  and the 360-test suite are unaffected. A Drift-table migration with a file
  backup remains future work.

## 5. Steps only you can do (still pending)

1. `npx wrangler login`
2. `npx wrangler d1 create dhadda-vault` → paste `database_id` into
   `sync-server/wrangler.toml`.
3. `npx wrangler d1 execute dhadda-vault --remote --file=sync-server/schema.sql`
4. `./scripts/deploy-sync` → note the Worker URL.
5. `WORKER_URL=https://dhadda-sync.<sub>.workers.dev ./scripts/deploy-web`
6. Edit `webapp/_headers` CSP `connect-src` and `webapp/config.js` are rewritten
   by the deploy script — commit the deployed URLs if desired.
7. Install the new APK over your current app (do not uninstall), then follow
   `design/ON_DEVICE_CHECKLIST.md`.

## 6. Known limits

- Receipts/photos are not synced (out of scope).
- Web pull is every 30 s while visible; local web changes push after 2 s.
- The pairing link is both access and recovery — anyone with it can decrypt.
- No automatic foreground/offline alarm scheduling was wired into `main.dart`;
  sync currently triggers from the Web access screen plus the web's polling.
- Keystore-backed key storage is not implemented: key/token live in app-private
  SharedPreferences. No new native plugin was added.
- Fiscal-year start is a placeholder setting (Android has no such pref yet).

## 7. Follow-up (this branch, same branch `sync`)

No new dependencies, no DB migration.

- **Triggers wired:** a repository-level hook in `ExpenseStore`
  (`cloudChangeHook`) queues one cloud row per changed record on the success
  path of every domain write; settings setters queue their own rows. The root
  shell owns one `CloudSync`: debounced push **5 s** after the last change,
  **push + pull on resume**, **pull every 60 s while foreground**, timers
  cancelled on pause and hook detached on dispose. "Sync now" still works.
- **Change capture proven:** `flutter test test/change_capture_test.dart`
  mutates through entry add/edit/delete, kept-add, event add/edit/delete,
  loan add/top-up/repayment/reminder/delete, category add/edit/budget/reorder/
  delete, account add/edit/archive/delete and the four synced settings, then
  asserts every `(table,id)` and its deleted flag is present in the outbox.
  Full suite: **372/372**, analyzer clean.
- **CORS fail-closed:** `ALLOWED_ORIGIN` was removed from `wrangler.toml`.
  Production requests from a browser origin are rejected with **503** unless
  the Pages origin was set via `wrangler deploy --var ALLOWED_ORIGIN:<url>`;
  a configured but non-matching origin gets no matching `Access-Control-Allow-Origin`.
  Local `wrangler dev` allows only `localhost`/`127.0.0.1`; requests with no
  `Origin` (the Flutter app) are allowed. Verified against local dev:
  local origin ACAO echoed, `https://evil.example` → 503, no-origin → 200.
- **Deploy order:** `./scripts/deploy-sync` (Worker first) →
  `WORKER_URL=… ./scripts/deploy-web` (Pages, then redeploy Worker with
  `ALLOWED_ORIGIN=<pages-url>`). Documented in `PROJECT_GUIDE.md` §1b.
- **Backup exclusion:** `android:dataExtractionRules` and
  `android:fullBackupContent` now point at XML files excluding all seven
  `expense_cloud_*` preferences. `android:allowBackup="false"` remains, so
  nothing is uploaded today; the rules are explicit defence in depth.
- **Sizes:** APK 98,981,785 → **98,999,297 bytes** (+17,512 for the follow-up,
  +230,720 from the original baseline). Web gzip unchanged at 24,028 B.

### Follow-up 2 (same branch)

- **Background flush:** `stopForeground()` is now async — on pause/inactive it
  cancels the 5 s debounce and periodic pull, then immediately pushes the
  outbox if non-empty (best effort, failures leave rows queued). `main.dart`
  calls it via `unawaited` from the lifecycle observer.
- **No echo:** new `test/pull_no_echo_test.dart` attaches the real change hook,
  applies a pulled batch (category, entry, setting), and asserts the outbox
  stays empty; applying the same batch twice leaves the domain fingerprint
  unchanged and the outbox still empty. It passes — `cloudApplying` in
  `ExpenseStore.applyCloudRows` correctly suppresses the hook.
- Full suite after both fixes: **373/373**, analyzer clean (info-only lints).

## 8. Not verified

No real Cloudflare deployment (needs your login), no physical-device run, no
formal contrast or long-duration battery measurement. Browser tests used
Chromium headless against a local Worker only.
