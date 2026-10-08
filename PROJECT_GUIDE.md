# Dhadda — Complete Project Guide

What this is, its Phases 0–8 history, the September 17, 2026 audit changes,
build artifacts, and remaining release work. Historical phase completion does
not mean production certification; see sections 14–19 for current status.
Repository: `https://github.com/hitmanbinod/Dhadda` · License: Apache-2.0 ·
Release line: **1.4.0+3** (`com.dhadda.expense`).

---

## 1. What Dhadda is

Minimal, offline-first, single-user expense tracker (Flutter + Dart,
Material 3, Android-first with a phone-hosted Flutter Web companion).
No accounts, no cloud, no ads, $0 operating cost. Features: expense/income
entry with reorderable categories, budgets, projects ("events"), lent/borrowed
ledger with reminders, file backup/export/import (plaintext + optional
encrypted), direct-WiFi PIN sync, link-mailbox relay sync (phone-hosted or
zero-dependency PC Node relay), "Show on PC" browser UI over LAN, mDNS,
opt-in Nepali-bank-tuned SMS import, PIN + biometric lock, Material You
theming. Distribution: **GitHub Releases + F-Droid only** (no Google Play).

## 2. Starting point (pre-roadmap, v1.3.1+2)

A working beta with three structural weaknesses that drove the roadmap:

1. **SharedPreferences-as-database** — all financial data as monolithic
   JSON values, rewritten in full on every change; no integrity, indexes,
   migrations, or encryption.
2. **Whole-snapshot last-write-wins sync** — two devices editing offline
   could silently lose one side's transactions; clock skew caused divergence.
3. **Implicit security posture** — 4-digit PIN oversold as protection,
   debug-signed releases, implicit Android cloud backup of plaintext data,
   stale embedded web bundle, unpinned toolchain.

Deliberately kept throughout: Flutter (Android + Web from one codebase),
Provider/ChangeNotifier (never migrated), offline-first, zero backend.

## 3. Phase 0 — Frozen baseline (COMPLETE)

- Baseline tag `pre-security-storage-migration` on v1.3.1+2.
- `docs/BASELINE.md` (historical record — never rewritten), behavior table,
  synthetic Snapshot v1 fixtures (`test/fixtures/phase0/`: empty, single,
  populated, 300-bulk, unicode, legacy, 3 corrupt shapes + generator),
  fixture round-trip tests. Suite was 49 tests then.

## 4. Phase 1 — Build / release foundation (COMPLETE)

- Pinned Flutter **3.47.2** (`.fvmrc` + CI `flutter-version`, must agree).
- **Fail-closed release signing**: no keys + no dev flag = hard Gradle
  error; debug-signed "releases" impossible. Secrets live only in CI.
- Deterministic embedded-web tool (`tool/build_embedded_web.dart`):
  root-relative bundle, version-checked, stale-wipe, `--check` for CI.
- Pages web build kept as a separate `--base-href` artifact, never
  copied into the app.
- GitHub Actions uses a pinned Flutter SDK, version-tagged actions,
  least-privilege permissions, lockfile enforcement, and Drift regeneration.
  Actions are not pinned to immutable commit SHAs, and regeneration alone
  does not assert that committed generated files match. Initial FOSS audit + Fastlane
  metadata skeleton. Explicit `allowBackup=false`.
- Reproducibility investigated and honestly labeled "not demonstrated".

## 5. Phase 2 — Real persistence (COMPLETE)

- `DomainStore` abstraction (`lib/data/domain_store.dart`); **Drift +
  SQLite** on native (`DriftDomainStore`), `PrefsDomainStore` kept for
  Web and as fallback.
- Schema v1 → v2 migration path (see §8 for v2 columns); safe,
  idempotent, verification-gated SharedPreferences migration that
  refuses to clobber on mismatch. Snapshot v1 import preserved.

## 6. Phase 4 — Sync correctness (COMPLETE, done before Phase 3 per plan)

- **Snapshot v2**: per-record `(rev, by)` logical revisions, tombstones
  (never GC'd), deterministic conflict ordering, legacy v1 import kept.
- Proven by fuzz + store + live-transport tests, incl. 1k/5k merge
  timing observations.

## 7. Phase 3 — Security at rest & lock (COMPLETE)

- PIN throttling (persisted progressive delays), PIN documented as a
  privacy gate (never an encryption key), **optional encrypted backups**
  (Argon2id + XChaCha20-Poly1305, pure-Dart `cryptography` package),
  log redaction, backup-policy docs. No database encryption (explicit
  decision, documented tradeoffs). No Android Keystore-backed application
  secret store was implemented; `docs/SECURITY.md` section 6 explicitly
  documents that decision. This corrects the earlier summary's claim.

## 8. Phase 5 — LAN hardening (COMPLETE)

- Throttled auth, bounded sessions/caps/body sizes, cryptographically
  random link secrets (PIN-only legacy peers rejected without silent
  downgrade), corrected trusted-LAN threat docs. Plain-HTTP LAN kept
  and honestly labeled trusted-home-network-only.

## 9. Phase 7 — Integration & device testing (COMPLETE)

- Host suite grew 49 → **179 tests** (migration, drift, sync-v2, crypto,
  throttle, SMS channel, reminders, diagnostics, log-privacy, journeys).
- Real-device validation on Xiaomi/Android 15: app render PASS,
  integration subset 2/2 PASS, biometric+PIN PASS, Show-on-PC IP PASS
  (+ stop/disappearance PASS), phone→PC relay transport PASS (tracer +
  live v2 payload), real-inbox SMS (channel/scan/candidates/Allow PASS;
  45-item import + rescan dedup PASS; denied-path PASS).
- Notable findings, all recorded in `docs/TESTING.md`: stale-harness-APK
  black screen (process fix, no code), HyperOS notification suppression
  (inexact → **exact alarms with inexact fallback** + in-context grant
  UX implemented and tested), Windows `.local` limitation, 60–90s fresh
  cold start. Two-physical-device convergence remains a hardware gap
  (non-blocking: transport + automated merge evidence stand).

## 10. Phase 6 — Performance (COMPLETE)

- Deterministic 1k/5k/20k/50k harness (`benchmark/`, CI-excluded).
- Found: dashboard triple-scan cost 1.4s/rebuild at 50k. Fixed by
  memoized single-pass analytics (`lib/analytics.dart`, `updatedAt`
  key) with 7 bit-exact equivalence tests — steady state ~0ms, cold
  compute 0.70ms at 50k. Public API unchanged.
- Measured verdicts, no guessing: no DB paging (15ms debounced filter
  + windowed rendering suffice), no index changes, no watch
  restructuring, no lazy startup (sync/export need full state), no
  isolates. Suite 186/186. Details: `docs/PERF.md`.

## 11. Phase 8 — Release engineering (repository work COMPLETE)

- Maintainer chose **Apache-2.0** (`LICENSE`), **1.4.0+3** (pubspec,
  `lib/version.dart`, embedded bundle, `fastlane/.../changelogs/3.txt`).
- Rewrote stock README; added truthful `docs/CHANGELOG.md` (with
  explicit non-claims); completed F-Droid submission reference
  (`docs/FDROID.md`); three artifact identities separated
  (debug-signed dev / genuinely **unsigned** F-Droid-shape /
  maintainer-signed GitHub) after review caught the unsigned path
  falling back to the debug key — fixed via `signingConfig = null`,
  production stays fail-closed.
- Reproducibility demonstrated: two full post-clean **unsigned**
  rebuilds byte-for-byte identical (`14E3118B…E0A45`); APK inspected
  (ID/version/non-debuggable/allowBackup=false, 8 accountable native
  libs/ABI, no GMS). FOSS audit clean (all BSD/MIT/Apache).
- GitHub workflow: tag-triggered, `dhadda-<tag>.apk` + SHA256SUMS.
  Statically verified; live CI needs a remote run.

## 12. How to work this repo

```text
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test                                   # 187 host tests at f5795f6
flutter test benchmark/                        # perf harness (not CI)
flutter test integration_test -d <android>     # needs device; SMS/SMSTP branches need inbox/relay setup
dart tool/build_embedded_web.dart --check      # embedded bundle freshness
flutter build apk --debug                      # local device testing
DHADDA_ALLOW_UNSIGNED_RELEASE=1 flutter build apk --release   # unsigned F-Droid-shape (never publish)
flutter build apk --release                    # fails closed without android/key.properties
```

Rules that survived all phases: Provider stays; money stays `double`;
Snapshot v1 import, v2 semantics, `(rev, by)` ordering, tombstones,
PIN model, backup crypto, LAN model, and `docs/BASELINE.md` are frozen
unless a new phase explicitly reopens them. Never `git add .` from a
parent dir; never commit secrets; never claim what wasn't measured.

## 13. Release checklist (maintainer actions remaining)

1. Create the keystore (`docs/RELEASE.md` §2), back it up twice, never
   commit it. 2. Add the 4 `DHADDA_KEYSTORE_*` CI secrets. 3. `git tag
   v1.4.0`, push **only the tag**. 4. GitHub Actions publishes the
   signed APK + checksums. 5. Submit the fdroiddata entry
   (`docs/FDROID.md` §6 has the recipe facts). 6. Tell users switching
   between GitHub and F-Droid builds requires reinstall (different
   signers).

## 14. September 17, 2026 audit fixes (12 local commits, `5ce8059..f5795f6`)

All on top of Phase 8. `flutter analyze` clean, host suite 187 tests
at `f5795f6`. Commits are local on `master`, nothing pushed.

Build / CI (2):

- `5ce8059` — drop nonexistent `cupertino_icons` asset dirs (CI
  analyze was red).
- `f7e5a9d` — CI signing fix: `storeFile` resolves relative to
  `android/app/` (`build.gradle.kts`), so the workflow writes
  `android/dhadda-release.jks` + `storeFile=../dhadda-release.jks`
  (`android/key.properties`), same shape as `docs/RELEASE.md`.
  See `.github/workflows/build.yml:109-118`.

High (5):

- H1 `42f4d49` — persist failures surface instead of fake `Saved`.
  `lib/store.dart:375` `_persistDomain` now returns `bool` (restores
  in-memory + revs/tombs on failure, sets `lastPersistError`);
  `lib/screens/add_screen.dart:337-344` and
  `lib/widgets/entry_actions.dart:57` show
  `Could not save — storage failed` and keep the entry. Covered by
  `test/migration_test.dart` failure case.
- H2 `9494db5` — diff-based reminder refresh.
  `lib/sync/reminders.dart:136-175`: builds `wanted` set, reschedules
  each loan independently, cancels only `_active.difference(wanted)`,
  tracks only what actually scheduled. Partial failure can no longer
  wipe all reminders via blanket `cancelAll`.
- H3 `2f8ae3b` — re-lock on background.
  `lib/main.dart:212-223`: `hidden`/`paused` re-sets `_locked=true`
  when the vault is enabled. Before, the lock only guarded process
  death (background → recents → return skipped PIN/biometric).
- H4 `5ff2572` — single-flight auto SMS import.
  `lib/main.dart:134-143` `_smsBusy` guard: overlapping boot+resume
  runs no longer parse the same inbox rows twice. Later call drops;
  next lifecycle event retries.
- H5 `ff9f028` — branded launch splash.
  `android/app/src/main/res/drawable/launch_background.xml:1-8` and
  `drawable-v21` variant: app icon centered on background for the
  first-frame window (matters on the documented 60–90s first-launch
  dexopt).

Medium (5 fixes in 4 commits):

- M1 `901dad4` — PBKDF2-HMAC-SHA256 PIN hashing.
  `lib/security.dart:19-59`: 10,000 iterations, 16-byte
  `Random.secure` salt per user, format
  `pbkdf2$iterations$salt-b64$hash-b64`. Legacy static-salt SHA-256
  entries still verify (`matches`, `lib/security.dart:63-83`) and
  upgrade on next PIN set. `test/pin_test.dart` covers both schemes.
- M2 `23e1ce2` — erase-all confirm honesty.
  `lib/screens/menu_screen.dart:886-888`: second dialog now says the
  app lock (PIN/biometric) and all settings go too.
- M3+M4 `f7a0d99` — CSV export + SMS dedup cap in one commit:
  `lib/sync/file_sync.dart:77-83` RFC-4180 escaping (quote when the
  field holds `"`, `,`, or newline; double embedded quotes — no more
  comma mangling); `lib/sync/sms.dart:55` imported-id cap 500→2000
  (oldest-first eviction).
- M5 `f5795f6` — WiFi receive button labeled as exchange.
  `lib/screens/sync_screen.dart:1007-1014`: `Receive / exchange now`
  + hint `Merges their data in and sends yours back so both sides end
  up with the same entries` (it merges in AND pushes back).
- M6 `c63b73c` — CSPRNG LAN session PIN.
  `lib/sync/wifi_host_io.dart:310-313` `newPin()` uses
  `Random.secure` (was time-seeded). Note: the older
  `lib/screens/sync_screen.dart:458-459` `_makePin()` time-seeded
  helper is still present on the send path; the canonical helper is
  `newPin()` in `wifi_host_io.dart`.
  **RESOLVED** — both call sites now use the CSPRNG generator and the
  duplicate is deleted; it lives in `lib/sync/session_pin.dart`,
  exported by the io server *and* the web stub.

Explicitly NOT touched (low items, by design): accessibility /
Semantics coverage, notification-tap deep-link, decimal display
rounding.

## 15. Test APKs built September 17, 2026 (local `build/`, gitignored)

```text
build/app/outputs/flutter-apk/app-debug.apk      212.2 MB  2026-09-17 16:10
build/app/outputs/flutter-apk/app-release.apk     88.3 MB  2026-09-17 20:24
```

SHA256 (this machine, these exact bytes):

```text
096CC3331CFCCC59E2A9E4E5E84B5DC6177E3CB7B67A18119F54063B1C9F6854  app-debug.apk
4FEEA43149348B7CFE584648EE80759DAEB3CA095CFCA8228CFBD9981A1D5048  app-release.apk
```

Build commands used:

```text
flutter build apk --debug
DHADDA_ALLOW_UNSIGNED_RELEASE=1 flutter build apk --release   # 631.9s, Font tree-shake 1645184 -> 12064 bytes
```

Installability warning: the release APK above is the **unsigned
F-Droid-shape** dev path (`signingConfig = null`). Android refuses to
install a truly unsigned APK — for on-phone testing use the debug APK,
or sign the release bytes yourself (`apksigner`) / run the signed CI
path. Do not publish the unsigned file.

## 16. Verification status (what was actually run here)

- `flutter analyze` (Sept 18): `No issues found!` (~80s). Only
  `flutter pub outdated` notices (38 packages with newer majors
  blocked by constraints) — not failures.
- Host tests: 187 at `f5795f6` (guide §12 command). Final-tree rerun
  is cheap (`flutter test`) but was not re-executed after the doc-only
  edits in this session; rerun before any tag.
- `flutter devices` (Sept 18): only Windows/Chrome/Edge visible — no
  phone connected, so no on-device install, splash check, two-device
  sync, or notification-delivery check was possible here.
- CI signing fix (`f7e5a9d`) is statically verified against
  `build.gradle.kts` + `docs/RELEASE.md`; live proof needs a tag-push
  CI run (see §13).
- Reproducibility claim in §11 (`14E3118B…E0A45`) predates the §14
  fixes; do not reuse those hashes for the current tree.

## 17. Install / test cheat-sheet (phone)

USB (recommended):

```text
# phone: tap Build number 7x -> Developer options -> USB debugging on,
# plug in, accept the RSA prompt, HyperOS may also need "Install via USB"
flutter devices            # phone must appear
flutter build apk --debug
flutter install
# manual fallback: copy build/app/outputs/flutter-apk/app-debug.apk to the
# phone, tap it, allow "install from unknown sources"
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

No cable: mail/Drive/WhatsApp the APK to yourself, open it on the
phone, allow installs from that app when asked.

Process notes from `docs/TESTING.md` (still apply): if a previous run
shows a black screen, uninstall first (stale harness APK); Xiaomi /
HyperOS notification tests need the in-context exact-alarm grant flow.

## 18. Remaining work / known limitations

1. Push + throwaway tag to prove CI signing live (statically fixed
   only).
2. Device checks: splash first frame, two-device convergence, SMS
   auto-import on real inbox, stock-Android notification delivery,
   Show-on-PC + relay from §9 against the new tree.
3. Low items deferred: Semantics coverage, notification-tap
   deep-link, decimal display rounding — say the word to schedule.
4. Tech debt noted while fixing: **DONE** — `_makePin()` deleted;
   both the send path and the relay box use the CSPRNG `newPin()` in
   `lib/sync/session_pin.dart`.
5. CI hardening gaps: actions version-tagged, not SHA-pinned; Drift
   regeneration without a committed-output diff check.
6. Housekeeping: `windows/flutter/generated_*` shows local
   modifications; `PROJECT_GUIDE.md` itself was untracked at time of
   writing — commit deliberately, never `git add .` from a parent
   dir, never commit secrets or keystores.

## 19. Where to look next

- Truthful behavior + non-claims: `docs/CHANGELOG.md`, `docs/BASELINE.md` (frozen).
- Security posture: `docs/SECURITY.md` (§6 = no Keystore app-secret store), `docs/SECURITY_LAN.md`.
- Persistence / sync: `docs/PERSISTENCE.md`, `lib/data/domain_store.dart`, `lib/sync/sync_v2.dart`.
- Release / F-Droid: `docs/RELEASE.md`, `docs/FDROID.md`, `docs/TESTING.md`, `docs/PERF.md`, `fastlane/metadata/android/en-US/changelogs/3.txt`.
- Entrypoints: `lib/main.dart:206-223` (lifecycle), `lib/store.dart:375-401` (persist), `lib/security.dart:14-59` (PIN), `lib/sync/reminders.dart:136-175`, `lib/sync/wifi_host_io.dart:85-313`, `lib/screens/sync_screen.dart:911-1014`.
