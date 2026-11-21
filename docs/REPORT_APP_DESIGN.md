# Report — Design of the Android and web apps (Dhadda)

Prepared 2026-11-21 for external review. Describes the current architecture
and UI design of the two surfaces of the same Flutter codebase, on branch
`round2` at HEAD `484ee77`. "Not verified" means no on-device run was
performed for that item.

---

## 1. One codebase, two surfaces

Dhadda is a single Flutter project (`package: expense`, app label **Dhadda**,
version 1.5.0+4) that targets Android and Flutter Web from the same Dart
sources. There are no separate native Android UI screens and no separate web
framework: the "Android app" and the "web app" are the same widget tree,
compiled to different targets.

The web surface exists in two forms:

1. **Standalone Flutter Web** — the ordinary `web/` shell, what `flutter run
   -d edge` or a static host serves (currently `http://127.0.0.1:8080` during
   development).
2. **Embedded phone-hosted bundle** — `assets/webapp/`, a release Flutter Web
   build served by the Android app itself over LAN ("Show on PC"), via
   `lib/sync/phone_host_io.dart`. `dart tool/build_embedded_web.dart` builds
   and copies it; `--check` verifies it. It is currently version 1.5.0+4 and
   root-relative (`<base href="/">`).

---

## 2. Shared UI design system

The visual language is defined in `lib/theme/`:

- `tokens.dart` — spacing scale (4/8/12/16/24/32), radii
  (icon 10, card 16, segmented 10, field 12, sheet 24, pill 999), component
  sizes (48 dp min tap, 36 dp icon tile, 48 dp segmented height) and motion
  (150/200/300 ms, `easeOutCubic`, zero duration under reduced motion).
- `palette.dart` — `AppColors` ThemeExtension with light/dark roles including
  `expense`, `income`, `accent`, `card`, `field`, `track`, `hairline`,
  `textPrimary/Secondary`.
- `typography.dart` — named text styles (`largeTitle`, `heroAmount`,
  `statValue`, `title`, `body`, `caption`, `amount`) consumed everywhere.
- `app_theme.dart` — Material 3 theme assembly, 12 accents, Material You
  dynamic seed on Android.

Reusable widgets in `lib/widgets/` (`app_card.dart`, `segmented_tabs.dart`,
`profile_avatar.dart`, `page.dart`, `receipt_field.dart`, etc.) keep grouped
cards, tabular amounts, 48 dp targets and Semantics labels consistent.

**Visual language:** calm Material 3 surfaces; grouped cards with hairline
dividers; one raised selected pill in each segmented control; amounts in
tabular figures with direction carried by colour (red expense / green income);
no decorative chart junk. Both light and dark are first-class.

---

## 3. Android app design

### 3.1 Navigation shell

`lib/main.dart` — `RootShell` with four tabs (Home / History / Insights /
Lent). On phones: a Material 3 `NavigationBar` at the bottom inside a
`Scaffold`; on widths > 900 dp: a `NavigationRail` on the left, no bottom bar.
`IndexedStack` keeps all four tabs mounted, so scroll positions, filters and
the Home month survive tab switches. Settings is a pushed route from the
per-tab avatar button, not a fifth tab. A PIN/biometric lock screen gates the
whole shell when configured.

### 3.2 Tab contents

- **Home** (`home_screen.dart`): profile row + month pager, balance hero,
  Spent/Income/Lent-out stat card, category stacked bar + legend, budgets,
  Events branches, Recent list with swipe-delete, Today ring, daily rhythm,
  forecast. Sections are reorderable/hideable via `Edit Home`
  (`home_layout.dart`). Scroll reveals a blurred compact profile bar.
- **History** (`history_screen.dart`): collapsible header/search on scroll,
  type/category/date/account filters, Entries/Categories/Events views, CSV
  export, Slidable delete with Undo, entries grouped by day and event branch.
- **Insights** (`insights_screen.dart`): period chips (Month / 3 / 6 / Year /
  Fiscal year), Pulse summary with comparison, How you pay account split,
  month-end forecast, category ring, paired spend/income monthly bars, Money
  on loan, largest expenses. Round 3.1 added How you pay and forecast.
- **Lent** (`lent_screen.dart`): To-receive / To-return summaries,
  Lent/Borrowed + Pending/Settled/All toggles, expandable loan cards with
  top-ups, repayments and one-time reminders.

### 3.3 Data and platform

- State: single `ExpenseStore` `ChangeNotifier` via `provider`; no other state
  library. Local `setState`/`ValueNotifier` for ephemeral UI.
- Persistence: Drift/SQLite on native (`lib/data/app_db.dart`, schema v3) with
  a Prefs fallback for web; domain models in `lib/models.dart`.
- Platform bridges in `android/app/src/main/kotlin/`: `MainActivity.kt`
  (`expense/mdns`, `expense/sms`, `expense/perm`, `expense/media`),
  `MdnsHelper.kt`, `SmsBridge.kt`, `MediaBridge.kt`, four widget providers.
- Permissions in `AndroidManifest.xml`: INTERNET, Wi-Fi state, CAMERA,
  biometric, POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM, multicast and READ_SMS.
  `allowBackup=false`; cleartext LAN traffic deliberately enabled.
- Native services: on-device HTTP servers for direct-WiFi sync and Show on PC,
  mDNS advertiser (`dhadda.local`), exact/inexact loan reminders, opt-in SMS
  import, camera/gallery receipt intents.

### 3.4 One-handed mode

Off by default (Settings → Appearance turns it on). Moves the
History/Insights/Lent segmented controls from the header to just above the
bottom navigation bar via a shared `oneHandedBottomPadding` helper, which adds
only a small gap because the Scaffold body already ends at the nav bar. Full
detail in `docs/DESIGN_STATUS.md` §4.

---

## 4. Web app design

### 4.1 Shell and layout

Same `RootShell` widget tree. On wide screens (including most browsers) the
NavigationRail replaces the bottom NavigationBar, and content is centred and
capped at `kPageMaxWidth = 880` dp with `kPageMargin = 16` dp. The four tabs
are otherwise identical to Android.

### 4.2 Web-specific differences

- **No native features:** `lib/sync/phone_host.dart` conditionally exports a
  stub on web (`phone_host_stub.dart`) — the browser cannot host the LAN
  server. Camera/gallery receipt capture uses the same MethodChannel, which
  on web has no native implementation (coverage: **not verified**).
- `dart.library.io` conditional exports are used for DB connection, DB
  recovery, test env, WiFi host and phone host, so web builds never compile
  native sqlite/file code.
- `shared_preferences` replaces Drift as the domain store on web (fallback
  backend).
- Page visibility/motion: media queries drive the rail vs bar switch and the
  reduced-motion zero-duration rule.

### 4.3 Branding / PWA

- `web/index.html` is still the stock Flutter shell: `<title>expense</title>`,
  description "A new Flutter project.", `apple-mobile-web-app-title=expense`.
  This is **stale** relative to the Dhadda brand and is worth fixing.
- `web/manifest.json` is correctly branded: name/short_name "Dhadda",
  standalone display, `#009688` theme/background, portrait orientation,
  192/512 icons incl. maskable variants.
- The embedded `assets/webapp/` build regenerates `index.html` with a
  root-relative base and a version.json read by the hosting app; it currently
  reports 1.5.0+4.

### 4.4 Phone-hosted mode (web served from Android)

`lib/sync/phone_host_io.dart`: a `shelf` server on 8080 (random fallback),
serving `assets/webapp/*` from the Flutter asset bundle with correct MIME and
`no-cache` plus SPA fallback to `index.html`. It also exposes the link/sync
API (`/api/sync/*`) and `/api/ping`, uses per-box throttling and a create
limiter, and tracks a `ValueNotifier<int>` hit counter. LAN-only, plain HTTP,
CORS `*` by design. mDNS advertises `http://dhadda.local:<port>` best-effort;
the IP URL is always shown too.

---

## 5. Cross-cutting design properties

- **Offline-first:** every feature works with no network; sync is opportunistic
  whole-Snapshot exchange with `(rev, by)` merge, tombstones, deterministic
  conflict ordering and 7-day mailbox TTL.
- **Privacy:** financial data is local; `allowBackup=false`; receipts are
  app-private files never in DB blobs, backups or sync payloads; PIN is a
  privacy gate, not encryption; backups optionally encrypted.
- **Accessibility:** 48 dp targets, Semantics labels on interactive widgets,
  reduced-motion support, light/dark contrast roles.
- **Testing:** ~356 automated tests including widget smoke tests at 360 dp and
  1280 px, both themes, 1.3× text scale, migration stress (5k entries),
  sync fuzz and end-to-end transports.

---

## 6. Review notes / known gaps

1. `web/index.html` branding is stale ("expense", stock description) while
   `web/manifest.json` and the embedded bundle are branded — inconsistent
   PWA identity.
2. The web build uses `--pwa-strategy none` (no service worker), so the web
   app is not an offline PWA; the embedded bundle relies on the phone host.
3. Web has no camera/gallery implementation for receipts — the buttons exist
   but their MethodChannel has no platform implementation. **Not verified.**
4. Wide-layout one-handed mode moves controls to the bottom even though there
   is no bottom NavigationBar to reach for; ergonomics on desktop are
   questionable.
5. The sticky/blur Home bar, gestures and on-device camera were not verified
   on the physical phone; all evidence is from automated tests and code.
6. The embedded bundle must be rebuilt and copied after every UI change;
   `dart tool/build_embedded_web.dart --check` gates this. It is currently
   in sync at 1.5.0+4.

---

## 7. Summary

Android and web are one Flutter codebase with a deliberately small platform
seam (`dart.library.io` conditionals + a few MethodChannels). The design is a
calm Material 3, grouped-card, tabular-amount UI with four persistent tabs,
per-device settings, offline-first data and local-only privacy. The web app is
the same UI minus native capabilities; it is also embedded into the Android
app for LAN "Show on PC". The main actionable inconsistencies are the stale
`web/index.html` branding and unverified web camera behaviour.
