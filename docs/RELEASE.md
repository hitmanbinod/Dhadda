# Dhadda Release & Build Guide (GitHub + F-Droid track)

No Google Play. No backend. This doc covers toolchain pinning, release signing,
the embedded-web workflow, and CI behavior. Baseline record stays in
`docs/BASELINE.md`.

## 1. Toolchain pinning

- Canonical version: **Flutter 3.47.2** (Dart 3.13.2) — the Phase 0-verified
  toolchain. Pinned in two places that must agree:
  - `.fvmrc` (`{"flutter": "3.47.2"}`) for local/FVM/IDE users;
  - `flutter-version: "3.47.2"` in `.github/workflows/build.yml` (both jobs).
- Do not float CI on `stable` alone for releases. When upgrading, update both
  pins, re-run the full validation (analyze, tests, web, debug APK), and record
  the new versions here.
- Dependencies resolve via the committed `pubspec.lock`; CI uses
  `flutter pub get --enforce-lockfile` so a stale lockfile fails loudly instead
  of silently resolving newer packages.

## 2. Release signing (GitHub releases)

Previous state: `release` builds silently used debug keys. That is gone.

- Maintainer key lives **outside the repo**: create once with
  `keytool -genkeypair -v -keystore dhadda-release.jks -alias dhadda -keyalg RSA
  -keysize 2048 -validity 10000`, back the `.jks` up offline (paper copy of
  location + recovery contacts, per maintainer practice), and never commit it.
- Local builds read `android/key.properties` (git-ignored, template below).
  `storeFile` resolves relative to `android/app/`:
  ```properties
  storeFile=../dhadda-release.jks
  storePassword=<your-store-password>
  keyAlias=dhadda
  keyPassword=<your-key-password>
  ```
- Missing `key.properties` on a release build = **hard Gradle failure** with setup
  instructions (fail-closed, never debug-signed). Debug builds, `flutter run`,
  and `flutter test` never need keys.
- Explicitly-unsigned dev releases (never publish): set
  `DHADDA_ALLOW_UNSIGNED_RELEASE=1`. The build logs a warning; artifacts from such
  builds must not be attached to releases.
- Verify a published APK: `apksigner verify --print-certs <apk>` and compare the
  SHA-256 fingerprint against the maintainer-published fingerprint (kept outside
  this repo). CI attaches `SHA256SUMS` to every tagged release.
- Tag builds in CI expect maintainer secrets (keystore + passwords as protected
  Actions secrets); non-tag builds use the unsigned-dev flag and are for testing
  only. Secret *names* are documented in `.github/workflows/build.yml`; values
  never appear here.
- F-Droid model: F-Droid signs its own builds from source. The maintainer key
  above is for GitHub releases only — users cannot switch between GitHub-signed
  and F-Droid-signed installs for the same package ID without reinstalling.
