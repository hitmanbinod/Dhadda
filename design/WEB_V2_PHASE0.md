# Web UI v2 — Phase 0 recon (no UI code)

Branch: `web-v2`, created from `web-parity` after a baseline commit of the
pre-existing working tree (`61d78b1`). Nothing merged, nothing pushed.

## How the web is built, served and bundled (report only)

- There is **one Flutter codebase** for Android and web. The web UI is the
  same `lib/**/*.dart` screens compiled by `flutter build web`; `web/` is only
  the HTML shell (`index.html` loads `flutter_bootstrap.js`), not a source app.
  There is no plain-JS/CSS web implementation in the repository.
- `tool/build_embedded_web.dart` runs
  `flutter build web --release --no-tree-shake-icons --pwa-strategy none`,
  verifies version/root-relative URLs, then copies `build/web` into
  `assets/webapp/`. `pubspec.yaml` declares `assets/webapp/` as an asset, so
  **the web bundle is embedded in the Android APK**; `lib/sync/phone_host_io.dart`
  serves it over LAN for "Show on PC".
- CI (`.github/workflows/build.yml`) also builds a separate Pages artifact with
  `--base-href`. No packaging or build files were changed in this phase.

## Measured current web size

| File | Raw bytes | Gzip bytes (level 9) |
|---|---:|---:|
| `assets/webapp/main.dart.js` | 4,334,194 | 1,258,782 |
| `assets/webapp/flutter.js` | 12,136 | 4,650 |
| `assets/webapp/flutter_bootstrap.js` | 12,927 | 5,136 |
| `design/tokens.css` | 1,214 | 568 |

Total Flutter loader + app JS ≈ **1.27 MB gzipped**. The task's ≤45 KB gzip
budget is not achievable with the existing Flutter-web stack; see conflicts.

## Theme-source colours (source wins)

`AppColors.resolve()` in `lib/theme/palette.dart` derives the accent with
`ColorScheme.fromSeed(seedColor: store.accent, brightness)`. Android default
seed is `0xFF009688` (teal) in `lib/store.dart`; there are 12 presets and a
custom picker; Material You dynamic colour is Android-only.

Computed with Flutter 3.47 for the static fallback seed:

| Role | Light | Dark |
|---|---|---|
| scheme primary (accent) | `#006A60` | `#82D5C8` |
| onPrimary | `#FFFFFF` | `#003731` |
| background (tokens.g.dart) | `#F5F3EE` | `#0B100F` |
| surface (tokens.g.dart) | `#FFFFFF` | `#121A18` |
| expense (tokens.g.dart) | `#B84B3C` | `#F2A092` |
| income (tokens.g.dart) | `#23784A` | `#8FD3A9` |

The measured phone values in the task (olive-gold `#685F12`, light bg
`#F4F3EE`, dark card `#121816`, expense `#B8483C`/`#F09888`, income
`#207848`/`#60D478`) disagree with the source. Per the task's own ordering,
the source values are recorded in `design/tokens.json` under `colors.web`;
measured-only roles (avatar, selected row, tile tints) are included there too.

## Balance sign question (needs a decision)

- Android Home shows balance as a **magnitude tinted by direction**, no minus
  sign (income green / expense coral).
- Android home-screen widget `WidgetData.signedAmount()` renders `-रू 2,000`.
- The web should follow the Android Home rule, but a minus sign is arguably
  clearer on desktop. The task asks that this be listed, not silently decided.

## Conflicts that block a literal full implementation

1. **Stack**: the task assumes a hand-written web app (inline SVG sprite, CSS
   variables, 45 KB gzip, "no framework"). The repository's web app is Flutter
   web; its JS alone is ~1.27 MB gzip and includes the Flutter framework.
   Staying on the existing stack cannot meet the performance budget.
2. **"Do not edit Android code"**: `lib/screens/*` is compiled into both
   platforms. Restyling those files changes Android. A web-only UI requires a
   separate web entrypoint/target, which changes packaging — explicitly out of
   scope for Phase 0 ("report only, do not change packaging").
3. **Colour source vs measurement**: resolved in favour of the source above;
   the olive accent is therefore not used.

## Phase 0 outputs

- `design/FEATURE_MATRIX.md` — 87 rows: 68 include, 15 device-only, 4 later.
- `design/tokens.json` — added `colors.web.light/dark` and `web` scale; the
  generated Android `tokens.g.dart` is unchanged (`sync_tokens.py --check`
  passes).
- `design/WEB_V2_PHASE0.md` — this report.
