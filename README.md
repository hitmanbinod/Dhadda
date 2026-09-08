# Dhadda

Minimal, offline-first, single-user expense tracker. No accounts, no cloud,
no fees, no ads — your data never leaves your devices.

- **Track** daily expenses/income across reorderable categories, event
  budgets ("events"), and a lent/borrowed ledger with reminders.
- **Private by design:** everything is stored on-device (SQLite for
  records, app preferences for settings). Optional encrypted file
  backups; explicit user-controlled export/import.
- **Sync over your own WiFi only:** direct PIN sync, link-mailbox relay
  (including a zero-dependency PC relay), and a phone-hosted "Show on
  PC" browser UI. Sync merges at record level and never silently drops
  offline edits.
- **SMS import (opt-in):** parses bank/wallet messages on-device into
  transactions; nothing is uploaded.
- **Lock:** optional 4-digit app PIN (a casual-privacy gate, not
  encryption) plus biometric unlock shortcut.

## Distribution

GitHub Releases and F-Droid only — no Google Play, no proprietary
services. See [`docs/RELEASE.md`](docs/RELEASE.md) for signing,
[`docs/FDROID.md`](docs/FDROID.md) for F-Droid notes, and
[`docs/CHANGELOG.md`](docs/CHANGELOG.md) for release notes.

License: [Apache-2.0](LICENSE).

## Limitations worth knowing

- Sync and "Show on PC" assume a **trusted home/private LAN**; traffic
  is plain HTTP on your network (see `docs/SECURITY_LAN.md`).
- Reminders are best-effort one-time OS alarms; aggressive OEM battery
  management can delay them (see `docs/TESTING.md`).
- `dhadda.local` discovery is best-effort; the numeric IP URL is the
  supported path on networks without mDNS.

## Build from source

Requires Flutter 3.47.2 (see `.fvmrc`), JDK 17, Android SDK:

```text
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release   # needs android/key.properties (docs/RELEASE.md)
```

`flutter test benchmark/` runs the (non-CI) performance harness.
