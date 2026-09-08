# Dhadda Reproducible-Build Notes (Phase 1 investigation, Phase 8 evidence)

Status (2026-09-08, Phase 8): **functionally reproducible, binary differs
only in the signature block** — demonstrated locally, not yet across
independent environments. Do not claim byte-for-byte reproducibility.

## Demonstrated (same machine, Flutter 3.47.2, JDK 17, two full
`flutter build apk --release` runs after `flutter clean`)

- Both APKs: 512 ZIP entries, identical names/order/sizes/timestamps.
- All 512 entry contents byte-identical (per-entry SHA256 compared):
  Dart AOT, engine, resources, manifest, native libs
  (`libsqlite3.so` from drift build hooks, `libflutter_zxing.so`
  from source), META-INF.
- Total byte differences: 7,759 in one 7.8KB span inside the APK
  signing-block region (before the central directory) — consistent
  with per-run signature-block nondeterminism under debug signing.
  No code/resource/manifest byte differs.
- Same-state incremental rebuilds were bit-identical (weak datapoint:
  shared build cache, honestly labeled as such).

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
5. **No git remote is configured** in this clone, so CI behavior is validated by
   inspection + local command parity, not by observed CI runs.

## What "demonstrated" would require (future work)

Build the same tag twice in clean containers (same `.fvmrc` toolchain),
normalize only documented non-semantic container metadata, compare hashes,
bisect the remaining diffs (start with zip timestamps via `SOURCE_DATE_EPOCH`
experiments and `--split-debug-info` stripping), and record the exact
toolchain fingerprints. Until then, releases are *traceable* (tag → lockfile →
toolchain → checksums) but not *proven reproducible*.
