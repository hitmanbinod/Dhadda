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

## 7. Not verified

No real Cloudflare deployment (needs your login), no physical-device run, no
formal contrast or long-duration battery measurement. Browser tests used
Chromium headless against a local Worker only.
