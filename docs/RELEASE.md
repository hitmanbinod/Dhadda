# Dhadda Release & Build Guide (GitHub + F-Droid track)

No Google Play. No backend. This doc covers toolchain pinning, release signing,
the embedded-web workflow, and CI behavior. Baseline record stays in
`docs/BASELINE.md`.

## 1. Toolchain pinning

- Canonical version: **Flutter 3.47.2** (Dart 3.13.2) — the Phase 0-verified
  toolchain. Pinned in two places that must agree:
  - `.fvmrc` (`{"flutter": "3.47.2"}`) for local/FVM/IDE users;
  - `flutter-version: "3.47.2"` in `.github/workflows/build.yml` (all three
    jobs: `web`, `embedded-web`, `apk`).
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
  `DHADDA_ALLOW_UNSIGNED_RELEASE=1`, or pass the equivalent Gradle property
  `--android-project-arg "dhaddaAllowUnsignedRelease=true"`. The property exists
  because F-Droid's `build.yaml` has no field that maps to an arbitrary
  environment variable; see `docs/FDROID.md` §6. The result is genuinely
  unsigned (`signingConfig = null` — no debug certificate fallback) and the
  build logs a warning; artifacts from such builds must not be attached
  to releases. This is the F-Droid/source-build shape: F-Droid signs
  its own builds from source.
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

## 3. Release runbook (maintainer, do these in order)

Everything below is maintainer-only and nothing in this repo can do it for you.
Nothing has been pushed: these steps begin with the push.

### 3.1 Before you start

```text
flutter --version                  # must be 3.47.2 (.fvmrc is the pin)
git status --short                 # expect only untracked PROJECT_GUIDE.md
flutter pub get --enforce-lockfile # the exact CI command
flutter analyze --no-fatal-infos   # expect: No issues found!
flutter test                       # expect: All tests passed!
dart tool/build_embedded_web.dart --check
```

Do not tag if any of these differ from CI. The last one proves the committed
`assets/webapp/` bundle matches `pubspec.yaml`; if it fails, rebuild with
`dart tool/build_embedded_web.dart` and commit the result.

### 3.2 Create the keystore (once, ever)

Run from `android/`. Choose your own passwords — they are not recoverable.

```text
cd android
keytool -genkeypair -v ^
  -keystore dhadda-release.jks ^
  -alias dhadda ^
  -keyalg RSA -keysize 2048 -validity 10000
```

Then write `android/key.properties` (git-ignored). Note `storeFile` is
relative to `android/app/`, so it needs the `../` — this differs from the
stock Flutter template and is the single easiest thing to get wrong:

```properties
storeFile=../dhadda-release.jks
storePassword=<store-password-you-just-chose>
keyAlias=dhadda
keyPassword=<key-password-you-just-chose>
```

Confirm it worked:

```text
flutter build apk --release          # should now succeed, signed
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

Back up `dhadda-release.jks` in **two** places, and record the SHA-256
fingerprint from `apksigner` somewhere outside this repo. Losing this file
means you can never update an existing GitHub install without a reinstall.

### 3.3 Add the four CI secrets

Repository → Settings → Secrets and variables → Actions. All four are required
for a tag build; the job fails closed without `DHADDA_KEYSTORE_BASE64`.

| Secret | Value |
|---|---|
| `DHADDA_KEYSTORE_BASE64` | base64 of the `.jks`, on one line |
| `DHADDA_KEYSTORE_PASSWORD` | your store password |
| `DHADDA_KEY_ALIAS` | `dhadda` |
| `DHADDA_KEY_PASSWORD` | your key password |

Produce the base64 payload on Windows (PowerShell, no trailing newline):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\dhadda-release.jks"))
```

On macOS/Linux: `base64 -i android/dhadda-release.jks | tr -d '\n'`

### 3.4 Push, then tag

```text
git push origin master              # origin/master is behind; push this FIRST
git tag v1.4.0
git push origin v1.4.0              # push ONLY the tag
```

Push `master` before tagging. A tag whose history is not on the default
branch means the release's provenance is not reviewable from the repo.

Tag triggers the `release` job, which attaches `dhadda-v1.4.0.apk` plus
`SHA256SUMS`. The build is only signed if the four secrets exist.

### 3.5 Verify the release

```text
# checksums
Get-FileHash build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256

# on the downloaded release asset, confirm the signer is YOUR key
apksigner verify --print-certs dhadda-v1.4.0.apk
```

CI does not currently run `apksigner verify` itself, so this manual step is
the only signer check. A misconfigured key would ship and only the user would
notice.

### 3.6 Then F-Droid

The F-Droid recipe (including the Gradle property that lets F-Droid build
without your key) is in `docs/FDROID.md` §6. Users switching between the
GitHub-signed and F-Droid-signed installs must **reinstall** — Android
refuses to replace an app signed by a different key.

## 4. Embedded web bundle vs GitHub Pages (two different artifacts)

- **Embedded (phone-hosted):** built by `dart tool/build_embedded_web.dart` —
  root-relative (no `--base-href`), `--pwa-strategy none`, version-checked
  (`pubspec.yaml` vs `lib/version.dart` vs `version.json`), stale files wiped,
  required files verified, non-zero exit on mismatch. `--check` verifies without
  building. The tool also prunes `build/web/assets/assets/webapp/` — the web
  compiler embeds the old committed bundle (it is a declared APK asset), and
  copying that back would nest bundles forever.
- **GitHub Pages:** built only by CI with `--base-href /<repo>/`. Never copy a
  Pages build into `assets/webapp/` (the tool rejects non-root `<base href>`).
- LAN protocol and Show-on-PC behavior are untouched by all of this; only how the
  bundle gets built and checked changed.

## 5. CI behavior (`.github/workflows/build.yml`)

- Toolchain pinned (`flutter-version: 3.47.2`), `pub get --enforce-lockfile`,
  analyze + tests in the `web` and `apk` jobs; `embedded-web` job gates the
  committed bundle via `--check`; the `apk` job rebuilds the bundle from source
  before building so APKs cannot embed stale web UI. Drift codegen
  (`dart run build_runner build --delete-conflicting-outputs`) runs before
  analyze in both build jobs so committed `.g.dart` files stay canonical.
- Permissions are least-privilege per job (`contents: read` default; Pages job
  adds `pages/id-token: write`; only the `release` job gets `contents: write`).
- Releases happen only on `v*` tags: signed APK (maintainer secrets, fail-closed
  without them) + `SHA256SUMS`, attached via the `release` job. Non-tag APKs are
  unsigned dev artifacts for testing, never published.
- No cloud services, no analytics, no secrets in the repo. A git remote *is*
  configured (`origin`), so pushing a branch or tag and reading the run is the
  real proof — workflow changes are still validated first by inspection plus
  the equivalent local commands, and a live CI run is required before trusting
  a release.
