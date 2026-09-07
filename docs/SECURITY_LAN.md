# Dhadda LAN Security (Phase 5)

Local-first, offline-first, cloud-free. No sync semantics changed in this
phase (revisions, tombstones, merge, v1 compat all Phase 4 behavior).
Baseline record stays in `docs/BASELINE.md`.

> **Authentication over plain HTTP does not provide confidentiality against
> a network observer.** Everything below raises the cost of guessing,
> abuse, and accidents on trusted networks. It does not make hostile
> networks safe. Use Show-on-PC and LAN sync only on networks you trust.

## 1. What is exposed, and to whom

| Surface | Authentication | Content sensitivity |
|---|---|---|
| Phone-host static bundle (`/`, assets) | none (public by design) | none: stock app files, no user data (the served UI is an independent empty instance until the user pairs it) |
| Phone-host `/api/ping` | none | existence + URL only (same as mDNS advertises) |
| Phone-host link API | per-box PIN (4–12 chars, user-chosen) | full snapshots of whoever paired |
| Direct-WiFi sender API | 6-digit sender PIN, then optional session token | full snapshots both directions |
| Node relay link/mailbox API | per-box PIN | full snapshots of whoever paired |
| mDNS | none (discovery only) | service name + port only |

## 2. Trusted-network requirement

Show-on-PC and Direct-WiFi UI state it inline (concise, no alarmism):
home WiFi or personal hotspot only — never airport, hotel, or open WiFi;
stop serving when done; QR codes hold address + PIN, so don't forward their
screenshots; pairing codes live as long as their box, so Stop/Unpair after
pairing. A passive observer on the same network sees credentials and
snapshots in cleartext — that is physics on plain HTTP, not a bug to patch
with UI copy.

## 3. PIN throttling (all servers, same policy)

`LanThrottle` (`lib/sync/lan_throttle.dart`): 10 free failures per scope,
then HTTP 429 + `Retry-After` for 60 s; any success resets; no permanent
lockout. In-memory and bounded (global 2-counter scope for single-PIN
servers; per-box scopes for link mailboxes, which already cap at 50 boxes
with TTL — no attacker-growable state). Correct credentials always work,
even mid-cooldown; only failures count. Restart resets (server lifetimes
are minutes-to-open-hours; documented, not a bypass: guessing 10 PINs per
restart across a 6-digit/8-char space stays infeasible inside credential
lifetimes). Wrong-PIN on non-existent boxes is not counted (404s are not
guesses); 403s are.

## 4. Direct-WiFi sessions

- Bootstrap: `POST /auth {pin}` → `{token}` (wrong PIN counts toward the
  throttle; unknown routes 404 for old senders, whose receivers keep the
  PIN header).
- Token: 128-bit CSPRNG hex (`Random.secure`), sent once in JSON, then
  `Authorization: Bearer`. Accepted alongside the legacy PIN header.
- TTL: server lifetime (≤5 min auto-close); no sliding refresh, no
  inactivity timeout needed at that span. Cap: 16 live tokens (oldest
  evicted). Revoke: `POST /logout` (idempotent) + server stop clears all.
- Replay within TTL is possible to a passive observer — stated, not solved
  (a nonce/MAC scheme would be theater without confidentiality; short TTLs
  are the control — see §9).
- Simple string equality is used for PIN/token compares: timing attacks
  over LAN against 128-bit tokens add nothing, and short numeric PINs are
  throttle-bound instead. Documented as a deliberate non-control.

## 5. Phone-host link API: sessions deliberately NOT added

The mailbox protocol is shared by three implementations (Node relay, phone
host, old app versions). PIN-per-request + per-box throttle + 7-day TTL is
the proportionate control there; a token layer would fork the protocol for
zero confidentiality gain on plain HTTP. Revisit only with a transport that
makes tokens meaningful.

## 6. Request limits and validation

- Bodies capped at 8 MiB on Dart servers (`lib/sync/http_limits.dart`;
  Content-Length pre-check → clean 413, streaming backstop for chunked).
  Basis: bulk-300 ≈ 67 KiB, ~1.5 MiB at 5k v2 records (~5x headroom, not a
  behavior limit). Node keeps its 6 MiB cap (same headroom class).
- Malformed JSON → 400, oversized → 413, both before any state mutation
  (upload handlers never run: tested with an upload counter).
- Shape checks stay minimal and compatible: JSON-validity + required-string
  fields; no content-type zealotry (native + browser clients vary; attackers
  set headers anyway).
- Errors are static strings; 500s carry only the error class (Phase 3
  policy extends here).

## 7. CORS: kept permissive on purpose

`Access-Control-Allow-Origin: *` remains on API responses because
browser-hosted Dhadda instances (phone browser receiving, Pages demo) call
these APIs cross-origin — removing it breaks legitimate receivers. The
residual (a hostile site attempting PINs cross-origin) is bounded by the
same throttle + TTLs that bound native attackers (≤10 free guesses, then
60 s cooldowns, inside minute-scale credential lifetimes). CORS was never
authentication; same-origin behavior for hosted UIs is unchanged.

## 8. Node relay protections

Same throttle policy (global bucket for the offer/session flow, per-box for
link push/pull), same 6 MB cap, static error strings, no payload/PIN/token
logging (only the pre-existing startup line + local crash file, whose V8
stacks carry no values). Mailbox data is in-memory with the existing TTLs;
the relay operator/process inherently sees relayed snapshots — that
boundary is unchanged and stated: run the relay on a machine you trust
(yours). `node --check` clean; live PIN-throttle + v2-passthrough +
safe-error behavior covered by tests.

## 9. Replay / integrity investigation (finding: defer protocol)

Captured PINs, tokens, and snapshots are replayable by a passive observer
for their TTLs — inseparable from plain HTTP. Evaluated: nonces, request
IDs, monotonic counters, timestamp windows, session-keyed MACs. All need a
confidential channel or pre-shared secret to beat "attacker replays bytes";
with neither, they add complexity without moving the boundary. Deferred
honestly. Controls that DO bound replay: ≤5-minute sender/token lifetimes,
explicit logout, per-pairing link PINs, Stop/Unpair hygiene.

## 10. TLS decision: deferred with rationale

Local HTTPS was investigated, not implemented. Trustworthy validation would
need user-installed CA/cert UX on rotating LAN IPs (often `192.168.x.y`
today, different tomorrow) plus mDNS-name handling, F-Droid offline builds,
and cert rotation — while browsers greet self-signed LAN certs with
warnings users learn to click through. That manufactures a padlock feeling
without trustworthy authentication: worse than honest HTTP + short-lived
credentials + trusted-network guidance. Revisit only with a genuinely
usable trust story (e.g., OS-trusted local CA flow), never silently.

## 11. mDNS / QR / discovery boundaries

- mDNS advertises service name + port only (verified in `MdnsHelper.kt`
  usage: `register(name: 'dhadda', port: …)`); never PINs, tokens, identity,
  or data. Discovery is not authentication.
- Direct-WiFi QR = URL + ephemeral PIN (server dies in ≤5 min). Link QR =
  origin + code + PIN with box TTL (days): treat as a secret while it
  lives, Stop when paired. QR is transport, not encryption. No QR/secret
  logging anywhere (verified: clients log nothing).
- No app-PIN material on LAN (verified: only pairing PINs travel).

## 12. Sensitive logging (Phase 3 policy holds)

LAN logs: method + static path, counts, error classes, 429/413/400 codes.
Never: PINs, tokens, Authorization headers, full URLs with secrets, query
strings carrying credentials, snapshots, financial content, SMS, backup
passwords. `git grep`-audited across Dart/Kotlin/Node in this phase.

## 13. What Phase 5 did NOT change

Sync semantics/revisions/tombstones/merge, v1 compat, money, schema (still
v2), PIN hashing, at-rest encryption posture, Provider/store shape, UI
beyond three guidance lines. No new dependencies (Dart `Random.secure` +
shelf/Node builtins only).

## 14. Remaining threats (accepted, stated plainly)

- Passive observer on the same network reads credentials + snapshots.
- Active MITM owns the exchange outright.
- Link-box PINs (user-chosen, sometimes 4 digits) + 7-day boxes: throttle
  bounds guessing, but a weak PIN on a long-lived box is the weakest link —
  prefer longer PINs; Stop/Unpair when done.
- Throttle state resets on server restart (bounded DoS-for-guesses tradeoff).
- No CSRF machinery: sessions are explicit Bearer tokens, never cookies.

## 15. Manual verification (emulator/spare/synthetic only)

1. Show on PC → second browser: trusted-network warning visible.
2. Wrong access PIN ×11 on link pull → ten 403s, then 429 + Retry-After;
   correct PIN works immediately after (no lockout).
3. Direct WiFi: `/auth` wrong PIN → 403; right PIN → 32-hex token; Bearer
   reads; logout → Bearer 403s; stop server → all access dies.
4. 8 MB+ POST → 413 with state unchanged; garbage JSON → 400.
5. `adb logcat` + Node console during failures: classes/codes only.
6. Full v2 sync round-trip still converges (regression: existing suites).
