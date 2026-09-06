# Dhadda Android Backup Policy (explicit, Phase 1)

## Previous behavior (implicit, risky)

No `android:allowBackup`, `fullBackupContent`, or `dataExtractionRules` was set
(verified in `android/app/src/main/AndroidManifest.xml` at Phase 0). Android
therefore Auto-Backed-Up the app by default: all SharedPreferences XML —
including `expense_txns_v1` (every transaction), `expense_loans_v1`,
`expense_backups_v1` (5 full snapshots), and `expense_pin_hash_v1` — was
eligible for upload to the user's Google Drive and for restore onto other
devices. Plaintext finances in cloud backup, with no user action or warning.

## New behavior (explicit)

`android:allowBackup="false"` on the `<application>` tag. Android performs no
cloud Auto Backup and no device-to-device restore of Dhadda data on any API
level (the flag predates `dataExtractionRules`, so no version split is needed).

Excluded: everything local — all `expense_*_v1` domain keys, PIN/biometric
state, SMS dedup IDs, settings. Nothing is carved out because nothing local is
safe to upload implicitly.

## What still works

- On-device storage is completely unaffected (`allowBackup` governs backup
  transport only, never local reads/writes).
- The intentional mechanism is the in-app **Export/Import** (share-sheet JSON /
  file picker, `lib/sync/file_sync.dart`) — user-initiated, user-routed,
  restorable via `restoreBackup`.

## Impact the maintainer accepts

- New phones will NOT receive Dhadda data via Google device-migration restore;
  migrate with an in-app Export file instead.
- Uninstall without an export still loses data (unchanged from before in
  practice — Auto Backup restore was never a supported flow).
- If a future encrypted store (Phase 3) changes the at-rest posture, revisit
  whether selected non-sensitive prefs may re-enter backup scope. Until then,
  this file is the decision record.
