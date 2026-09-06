# Dhadda Reproducible-Build Notes (Phase 1 investigation)

Status: **investigated and documented, NOT demonstrated.** No two-environment
comparison has been run. Do not claim reproducibility.

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
5. **No git remote is configured** in this clone, so CI behavior is validated by
   inspection + local command parity, not by observed CI runs.

## What "demonstrated" would require (future work)

Build the same tag twice in clean containers (same `.fvmrc` toolchain),
normalize only documented non-semantic container metadata, compare hashes,
bisect the remaining diffs (start with zip timestamps via `SOURCE_DATE_EPOCH`
experiments and `--split-debug-info` stripping), and record the exact
toolchain fingerprints. Until then, releases are *traceable* (tag → lockfile →
toolchain → checksums) but not *proven reproducible*.
