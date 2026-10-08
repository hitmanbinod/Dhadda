# Dhadda LAN Security (Phase 5, incl. link-auth closure review)

Local-first, offline-first, cloud-free. No sync semantics changed in this
phase (revisions, tombstones, merge, v1 compat all Phase 4 behavior).
Baseline record stays in `docs/BASELINE.md`.

> **Authentication over plain HTTP does not provide confidentiality against
> a network observer.** Everything below raises the cost of guessing,
> abuse, and accidents on trusted networks. It does not make hostile
> networks safe. Use Show-on-PC and LAN sync only on networks you trust.

## 0. Guarantee tiers (read first)

- v2 <> v2: full record-level convergence guarantees
- v2 <> v1: backward-compatible, but guarantees are reduced on the legacy side
- v1 <> v1: original Snapshot v1 last-write-wins behavior remains

The same tiering applies to authentication strength below: wherever an old
client or relay cannot carry the strong link secret, that path keeps the
legacy PIN-only behavior with explicitly reduced guarantees -- never a
silent downgrade of a strong-capable pairing.

## 1. What is exposed, and to whom

| Surface | Authentication | Content sensitivity |
|---|---|---|
| Phone-host static bundle (`/`, assets) | none (public by design) | none: stock app files, no user data (the served UI is an independent empty instance until the user pairs it) |
| Phone-host `/api/ping` | none | existence + URL only (same as mDNS advertises) |
| Phone-host link API | per-box PIN **plus** 128-bit link secret when the box carries one (Sec. 5); legacy boxes PIN-only (reduced strength) | full snapshots of whoever paired |
| Direct-WiFi sender API | 6-digit sender PIN, then optional session token | full snapshots both directions |
| Node relay link/mailbox API | same link model as phone host (PIN + optional secret) | full snapshots of whoever paired |
| mDNS | none (discovery only) | service name + port only |

## 2. Trusted-network requirement

Show-on-PC and Direct-WiFi UI state it inline (concise, no alarmism):
home WiFi or personal hotspot only -- never airport, hotel, or open WiFi;
stop serving when done; QR codes hold address + PIN, so don't forward their
screenshots; pairing codes live as long as their box, so Stop/Unpair after
pairing. A passive observer on the same network sees credentials and
snapshots in cleartext -- that is physics on plain HTTP, not a bug to patch
with UI copy.

## 3. PIN throttling (all servers, same policy)

`LanThrottle` (`lib/sync/lan_throttle.dart`): 10 free failures per scope,
then HTTP 429 + `Retry-After` for 60 s; any success resets; no permanent
lockout. In-memory and bounded (global 2-counter scope for single-PIN
servers; per-box scopes for link mailboxes). Correct credentials always
work, even mid-cooldown; only failures count. Restart resets (server
lifetimes are minutes-to-open-hours; documented, not a bypass: guessing
10 PINs per restart across a 6-digit/8-char space stays infeasible inside
credential lifetimes). Wrong-PIN on non-existent boxes is not counted
(404s are not guesses); 403s are.

### 3a. Unauthenticated mailbox creation

`POST /api/sync/link` cannot require a credential: the device that starts
a pairing has no shared secret yet, so there is nothing to check. That made
the endpoint free -- any peer could allocate boxes until the 50-box cap,
each holding a snapshot (8 MiB cap on the phone host, 6 MiB on the Node
relay), evicting live pairings on the way.

Bounded by rate instead, identically on both servers: **10 accepted
creations per 60 s**, then HTTP 429 + `Retry-After`. Only well-formed,
accepted boxes consume a slot, so a peer cannot lock the owner out of
pairing by sending junk (every rejection stays 400, never 429).

`LanThrottle` deliberately does *not* cover this: it counts failures, and a
successful creation is the abuse itself.

Not changed: the memory ceiling itself. `maxBoxes = 50` still bounds a
host at ~400 MB of attacker-reachable snapshots in the worst case, and
`LinkStore.create` still evicts the oldest box when full. Lowering either is
a deliberate protocol-constant change with a compatibility cost, so the
rate limit is the fix and the ceiling stays a documented residual.

## 4. Direct-WiFi sessions

- Bootstrap: `POST /auth {pin}` -> `{token}` (wrong PIN counts toward the
  throttle; unknown routes 404 for old senders, whose receivers keep the
  PIN header).
- Token: 128-bit CSPRNG hex (`Random.secure`), sent once in JSON, then
  `Authorization: Bearer`. Accepted alongside the legacy PIN header.
- TTL: server lifetime (5 min or less auto-close); no sliding refresh, no
  inactivity timeout needed at that span. Cap: 16 live tokens (oldest
  evicted). Revoke: `POST /logout` (idempotent) + server stop clears all.
- Replay within TTL is possible to a passive observer -- stated, not solved
  (a nonce/MAC scheme would be theater without confidentiality; short TTLs
  are the control -- see Sec. 9).
- Simple string equality is used for PIN/token compares: timing attacks
  over LAN against 128-bit tokens add nothing, and short numeric PINs are
  throttle-bound instead. Documented as a deliberate non-control.

## 5. Link/mailbox authorization: high-entropy secret, not the PIN

A user-chosen 4-digit PIN (10,000 possibilities) at ~11 guesses/minute
falls in ~16 hours -- inside a 7-day mailbox lifetime. Throttling alone
cannot fix that math, so long-lived link boxes carry a second credential
with real entropy. Short-lived direct-WiFi pairing (6-digit PIN, 5-minute
or less server) needs no secret: at most ~15 guesses fit in the server
lifetime.

- **Generation:** 128-bit hex from `Random.secure`, client-side at link
  create (`newLinkSecret()`). Independent from the app PIN, user PINs,
  timestamps, and device IDs.
- **Transport:** stored opaquely server-side per box; travels in the pairing
  QR as an optional 4th `::` part (the QR channel is already a temporary
  secret -- old parsers reject 4-part codes as "not a sync code", which is
  safe and explicit). Manual server/code/PIN entry carries no secret, so it
  joins legacy boxes only; strong boxes need a scan.
- **All random material comes from a CSPRNG**, with no new dependencies: Dart
  uses `Random.secure()` everywhere including Web; the Node relay uses
  `crypto.randomBytes` (a Node built-in, so the file stays at zero npm
  dependencies). This covers the pairing PIN (`newPin()`), the 128-bit link
  secret, the direct-WiFi session token, **and** the relay's own session and
  box ids -- the last of which were on `Math.random()` until the September 2026
  audit, a predictable PRNG whose internal state can be reconstructed from a
  few observed ids.
- **Enforcement (Node relay, phone host, `LinkStore` alike):** a box WITH a
  secret requires matching PIN **and** secret on every push/pull; PIN-only
  (or wrong-secret) attempts get a distinct 403 (`link secret required -
  update app`), never a silent downgrade to PIN-only. Boxes WITHOUT a
  secret (old clients omit the field) stay legacy PIN-only with reduced
  guarantees -- including against a new relay, which must never brick old
  clients by inventing secrets for them.
- **Lifetime:** box TTL (7-day sliding) + unlink/Stop deletes the box; the
  secret dies with it. Client-side it lives in the pairing record
  (`linkSecret`, sandboxed prefs) and is cleared on unpair/erase. Never in
  pull responses, logs, or error messages (only the static
  `link secret required` string, which reveals nothing guessable).
- **Why not sessions here:** the mailbox protocol is shared by three
  implementations incl. old apps; PIN+secret per request with throttle and
  TTL is the proportionate control, and sessions would add zero
  confidentiality on plain HTTP. Revisit only with a transport that makes
  tokens meaningful.

## 6. Request limits and validation

- Bodies capped at 8 MiB on Dart servers (`lib/sync/http_limits.dart`;
  Content-Length pre-check -> clean 413, streaming backstop for chunked).
  Basis: bulk-300 ~67 KiB, ~1.5 MiB at 5k v2 records (~5x headroom, not a
  behavior limit). Node keeps its 6 MiB cap (same headroom class).
- Malformed JSON -> 400, oversized -> 413, both before any state mutation
  (upload handlers never run: tested with an upload counter).
- Shape checks stay minimal and compatible: JSON-validity + required-string
  fields; no content-type zealotry (native + browser clients vary; attackers
  set headers anyway).
- Errors are static strings; 500s carry only the error class (Phase 3
  policy extends here).

## 7. CORS: kept permissive on purpose

`Access-Control-Allow-Origin: *` remains on API responses because
browser-hosted Dhadda instances (phone browser receiving, Pages demo) call
these APIs cross-origin -- removing it breaks legitimate receivers.
Re-review after the link-secret change: cross-origin guessing against a
secret box must defeat 128 bits, which is infeasible regardless of origin,
so the residual is accepted (not merely bounded). Legacy PIN-only boxes
stay throttle-bounded as before. CORS was never authentication;
same-origin behavior for hosted UIs is unchanged.

## 8. Node relay protections

Same throttle policy (global bucket for the offer/session flow, per-box for
link push/pull), same 6 MB cap, static error strings, no payload/PIN/token
logging (only the pre-existing startup line + local crash file, whose V8
stacks carry no values). Mailbox data is in-memory with the existing TTLs;
the relay operator/process inherently sees relayed snapshots -- that
boundary is unchanged and stated: run the relay on a machine you trust
(yours). `node --check` clean; live PIN-throttle + secret-enforcement +
v2-passthrough + safe-error behavior covered by tests.

## 9. Replay / integrity investigation (finding: defer protocol)

Captured PINs, tokens, and snapshots are replayable by a passive observer
for their TTLs -- inseparable from plain HTTP. Evaluated: nonces, request
IDs, monotonic counters, timestamp windows, session-keyed MACs. All need a
confidential channel or pre-shared secret to beat "attacker replays bytes";
with neither, they add complexity without moving the boundary. Deferred
honestly. Controls that DO bound replay: 5-minute-or-less sender/token
lifetimes, explicit logout, per-pairing link secrets, Stop/Unpair hygiene.

## 10. TLS decision: deferred with rationale

Local HTTPS was investigated, not implemented. Trustworthy validation would
need user-installed CA/cert UX on rotating LAN IPs (often `192.168.x.y`
today, different tomorrow) plus mDNS-name handling, F-Droid offline builds,
and cert rotation -- while browsers greet self-signed LAN certs with
warnings users learn to click through. That manufactures a padlock feeling
without trustworthy authentication: worse than honest HTTP + short-lived
credentials + trusted-network guidance. Revisit only with a genuinely
usable trust story (e.g., OS-trusted local CA flow), never silently.

## 11. mDNS / QR / discovery boundaries

- mDNS advertises service name + port only (verified in `MdnsHelper.kt`
  usage: `register(name: 'dhadda', port: ...)`); never PINs, tokens,
  identity, or data. Discovery is not authentication.
- Direct-WiFi QR = URL + ephemeral PIN (server dies in 5 min or less).
  Link QR = origin + code + PIN plus the link secret as a 4th field
  (3-part legacy codes still parse, with reduced guarantees). Treat any
  pairing QR as a secret while it lives, Stop when paired. QR is transport,
  not encryption. No QR/secret logging anywhere (verified: clients log
  nothing; pull responses never contain secrets -- asserted in tests).
- No app-PIN material on LAN (verified: only pairing PINs travel).

## 12. Sensitive logging (Phase 3 policy holds)

LAN logs: method + static path, counts, error classes, 429/413/400 codes.
Never: PINs, tokens, secrets, Authorization headers, full URLs with
secrets, query strings carrying credentials, snapshots, financial content,
SMS, backup passwords. `git grep`-audited across Dart/Kotlin/Node in this
phase (link-secret strings verified absent from all log/error paths).

## 13. What Phase 5 did NOT change

Sync semantics/revisions/tombstones/merge, v1 compat, money, schema (still
v2), PIN hashing, at-rest encryption posture, Provider/store shape, UI
beyond guidance lines. New code: `lan_throttle.dart`, `http_limits.dart`,
link-secret fields/plumbing. New dependencies: none (Dart `Random.secure` +
shelf/Node builtins only).

## 14. Remaining threats (accepted, stated plainly)

- Passive observer on the same network reads credentials + snapshots.
- Active MITM owns the exchange outright.
- Legacy PIN-only link boxes (old clients, or relays that drop the secret
  field): a user-chosen short PIN on a 7-day box is throttle-bounded but
  brute-forceable inside the TTL -- reduced guarantees, stated plainly.
  Prefer longer PINs; Stop/Unpair when done; update both devices so new
  pairings carry secrets.
- Throttle state resets on server restart (bounded DoS-for-guesses tradeoff).
- No CSRF machinery: sessions are explicit Bearer tokens, never cookies.

## 15. Manual verification (emulator/spare/synthetic only)

1. Show on PC -> second browser: trusted-network warning visible.
2. Wrong access PIN x11 on link pull -> ten 403s, then 429 + Retry-After;
   correct PIN works immediately after (no lockout).
3. Direct WiFi: `/auth` wrong PIN -> 403; right PIN -> 32-hex token; Bearer
   reads; logout -> Bearer 403s; stop server -> all access dies.
4. 8 MB+ POST -> 413 with state unchanged; garbage JSON -> 400.
5. Link secret box: correct PIN+secret -> 200; PIN-only -> 403 naming the
   upgrade (never "wrong PIN"); wrong secret -> 403; unlink -> 404 even
   with the secret; pull bodies contain no secret field.
6. `adb logcat` + Node console during failures: classes/codes only.
7. Full v2 sync round-trip still converges (regression: existing suites).
