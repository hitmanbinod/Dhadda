# Changelog

All notable user-facing changes. Dhadda is distributed via GitHub
Releases + F-Droid only.

## 1.4.0 (versionCode 3)

First public open-source release line (Apache-2.0).

- **Storage:** financial records moved from SharedPreferences JSON to
  a transactional SQLite database (Drift), with automatic,
  verification-gated migration that preserves existing data. Old
  backup files still import.
- **Sync:** record-level merge with per-record revisions and deletion
  records — two devices adding different transactions offline now
  converge instead of one side winning. Legacy Snapshot v1 peers still
  import.
- **Backups:** optional encrypted backup format (modern passphrase KDF
  + authenticated encryption) alongside labeled plaintext export.
- **App lock:** PIN attempts are rate-limited with progressive delays;
  the PIN remains a privacy gate, not encryption. Android cloud backup
  of app data is explicitly disabled; in-app export/import is the
  backup mechanism.
- **LAN sync:** session credentials are cryptographically random;
  wrong-PIN attempts throttled; request sizes bounded. Local HTTP
  remains trusted-LAN only — see `docs/SECURITY_LAN.md`.
- **Reminders:** exact alarms where the OS grants access, inexact
  fallback otherwise; delivery is best-effort on restrictive OEM skins.
- **Performance:** dashboard aggregates memoized (large histories stay
  responsive); deterministic 1k–50k benchmark harness (`docs/PERF.md`).
- **Builds:** pinned Flutter 3.47.2 toolchain, fail-closed release
  signing, reproducible embedded-web bundle, SHA256SUMS on releases.

What this release does **not** claim: database encryption at rest,
confidentiality against hostile networks, cloud sync, automatic
cross-device sync, or guaranteed reminder delivery on every OEM.

## 1.3.1 (versionCode 2)

Pre-roadmap baseline (see `docs/BASELINE.md` — historical record):
working beta with SharedPreferences storage, whole-snapshot sync,
PIN/biometric lock, SMS import, and phone-hosted web UI.
