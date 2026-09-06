# PROJECT_CONTEXT.md — Dhadda (Expense Tracker)

> Generated 2026-09-06 from direct inspection of the repository at
> `C:\Users\obino\Desktop\bin\Projects\Expense` (package `expense`, app label `Dhadda`,
> `pubspec.yaml` version `1.3.1+2`, `lib/version.dart` `kAppVersion 1.3.1`,
> `kBuildStamp 2026-09-06 (hostfix)`).
> Source code and configuration are the source of truth. Anything not verifiable in
> the repo is marked `NOT VERIFIED`. No secrets are included. Documentation only —
> no code was modified.

---

## 1. Project Overview

- **What it is:** **Dhadda** — a minimal, offline-first, single-user expense tracker
  built with Flutter (Android app + Flutter-web companion). No accounts, no cloud.
- **Main purpose:** Track daily expenses/income on Android; view/operate the same data
  from any same-WiFi browser (desktop included) via the phone-hosted "Show on PC" mode.
- **Intended users:** One person (the maintainer) and their household devices.
  Single-user by design — no multi-user model, no login server, no shared backend.
- **Problems it solves:** (1) subscription/cloud expense apps → free, local, $0 operating
  cost; (2) phone-only data → full app served to same-WiFi browsers; (3) two-device drift
  → snapshot sync over file / direct WiFi / link mailbox with last-write-wins, plus a
  lent/borrowed ledger with reminders; (4) manual entry friction → opt-in SMS auto-import
  tuned for Nepali banks/wallets (Nabil, NIC Asia, eSewa, Khalti, ATM messages).
- **Current stage:** Working **beta / late MVP**. All core flows are implemented and
  covered by 49 automated tests in 12 files (`test/`). Real-device cross-device checks
  (mDNS on Windows, PC-browser path) are still being verified.
- **Major completed functionality:** 4-tab app (Home/History/Lent/Menu); Add-entry flow
  with reorderable categories; search/filter/CSV history; lent & borrowed ledger with
  one-time reminders; projects ("events"); budgets; 4-digit PIN + biometric unlock;
  theming (light/dark/system + Material You + custom accents); file export/import; direct
  WiFi PIN sync; link-mailbox relay sync (PC relay + phone-hosted); phone-hosted web
  serving with mDNS; SMS inbox import (manual + auto); rolling local backups.

---

## 2. Current Features

### Fully implemented

- **Home dashboard** (`lib/screens/home_screen.dart`, 366 lines): month pager with
  calendar jump, Spent/Income/Balance/Lent-out cards, `fl_chart` pie with tap/long-press
  category spotlight, legend, per-category budget bars, recent-8 list, pull-to-refresh
  sync, Add button. Entry point of the app (`RootShell` index 0, `lib/main.dart`).
- **Add entry** (`lib/screens/add_screen.dart`, 344 lines): Expense/Income toggle, strict
  amount validation (`parseAmount` in `lib/format.dart`), category chips with long-press
  reorder mode, event picker + inline new-event dialog, date/time pickers,
  cash/bank/card/ewallet mode. Persists via `ExpenseStore.addTransaction`.
- **History** (`lib/screens/history_screen.dart`, 849 lines): debounced search
  (note/category/mode), type + category `GlassBox` filters, day filter + calendar FAB,
  CSV export (`FileSync.buildCsv`), `Slidable` delete with Undo, tap/long-press edit
  sheet (`lib/widgets/entry_actions.dart`), Entries/Categories/Events views, category
  drag-reorder + rename/budget/icon/color/delete, per-event expandable totals.
- **Lent & Borrowed ledger** (`lib/screens/lent_screen.dart`, 618 lines): lent/borrowed
  toggle, pending/settled/all filter, To-receive/To-return header totals, principal +
  top-ups + repayments per person, person-name autocomplete, per-loan one-time OS
  reminder (date + time), settled when `pending <= 0.005` (`lib/models.dart`).
- **Projects ("events")**: `Project` pots tag transactions (`Txn.projectId`); per-event
  totals; deleting an event untags its txns. UI: History > Events, Add screen.
- **Budgets**: per-category monthly budget, progress bars on Home, editable in the
  category customize dialog (`store.setBudget` / `updateCategory`).
- **Security**: 4-digit PIN (`lib/security.dart`, SHA-256 + static salt, key
  `expense_pin_hash_v1`), lock screen (`lib/screens/lock_screen.dart`), biometric-only
  unlock fast-path (`local_auth`), lock check on launch (`lib/main.dart`).
- **Appearance**: Light/System/Dark, 12 preset accents + `flex_color_picker` custom
  wheel, Material You dynamic seed on Android (`dynamic_color`), 10-currency selector
  (default NPR), editable user name. All in `MenuScreen` + `ExpenseStore`.
- **File backup/sync** (`lib/sync/file_sync.dart`): export snapshot JSON via share
  sheet, import via file picker, 5 rolling auto-backups with restore.
- **Direct WiFi sync**: sender hosts PIN shelf server (`lib/sync/wifi_host_io.dart`:
  `GET /meta`, `GET /snapshot`, `POST /snapshot`, header `x-sync-pin`); QR format
  `EXPENSESYNC::<url>::<pin>` (`lib/sync/wifi_client.dart`).
- **Link-mailbox relay sync**: persistent 8-char link codes + numeric PINs; peers
  exchange snapshots through `LinkStore` mailboxes; PC Node relay
  (`server/serve-expense.cjs`) and phone host implement the same protocol; QR format
  `EXPENSESYNC2::<origin>::<code>::<pin>` (`lib/sync/relay_client.dart` `QrV2`);
  `LinkEngine` (`lib/sync/link_sync.dart`) auto-syncs on change (3 s debounce), every
  15 s, and on resume.
- **Show on PC** (`lib/sync/phone_host_io.dart`): serves bundled Flutter-web UI
  (`assets/webapp/`, 43 files) + link API on LAN (port 8080 → random fallback),
  wakelock while serving, served-request counter (`hits`), `GET /api/ping` health,
  explicit `GET /` route, hardened middleware (safe counter bump, caught handler errors
  return `Dhadda host error: …`), SPA fallback to `index.html`, `no-cache`.
- **mDNS**: `http://dhadda.local:<port>` via native `NsdManager` (`MdnsHelper.kt`,
  channel `expense/mdns`, `_http._tcp.`). Best-effort; IP URL always shown too.
- **SMS import, opt-in** (`lib/sync/sms.dart`, `lib/sync/sms_parse.dart`,
  `SmsBridge.kt`): Manual/Auto modes + sender allowlist; inbox read (90 days, ≤300
  rows) over `expense/sms`; pure-Dart parser (amount/direction/merchant/mode,
  25-category keyword map + custom names); imported IDs capped at 500.
- **Reminders** (`lib/sync/reminders.dart`): one-time scheduled OS notifications
  (`flutter_local_notifications` + `timezone`, channel `loan_reminders`); refreshed on
  loan changes, boot, resume; never throws; web no-op.
- **Erase + About**: double-confirm wipe + reseed (`eraseAll`); About shows
  `Expense $kAppVersion ($kBuildStamp)` (`lib/screens/menu_screen.dart:430`).

### Partially implemented

- **Desktop mDNS resolution**: Android advertiser complete; Windows Chrome/Edge often
  cannot resolve `.local` without Bonjour (environmental). IP URL is the supported path.
- **Embedded web bundle freshness**: checked-in `assets/webapp/version.json` says
  `1.3.0+1` while the app is `1.3.1+2` — bundle lags until a manual rebuild + copy
  (no copy script exists; see §"Embedded Web Build Reproducibility").
- **Store readiness**: Play listing texts exist (`fastlane/metadata/`), but no
  `Fastfile`/`Appfile`, and release signs with **debug keys** (see §"Google Play
  Release Readiness").

### Planned but not implemented

- Maintainer-requested UI polish batch (bigger/aligned overview calendar, remove pie
  long-press hint, category-chart/Add-button reorder, logical icon packs, expansion-tile
  animation refinement, redesigned accent picker) — requested work, NOT in code.
- No `integration_test/` directory. No iOS target (`flutter_launcher_icons: ios: false`).

---

## 3. Complete Technology Stack

### Android / Frontend (Flutter app, not native Android UI)

| Technology | Version | Purpose | Configured / used in |
|---|---|---|---|
| Flutter (stable toolchain) | 3.47.2 observed locally; pubspec sets no `flutter:` constraint (`NOT VERIFIED` as pinned) | UI framework | `lib/` (34 files), `web/` shell |
| Dart | `^3.13.2` (`pubspec.yaml:22`) | language | all `lib/**/*.dart` |
| Material 3 | Flutter SDK (`useMaterial3: true`, `lib/main.dart`) | design system | all screens |
| Navigation | Navigator 1.0 (`MaterialPageRoute`) + `NavigationBar`/`NavigationRail` + `IndexedStack` | 4-tab shell + pushed screens | `lib/main.dart` (`RootShell`) |
| State | `provider` `^6.1.2` (`ChangeNotifier`) + `setState` + `ValueNotifier` (host hits) | global store + local UI state | `lib/main.dart`, `lib/store.dart`, `lib/sync/phone_host_io.dart` |
| Serialization | `dart:convert` manual `toJson`/`fromJson` (no codegen) | snapshots + prefs | `lib/models.dart`, `lib/store.dart` |
| Persistence | `shared_preferences` `^2.3.2` (plain JSON strings; **no DB engine**) | all persistence | `lib/store.dart`, `lib/security.dart`, `lib/sync/sms.dart` |
| HTTP client | `http` `^1.2.2` | sync clients | `lib/sync/wifi_client.dart`, `lib/sync/relay_client.dart` |
| HTTP serve | `shelf` `^1.4.2` + `shelf_router` `^1.1.4` | on-device servers | `lib/sync/wifi_host_io.dart`, `lib/sync/phone_host_io.dart` |
| Charts | `fl_chart` `^0.69.0` | Home pie | `lib/screens/home_screen.dart` |
| QR render/scan | `qr_flutter` `^4.1.0` + `flutter_zxing` `^3.0.1` (F-Droid-safe, no ML Kit) | sync codes | `lib/screens/sync_screen.dart`, `lib/screens/scan_screen.dart` |
| Biometric | `local_auth` `^3.0.2` | fingerprint unlock | `lib/main.dart`, `lib/screens/menu_screen.dart` |
| Dynamic color | `dynamic_color` `^2.1.0` | Material You seed | `lib/store.dart` (`_refreshDynamicSeed`) |
| Color picker | `flex_color_picker` `^4.0.0` | custom accent wheel | `lib/screens/menu_screen.dart` |
| Wakelock | `wakelock_plus` `^1.8.0` | keep server alive while serving | `lib/screens/sync_screen.dart` only |
| Notifications | `flutter_local_notifications` `^22.3.0` + `timezone` `^0.11.1` + `flutter_timezone` `^5.1.0` | loan reminders | `lib/sync/reminders.dart` |
| Slidable | `flutter_slidable` `^4.0.3` | swipe-to-delete | `lib/screens/history_screen.dart` |
| File pick/share | `file_picker` `^12.2.0` + `share_plus` `13.2.1` (exact pin) | backup export/import, CSV | `lib/sync/file_sync.dart` |
| uuid / intl / crypto | `^4.5.1` / `^0.20.2` / `^3.0.7` | IDs, formatting, PIN hash | `lib/store.dart`, `lib/format.dart`, `lib/security.dart` |
| Dev: lints/icons | `flutter_lints` `^6.0.0`, `flutter_launcher_icons` `^0.14.4` | analysis, launcher icons | `analysis_options.yaml`, `pubspec.yaml:106-116` |
| Kotlin/AGP/Gradle | KGP `2.4.0`, AGP `9.1.0` (`settings.gradle.kts`); Gradle `9.3.1-all` (wrapper); JVM 17; desugar `2.1.4` | native bridge + build | `android/` |
| minSdk/targetSdk/compileSdk | No literals — delegated to Flutter plugin (`flutter.minSdkVersion` etc., `android/app/build.gradle.kts`); exact numbers `NOT VERIFIED` | build config | `android/app/build.gradle.kts` |
| Native bridge | 3 `MethodChannel`s (`expense/mdns`, `expense/sms`, `expense/perm`) | NsdManager, inbox read, camera grant | `MainActivity.kt`, `MdnsHelper.kt`, `SmsBridge.kt` |

Apparent-but-unused dependencies: none confirmed — each maps to ≥1 usage site
(narrowest: `dynamic_color` only in `store.dart`, `wakelock_plus` only in
`sync_screen.dart`). Nothing may be removed per task rules.

### Backend

No hosted backend. Two optional **local** companions share one sync protocol:

| Component | Language / deps | Endpoints | Entry |
|---|---|---|---|
| PC LAN relay | Node.js, plain CommonJS, **zero npm deps** | static host + `POST /api/sync/offer`, `GET /api/sync/session`, `POST /api/sync/answer`, `POST /api/sync/link|push`, `GET /api/sync/pull`, `POST /api/sync/unlink|close` | `server/serve-expense.cjs`; run `node server/serve-expense.cjs build/web 8080` |
| Phone-hosted server | Dart (`shelf`) in-app | `POST /api/sync/link|push|unlink`, `GET /api/sync/pull`, `GET /api/ping`, `GET /` + static webapp + SPA fallback | `lib/sync/phone_host_io.dart` |
| Direct-WiFi sender | Dart (`shelf`) in-app | `GET /meta`, `GET /snapshot`, `POST /snapshot` (`x-sync-pin`) | `lib/sync/wifi_host_io.dart` |

LAN auth = link/box PINs (4–12 chars), never accounts. CORS `*`. In-memory only
(20 sessions / 50 boxes caps; Node relay loses everything on restart — by design).

### Infrastructure and Services

| Service | Status (verified) |
|---|---|
| Firebase / Supabase / cloud | **Absent** — no `google-services.json`, `firebase_options.dart`, or `.env` anywhere |
| Analytics / crash reporting | None. `debugPrint` in phone host (via `adb logcat`) is the only diagnostics |
| CI/CD | `.github/workflows/build.yml`: `web` job (analyze → test → `build web --pwa-strategy none` → Pages); `apk` job (`build apk --release` → artifact; Release asset on `v*` tags). Java Temurin 17, `flutter-action@v2` stable |
| Third-party / AI APIs | None |

---

## 4. Project Architecture

```text
Flutter App (one codebase: Android + Web)
│
├── UI ── lib/screens/ (Home, History, Lent, Menu, Sync, Add, Scan, Lock)
│   └── lib/widgets/ (page, glass, entry_actions, delete)
├── Global state ── ExpenseStore (ChangeNotifier via provider)
│   ├── per-screen setState; ValueNotifier<int> hits (host request counter)
│   └── WidgetsBindingObserver (resume → LinkEngine.syncNow + reminders + auto-SMS)
├── Domain ── lib/models.dart (Category, Txn, Loan, Topup, Repayment, Project, Snapshot)
├── Persistence ── SharedPreferences JSON strings (no DB engine)
├── Sync (all exchange atomic Snapshot JSON; last-write-wins)
│   ├── FileSync (share/file_picker) ── manual
│   ├── WifiHost/WifiClient (shelf + http, x-sync-pin) ── direct
│   ├── LinkClient/LinkEngine/LinkStore ── mailbox relay (Node relay OR phone host)
│   ├── PhoneHost (shelf: webapp + link API + /api/ping + mDNS URL)
│   ├── SMS import (SmsBridge → sms_parse → store) + Reminders (local notifications)
└── Native Android (Kotlin, 3 MethodChannels)
    ├── expense/mdns → NsdManager (MdnsHelper.kt)
    ├── expense/sms  → Telephony inbox (SmsBridge.kt)
    └── expense/perm  → camera grant (MainActivity.kt)
```

**Data flow:** UI reads `ExpenseStore` via `watch`/`Consumer`; mutations call store
methods → in-memory lists update → `_touch()` stamps `updatedAt` (UTC ISO) → `_saveAll()`
writes 5 prefs keys → `notifyListeners()` rebuilds → `LinkEngine` listener debounces 3 s
and pushes/pulls if linked. Imports (`store.dart:862` `importSnapshotString`) compare
`updatedAtTime`; a newer remote **replaces all four collections atomically** (backup
first), otherwise `Already up to date`. Snapshots are never partially merged.

---

## 5. Project Folder Structure

```text
Expense/
├── lib/ (34 files)
│   ├── main.dart | models.dart | store.dart | format.dart | security.dart | version.dart
│   ├── screens/ (8: home, history, lent, menu, sync, add, scan, lock)
│   ├── sync/ (13: file, link_store, link_sync, mdns, permissions, phone_host[_io|_stub],
│   │           relay_client, reminders, sms, sms_parse, wifi_client, wifi_host[_io|_stub])
│   └── widgets/ (4: page, glass, entry_actions, delete)
├── android/ (manifest, 3 Kotlin files, Kotlin-DSL Gradle; appId com.dhadda.expense)
├── web/ (Flutter shell; manifest.json = Dhadda, #009688)
├── assets/icon/ (launcher sources) + assets/webapp/ (checked-in web build, 43 files)
├── server/serve-expense.cjs (zero-dep Node LAN host + relay)
├── test/ (12 files, 49 tests) + .github/workflows/build.yml
├── windows/ (Flutter scaffold, no custom code) + fastlane/metadata/ (texts only)
└── pubspec.yaml / pubspec.lock / analysis_options.yaml / README.md (stock template)
```

Generated/ignored (not detailed): `build/`, `.dart_tool/`, `.idea/`, `*.log` transcripts,
stub `package-lock.json` (server has no npm deps).

---

## 6. Important Files

| File | Purpose | Technology | Related feature |
|---|---|---|---|
| `pubspec.yaml` | Deps (23 direct), version `1.3.1+2`, `assets/webapp/` entries, icon config | Flutter | whole app |
| `lib/main.dart` | Entry, M3 theme, `RootShell` 4 tabs, PIN gate, auto-SMS, resume sync | provider | shell, lock, sync |
| `lib/store.dart` | Global state + JSON persistence + snapshots + backups (895 lines) | provider/prefs | everything |
| `lib/models.dart` | Entities + `Snapshot` protocol (472 lines) | dart:convert | data + sync |
| `lib/version.dart` | `kAppVersion 1.3.1`, `kBuildStamp 2026-09-06 (hostfix)` | Dart | About screen |
| `lib/security.dart` | `PinVault`: SHA-256 PIN (`expense_pin_hash_v1`) + biometric flag | crypto/prefs | PIN lock |
| `lib/format.dart` | money/date/greeting, strict `parseAmount` | intl | display + validation |
| `lib/screens/home_screen.dart` | Dashboard: stats, pie, budgets, recent | fl_chart | overview |
| `lib/screens/history_screen.dart` | Search/filter/CSV/reorder/events (849 lines) | slidable | history |
| `lib/screens/lent_screen.dart` | Lent/borrowed ledger + reminders (618 lines) | notifications | loans |
| `lib/screens/menu_screen.dart` | Settings: theme, PIN, currency, SMS, erase (795 lines) | local_auth | settings |
| `lib/screens/sync_screen.dart` | Sync hub: relay, PC host, file, WiFi (936 lines) | shelf/http/QR | all sync |
| `lib/screens/add_screen.dart` | 3-tap entry + category reorder | Flutter | data entry |
| `lib/screens/scan_screen.dart` | QR scan + manual paste | flutter_zxing | pairing |
| `lib/screens/lock_screen.dart` | PIN pad | Flutter | lock |
| `lib/sync/phone_host_io.dart` | Phone web+API server, `/api/ping`, hardened middleware | shelf/router | Show on PC |
| `lib/sync/link_store.dart` | Mailbox: 7-day TTL, 50 boxes, 8-char IDs | pure Dart | relay protocol |
| `lib/sync/link_sync.dart` | `LinkEngine` auto-converge | http/link | auto-sync |
| `lib/sync/relay_client.dart` | Link client, `QrV2`, `decideSync`, error mapping | http | relay pairing |
| `lib/sync/wifi_host_io.dart` / `wifi_client.dart` | Direct PIN sender / receiver | shelf/http | Direct WiFi |
| `lib/sync/file_sync.dart` | Share/file-picker backup + CSV builder | share_plus | file sync |
| `lib/sync/sms_parse.dart` / `sms.dart` | Bank SMS parser + inbox bridge client | MethodChannel | SMS import |
| `lib/sync/reminders.dart` | One-time loan notifications | local notifications | reminders |
| `lib/sync/mdns.dart` / `permissions.dart` | mDNS + camera channel clients | MethodChannel | .local, scan |
| `lib/widgets/` | `page`, `glass`, `entry_actions`, `delete` | Flutter | shared UI |
| `android/app/src/main/AndroidManifest.xml` | Label `Dhadda`, 8 permissions, no services | Android | install surface |
| `android/.../MainActivity.kt` | 3 MethodChannels, `FlutterFragmentActivity` | Kotlin | bridge |
| `android/.../MdnsHelper.kt` | NsdManager advertiser + multicast lock | Kotlin | mDNS |
| `android/.../SmsBridge.kt` | Inbox query, 90-day, ≤300 rows | Kotlin | SMS import |
| `android/app/build.gradle.kts` | `com.dhadda.expense`, Java 17, debug-key release, desugar | Gradle KTS | build |
| `android/settings.gradle.kts` | AGP `9.1.0`, KGP `2.4.0` | Gradle | build |
| `server/serve-expense.cjs` | LAN static host + relay (zero-dep) | Node.js | PC sync |
| `.github/workflows/build.yml` | CI: web→Pages, apk→artifact/Release | GH Actions | CI/CD |
| `web/manifest.json` | PWA identity (`Dhadda`, `#009688`) | Web | web install |
| `assets/webapp/` | Embedded web bundle served by phone host | Flutter web | Show on PC |

## 7. Application Screens and Navigation

Shell: `RootShell` (`lib/main.dart`) — 4 tabs (`NavigationBar`; `NavigationRail` when
width > 900) over an `IndexedStack`. AppBar shows a time-aware greeting on Home
(`homeGreeting`) plus a sync icon that pushes `SyncScreen`. FABs/dialogs use
`showDialog`/`showDatePicker`/`showTimePicker`.

| Screen (file) | Purpose | Reached via | Navigates to | State / data ops |
|---|---|---|---|---|
| Home (`home_screen.dart`) | Month stats, pie, budgets, recent | Tab 0 | Add (button), edit sheet (tap txn), Sync (pull-to-refresh) | `watch` store; `monthSpend/monthIncome/spendByCategory` |
| History (`history_screen.dart`) | Search/filter/edit/reorder/export | Tab 1 | Edit sheet, category/event dialogs, calendar picker | local filter state; CRUD + `moveCategoryTo`, CSV |
| Lent (`lent_screen.dart`) | Lent/borrowed ledger + reminders | Tab 2 | Person/topup/repayment/reminder dialogs | `addLoan/addBorrow/lendMore/addRepayment/setReminderAt/deleteLoan` |
| Menu (`menu_screen.dart`) | Settings, PIN, SMS, erase, About | Tab 3 | Sync screen, PIN/biometric/SMS dialogs | prefs-backed setters; `eraseAll` |
| Sync (`sync_screen.dart`) | Relay, PC host, file, WiFi, backups | AppBar icon, Menu card | Scan screen, system share/picker | `LinkEngine` + local busy/poll state |
| Add (`add_screen.dart`) | Create txn | Home Add button | (pops on save) | `addTransaction` |
| Scan (`scan_screen.dart`) | QR pairing input | Sync screen | (pops with raw string) | camera permission |
| Lock (`lock_screen.dart`) | PIN gate | Launch (if PIN set) | app content on unlock | `PinVault.verify` |

```text
Launch → [PIN?] → Lock → Tabs(Home|History|Lent|Menu)
Home → Add ⇄ Home · History ⇄ edit sheet · Any tab →(AppBar) Sync ⇄ Scan
Sync ⇄ share/file-picker · Lent ⇄ loan dialogs · Menu ⇄ Sync / PIN / SMS dialogs
```

## 8. Data Models

All in `lib/models.dart`; persisted as JSON inside SharedPreferences (see §9);
transported atomically inside `Snapshot`. No IDs are server-issued (`uuid` v4 locally).

- **Category** `{id, name, icon (codePoint int), color (ARGB int), budget double}`.
  8 seeds (`defaultCategories()`); `fuel` auto-inserted before `other` on legacy loads;
  `other` is protected from deletion (its txns' fallback); `iconData`/`colorValue`
  resolve via `kIconChoices` (24) / `kColorChoices` (12).
- **Txn** `{id, type expense|income, amount, categoryId, date (epoch ms), note, mode
  cash|bank|card|ewallet, projectId}`. Sorted desc by date after every load/import.
- **Loan** `{id, person, lent, dateLent, dueDate?, note, repayments[], topups[],
  kind lent|borrowed, remindAt (epoch ms, 0 = off)}`; derived `totalLent/returned/
  pending/settled`; legacy `remindFreq` strings migrate to one-time tomorrow-9AM.
- **Topup / Repayment** `{id, amount, date, note}` — same shape, opposite direction.
- **Project** `{id, name, note, created, icon, color}` — event pot; `Txn.projectId` is
  the only relation (no join table; delete untags).
- **Snapshot** `{version (=kSnapshotVersion 1), updatedAt (UTC ISO), deviceId,
  deviceName, categories[], transactions[], loans[], projects[]}` with
  `encode()/decode()` and `updatedAtTime`. The **entire sync contract** is this object.

## 9. Database

- **Technology:** none — no SQLite/Drift/Hive/ObjectBox. `SharedPreferences` holding
  plain JSON strings (`lib/store.dart:13-18`).
- **Keys (verified):** `expense_cats_v1`, `expense_txns_v1`, `expense_loans_v1`,
  `expense_projects_v1`, `expense_meta_v1` (deviceId/deviceName/relay/link/currency/
  theme/accent/materialYou/userName/sms prefs/updatedAt/lastSynced), `expense_backups_v1`
  (string-list, newest 5 snapshots). Security: `expense_pin_hash_v1`,
  `expense_biometric_v1` (`lib/security.dart:10-11`). SMS: `expense_sms_ids_v1`
  (≤500 ids, `lib/sync/sms.dart:11`).
- **Relationships:** application-level only (`categoryId`, `projectId` strings; loan
  sub-lists embedded). No foreign keys, no indexes, no migrations framework (only
  ad-hoc legacy handling: fuel insert, `remindFreq` migration, empty-categories reseed).
- **Caching:** in-memory lists are the cache; `loaded` flag gates UI.
- **Offline behavior:** fully offline-first — every feature works without network.
- **Synchronization:** atomic whole-snapshot replace on newer `updatedAt`
  (`store.dart:862-888`); 5 auto-backups before each replace; `restoreBackup(i)`
  force-imports. See §"Sync Conflict Analysis" for loss semantics.

## 10. API and Networking

- **Architecture:** three tiny LAN HTTP APIs (shelf server-side, `http` client-side),
  JSON only, no versioning headers, no API keys. Base URL = discovered LAN origin
  (`http://<ip>:<port>`), never hardcoded (old loopback-in-QR bug fixed via server-side
  `lanOrigin()` in `server/serve-expense.cjs`).
- **Link protocol** (PC relay + phone host identical): `POST /api/sync/link`
  `{pin,deviceId,snapshot,name,time} → {link,origin}`; `POST /api/sync/push` (same +
  `link`); `GET /api/sync/pull?link&pin&deviceId → {peers[]}` (self excluded);
  `POST /api/sync/unlink`; legacy offer/answer (`/offer`, `/session`, `/answer`,
  `/close`) retained in relay client + Node relay. PINs 4–12 chars; boxes 8-char IDs,
  7-day sliding TTL, 50-box cap (`lib/sync/link_store.dart`).
- **Direct WiFi:** `GET /meta → {updatedAt}`, `GET /snapshot → snapshot JSON`,
  `POST /snapshot` (body = snapshot; auth header `x-sync-pin`); sender auto-closes
  after 5 min (`lib/sync/wifi_host_io.dart`).
- **Phone host extras:** `GET /api/ping → {ok, serve}`; static `assets/webapp/*`
  with MIME map + `no-cache` + SPA fallback (`lib/sync/phone_host_io.dart`).
- **QR contracts:** direct `EXPENSESYNC::<url>::<pin>`; link
  `EXPENSESYNC2::<origin>::<code>::<pin>`; phone host = plain URL string.
- **Client behavior:** 8–20 s timeouts; 403 → wrong PIN, 404 → link gone (clears local
  link), 410 → already answered; `friendlySyncError` maps socket/timeout/DNS to
  same-WiFi guidance (`lib/sync/relay_client.dart`). No retries except `LinkEngine`
  cadence (3 s debounce, 15 s poll, on-resume) and two mDNS attempts.
- **Realtime/WebSockets:** none — polling only.

## 11. Authentication

There is **no account system**. Exactly two mechanisms exist:

1. **Local app lock (implemented):** optional 4-digit PIN, SHA-256 of
   `'expense-tracker::pin::v1::<pin>'` stored in prefs (`lib/security.dart`);
   biometric (`local_auth`, `biometricOnly: true`, reason `Unlock Expense`) is an
   unlock shortcut gated behind the PIN (`lib/main.dart`, `menu_screen.dart`).
   Lock state is in-memory only; nothing leaves the device.
2. **LAN pairing PINs (implemented):** per-session 6-digit sender PINs, per-link user
   numeric PINs (4–12 chars), 8-char link codes. Transmitted over plain HTTP on the
   LAN and inside QR strings. No tokens, no expiry except box TTL/session close, no
   logout — "Stop"/"Unlink" destroys the server-side box. See §"Security Threat Model".

No signup/login/logout, no OAuth, no protected routes beyond the PIN gate.

## 12. State Management

```text
ExpenseStore (ChangeNotifier, provider) → Consumer/watch/read → widgets
per-screen setState (tabs, month, filters, dialogs, lock, sync busy/poll)
ValueNotifier<int> hits + ValueListenableBuilder (host request counter)
WidgetsBindingObserver → resume: LinkEngine.syncNow + Reminders.refresh + auto-SMS
```

- **UI state:** `notifyListeners()` after every mutation; `loaded` flag gates first
  paint; local ephemeral state stays in `State` classes.
- **Loading:** `!loaded` spinner; `_busy` flags disable sync buttons; 2 s link-poll
  spinner. No skeleton screens, no global loader.
- **Errors:** human-readable strings (snackbars/dialogs), never raw exceptions;
  `friendlySyncError` for network; all platform/IO boundaries `try/catch`.
- **Persistent state:** entire domain + settings in the 6 prefs keys (§9); link session
  (`relayOrigin/linkId/linkPin/linkPeer/linkStatus`) survives restarts (`link_test.dart`).
- **Shared/global:** single `ExpenseStore` instance at app root; `onLoansChanged`
  callback fans out to `Reminders.refresh`. No Riverpod/Bloc/GetX (do not migrate
  without a concrete reason — see §"Architecture Scaling Assessment").

## 13. Dependencies

All versions are pubspec constraints (resolved pins live in `pubspec.lock`):

| Name | Constraint | Purpose | Used in |
|---|---|---|---|
| shared_preferences | ^2.3.2 | all persistence | `store.dart`, `security.dart`, `sms.dart` |
| provider | ^6.1.2 | state | `main.dart`, screens |
| uuid | ^4.5.1 | txn/loan/project IDs | `store.dart` |
| intl | ^0.20.2 | money/date format | `format.dart` |
| crypto | ^3.0.7 | PIN SHA-256 | `security.dart` |
| share_plus | 13.2.1 exact | export share sheet | `file_sync.dart` |
| file_picker | ^12.2.0 | import JSON | `file_sync.dart` |
| shelf / shelf_router | ^1.4.2 / ^1.1.4 | on-device servers | `wifi_host_io.dart`, `phone_host_io.dart` |
| http | ^1.2.2 | sync clients | `wifi_client.dart`, `relay_client.dart` |
| qr_flutter | ^4.1.0 | render codes | `sync_screen.dart` |
| fl_chart | ^0.69.0 | Home pie | `home_screen.dart` |
| local_auth | ^3.0.2 | biometric | `main.dart`, `menu_screen.dart` |
| dynamic_color | ^2.1.0 | Material You | `store.dart` |
| flex_color_picker | ^4.0.0 | custom accent | `menu_screen.dart` |
| wakelock_plus | ^1.8.0 | serving awake | `sync_screen.dart` |
| flutter_local_notifications | ^22.3.0 | reminders | `reminders.dart` |
| timezone / flutter_timezone | ^0.11.1 / ^5.1.0 | zoned schedules | `reminders.dart` |
| flutter_slidable | ^4.0.3 | swipe delete | `history_screen.dart` |
| flutter_zxing | ^3.0.1 | QR scan | `scan_screen.dart` |
| flutter_test / flutter_lints / flutter_launcher_icons | SDK / ^6.0.0 / ^0.14.4 | tests, lints, icons | `test/`, `analysis_options.yaml`, `pubspec.yaml` |

Node relay: **zero dependencies** (built-ins only). No unused package confirmed.

## 14. Configuration

- **App ID / label:** `com.dhadda.expense`, `Dhadda` (`build.gradle.kts`,
  `AndroidManifest.xml:13`).
- **versionName / versionCode:** `1.3.1` / `2` (from `pubspec.yaml` `1.3.1+2`).
- **minSdk / targetSdk / compileSdk:** delegated to the Flutter plugin
  (`flutter.minSdkVersion` etc.) — exact numbers `NOT VERIFIED` in the repo (resolve
  via `flutter build` output or the installed Flutter 3.47 SDK).
- **Kotlin 2.4.0, AGP 9.1.0** (`settings.gradle.kts`), **Gradle 9.3.1** (wrapper),
  **JVM 17**, desugar `2.1.4`. CI Java: Temurin 17.
- **Build variants:** only `release` block, signed with **debug keys** + TODO for real
  signing (`build.gradle.kts`). No flavors, no per-ABI splits in Gradle (splits are
  passed as `flutter build` flags instead). No `.env`, no flavors config.
- **Lints:** `package:flutter_lints/flutter.yaml`, empty custom rules
  (`analysis_options.yaml`); `flutter analyze` is clean and CI-gated.
- **Web/Pages:** `--pwa-strategy none --no-tree-shake-icons --base-href /<repo>/` (CI).
- **Secrets placeholders:** none needed — the project holds no API keys/tokens by
  design (`API_KEY=<none — no remote services>`).

## 15. What Has Been Completed So Far

Chronological/logical, verifiable from code + CI + tests:

1. Scaffolded Flutter app (Android + Web + Windows scaffold), 4-tab shell, M3 theming.
2. JSON-in-prefs persistence + `Snapshot` protocol + file export/import + 5 backups.
3. Home/History/Add with categories, budgets, search, CSV, reorder, edit sheets.
4. Lent/borrowed ledger with top-ups, repayments, autocomplete, one-time reminders.
5. Projects/events, Fuel auto-migration, `other`-last ordering rule.
6. PIN lock (hashed) + biometric shortcut + lock screen.
7. Direct-WiFi PIN sync (shelf sender + http receiver + QR v1 + e2e test).
8. Link-mailbox relay (pure-Dart `LinkStore`, Node PC relay, `QrV2`, `LinkEngine`
   auto-sync) replacing/augmenting one-shot offer/answer.
9. Phone-hosted "Show on PC" (bundled webapp serving, wakelock, hits counter,
   `/api/ping`, hardened 500s) + native mDNS advertiser.
10. SMS import (native inbox bridge + pure-Dart bank parsers + allowlist + auto mode).
11. CI (Pages + APK + tagged releases), launcher icons, Play listing texts.
12. 49-test suite incl. widget smoke tests at phone + desktop sizes.

Key decisions (why, where verifiable): no backend/no DB engine (zero-cost constraint —
prefs + JSON nearest the constraint); atomic whole-snapshot sync (simplicity over merge —
`store.dart:862`); `flutter_zxing` over ML Kit (F-Droid compatibility, no Play Services);
dual `*_io`/`*_stub` files behind `dart.library.io` (web cannot host — compile-time
separation); mDNS best-effort with IP primary (Windows `.local` often unresolvable).

## 16. Current Known Problems

Code/log-verified only (zero `TODO/FIXME` markers in `lib/`):

- **Release signed with debug keys** (`android/app/build.gradle.kts` + TODO) — blocks
  any store submission.
- **Embedded web bundle stale** (`assets/webapp/version.json` = `1.3.0+1` vs app
  `1.3.1+2`); no script copies `build/web → assets/webapp/` (grep finds no step).
- **Old debug build log** (`.apk-build.log`) shows `SmsBridge.kt:44`
  `onRequestPermissionsResult` missing-`override` failing `compileDebugKotlin`;
  current release builds succeed — re-verify before next debug run.
- **mDNS unreliable off-device:** `dhadda.local` fails on Windows w/o Bonjour and on
  networks with multicast/AP isolation; IP fallback is the supported path.
- **500-class risk class closed, not root-caused on-device:** the 2026-09-06
  `hostfix` hardened the middleware (explicit `/`, `/api/ping`, safe `hits` bump,
  informative error bodies) but the triggering request never reached the app
  (counter stayed 0) — see §"Sync Conflict Analysis" scope note: network, not code.
- **Manifest comment drift:** `READ_SMS` comment claims "nothing auto-read", but Auto
  SMS mode exists (`lib/main.dart:115-168`).
- **Doc drift:** `web/index.html` title/description still say `expense`/`A new Flutter
  project.`; `README.md` is the stock template; `package-lock.json` is a stub.
- **Untested areas:** no integration tests; no on-device LAN/mDNS/SMS/notification
  tests (all platform seams mocked or best-effort); no backup-restore-across-versions
  test; large-history performance unmeasured (see persistence assessment).

## 17. Decisions That Should Not Be Accidentally Changed

- Package `com.dhadda.expense` + label `Dhadda` (installed-data identity).
- prefs keys (`expense_*_v1`) and JSON shapes — renames orphan user data.
- `Snapshot` fields + whole-snapshot replace semantics — all four transports + tests
  depend on it (`snapshot_test.dart`, `wifi_sync_e2e_test.dart`).
- QR prefixes `EXPENSESYNC::` / `EXPENSESYNC2::` and plain-URL host QR — cross-version
  pairing breaks if altered.
- `other` category protected + last; Fuel-before-Other migration.
- PIN exactly 4 digits, SHA-256 `expense-tracker::pin::v1::` format, biometric as
  unlock-only shortcut (never a replacement credential store).
- Port preference 8080 → random; subnet preference 192.168 → 10 → 172; 7-day box TTL;
  5-backup cap; 500 SMS-ID cap; settled threshold `0.005`.
- `flutter_zxing` (no ML Kit), `dart.library.io` stub split, mDNS best-effort + IP
  primary, `--pwa-strategy none` for the embedded bundle.

## 18. Development Conventions

- **Naming:** `expense_*_v1` prefs keys; `k*` constants (`kAppVersion`, `kIconChoices`);
  `*_screen.dart` / `*_io.dart` / `*_stub.dart` suffixes; `show*` dialog helpers.
- **Packages:** flat `lib/` (`screens/`, `sync/`, `widgets/`); no barrel files except
  `format.dart` re-exporting models.
- **State:** single `ChangeNotifier` store, `watch` for rebuilds / `read` in callbacks,
  `notifyListeners()` inside every mutator after `_touch()`; ephemeral UI in `setState`.
- **Errors:** `try/catch` at every platform/IO seam returning safe defaults; UI gets
  short human strings; `friendlySyncError` centralizes network mapping; notifications
  and hosting must never throw (`reminders.dart:11-12`).
- **Sync:** JSON over HTTP, `updatedAt` compare, backup-before-replace, newest-peer-wins;
  PINs as plain fields/headers, CORS `*` (LAN-only assumption — see threat model).
- **UI:** `pageInsets`/`kPageMaxWidth 880` centering, `GlassBox` frosted filters,
  `showEntryActions` + `deleteWithUndo` shared flows, `confirmDeleteTxn` before
  destructive acts, `Currency: <name>` labels — keep the established wording.

## 19. How to Build and Run the Project

- **Required:** Flutter stable (3.47.2 observed; Dart `^3.13.2`), JDK 17, Android SDK
  (or the CI path below), Node.js ≥ 18 (`NOT VERIFIED` minimum; 25.5.0 observed) for
  the PC relay only. No secrets, no `.env`, no Firebase setup — by design.
- **Setup:** `flutter pub get` at repo root. Accept Android licenses once
  (`flutter doctor --android-licenses`).
- **Static checks + tests (also what CI runs):**
  `flutter analyze` → must be clean; `flutter test` (49 tests, ~12 files) →
  `flutter test test/<file>.dart` for one file.
- **Run on device:** `flutter run` (Android; grant camera/SMS/notifications when the
  corresponding feature is used). Web preview: `flutter run -d chrome`.
- **Build:** `flutter build apk --release --split-per-abi --obfuscate
  --split-debug-info=build\debug-info` (per-ABI APKs incl. `app-arm64-v8a-release.apk`,
  ~37 MB last measured — `NOT VERIFIED` in current tree); plain `flutter build apk
  --release` matches CI; `flutter build appbundle --release` for Play (see readiness).
- **Embedded web bundle:** `flutter build web --release --no-tree-shake-icons
  --pwa-strategy none`, then **manually** copy `build/web/` → `assets/webapp/` (no
  script exists — this manual step is why the bundle lags; see reproducibility §).
- **PC relay:** `node server/serve-expense.cjs build/web 8080`, open the printed LAN
  URL on the phone (same WiFi, no VPN). Phone host needs no PC: Sync → Show on PC.

## 20. Testing

- **Runner:** `flutter_test` via `flutter test`; CI runs full suite after analyze.
- **12 files / 49 tests:** `greeting` (2), `link_store` (4), `link` (2), `mdns` (3,
  mocked channel), `pin` (2, mocked prefs), `projects` (6), `relay` (4), `settings`
  (10), `sms_parse` (8), `snapshot` (4), `widgets_smoke` (2 `testWidgets`, phone
  360×740 + desktop 1280×800 layout audit of all screens), `wifi_sync_e2e` (2, real
  shelf↔http over localhost + PIN). See `test/` for exact names.
- **Gaps:** no `integration_test/`; no on-device LAN/mDNS/SMS/notification tests;
  no cross-version backup-restore test; no performance test for large histories;
  `LinkEngine`'s timers/debounce covered only indirectly via `link_test.dart`.

## 21. Current Technical Status

**Beta / late MVP, not production-ready.** Rationale: all planned single-user flows are
implemented, analyzed clean, and unit/widget-tested (49/49), but release signing is
debug keys, the embedded web bundle is stale, cross-device LAN behavior is verified
only ad hoc, there are no integration tests, and Play blockers (signing, AAB,
READ_SMS declaration, data-safety form) are untouched. The architecture (prefs JSON,
atomic snapshots) is adequate for a single user's scale but has documented loss and
growth limits (see the two analysis sections below).

## 22. Recommended Next Steps

- **P0 — critical:** (1) Real release signing + `appbundle` build; decide Play vs
  sideload/F-Droid (READ_SMS likely untenable on Play — see readiness). (2) Automate
  `build/web → assets/webapp/` in CI or a script so the bundle cannot lag again.
  (3) Close the Show-on-PC LAN verification loop (phone-local browser test, then PC
  `/api/ping`, then app) and record the outcome.
- **P1 — important:** Fix manifest comment drift (`READ_SMS` auto mode); `web/index.
  html` title/description; `README.md`; re-run a debug build to clear/confirm the old
  `SmsBridge` override failure; add `android:allowBackup`/`dataExtractionRules`
  decision (financial data currently auto-backs-up by default).
- **P2 — improvement:** Maintainer UI polish batch (calendar size/alignment, pie-hint
  removal, chart/button order, icon packs, expansion animations, accent-picker
  redesign); cross-version restore test; large-history perf measurement (5k–20k txns).
- **P3 — optional:** Fastlane `Fastfile`/`Appfile`; desktop-native packaging; PWA
  install polish for the hosted web UI; analytics-free usage stats (`NOT VERIFIED`
  need — maintainer decides).

## 23. AI Handoff Instructions

You are continuing **Dhadda**, a Flutter offline-first single-user expense tracker
(`com.dhadda.expense`, v1.3.1+2). Everything persists as JSON in SharedPreferences
(`lib/store.dart`); there is no backend, no DB engine, no auth server. Sync = atomic
whole-`Snapshot` exchange, last-write-wins — read `lib/models.dart` (`Snapshot`) and
`lib/store.dart:862-888` before touching any sync code, and read §"Sync Conflict
Analysis" below so you never promise merge behavior that does not exist. State is
`provider` + `ChangeNotifier` (+ `setState`, one `ValueNotifier`); do not introduce a
new state library. Follow existing conventions (§18): `expense_*_v1` keys,
`show*` dialogs, `friendlySyncError` mapping, backup-before-replace, `other`-last.
Before modifying code, inspect the cited files; `flutter analyze` must stay clean and
`flutter test` must stay 49/49 (add tests for new logic). Never touch: package name,
prefs keys/JSON shapes, QR prefixes, PIN format, sync replace semantics. Known limits:
whole-file rewrites on every keystroke (fine at this scale), sync can drop a slower
device's edits (by design — warn, don't silently "fix"), mDNS is best-effort with IP
primary, the embedded web bundle is manually copied (rebuild + copy or it lags). Top
priorities: release signing/AAB decision, web-bundle automation, LAN verification
closure, then the UI polish batch. Documentation-only tasks must not change code,
deps, or files outside the requested doc.

## 24. Final Project Snapshot

PROJECT: Dhadda — offline-first single-user Flutter expense tracker (Android + hosted
Flutter-web), $0 backend, lent/borrowed ledger, LAN snapshot sync, SMS import.

CURRENT STATUS: Beta / late MVP — feature-complete for single user, 49/49 tests,
analyze clean; not production-ready (debug signing, stale web bundle, Play blockers).

FRONTEND / ANDROID STACK: Flutter 3.47.2 + Dart 3.13.2, Material 3, provider/
ChangeNotifier, dart:convert JSON, shelf+shelf_router servers, http client, fl_chart,
qr_flutter+flutter_zxing, local_auth, dynamic_color, flex_color_picker, wakelock_plus,
flutter_local_notifications+timezone, slidable, file_picker+share_plus; Kotlin bridge
(3 MethodChannels); KGP 2.4.0, AGP 9.1.0, Gradle 9.3.1, JDK 17.

BACKEND STACK: None hosted. Optional local: zero-dep Node LAN relay
(`server/serve-expense.cjs`) + in-app shelf servers (direct WiFi, phone host) sharing
one link-mailbox protocol (7-day TTL, PIN-gated, CORS `*`).

DATABASE: No engine. SharedPreferences JSON: `expense_cats/txns/loans/projects/meta/
backups_v1` + PIN/biometric/SMS-ID keys; atomic whole-snapshot replace; 5 backups.

AUTHENTICATION: No accounts. Optional 4-digit PIN (SHA-256 + static salt, local only)
+ biometric unlock shortcut; LAN pairing via per-link numeric PINs over plain HTTP.

ARCHITECTURE: Single `ExpenseStore` (ChangeNotifier) → provider → 8 screens; models in
`models.dart`; sync transports exchange atomic `Snapshot`s (last-write-wins); native
Kotlin only for mDNS/SMS/camera.

MAJOR COMPLETED FEATURES: Home pie/budgets/recent; Add with reorderable categories;
History search/filter/CSV/reorder/events; lent/borrowed ledger + one-time reminders;
projects; PIN+biometric; themes/Material You/currency; file backup; direct-WiFi sync;
link-relay sync + auto engine; Show-on-PC hosting + mDNS; SMS import; CI (Pages+APK).

PARTIALLY COMPLETED: Windows `.local` resolution (environmental); embedded web bundle
freshness (stale 1.3.0 vs app 1.3.1); store-readiness (texts only, debug signing).

PLANNED: UI polish batch (calendar, pie hint, chart order, icon packs, animations,
accent picker); release signing/AAB route; web-bundle automation; integration tests.

KNOWN ISSUES: debug-key release signing; stale `assets/webapp/` + no copy script;
old debug `SmsBridge` override failure in stale log; mDNS blocked on some networks;
manifest `READ_SMS` comment drift; stock README/web title; no integration tests.

TOP PRIORITIES: P0 signing+AAB/store-route decision, web-bundle automation, LAN
verification closure; P1 manifest/README/title fixes + backup-config decision; P2 UI
polish + perf measurement.

IMPORTANT FILES: `lib/store.dart`, `lib/models.dart`, `lib/main.dart`,
`lib/sync/phone_host_io.dart`, `lib/sync/link_store.dart`, `lib/sync/link_sync.dart`,
`lib/sync/relay_client.dart`, `lib/security.dart`, `AndroidManifest.xml`, the 3
Kotlin files, `build.gradle.kts` files, `server/serve-expense.cjs`, `pubspec.yaml`,
`.github/workflows/build.yml`, `test/` (12 files).

IMPORTANT ARCHITECTURAL RULES: never rename package/prefs keys/QR prefixes; never
change snapshot replace semantics or PIN format; keep `other` last + protected;
mDNS best-effort with IP primary; `flutter analyze` clean + tests green; no new state
library without concrete cause.

NEXT RECOMMENDED TASK: Decide the distribution route (Play vs sideload/F-Droid),
then implement real release signing (or document sideload), add the AAB build, and
automate `build/web → assets/webapp/` so the embedded bundle can never lag again.

---

## Data Persistence Risk Assessment

Exact store inventory (all keys verified by grep — `lib/store.dart:13-18`,
`lib/security.dart:10-11`, `lib/sync/sms.dart:11`):

**Critical financial/domain data** (loss = money records gone):
`expense_cats_v1` (categories + budgets), `expense_txns_v1` (every transaction),
`expense_loans_v1` (lent/borrowed principals, repayments, top-ups, reminders),
`expense_projects_v1` (events), `expense_backups_v1` (last 5 full snapshots — the only
safety net). All plain JSON, unencrypted at rest.

**Application preferences** (loss = annoyance, reseedable): inside
`expense_meta_v1` — `currency, themeMode, accent, materialYou, userName, smsMode,
smsSenders, deviceId/deviceName, relayOrigin/linkId/linkPin/linkPeer/linkStatus,
updatedAt, lastSynced`.

**Security-related data:** `expense_pin_hash_v1` (SHA-256 hex of
`expense-tracker::pin::v1::<pin>`, `lib/security.dart`), `expense_biometric_v1`
(`true` flag), `expense_sms_ids_v1` (≤500 imported SMS ids — dedup, not secret).

**Growth behavior (read the code, not measured):** every mutation calls `_saveAll()`,
which rewrites **all five data keys in full** (`store.dart` `_touch`/`_saveAll`);
every `importSnapshotString` pushes a **full extra snapshot copy** into the backups
list. Cost per keystroke is therefore O(entire history), and total prefs footprint is
roughly ~6× history size (live keys + 5 backups). SharedPreferences loads everything
into memory at startup; there is no pagination, no index, no compaction. At hundreds
to low-thousands of transactions this is fine on modern phones; at tens of thousands
(or photo/note-heavy use — notes are unbounded strings) expect slower startup, UI
jank on save (writes are async but `notifyListeners` rebuilds are sync), and rising
risk of a torn write killing a whole key (a corrupt key decodes to defaults/empty —
`snapshot_test.dart` proves corrupt snapshots throw rather than half-load, which is
safe but means **one bad byte can discard one whole collection**, backups aside).
No encryption: anyone with the unlocked device, a backup file, or (by Android
default) the Google-Drive Auto Backup can read every transaction (see threat model).
Do not modify the implementation per task rules — but any future growth work should
start here (append-only log, key rotation/compaction, encrypted store).

## Sync Conflict Analysis

Verdict first: **yes, a transaction can be lost — by design.** There is no merge;
there is only whole-snapshot replacement by wall-clock `updatedAt`.

Scenario trace, citing the exact code:

1. A and B hold identical snapshots (`updatedAt = T0`).
2. A (offline) adds txn X → A's `_touch()` sets `updatedAt = T1` (`lib/store.dart`).
3. B (offline) adds txn Y → B's `updatedAt = T2`.
4. They sync. Whichever snapshot arrives with the strictly greater timestamp wins:
   - File/direct import: `importSnapshotString` (`store.dart:862-888`) —
     `if (!force && !r.isAfter(l)) return 'Already up to date'`; otherwise it
     **overwrites all four collections** (`transactions = remote.transactions`, …)
     and stamps the winner's `updatedAt`. The loser's exclusive txn is gone from
     live data (a pre-replace backup is pushed — recoverable only via manual
     `restoreBackup`, which itself force-overwrites the other side).
   - Link auto-sync: `_adoptPeers` (`sync_screen.dart:167-181`) and `LinkEngine`
     (`link_sync.dart:83-89`) pick the peer slot with the newest `timeValue` and
     import only if `best.timeValue.isAfter(localTime)` — same newer-wins outcome;
     `decideSync` (`relay_client.dart:161`) is the same comparison for offer/answer.
5. If `T1 == T2` (same millisecond) or clocks skew, `isAfter` is false both ways:
   both sides report "up to date" and **each keeps only its own txn — silent
   permanent divergence** until a later edit re-stamps one side.

Equal-timestamp ties, clock skew across devices, and the 5-backup rotation (a 6th sync
evicts the generation containing the lost txn) bound recoverability. Do not change the
algorithm per task rules — but never describe sync as "merging", and any future design
should consider per-record IDs + tombstones instead of wall-clock whole-state replace.

## Security Threat Model

Scope: personal single-user app, attacker = thief with the phone, someone on the same
LAN, or anyone obtaining an export/QR photo. Secrets: none exist server-side; PINs and
codes are the only credentials and are covered below without values.

- **4-digit PIN hashing (realistic weakness, accepted):** SHA-256 unsalted-globally —
  salt is the hard-coded string `expense-tracker::pin::v1::` (`lib/security.dart`),
  identical on every install. 10,000 possible PINs: anyone extracting
  `expense_pin_hash_v1` from prefs/backup brute-forces it instantly (offline, no
  rate limit). Realistic impact is LOW *only* because extracting prefs already
  requires the unlocked device or a backup — at which point the data is readable
  anyway. Do not oversell the PIN: it is a casual-snooper gate, not encryption.
- **Static salt (theoretical on its own):** rainbow tables are pointless for a 4-digit
  space; the salt's only job is domain separation, which it does. No action needed.
- **Biometric (realistic strength):** `biometricOnly: true` via OS keystore-backed
  `local_auth`; it only *unlocks*, never decrypts (nothing is encrypted). Failure
  falls back to PIN. Sound as designed.
- **Local storage (realistic exposure):** all financial data + PIN hash in plaintext
  SharedPreferences XML; Android Auto Backup uploads it to Google Drive **by default**
  (no `allowBackup=false`, no `dataExtractionRules` — verified absent in the
  manifest). Threats: unlocked-device snooping, backup-scope overreach, rooted-device
  reads. High-likelihood, low-sophistication.
- **Exported backups (realistic exposure):** share-sheet JSON/CSV is plaintext in
  whatever chat/mail/Drive app receives it, forever. Users must treat exports as
  sensitive documents.
- **LAN HTTP servers (realistic, scoped):** three shelf servers + Node relay speak
  plain HTTP with CORS `*` (`phone_host_io.dart`, `wifi_host_io.dart`,
  `serve-expense.cjs`). Anyone on the same WiFi can read snapshots (full financial
  history) and push malicious ones (no integrity beyond the PIN). Scoped by: LAN-only
  bind, 5-minute sender lifetime, PIN per box, best-effort mDNS. Public/coffee-shop
  WiFi = hostile; home WiFi = trusted-by-assumption. Never expose these ports beyond
  the LAN.
- **Sync PINs (realistic if mishandled):** 6-digit sender PINs and 4–12-char link
  PINs are the sole LAN auth and travel inside QR payloads; a photographed/shared QR
  equals access while the box/session lives. Short lifetimes (5-min sender, 7-day
  sliding boxes, explicit Stop/Unlink) contain this — keep them short.
- **QR pairing (realistic):** QR strings contain origin + code + PIN in cleartext;
  screenshots, chat history, and the pasted-code `TextField` (clipboard) all retain
  them. Same mitigations as PINs; add "don't forward sync codes" to user guidance.
- **CORS `*` (theoretical here):** harmless in practice — these endpoints are consumed
  by non-browser clients or same-origin web views on a trusted LAN; browsers are not
  the threat, LAN neighbors are, and CORS never stopped them.
- **SMS access (realistic, permission-shaped):** `READ_SMS` + 90-day/300-row inbox
  reads (`SmsBridge.kt`) expose OTPs and bank messages to the app process; blast
  radius is contained (on-device parsing, allowlist-gated, 500-ID dedup store, no
  exfiltration anywhere in the code — verified: no network call carries SMS data).
  The manifest comment understates Auto mode (see §16) — fix the wording, keep the
  gating.

## Google Play Release Readiness

Verified item by item against the repo (blockers marked ⛔, advisories ⚠️):

- **package / application ID:** `com.dhadda.expense` ✅ (`build.gradle.kts`).
- **versionCode / versionName:** `2` / `1.3.1` from `1.3.1+2` ✅ (monotonic discipline
  is maintainer-owned going forward).
- **minSdk / targetSdk / compileSdk:** delegated to Flutter plugin, no literals —
  ⚠️ unresolved in-repo (`NOT VERIFIED`); confirm via a build log before submission
  (16 KB-page / 64-bit / target-API policy all key off these).
- **Release signing:** ⛔ debug keys (`signingConfig(debug)`, TODO in
  `android/app/build.gradle.kts`). Must create an upload keystore + `key.properties`
  (never commit it) before any submission.
- **APK/AAB:** ⛔ CI builds `apk` only; Play requires **AAB**
  (`flutter build appbundle`). No `split`s config issue for AAB (bundles handle it).
- **READ_SMS declaration:** ⛔ high-risk. Play's SMS/Call-Log policy permits this
  group only for approved core-use cases (default SMS handler etc.); a finance
  tracker is very unlikely to pass the Permissions Declaration Form. Realistic routes:
  (a) drop SMS import for the Play track, or (b) distribute via sideload/F-Droid
  (consistent with the existing `flutter_zxing`-over-ML-Kit choice).
- **Notification permission:** ✅ `POST_NOTIFICATIONS` + runtime request path
  (`reminders.dart`); declare usage in the Data safety form.
- **mDNS/network permissions:** ✅ `INTERNET/ACCESS_WIFI_STATE/
  ACCESS_NETWORK_STATE/CHANGE_WIFI_MULTICAST_STATE` are normal/install-time; no
  background-service or foreground-service types declared (none needed — serving is
  foreground-activity-bound, which matches the "works while app stays open" copy).
- **Backup configuration:** ⚠️ `android:allowBackup`, `fullBackupContent`, and
  `dataExtractionRules` are all absent → Auto Backup defaults ON, sweeping plaintext
  finances + PIN hash to Drive. Decide explicitly (exclude or document) before
  shipping; also drives the Data-safety "data collected/stored" answers.
- **Listing/policy:** ⚠️ store texts exist but no Data-safety form, no privacy
  policy URL, `README` is stock, web title says "expense". Sensitive-permission +
  finance-category review will demand all three.

## Embedded Web Build Reproducibility

Exact generation path (verified — no script, no CI step does this): a human runs
`flutter build web --release --no-tree-shake-icons --pwa-strategy none` (flags from
CI's web job, minus `--base-href`), then **manually copies** `build/web/` over
`assets/webapp/` (22 explicit `assets/webapp/...` entries in `pubspec.yaml:82-104`
bake it into the APK; `phone_host_io.dart:92` serves it via
`rootBundle.load('assets/webapp/$name')`). Grep for `assets/webapp|build/web` hits
only `pubspec.yaml`, `phone_host_io.dart`, `build.yml`, and the bundle itself —
there is no `tool/`, `Makefile`, or workflow step performing the copy.

Why versions diverge: the APK version comes from `pubspec.yaml` at *APK build* time
while the web bundle is a *stale artifact* from an earlier, separately-invoked web
build — nothing couples them. Observable proof in-tree: `assets/webapp/version.json`
says `1.3.0+1` while `pubspec.yaml`/`version.dart` say `1.3.1+2`/`1.3.1`. Additional
drift vectors: a `build/web` with Pages `--base-href /<repo>/` copied by mistake
breaks root-served asset paths; forgetting `--pwa-strategy none` ships a live
service worker that caches stale UI inside the "no-cache" host.

Recommended automation (do NOT implement under this task): a single
`tool/build_webapp.dart|ps1` (or CI job) that (1) stamps `version.dart` +
`pubspec.yaml`, (2) builds web with fixed flags **without** `--base-href`,
(3) asserts `version.json` equals the app version, (4) rsyncs to `assets/webapp/`,
(5) fails the build on mismatch; run it as a `preBuild` dependency of
`assembleRelease` (or a required CI check) so a lagging bundle can never ship.

## Architecture Scaling Assessment

`ExpenseStore` (`lib/store.dart`, 895 lines) is a benevolent god-object. Counted
responsibilities: (1) four domain collections + category/loan/project/txn CRUD,
(2) persistence (encode/decode, 6 keys, backups, reseed, legacy migrations),
(3) snapshot export/import + conflict rule, (4) link-session state, (5) appearance
settings (theme/accent/Material You seed fetch), (6) currency + user name,
(7) SMS prefs, (8) derived analytics (`monthSpend`, `spendByCategory`, project/loan
totals), (9) `onLoansChanged` fan-out. It works because the scale is one user and
every write path funnels through `_touch()` → `_saveAll()` → `notifyListeners()`.

Seams worth splitting *when pain appears* (not now): a `SettingsStore`
(theme/accent/currency/name/Material You), a `SyncState` (link fields + status),
a `Budget/analytics` view-model of derived getters, and a persistence gateway
hiding the prefs keys behind load/save (so a future encrypted/DB store swaps in one
place). Keep one `ChangeNotifier` root and keep mutators notifying — the pattern is
sound. **Do NOT migrate state libraries**: there is no concrete technical driver
(no cross-feature stream fan-in, no undo-stack, no complex async orchestration that
`ChangeNotifier` cannot express); a rewrite would churn all 8 screens for zero
user-visible gain. Split along the seams above inside the current library instead.

## Recommended Future Stack

CURRENT STACK: Flutter (Material 3) + provider/ChangeNotifier; SharedPreferences
JSON (no DB); dart:convert manual models; shelf/http LAN sync (atomic snapshots,
last-write-wins); zero-dep Node relay; native Kotlin only for mDNS/SMS/camera;
`flutter_zxing` scanning; local notifications; GitHub Actions (Pages + APK); no
Firebase/cloud/AI/vendor SDKs.

RECOMMENDED EVOLUTION (incremental, evidence-linked — no rewrites):
1. **Persistence first:** keep the JSON shape, move bytes into `flutter_secure_storage`
   (PIN-gated key) or SQLCipher-backed store when history or the threat model demands
   it; add append-only change log + compaction to escape O(history) rewrites and the
   torn-key risk. (Drivers: §§ Persistence Risk, Threat Model.)
2. **Sync second:** keep snapshot bootstrap, add per-record `updatedAt` + tombstones
   so offline edits on two devices merge instead of clobber (§Conflict Analysis);
   keep QR/PIN pairing UX unchanged.
3. **Distribution:** resolve Play-vs-sideload (READ_SMS forces the question); add AAB
   + real signing either way; automate the web-bundle step (bundles should never lag).
4. **Observability without vendors:** on-device sync diary (last N decisions with
   timestamps) + exportable diagnostics; still no analytics SDK.
5. **UI/tests:** widget-test new screens (pattern exists), add one `integration_test`
   for the add→history→backup golden path, then the maintainer's UI polish batch.
6. Explicitly **not** recommended: native-Android rewrite (Flutter blocks nothing in
  the repo — camera/SMS/mDNS/notifications all already bridge cleanly), new state
  library (no driver), hosted backend or realtime DB (violates the $0/offline-first
  constraint the whole project is built around).

---

*End of PROJECT_CONTEXT.md — 24 requested sections + 7 analysis sections, complete.
No source code was modified, no dependency updated, nothing deleted.*
