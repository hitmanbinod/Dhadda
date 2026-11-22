# Web UI v2 — final report

## 1. Branch and commits

Branch `web-v2`, created from `web-parity`. Nothing merged, nothing pushed.

| Commit | Phase |
|---|---|
| `61d78b1` | baseline: preserved the pre-existing working tree on `web-parity` before branching |
| `c79eb69` | Phase 0 — recon, feature matrix, source-derived web tokens |
| `fdcfc67` | Phase 1 — token generation, base stylesheet, icon sprite |
| `a5b2559` | Phases 2-7 — shell, screens, dialogs, demo store |
| `041312a` | Phase 8 — screenshots at 1440×900 and 390×844, light and dark |

Phase 9 (this report plus doc updates) is the final local commit.

## 2. Per screen

- **Shell** ✅ — 232 px sidebar, real app monogram, one primary New entry button
  with N hint, four nav rows, sync status + single avatar in footer. No top bar,
  no repeated page title, no duplicated avatar. Command palette (Ctrl/Cmd+K or
  `/`), theme switching without flash, keyboard N / Esc / `[` `]` / 1-4.
- **Home** ✅ with layout difference — desktop uses row 3 = balance + stat strip
  (5fr/7fr) and row 4 = By category/Budgets/Events left + Recent right (7fr/5fr).
  Events are present; By category has the proportional segment bar with
  selection glow/dim. Balance and its eye are adjacent. Magnitude + colour is
  used for negatives (per decision). Phone keeps Android order in one column.
- **History** ✅ partially — inline search, type chips, day groups, signed
  amounts, hover edit/duplicate/delete, Undo toast, bulk-select bar, 60-row
  paging. `content-visibility:auto` is **not** applied; Categories/Events views
  and CSV export are **not** implemented in this prototype.
- **Insights** ✅ partially — equal-width period control, summary, Where it
  went, Money on loan, Monthly rhythm bars. Forecast, How you pay, Largest
  expenses and fiscal-year handling are **not** implemented.
- **Lent** ✅ partially — Lent/Borrowed toggle, status chips, totals, person
  cards with progress and due date. Top-up/repayment buttons are present but
  have no dialog handlers yet.
- **Settings** ✅ partially — theme, accent swatch, calendar AD/BS toggle,
  hide-balance, currency, Edit Home drawer, receipts disclosure, account sheet,
  erase. **Not implemented:** accounts manager, auto-category rules, full
  backup export/import (device-only/later per matrix).
- **Entry sheet** ✅ — centred 480 px modal, Expense/Income control, hero
  amount with baseline symbol, category tiles, note, date, Enter saves,
  Esc closes, Undo toast after delete. Repetition auto-suggestions and receipt
  picker are absent (web has no platform receipt bridge).
- **Phone mode** ✅ — bottom tabs, round Add FAB, avatar in Home header,
  bottom-sheet styling. Sheets still use the centred-scrim markup with a
  bottom-anchored panel.

## 3. Where the Android source disagreed with the brief

- **Accent colour**: the brief measured olive-gold `#685F12` (light) and
  `#DCD06C` (dark). The source wins: `AppColors.resolve()` uses
  `ColorScheme.fromSeed(0xFF009688)`, giving `#006A60`/`#82D5C8`. The web
  tokens use those values. Earlier measured indigo/olive values are reported in
  `design/WEB_V2_PHASE0.md` but not used.
- **Material You**: Android uses `dynamic_color` (`dynamic_color` package in
  `pubspec.yaml`); web cannot. The static fallback scheme is used, as instructed.
- **Balance sign**: Android Home shows a magnitude tinted by direction (no
  minus); the Android widget uses `-रू 2,000`. Per the decision, web follows
  Home (magnitude + colour).
- **Other measured values** (light bg `#F4F3EE`, dark card `#121816`,
  expense/income shades) also differ slightly from `tokens.g.dart`; source
  values are used. Measured-only roles (avatar, selected row, tile tints) were
  added under `colors.web`.

## 4. FEATURE_MATRIX.md summary

87 rows: **68 include**, **15 device-only/hidden**, **4 later**.

## 5. Budget numbers

| Metric | Before | After (web-v2) |
|---|---:|---:|
| Web JS+CSS gzip | 1,268,568 B (Flutter `main.dart.js` + loaders) | **16,514 B** production / 17,949 B with demo |
| Third-party code | Flutter framework in JS bundle | none |
| Icon sprite | Material icon font (tree-shaken) | `icons.svg` 1,113 B gzip |
| Fonts | system | system with Nepali fallbacks |
| Android diff `web-parity..HEAD -- android` | — | **empty** |
| Web files in APK | yes — `assets/webapp/`, 43.8 MB / 45 files, ~94 MB release APK | web-v2 **not** bundled; APK unchanged |

The legacy Flutter-web build and `assets/webapp/` were deliberately left
untouched; switching the phone host to serve `web-v2/` is a packaging/hosting
task, out of scope here.

## 6. What could not be verified visually

Screenshots were taken and inspected at 1440×900 and 390×844 in both themes for
Home, History, Insights, Lent, Settings and the entry sheet
(`design/screenshots/`). Automated checks confirm no horizontal scroll, no text
below 12 px (the 0.6em currency mark is excluded), one page title, and no
console/page errors. Not verified: real-device rendering, keyboard-focus ring
contrast in every state, colour-contrast ratios with a formal checker, screen
reader behaviour, and any interaction not exercised by the screenshot script
(drawer toggles, palette commands, delete/Undo flows).

## 7. Demo mode

Serve the folder with any static server, e.g.
`python -m http.server 8099 --directory web-v2`, then open
**http://127.0.0.1:8099/?demo=1**. `demo-data.js` is only requested when the
`demo` query parameter is present; it loads ~46 entries across three months,
two events and three loans into an in-memory store and never reads or writes
`localStorage`. Without the parameter the app uses the real `expense_*_v1` keys.

## Honest status

This is a working presentation prototype, not the full 87-row parity target.
The shell, Home, entry sheet and the main structure of all screens are in place
and visually checked; the gaps listed in section 2 remain before it could
replace the shipped Flutter web UI.
