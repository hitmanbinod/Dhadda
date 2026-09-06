# Dhadda F-Droid & FOSS Notes (Phase 1 foundation)

Target: GitHub + F-Droid only. No Google Play. This doc records the Phase 1
dependency audit and metadata state. It does NOT claim F-Droid acceptance.

## 1. Open-source license: ABSENT (flagged, not chosen)

The repo has **no LICENSE file**. F-Droid requires a FOSS license; the
maintainer must choose one (roadmap §8.1 lists GPL-3.0-or-later, AGPL-3.0,
Apache-2.0, MIT as candidates). No license was added in Phase 1 — choosing one
is a maintainer decision, not an automation default.

## 2. Direct-dependency FOSS audit (method + result)

Method (2026-09-06, reproducible): for each `pubspec.yaml` runtime dependency,
resolved via `.dart_tool/package_config.json` into the local pub cache and read
the packaged `LICENSE*` header; then scanned the committed `pubspec.lock` for
`firebase|gms|google_mobile|admob|play_services|facebook|analytics|crashlytics`
(zero hits). No dependency was added, removed, or upgraded for this audit.

| Package | Purpose | License (as packaged) | FOSS-compatible | Proprietary/Google SDK | F-Droid concern |
|---|---|---|---|---|---|
| shared_preferences | all persistence | BSD-3-Clause | yes | none | none |
| provider | state | MIT | yes | none | none |
| uuid | IDs | MIT | yes | none | none |
| intl | formatting | BSD-3-Clause | yes | none | none |
| crypto | PIN hash | BSD-3-Clause | yes | none | none |
| share_plus (13.2.1 pinned) | export share | BSD-3-Clause | yes | none (AndroidX share sheet) | none |
| file_picker | import picker | MIT | yes | none | none |
| shelf / shelf_router | on-device HTTP servers | BSD-3-Clause / Apache-2.0 | yes | none | none |
| http | sync clients | BSD-3-Clause | yes | none | none |
| qr_flutter | render QR | BSD-3-Clause | yes | none | none |
| fl_chart | Home pie | MIT | yes | none | none |
| local_auth | biometric | BSD-3-Clause | yes | none (AndroidX Biometric, no GMS) | none |
| dynamic_color | Material You | Apache-2.0 | yes | none | none |
| flex_color_picker | accent wheel | BSD-3-Clause | yes | none | none |
| wakelock_plus | serving awake | BSD-3-Clause | yes | none | none |
| flutter_local_notifications | reminders | BSD-3-Clause | yes | none | none |
| timezone / flutter_timezone | zoned schedules | BSD-3-Clause / Apache-2.0 | yes | none | none |
| flutter_slidable | swipe delete | MIT | yes | none | none |
| flutter_zxing | QR scan (no ML Kit) | MIT (+ zxing-cpp native, Apache-2.0, compiled from source) | yes | none (no Play Services — the reason it was chosen) | none known |
| flutter_lints / flutter_launcher_icons (dev) | lints, icons | BSD-3-Clause / MIT | yes | none | none |

Build-only: `desugar_jdk_libs:2.1.4` (Apache-2.0), AGP/Gradle/Kotlin (Apache-2.0).
Node relay: zero dependencies. Result: **no incompatible or suspicious
dependency found; nothing replaced.**

Unresolved / maintainer review: full transitive closure was NOT individually
read (spot-checked ecosystem packages only — all flutter/packages/dart-lang
BSD-style); native `.so` provenance beyond zxing-cpp not traced; confirm again
at F-Droid submission time. Re-audit on every dependency change.

## 3. Upstream metadata (fastlane, F-Droid-compatible layout)

Present under `fastlane/metadata/android/en-US/`: `title.txt` (Dhadda),
`short_description.txt`, `full_description.txt` (both already accurate —
offline-first, no account/cloud/fees), `images/icon.png` (from
`assets/icon/app_icon.png`), `changelogs/<versionCode>.txt` (started at `2.txt`).
F-Droid build metadata (package ID `com.dhadda.expense`, source ref, build
recipe) still belongs in the F-Droid data repo / later phase — not invented here.
