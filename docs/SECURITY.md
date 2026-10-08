# Dhadda Security at Rest (Phase 3)

Distribution: GitHub + F-Droid only. No cloud, no accounts, no analytics.
Baseline record stays in `docs/BASELINE.md`.

## 1. Threat model (realistic only)

| Threat | Assessment | Control in place |
|---|---|---|
| A. Casual access to an unlocked phone | High likelihood, low skill | 4-digit app lock + progressive-delay throttle |
| B. Repeated PIN guessing | 10,000 combinations; physical access assumed | Throttle: 0–4 free, then 5/10/20/40/80/160s, 5-min cap; persisted; reset on unlock only |
| C. Extracted app storage (lost/stolen device, backup scrape, rooted read) | Locked modern device: Android file-based encryption + sandbox + `allowBackup=false` already protect. Unlocked/rooted: out of scope | Platform posture + explicit backup exclusion (no app change claims more) |
| D. Exported backup theft (chat/mail/drive) | High likelihood: plaintext exports are the most exposed artifact | OPTIONAL password-based encrypted backups (this phase) |
| E. Log exposure (logcat/crash files) | Medium: exception messages can echo payload bytes | Error-class-only logging (this phase) |
| F. Biometric bypass | OS-guaranteed: `biometricOnly` via `local_auth`; unlock-only, no key material | Documented limitations below |

Explicitly NOT claimed: rooted-runtime resistance, malicious-OS resistance,
memory-inspection resistance, LAN confidentiality (Phase 5).

## 2. App lock ≠ encryption (read before touching auth code)

- The 4-digit PIN is an **application privacy gate**: it keeps casual eyes
  out while the app opens. It is not, and can never be, encryption — 10,000
  combinations fall to offline brute force instantly.
- Biometric unlock is an **OS-backed shortcut to the same gate**: it proves
  presence, exposes no keys (there are none to expose), and falls back to
  the PIN silently.
- The PIN hash must never become, or derive, a database or backup key.
  Backup passphrases are independent user secrets (the UI refuses the idea
  that the app PIN qualifies).
- The lock re-arms when the app leaves the foreground (`hidden`/`paused`).
  Re-locking also **pops every route pushed above the shell** (Sync, Add,
  Scan), because the lock gate replaces only `home`: a pushed pairing screen
  would otherwise stay mounted, visible and interactive above the locked
  home, putting the pairing PIN and link secret on screen with no
  authentication at all.

## 3. PIN hashing: unchanged, with rationale

`PinVault` stores SHA-256(`expense-tracker::pin::v1::<pin>`) — salted against
rainbow tables across apps, but fast and unsalted per-install. Against an
attacker who already extracted app storage (the only way to reach the hash),
the data beside it is already readable, so a slower KDF would add theater,
not security, while complicating every install. Changed only if the storage
model ever makes the hash the hardest target — it is not.

## 4. Rate limiting (`PinThrottle`, `lib/security.dart`)

- Free attempts: failures 0–4 verify immediately (fat fingers forgiven).
- Then required waits of 5/10/20/40/80/160 seconds, capped at 5 minutes.
- Counter + last-failure timestamp persist in SharedPreferences
  (`expense_pin_fails_v1`, `expense_pin_lastfail_v1`): delays survive
  restart; corrupt values safely default to no delay (never crash the lock).
- Reset ONLY on successful unlock: PIN-pad success and biometric success
  (both prove the user; biometrics cannot be guessed). PIN change/remove
  verify through the throttle but never reset it, so settings cannot launder
  a guessing streak. No permanent lockout, no network, injectable clock for
  deterministic tests (`test/pin_throttle_test.dart`, 7 tests).

## 5. Biometrics: behavior and limits

- `local_auth`, `biometricOnly: true`, used in exactly two places: launch
  fast-path (`main.dart`) and enabling the toggle (`menu_screen.dart`).
  No custom biometric storage anywhere.
- Success unlocks the app and resets throttle delays (policy §4).
- Failure/unavailable/enrolled-changed falls back to the PIN pad silently;
  disabling the toggle needs no auth (settings sit behind the unlocked app).
- Device-credential fallback (PIN/pattern-as-biometric): not requested;
  `biometricOnly` excludes it. If the OS offers none enrolled, the pad stays.

## 6. Secure key storage: not required, none added

No cryptographic keys exist in this phase: database encryption is deferred
(§7) and backup encryption is password-based and portable by design (a
Keystore-wrapped key would break cross-device restore). Adding
`flutter_secure_storage` or equivalent would add review surface for zero
protected secrets. Revisit only if a future phase introduces a real key
(DB key under Option B).

## 7. Database encryption decision: DEFERRED (explicit)

Evaluated against Drift 2.x + sqlite3 native backend + schema v2 + F-Droid:

**Option A — plain SQLite + sandbox + `allowBackup=false` + app lock
(RECOMMENDED, adopted).** Gains: zero new native/binary surface, zero
migration risk, zero key-loss risk, F-Droid clean, current backup/restore
flows untouched. Threats solved: casual access (lock), cloud/backup scrape
(exclusion), locked-device theft (platform FBE). Not solved: powered-off
extraction past a weak lockscreen; rooted runtime (unsolvable in-app).

**Option B — encrypted SQLite (SQLCipher-class) with a random
Keystore-held key.** Gains: at-rest ciphertext against powered-off
extraction. Costs: prebuilt native crypto binaries (F-Droid + reproducible-
build friction), a key whose loss destroys everything, a crash-safe
plaintext→ciphertext migration over schema-2 data with rev/tombstone
preservation, ongoing maintenance. Threats still not solved: unlocked or
rooted runtime (key must be in memory to run).

**Option C — other FOSS at-rest designs** (file-level encryption, custom
stores): all strictly worse than A-or-B on complexity without improving the
threat coverage for a single-user offline app.

Decision: adopt A now; B stays a documented future option, NOT a silent
default. Revisit triggers: F-Droid-clean SQLCipher packaging, or a concrete
incident class A cannot cover. A " proven not-yet" beats a risky partial
cipher.

## 8. Encrypted backups: IMPLEMENTED (optional, additive)

- Format `dhadda-enc-backup` v1 (separate version line from Snapshot v1):
  Argon2id(password, random 16-B salt; 32 MiB, 3 passes, 1 lane) →
  XChaCha20-Poly1305 AEAD (random 24-B nonce per backup) over the exact
  Snapshot v1 JSON. Parameters ride in the envelope for agility.
- Plaintext export/import is unchanged and remains the default; `.enc.json`
  export sits beside it in Menu → Backup; both file imports auto-detect and
  prompt for the passphrase (`lib/sync/backup_crypto.dart`,
  `lib/widgets/backup_password.dart`).
- Guarantees tested (`test/backup_crypto_test.dart`, 8 tests): round-trips
  (unicode/empty/populated/bulk), wrong password → clear message, bit-flip →
  auth failure, malformed/absurd envelopes fail before KDF work, ciphertext
  randomized per encryption, empty password refused, decrypt failure touches
  no app state.
- The app PIN is refused as a concept (UI copy says so); passphrases are
  never stored, logged, or synced.

## 9. Web security boundary

GitHub Pages and phone-hosted Web use `PrefsDomainStore` (browser storage):
no Keystore equivalent exists there, and none is claimed. Encrypted-backup
*files* work identically in browsers (pure-Dart crypto), but data the hosted
app itself holds is only as private as the browser profile. No cloud added.

## 10. Android backup: unchanged and verified

`android:allowBackup="false"` (Phase 1) still set — re-verified in
`AndroidManifest.xml` during this phase; no Phase-3 change touches it.
Explicit user Export/Import (now incl. encrypted) remains the only backup
mechanism. `docs/BACKUP_POLICY.md` still authoritative.

## 11. Sensitive logging policy (audited this phase)

Rule: logs carry operation type, counts, and error CLASSES — never messages,
stacks, payloads, or secrets. Changed: all `($e)` interpolations in
`lib/store.dart` → `(${e.runtimeType})`; phone-host counter/handler logs
likewise; the host's HTTP 500 body no longer echoes exception text
(`Dhadda host error (<class>).` instead). Kept deliberately: request
method+path (static routes only), orphan-drop counts, Node startup line and
local-only crash file (V8 stacks carry no values; relay errors are static
strings). SMS bodies, notes, amounts, snapshots, PINs/hashes, QR secrets:
no log site found in Dart, Kotlin (`MdnsHelper` logs codes only), or Node.

## 12. Recovery / key-loss behavior

- No encryption keys exist → nothing to lose; reinstall/app-clear behaves
  exactly as before (fresh install path, legacy keys absent).
- Forgotten backup passphrase = unopenable file (by design; stated in the
  export dialog). No backdoor, no recovery question.
- Real-data validation stays on emulator/copies/test installs, never the
  primary phone; real exports stay outside Git.

## 13. Manual verification procedure

1. Fresh install → set PIN → fat-finger 5 wrong tries → 5s wait shown →
   correct PIN unlocks instantly with no wait.
2. Kill/reopen mid-delay → delay persists.
3. Enable biometric (if available) → unlock via biometric after failures →
   counter reset.
4. Export encrypted backup with passphrase → share to PC → wrong password
   fails clearly → right password imports with identical totals.
5. `adb logcat` while syncing/failing: error classes only, no notes/amounts.
6. Confirm `allowBackup=false` still in the manifest.
