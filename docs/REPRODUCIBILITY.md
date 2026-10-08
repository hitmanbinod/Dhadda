# Dhadda Reproducible-Build Notes (Phase 1 investigation, Phase 8 evidence)

Status (2026-09-08, Phase 8): **byte-for-byte reproducible for genuinely
unsigned release builds on the same machine.** Debug-signed builds are
NOT byte-identical (per-run signature-block nondeterminism) and must
never be mistaken for release artifacts — see §"Three artifact
identities". Cross-environment demonstration (e.g. F-Droid infra) is
still external.

## Demonstrated: two full unsigned rebuilds are bit-identical

`DHADDA_ALLOW_UNSIGNED_RELEASE=1 flutter build apk --release`, twice,
each after `flutter clean` (Flutter 3.47.2, JDK 17, same machine):

- Unsigned build 1 SHA256:
  `14E3118BE9F3562F001972B6C9935EA2A91A826C7194B293729A64202C8E0A45`
- Unsigned build 2 SHA256: identical (`14E3118B…E0A45`).
- `apksigner verify` fails on both (`Missing META-INF/MANIFEST.MF`),
  proving no certificate — debug or otherwise — is present.

This supersedes the earlier debug-signed comparison (512/512 entries
identical, ~8KB signing-block diff): that diff was signature
nondeterminism, eliminated at the source by building genuinely
unsigned. An earlier incremental same-state rebuild also matched
bit-for-bit (weak datapoint: shared cache, labeled as such).

## Three artifact identities (do not conflate)

1. **Debug APK** (`flutter build apk --debug`): debug-signed,
   debuggable, local development/testing only.
2. **Unsigned release APK** (`DHADDA_ALLOW_UNSIGNED_RELEASE=1
   flutter build apk --release`): release/non-debuggable, NO
   certificate (`signingConfig = null` in `build.gradle.kts`). This is
   the F-Droid/source-build shape: F-Droid signs its own builds. Never
   publish an unsigned artifact as a GitHub release.
3. **GitHub production APK** (tag + maintainer keystore via CI
   secrets): release/non-debuggable, maintainer-signed. Cannot be
   produced locally without the keystore; the build fails closed
   without it (verified: `Release signing keys missing` hard error).

## Caveats

- Clean rebuilds on stock Windows need symlink privilege (Developer
  Mode); without it the first post-clean build fails creating plugin
  symlinks and the retry succeeds. F-Droid/CI containers differ —
  this status covers same-machine content determinism only.
- Signing differs by distributor by design (GitHub maintainer key vs
  F-Droid key): the honest target remains source-to-binary
  traceability (tag + lockfile + toolchain + SHA256SUMS), for which
  content-identity is the meaningful property.

## What pins determinism today (improvements landed in Phase 1)

- Toolchain pinned: `.fvmrc` + `flutter-version: 3.47.2` in CI (was floating
  `stable`).
- Dependencies pinned: committed `pubspec.lock` + `flutter pub get
  --enforce-lockfile` in CI (was silent re-resolution).
- Embedded web: `tool/build_embedded_web.dart` rebuilds from source with fixed
  flags and version checks; the `apk` CI job rebuilds it before every APK so
  artifacts cannot silently mix versions.
- No remote services, no analytics, no server-driven config at build time.

## Known variability sources (blockers to bit-for-bit claims)

1. **Flutter/Gradle outputs embed absolute paths and timestamps.** Observed
   locally: build logs, `main.dart.js` sourceMappingURL-adjacent metadata, and
   APK zip entry timestamps differ run to run. No normalization step exists.
2. **Signing differs by distributor by design.** GitHub APKs (maintainer key)
   and F-Droid APKs (F-Droid key) will never be byte-identical; the honest
   target is *source-to-binary traceability* (tag + lockfile + toolchain +
   SHA256SUMS), not identical bytes across signers.
3. **Native artifacts:** `flutter_zxing` (zxing-cpp), canvaskit/wasm in the web
   bundle, and desugared JDK libs come from the toolchain/SDK — reproducible
   only if the toolchain is identical (see pinning above).
4. **Environment assumptions:** JDK 17 (Temurin in CI), Android SDK with
   current build-tools, `flutter`/`dart`/`keytool`/`sha256sum` on PATH, ~8 GB
   Gradle heap (`gradle.properties`). None of these are containerized yet.
5. A git remote **is** configured (`origin`), so CI behavior can be proven by
   pushing and reading the run. Until a run has been observed, treat the
   workflow as validated by inspection + local command parity only.

## What "demonstrated" would require (future work)

Build the same tag twice in clean containers (same `.fvmrc` toolchain),
normalize only documented non-semantic container metadata, compare hashes,
bisect the remaining diffs (start with zip timestamps via `SOURCE_DATE_EPOCH`
experiments and `--split-debug-info` stripping), and record the exact
toolchain fingerprints. Until then, releases are *traceable* (tag → lockfile →
toolchain → checksums) but not *proven reproducible*.
