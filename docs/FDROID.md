# Dhadda F-Droid & FOSS Notes (Phase 1 foundation)

Target: GitHub + F-Droid only. No Google Play. This doc records the Phase 1
dependency audit and metadata state. It does NOT claim F-Droid acceptance.

## 1. Open-source license: Apache-2.0 (LICENSE, SPDX `Apache-2.0`)

`LICENSE` carries the full Apache License 2.0 text. No GPL-incompatible
or proprietary dependency was found in the audits below, so the
permissive license applies cleanly to the whole tree.

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

## 3. Phase 2 additions (same method: packaged LICENSE headers read)

| Package | Purpose | License | FOSS-compatible | Concern |
|---|---|---|---|---|
| drift 2.34.4 | SQLite ORM/migrations | MIT | yes | none in code |
| path_provider 2.1.6 | DB file location | MIT | yes | none |
| path 1.9.1 | path join | MIT | yes | none |
| drift_dev 2.34.6 / build_runner 2.16.1 (dev-only) | codegen | MIT | yes | build-time only |
| sqlite3 3.x (transitive via drift) | native SQLite via build hooks | public-domain SQLite + MIT wrapper | yes in code | **Open item:** native libs now compile from source at build time via hooks (better than prebuilt `.so`), but F-Droid native-binary provenance must still be confirmed at submission; the obsolete `sqlite3_flutter_libs` stub was evaluated and removed |

No Firebase/GMS/ads/analytics anywhere (lockfile re-scanned clean). No
dependency replaced for this audit. License snapshot: everything permissive.

## 4. Phase 3 addition (same method: packaged LICENSE header read)

| Package | Purpose | License | FOSS-compatible | Concern |
|---|---|---|---|---|
| cryptography 2.9.0 | Argon2id + XChaCha20-Poly1305 for optional encrypted backups (pure Dart, no native code → identical on Android/Web) | Apache-2.0 | yes | none: no binaries, no network, no platform SDKs |

## 5. Upstream metadata (fastlane, F-Droid-compatible layout)

Present under `fastlane/metadata/android/en-US/`: `title.txt` (Dhadda),
`short_description.txt`, `full_description.txt` (both already accurate —
offline-first, no account/cloud/fees), `images/icon.png` (from
`assets/icon/app_icon.png`), `changelogs/<versionCode>.txt` (`2.txt` for
1.3.1, `3.txt` for 1.4.0).
F-Droid build metadata (package ID `com.dhadda.expense`, source ref, build
recipe) still belongs in the F-Droid data repo / later phase — not invented here.

## 6. Phase 8 submission reference (for the fdroiddata entry)

Upstream facts an F-Droid submission needs (verified this phase):

```text
Application ID: com.dhadda.expense
Current version: 1.4.0 / versionCode 3
License (SPDX): Apache-2.0
Source: <upstream git URL> at tag v1.4.0 (tag naming: v<version>)
Category: Finance Manager (from fdroiddata/config/categories.yml; there is
  no "Money" category)
Flutter: 3.47.2 (see .fvmrc; CI pins flutter-version 3.47.2)
JDK: 17; AGP/Kotlin per android/settings.gradle.kts
Build flavor: default; build command: flutter build apk --release
  WITHOUT maintainer key material (F-Droid signs its own builds;
  android/key.properties is git-ignored and absent upstream). The
  Gradle fail-closed check must be satisfied by the F-Droid recipe, never
  by weakening it -- see "F-Droid build recipe" below for the exact flag.
Pre-build: flutter pub get --enforce-lockfile;
  dart run build_runner build --delete-conflicting-outputs
Anti-features: none apply (no network services, no ads, no tracking,
  no non-free dependencies; local-network sync is user-initiated on a
  trusted LAN and documented in docs/SECURITY_LAN.md)
```

### F-Droid build recipe

`android/app/build.gradle.kts` fails CLOSED on a release build that has
neither key material nor an explicit opt-in, so a plain
`flutter build apk --release` cannot succeed upstream. That is deliberate
for maintainer builds; F-Droid needs a supported way in.

The opt-in is accepted as either an environment variable or a Gradle
property (`-PdhaddaAllowUnsignedRelease=true`). F-Droid's build metadata has
no field that sets an arbitrary environment variable, so the recipe passes it
on the `flutter build` command line via `--android-project-arg`:

```yaml
build:
  - export PUB_CACHE=$(pwd)/.pub-cache
  - $$flutter$$/bin/flutter build apk --release --android-project-arg "dhaddaAllowUnsignedRelease=true"
output: build/app/outputs/flutter-apk/app-release.apk
```

Note `--android-project-arg` takes `key=value` — it adds the `-P` itself, so
do not include it. (An earlier draft of this doc used a `properties:` YAML
field; that field does not exist in F-Droid's build metadata. The correct
fields are `build`, `output`, `gradleprops`, `scanignore`/`scandelete`, and
`rm`.)

The complete, ready-to-copy metadata file is **`fdroid/com.dhadda.expense.yml`**,
modelled on F-Droid's own `templates/build-flutter.yml`.

**What was verified locally** (clean `git clone` of the pinned commit, no
`android/key.properties`):

| Check | Result |
|---|---|
| `flutter build apk --release` (no opt-in) | fails closed, as designed |
| `flutter pub get --enforce-lockfile` | lockfile honored |
| `flutter build apk --release --android-project-arg "dhaddaAllowUnsignedRelease=true"` | succeeds, 88.4 MB |
| Output APK signature | genuinely unsigned (F-Droid applies its own key) |
| applicationId / versionCode / versionName | `com.dhadda.expense` / `3` / `1.4.0` |

**Not yet verified:** an actual `fdroid build` inside F-Droid's container. That
needs their buildserver; the Flutter 3.47.2 tag does exist upstream, which is
what the `srclibs: [flutter@stable]` + `git -C $$flutter$$ checkout -f 3.47.2`
pin depends on.

### Known F-Droid friction points

1. **Category.** F-Droid rejects categories not in
   `fdroiddata/config/categories.yml`. The correct value for this app is
   `Finance Manager` (there is no `Money` category).
2. **Committed binaries.** F-Droid's scanner refuses to build when binaries are
   committed. `assets/webapp/` is a committed Flutter web bundle (~38 MB of
   `.wasm`/`.symbols`) used by the "Show on PC" feature. The recipe
   `scanignore`s it, justified in `MaintainerNotes`; it is deterministic
   output of `dart tool/build_embedded_web.dart` and CI already verifies its
   freshness with `--check`. If reviewers object, the alternative is to `rm`
   the bundle and rebuild it in `prebuild` — at the cost of requiring
   `flutter build web` (and its `precache`) to work in their container.
3. **`commit:` must be a full 40-character hash**, not a tag name. Tags are
   still needed for `UpdateCheckMode: Tags` to detect future releases, so tag
   `v1.4.0` even though the recipe references a commit hash.
4. **`--split-per-abi` is not used.** A single universal APK is simpler for a
   first submission. Splitting would cut per-device size but requires three
   build blocks plus `VercodeOperation`, which changes the version-code
   scheme.
5. **Two signatures, two installs.** F-Droid signs with its own key, so the
   artifact differs from the maintainer-signed GitHub build. Switching between
   them requires a reinstall — Android refuses to replace an app signed by a
   different key.

This is metadata readiness, not acceptance: F-Droid review and
inclusion remain an external process. Reproducibility status is in
`docs/REPRODUCIBILITY.md`.
