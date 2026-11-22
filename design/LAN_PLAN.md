# Dhadda — Prompt 3 Phase 0 recon: phone-hosted LAN sync

Status: **AWAITING `go`** — no code has been changed.
Branch: `lan-sync`, created from `sync` at `081745f`.
Repo: `C:\Users\obino\Desktop\Dhadda`. Date: 2026-11-22.

Scope of this document: answer the eight Phase 0 questions with verified facts
(git history, source, measured bytes, test runs). Phase 1 (`LAN_PROTOCOL.md` +
vectors) starts only after the maintainer replies `go`.

Uncommitted user work carried onto the branch: `webapp/config.js` changes the
deployed Worker URL from the placeholder to `http://127.0.0.1:8787` (local
`wrangler dev`). It is **not** part of this plan and will not be committed.

---

## 0. Baselines (measured today)

| Item | Measured value | How |
| --- | --- | --- |
| Pre-cloud release APK (Prompt 3 budget reference) | **98,768,577 bytes** | `design/SYNC_PLAN.md:52,101` |
| Current release APK (with cloud) | **98,999,297 bytes** | `build/app/outputs/flutter-apk/app-release.apk`, 2026-11-22 11:35 |
| Cloud-phase growth so far | **+230,720 bytes** (+0.23%) | difference |
| Debug APK present | 221,047,437 bytes | `build/app/outputs/flutter-apk/app-debug.apk` |
| Embedded legacy Flutter-web bundle | **45 files / 45,915,038 bytes (43.79 MiB)** | `assets/webapp/`, incl. `main.dart.js` 4,334,194 B |
| Same bundle, DEFLATE-compressed sum | **~15,609,653 bytes (14.89 MiB)** | per-file zlib deflate level 6 — approximates its APK share |
| Plain JS `webapp/` | **85,830 bytes raw**, **22,964 bytes gzip** (JS+CSS+HTML+JSON, level 9) | measured |
| Web budget | 60 KB gzip | Prompt 3 §11 |
| Android budget | ≤450 KB growth over 98,768,577 | Prompt 3 §11 |
| Toolchain | Flutter 3.47.2 / Dart 3.13.2 | `flutter --version` |
| minSdk / targetSdk | **24 / 36** | merged release manifest, `flutter.targetSdkVersion` in `build.gradle.kts:48` |
| Java / Kotlin target | 17 / JVM 17 | `build.gradle.kts:37-39,105-109` |
| Connected device | `adb-4750a3bc-ewPaNc._adb-tls-connect._tcp` (one device) | `adb devices` |

Budget arithmetic: replacing the 14.89 MiB compressed Flutter bundle with the
~86 KB plain-JS app (plus vendored crypto, ≤25 KB gzip) should make the APK
**~14.8 MB smaller than the pre-cloud baseline**, i.e. far inside the +450 KB
limit. Exact numbers will be measured in Phase 5 and again in Phase 7.

---

## 1. Why "Show on PC" and scan-to-sync stopped working

### The concrete, bisectable cause

`git log -S"usesCleartextTraffic" -- android/app/src/main/AndroidManifest.xml`
points at one commit:

**`2afcd8f` (2026-11-13) — "Add event branches, category drill-down, and
resilient file import"**, whose message says *"cleartext LAN is allowed for
sync"*. Its manifest diff adds:

```diff
-        android:allowBackup="false">
+        android:allowBackup="false"
+        android:usesCleartextTraffic="true">
```

and the in-tree comment states the symptom verbatim:

> Without this flag Android 9+ silently blocks all outbound sync calls from
> the phone while hosting (Show on PC) keeps working, which made pairing look
> completely broken.

So the failure was **not** in the QR code, the server or the UI. Android blocks
cleartext traffic from apps targeting API 28+ unless opted in. The phone's own
HTTP client could no longer call `http://192.168.x.x:8080/api/sync/link`
(it calls its *own* hosted server to create a link box), nor the PC/node relay
used by scan-to-sync. The browser on the PC could still open the hosted page
(inbound hosting is unaffected), which is why it looked like "the page opens
but pairing never happens". `2afcd8f` fixed it. The 1.5.0 release installed on
the phone (2026-11-21) contains the fix.

Verifying work done in Phase 0: `flutter test` for
`wifi_sync_e2e_test.dart`, `link_test.dart`, `sync_v2_e2e_test.dart`,
`lan_security_test.dart`, `sync_screen_paste_test.dart`, `mdns_test.dart` →
**27/27 passed**. LAN tests also emit the real `phone-host ...` request logs,
so the Dart server itself is healthy.

### Secondary causes that still make the old path unusable today

1. **The served UI is a second copy of the app, not the phone's data.**
   `phone_host_io.dart:158-180` serves `assets/webapp/*`, a compiled *Flutter
   web* build. On web, `lib/data/db_connection_stub.dart:5` throws
   `UnsupportedError` and the app uses `PrefsDomainStore` (browser
   localStorage). The phone uses Drift/SQLite. Opening the address therefore
   shows an empty, separate tracker; the only bridge is the link-mailbox sync
   with a 4–12 char PIN. That is not "your expenses on the PC".
2. **43.8 MB uncompressed over Wi-Fi** (`main.dart.js` 4.3 MB + CanvasKit
   WASM), no gzip in `phone_host_io.dart:173-179`. Slow first load and a
   98 MB APK. The bundle is rebuilt by hand via
   `tool/build_embedded_web.dart`; it has drifted before (1.3.0+1 vs app
   1.3.1+2, `PROJECT_CONTEXT.md:480`) and is currently 1.5.0+4.
3. **No foreground service.** `_startServe` (`sync_screen.dart:398-420`) only
   enables `WakelockPlus`, i.e. `FLAG_KEEP_SCREEN_ON`. Android suspends the
   process when the screen turns off or the app backgrounds → the server
   drops. `PROJECT_CONTEXT.md:487-490` also records a 2026-09-06 incident
   where the request never reached the app (counter stayed 0), attributed to
   the network, not the code.
4. **Settings now advertises a dead path.** `menu_screen.dart:405-413` →
   `WebAccessScreen` uses `CloudSync.defaultWorker` =
   `https://dhadda-sync.YOUR-SUBDOMAIN.workers.dev` (`cloud_sync.dart:20`) —
   a literal placeholder, never deployed. That is the "Web access (cloud)"
   row Prompt 3 §10 asks to remove.
5. **Whole-snapshot last-writer-wins.** `PROJECT_CONTEXT.md:716-744` proves
   equal-timestamp ties and clock skew silently diverge, and an older
   snapshot can erase one side's exclusive transactions. Prompt 3's row
   protocol replaces this.

### What the old code does and what is reusable

| Old feature | Where | Status / reuse |
| --- | --- | --- |
| Phone-hosted server | `lib/sync/phone_host_io.dart` (shelf, port 8080 → random), `phone_host.dart` (IO/stub export) | **Reuse** the `dart:io` `HttpServer` idea, private-IP discovery (`phoneLanIp()`), MIME table, SPA fallback, capped bodies (`http_limits.dart`) and throttle (`lan_throttle.dart`). Replace CORS `*`, PIN boxes and static Flutter bundle. |
| QR show | `qr_flutter` in `sync_screen.dart:843-856` (address URL) and `QrV2` for pairing | **Reuse** `qr_flutter` for the address QR; new pairing QR is a different payload. |
| QR scan | `lib/screens/scan_screen.dart` + `flutter_zxing` | **Reuse** for "Scan computer's QR" (Phase 3). |
| Pairing code / PIN | `lib/sync/session_pin.dart`, `6-digit sender PIN`, `link_store.dart` 4–12 char PIN, CSPRNG | **Reuse** only the CSPRNG habit / UX pattern; the new 8-char code and X25519 handshake replace the semantics. |
| Mailbox relay | `lib/sync/link_store.dart`, `link_sync.dart`, `relay_client.dart`, `server/serve-expense.cjs` | **Do not reuse** for LAN. Keep files, mark shelved. `applyCloudRows` + change hook are reused instead. |
| Phone-to-phone snapshot (Direct WiFi) | `lib/sync/wifi_host_io.dart` (`/meta`, `/snapshot`, `/snapshot-v2`, `/auth`, 6-digit PIN, 5-min TTL), `wifi_client.dart` | **Works** (e2e test green) and stays behind "More ways to sync". Whole-snapshot LWW limitation remains; not changed in this task. |
| File export/import | `lib/sync/file_sync.dart`, `backup_crypto.dart`, `store.importFilePayload` | **Works**; stays unchanged. |
| UUIDs | `uuid` package, `store.deviceId` | **Reuse** for `device_id`. |
| `(rev, by)` LWW | `store._revs`, `RecordMeta`, `sync_v2.dart` | **Reuse** the tie-break idea; Prompt 2's `CloudSync.resolveWinner` is `(ua, device_id)`. |
| mDNS | `lib/sync/mdns.dart` → `expense/mdns` MethodChannel → `MdnsHelper.kt` | **Optional** (Phase 8); Windows `.local` is known unreliable (`PROJECT_CONTEXT.md:485`). |

**Answer to "do phone-to-phone and file still work":** yes, by code and tests.
They are not verified on a real device in this phase.

---

## 2. How the old Show on PC served the UI, and the new bundling plan

### Old path (verified)

1. `sync_screen.dart:398` → `startPhoneHost()` (`phone_host_io.dart:139`).
2. `shelf_io.serve(handler, InternetAddress.anyIPv4, 8080)`, falling back to
   port 0 (`phone_host_io.dart:355-368`); `phoneLanIp()` prefers 192.168 →
   10 → 172 and the URL is `http://<ip>:<port>` (`:369-371`).
3. Routes: `POST /api/sync/link|push|unlink`, `GET /api/sync/pull`,
   `GET /api/ping`, explicit `GET /`, wildcard `GET /<path|.*>` with SPA
   fallback to `index.html` (`:182-317`).
4. Every static file is `rootBundle.load('assets/webapp/$name')` (`:158-180`),
   returned with a small MIME map and `Cache-Control: no-cache`. **No gzip.**
5. Middleware adds `Access-Control-Allow-Origin: *` to everything, handles
   `OPTIONS`, logs only the request path, and turns exceptions into a generic
   500 (`:319-353`).
6. `Mdns.register(name: 'dhadda', port)` advertises `dhadda.local` best-effort
   (`sync_screen.dart:422-442`).

### New path (Phase 2/4)

- Bundle `webapp/` as Flutter assets: add `- webapp/` (plus subdirs if any) to
  `pubspec.yaml:flutter:assets`. Raw size **85,830 bytes**; expected
  compressed APK share ~25–30 KB. Vendor `@noble/*` into `webapp/vendor/`
  with version/SHA-256/licence in `webapp/vendor/README.md` (≤25 KB gzip).
- Serve them from a `dart:io` `HttpServer` (shelf is already a dependency, so
  either keep shelf or use raw `HttpServer`; no new Dart dependency). Keep the
  private-IP discovery, fixed-port-first logic and capped bodies. Add gzip for
  text assets, `no-store` on API responses, the security headers from §5, no
  CORS, and a strict `Host` check.
- **Remove `assets/webapp/` from `pubspec.yaml`** (keep the files on disk for
  history) → ~14.89 MB of compressed assets leave the APK. This is the single
  biggest win and needs no schema/data change.
- Total web gzip expected ~47 KB (22.4 KB current + ≤25 KB noble) < 60 KB.

---

## 3. Present Android sync UI surface

| Concern | File / lines | Notes |
| --- | --- | --- |
| Main sync hub | `lib/screens/sync_screen.dart` (42 KB) | Sections in order: quick relay offer/join (`:81-390`), Show on PC (`:396-457`, UI at `:818-914`), Direct WiFi send/receive (`:489+`, UI at `:958+`), file backup (`:459-487`, `:926-956`), This device. |
| Home-header sync icon | `home_screen.dart:663` and `:731` (label `'Sync'`) → `onOpenSync` → `main.dart:372-375` `_openSync()` → `SyncScreen(engine: _link)` | **Target for the new "Use on computer" screen** (Prompt 3 §6). History has the same hook (`history_screen.dart:284`). |
| Settings → Data → Web access (cloud) | `menu_screen.dart:405-413` → `WebAccessScreen` | **Remove in Phase 5** (Prompt 3 §10). |
| Settings → Sync → Open sync | `menu_screen.dart:468-493` → `SyncScreen(engine: _link)` | Keep as "More ways to sync" entry. |
| Cloud screen | `lib/screens/web_access_screen.dart` (168 lines) | Status, Create link, Sync/Pull now, Disconnect, Delete cloud copy. Guard behind `kEnableCloudSync = false`. |
| QR scanner | `lib/screens/scan_screen.dart` (`flutter_zxing`) | Wire to "Scan computer's QR". |
| Design vocabulary | `lib/widgets/page.dart`, `app_card.dart`, `settings_row.dart`, `section_header.dart`, `segmented_tabs.dart`, `theme/tokens.dart` (`Spacing`, radii), `theme/typography.dart` (`AppType`), `theme/palette.dart` (`AppColors.of`) — all used in `web_access_screen.dart` | New screen must use these, not hard-coded values. `design/PARITY.md` is the contract; Android leads and `design/tokens.json` → `scripts/sync_tokens.py` → `design/tokens.css` feeds the web. |

---

## 4. Change hook, `applyCloudRows`, row serializer — how LAN reuses them

- **Hook:** `ExpenseStore.cloudChangeHook` at `store.dart:45-49`:
  `Future<void> Function(String table, String id, Object data, {bool deleted})?`,
  called once per mutated record **after** a successful domain write, and
  suppressed while `cloudApplying == true` (`:51-52`) so remote rows never
  echo. Settings mutations also call it (`:831,891,929,1000`).
  `CloudSync.attach()` (`:72-73`) simply assigns `store.cloudChangeHook = queue`.
  → The LAN sender will attach its own hook the same way; it is mutually
  exclusive with the cloud client because cloud is flagged off.
- **Outbox:** `CloudSync.queue()` (`:229-240`) builds a row and stores it in
  app-private SharedPreferences, removing the older row for the same
  `(t,id)`. `pushAll()` (`:251-262`) enumerates categories, entries, events,
  people and four settings keys. → Reuse as the LAN outbox, but with `seq`
  counters and AEAD envelopes instead of AES-GCM cloud rows.
- **Row serializer:** `_row(t,id,data,deleted)` at `cloud_sync.dart:224-227`
  emits `{t, id, ua, d, data}`; `push()` (`:264-285`) adds `device_id, iv, ct`.
  → Keep `t/id/d/data`; replace `ua` with the row's LWW stamp and add `seq`
  for replay protection.
- **Ingest:** `CloudSync.pull()` (`:296-319`) decrypts, compares `ua` against
  `_uas[k]`, collects winners and calls `store.applyCloudRows(applied)`.
- **Apply:** `ExpenseStore.applyCloudRows()` at `store.dart:2073-2144` handles
  `categories/entries/events/people/settings`, inserts or replaces by id,
  honours `d==1` tombstones, then calls `_domain.replaceAll(...)`, `_touch()`
  and `notifyListeners()` inside a re-entrancy guard. **No collection is
  cleared.** → Reuse verbatim for `POST /api/push` and for WS `changed`
  frames. Settings keys currently handled: `userName`, `currency`,
  `calendarSystem`, `homeLayout` (`fiscalYearStart` acknowledged but not
  consumed).
- **LWW:** `CloudSync.resolveWinner` (`:44-56`) — larger `ua` wins; ties by
  lexicographically larger `device_id`. → Reuse exactly; Prompt 3 §5 uses
  `ua` + `device_id` tie-break.
- **Events:** `WS /api/events` broadcasts the same row shape, so `applyCloudRows`
  is the single funnel for snapshot, push and live frames. The phone's own UI
  writes go through the existing repository hooks, so validation and derived
  totals stay consistent.

---

## 5. Crypto choice, interop and flaws found in Prompt 3 §5

### Choice

- **Dart:** existing `cryptography: ^2.9.0` (`pubspec.yaml:64`) already provides
  X25519, HKDF, HMAC and ChaCha20-Poly1305. **No new Dart dependency.**
- **JS:** vendor the ES-module builds of `@noble/curves` (X25519),
  `@noble/hashes` (SHA-256, HKDF, HMAC) and `@noble/ciphers`
  (ChaCha20-Poly1305) into `webapp/vendor/`, with version, SHA-256 and MIT
  licence in `webapp/vendor/README.md`. No CDN, no npm at runtime.
- `window.crypto.getRandomValues` **is** available on plain HTTP (only
  `crypto.subtle` is gated), so it is the CSPRNG source for `ePC` and `s`.
- Interop proof: shared KAT vectors in `design/test-vectors/lan.json`,
  reproduced by both `test/lan_crypto_test.dart` and
  `scripts/lan-simulate` (Node importing the **web client code**).
  `crypto.subtle` is deliberately never used in the LAN path.

### Flaws / gaps in §5 that must be resolved in `LAN_PROTOCOL.md`

1. **Offline code recovery (serious).** `proof` is sent in cleartext over the
   LAN and is a verifier for an 8-char code from a 31-char alphabet
   (≈2^39.6). X25519 public keys `epc`/`ephone` and `sid` are also in the
   clear, so a passive sniffer can compute `Z` and `T`. They can then brute
   force the code offline from one captured `proof` and derive `K`, decrypting
   the whole session later. The 5-attempt lockout does not help against
   offline work. **Proposed fix (needs approval — adds a KDF call, not a
   dependency):** stretch the code with PBKDF2-HMAC-SHA256
   (`codeKey = PBKDF2(code, salt=T, iterations≈210000, 32 bytes)`) before the
   HKDF/HMAC, in both Dart and noble. If rejected, state the residual risk
   plainly in the protocol doc.
2. **Trusted reconnect transcript is undefined.** §5 reuses `T` but only
   defines `T = SHA256(epc ‖ ephone ‖ sid)` for code mode; `/session/hello`
   has no `sid`. Define explicitly `T = SHA256(epc ‖ ephone ‖ nonce)` for the
   trusted path (and the exact HKDF `info`, e.g.
   `dhadda-trusted-session-v1`) before coding.
3. **Counter reset on reconnect.** If a session key survives a WS reconnect
   and the counter restarts at 0, strict-increase replay checks reject every
   new frame. Define: either derive a fresh session key for every WS
   connection, or persist the last sent/received counter and resume from it.
   Recommend fresh key per connection + keep the trust secret stable.
4. **AAD is unspecified.** Bind `sid`, direction and counter into the AEAD AAD;
   nonce uniqueness alone prevents reuse but not cross-context replay if two
   sessions ever share a key.
5. **Global 5-attempt lockout is a DoS knob.** Anyone on the LAN can spend the
   five attempts of the currently displayed code. Keep the "5 total" rule as
   specified, but add a short cooldown between wrong attempts and immediately
   tell the phone "too many attempts" (the UI already needs that state).
6. **QR consent is implicit.** "Scan = consent" means a malicious QR can make
   the phone pair with a rogue computer. The phone already received `name`
   and the source IP in `hello`; show them on the pairing screen at scan time
   and offer immediate Disconnect/Forget. Do **not** add a second Allow tap
   (Prompt 3 forbids it).
7. **`/pair/poll` is unauthenticated beyond `sid`.** `sid` is visible in the
   sniffable `hello` response. Anyone can poll and learn pairing state and
   possibly `proof_phone`. Neither yields `K` (ECDH private key is needed),
   but require `epc` with `sid` for polling to close the leak.
8. **CSP is slightly too open.** `connect-src 'self' ws:` permits WebSocket to
   any host; restrict to the phone origin/`ws://<ip>:<port>`. Also allow
   `img-src 'self' data:` for QR images and `'unsafe-inline'` only for the
   pre-paint theme snippet if it stays.
9. **Host check is for HTTP only.** Apply it to the WebSocket upgrade too, and
   allow `127.0.0.1`/`localhost` only in debug for integration tests.
10. **Code "works once" needs a state machine.** Pairing endpoints must answer
    only while the pairing screen is active; mark the code consumed *before*
    showing the Allow sheet so a double-submit cannot pair twice.

None of these weaken the design if fixed in the protocol doc; items 1 and 2
need a decision before Phase 1 (see §7).

---

## 6. Background hosting on Android (Phase 7)

Facts from `AndroidManifest.xml` and `build.gradle.kts`:

- `targetSdk = 36` (Android 16), `minSdk = 24`; Java/Kotlin 17.
- Already declared: `INTERNET`, `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`,
  `CAMERA`, `USE_BIOMETRIC`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
  `CHANGE_WIFI_MULTICAST_STATE`, `READ_SMS`. `usesCleartextTraffic="true"`.
- **Missing:** `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`.
  Verified in the merged release manifest: no `WAKE_LOCK` is contributed by
  `wakelock_plus` (its own manifest is empty), so `WakelockPlus.enable()` only
  keeps the screen on via `FLAG_KEEP_SCREEN_ON`; it is not a partial wake lock.
- No service/receiver other than the four widget receivers (no FGS, no
  notification channel).
- Native code pattern already exists: `MainActivity.kt` registers five
  MethodChannels (`expense/widget`, `expense/widget_actions`,
  `expense/mdns`, `expense/sms`, `expense/media`, `expense/perm`); `MdnsHelper.kt`,
  `MediaBridge.kt`, `SmsBridge.kt` show the style. A new
  `expense/host_service` channel + `DhaddaHostService : Service` fits without
  a Dart dependency.

**Plan and exact manifest additions (Phase 7, own commit):**

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<service android:name=".DhaddaHostService"
         android:exported="false"
         android:foregroundServiceType="dataSync" />
```

- `dataSync` is the correct type at API 34+ for a network data-transfer
  service; it requires `FOREGROUND_SERVICE_DATA_SYNC`. Must be verified on the
  API 36 device in Phase 7 — Android keeps tightening FGS rules, and if the OS
  refuses, report honestly and ship the app-open-only version rather than
  weakening permissions.
- Kotlin service responsibilities only: `startForeground()` with a small
  notification ("Dhadda is available on your computer · Stop"), acquire a
  **partial wake lock** and a **Wi-Fi lock** (`WifiManager.createWifiLock`,
  needs `ACCESS_WIFI_STATE`), run the 2-hour idle auto-stop timer, and forward
  Stop taps to Dart over the MethodChannel.
- Important honest limit: the Kotlin service **cannot host the Dart
  `HttpServer` in another process**. The Dart server runs in the same Flutter
  process; the service only keeps that process alive. If Android kills the
  process, the server dies and the computer reconnects/backoff.
- `POST_NOTIFICATIONS` is a runtime permission on API 33+. If denied, still
  allow foreground serving and explain in the UI; do not block Start.
- APK cost: a few KB of DEX (one `Service`, one notification channel) plus
  three permission lines — expected **< 20 KB**, to be measured against the
  Phase 5 APK in the Phase 7 commit.
- Handle Wi-Fi/IP change (update the shown URL), app resume, and idle
  auto-stop; no timer, wake lock or socket while Stopped.

---

## 7. Steps only the maintainer can do / decisions for the maintainer

### Decisions needed before Phase 1

1. **Approve the PBKDF2 stretch** in §5 item 1 (uses existing libs only), or
   accept the documented offline-code-recovery risk. My recommendation:
   approve.
2. **Confirm the trusted-reconnect transcript** `T = SHA256(epc‖ephone‖nonce)`
   and the session-key HKDF info strings (§5 item 2).
3. **Foreground service: yes/no** (§6). Recommendation: yes, last commit; fall
   back to app-open-only if API 36 refuses.
4. **mDNS / `dhadda.local` (Phase 8):** include only if it works on Windows 11
   Chrome/Edge without extra dependencies; otherwise skip and say so.
   Recommendation: skip unless you want it.
5. **Remove `assets/webapp/` from `pubspec.yaml`** (~14.89 MB APK saving).
   Files stay on disk; nothing user-data-related is touched. Recommendation:
   yes.
6. **Keep "More ways to sync"** (phone-to-phone + file backup) unchanged?
   Recommendation: yes, collapsed at the bottom as Prompt 3 §6 says.

### Steps only you can do (on-device / network)

- Confirm the phone is awake, Dhadda is open, and phone + PC are on the same
  **home/hotspot** Wi-Fi (not guest/hotel/AP-isolated).
- Tell me the phone's Wi-Fi IP/port shown on screen for the final browser
  test, and open `http://<phone-ip>:<port>` in Chrome/Edge on the PC (never
  `localhost` for the final check).
- Grant the notification permission when prompted (Phase 7), and reserve the
  phone's IP in the router if you want the trust key to survive IP changes.
- Camera permission for the phone to scan the computer's QR; physically hold
  the QR up to the phone.
- Walk the ~15-step `ON_DEVICE_CHECKLIST_LAN.md` (Phase 6) and report results.
- Wrong-code / expired-code / forgot-device cases need your eyes on the
  phone's Allow sheet and countdown.

I will only install the `.dev` debug app (`com.dhadda.expense.dev`) on the one
connected device, list packages first, and never touch `com.dhadda.expense`.

---

## 8. Phase order and risks (as specified)

0. This recon → **STOP for `go`**.
1. `design/LAN_PROTOCOL.md` + `design/test-vectors/lan.json`, Dart & JS
   primitives with interop proof.
2. Phone server core: static files, pairing, sessions, encrypted API, WS, tests.
3. Phone UI: "Use on computer", Allow sheet, trusted list, QR scan, replace
   Show on PC.
4. Web: vendored crypto, pairing page, remote store behind `window.DhaddaSync`,
   live events, all states; drop `sw.js` registration for LAN HTTP.
5. Cloud flag-off, remove Settings "Web access", docs, measure budgets.
6. Verification, `ON_DEVICE_CHECKLIST_LAN.md`, dev install and real-LAN run.
7. Foreground service (own commit, report exact manifest/permission changes).
8. Optional mDNS (skip if it fails the Windows test).

Risks worth naming now: the `crypto.subtle`/secure-context trap on LAN HTTP
(§3.1) is handled by the noble exception; camera-on-HTTP is handled by
computer-shows-QR / phone-scans; AP isolation is a network condition that no
code can fix, so it needs the friendly Troubleshoot panel; and the foreground
service is the riskiest phase and is deliberately last.

No merge, no push, no Cloudflare commands, no new Dart dependency, no schema
change, no logging of codes/keys/tokens.
