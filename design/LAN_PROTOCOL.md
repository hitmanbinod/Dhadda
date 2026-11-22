# Dhadda LAN sync protocol (Prompt 3, Phase 1)

Status: implemented primitives; endpoints are the contract for Phase 2.
Implementations: `lib/sync/lan_crypto.dart` (Dart) and
`webapp/lan-crypto.js` + `webapp/vendor/noble-1.x-min.js` (browser).
Shared known answers: `design/test-vectors/lan.json`.

## 0. Threat model and honest limits

The page is served over plain HTTP on a LAN address. It is **not a secure
context**: `crypto.subtle` is unavailable, camera capture is unavailable, no
service worker/PWA is possible. The computer shows a QR and the phone scans
it, never the reverse. The phone is the single source of truth and stores all
expense data; the computer stores only a trust key and holds rows in memory.

We add application-layer encryption so a passive sniffer on a trusted home
network cannot read or modify data. We do **not** claim protection against an
active attacker who rewrites the page on that network. Use only a network you
trust. If the phone's IP changes, the browser origin changes and the computer
must pair again.

Never log codes, keys, secrets, proofs or frame contents.

## 1. Primitives (exact)

| Primitive | Dart | Browser |
| --- | --- | --- |
| X25519 | `cryptography` `X25519()` | noble `x25519` |
| SHA-256 | `Sha256()` | noble `sha256` |
| HMAC-SHA256 | `Hmac.sha256()` | noble `hmac(sha256, …)` |
| HKDF-SHA256 | `Hkdf(hmac: Hmac.sha256(), outputLength: 32)` | noble `hkdf(sha256, …)` |
| ChaCha20-Poly1305 | `Chacha20.poly1305Aead()` | noble `chacha20poly1305` |
| PBKDF2-HMAC-SHA256 | `Pbkdf2.hmacSha256(iterations: 210000, bits: 256)` | noble `pbkdf2` |

All byte strings are raw bytes unless a field is explicitly a string. Hex in
vectors is lowercase. `‖` means byte concatenation. `utf8(x)` is UTF-8 encoding.

### 1.1 Pairing code

- Alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (31 chars, no look-alikes).
- 8 characters shown as `ABCD-EFGH`, from a CSPRNG.
- Normalisation: uppercase, delete `-`, `_` and whitespace; reject any other
  character; exactly 8 characters after cleaning. Case and the hyphen are
  forgiving; look-alikes (`0`, `O`, `1`, `I`) are rejected, not auto-corrected.
- Lifetime 120 s, single use, 5 wrong attempts **in total** while displayed,
  then the code dies and the phone says so. Countdown + "New code" on screen.
- Pairing endpoints answer only while the active pairing screen is open. Mark
  the code consumed before showing the Allow sheet so a double-submit cannot
  pair twice.

### 1.2 Code stretch (deviation from Prompt 3 §5 — approved default)

The 8-char code has ≈39.6 bits. A passive sniffer sees `proof_pc`, `epc`,
`ephone` and `sid`, can compute `Z` and `T`, and could otherwise brute-force
the code offline and derive the session key. We therefore stretch it:

```
codeKey = PBKDF2-HMAC-SHA256(password = utf8(code), salt = T,
                             iterations = 210000, dkLen = 32)
```

Both sides use this as the HMAC key for proofs. No new dependency: Dart
`cryptography` and the vendored noble bundle already provide PBKDF2.

### 1.3 Transcripts and keys

```
T_code = SHA256(epc ‖ ephone ‖ utf8(sid))       # code mode AND QR mode
T_trust = SHA256(epc ‖ ephone ‖ nonce)          # trusted reconnect
proof(key, label, T[, suffix]) = HMAC-SHA256(key, utf8(label) ‖ T ‖ suffix)
qrKey   = HKDF-SHA256(ikm = s, salt = T, info = utf8("dhadda-qr-v1"), 32)
K       = HKDF-SHA256(ikm = Z, salt = T, info = utf8("dhadda-session-v1"), 32)
K_trust = HKDF-SHA256(ikm = Z ‖ device_secret, salt = T_trust,
                      info = utf8("dhadda-trusted-session-v1"), 32)
```

`Z` is the raw 32-byte X25519 shared secret. `"pc"` and `"phone"` are the two
proof labels. The pairing HKDF info string is `dhadda-pair-v1` (reserved for
transcript separation; the stretched code key is the HMAC key).

### 1.4 AEAD envelope (fixes §5's 9-byte nonce)

ChaCha20-Poly1305 requires a **12-byte nonce**; §5 sketches only
`direction byte + 64-bit counter` (9 bytes). We pad explicitly:

```
nonce = [direction] ‖ 0x00 0x00 0x00 ‖ uint64be(counter)     # 12 bytes
direction: 0x00 = computer→phone, 0x01 = phone→computer
AAD = utf8("dhadda-lan-v1") ‖ utf8(sid) ‖ [direction] ‖ uint64be(counter)
wire = ciphertext ‖ 16-byte Poly1305 tag
```

The counter is strictly increasing **per direction per session**. Reject any
frame whose counter is not greater than the last accepted counter for that
direction, and any frame that fails AEAD verification. A new WS connection
derives a fresh session key so counters restart safely (see flaw F3).

## 2. Pairing flows

### 2.1 Code mode (computer types the code)

1. Computer generates ephemeral `ePC`, calls
   `POST /pair/hello {epc: hex, name: "Chrome on Windows", trust: bool}`.
2. Phone generates `ePhone`, creates `sid`, holds the pending session, returns
   `{sid, ephone: hex}`. Both compute `Z` and `T_code`.
3. User types the code into the computer. It sends
   `POST /pair/confirm {sid, proof: hex(proof(codeKey, "pc", T_code))}`.
   **The code itself is never sent.**
4. Phone verifies the proof with a constant-time compare; a failure consumes
   one of the five attempts. It then shows
   "Allow Chrome on Windows (192.168.x.x)? Trusted for 30 days" with
   Allow / Deny.
5. On Allow the phone replies
   `{proof_phone: hex(proof(codeKey, "phone", T_code)), secret?}`.
   The computer verifies `proof_phone` (proving the phone knew the code) and
   derives `K`.
6. If `trust` was requested, the phone creates a random 32-byte
   `device_secret` and a `device_id`, stores
   `{id, name, secret, created, expires}` in app-private storage, and returns
   `secret` as an AEAD envelope under `K` whose plaintext is
   `{"device_id":…,"device_secret":…,"expires":…}`.

### 2.2 QR mode (phone scans the computer's QR)

1. Computer makes `ePC` and a random 16-byte `s`, calls
   `POST /pair/hello {epc, name, trust, mode: "qr"}`.
2. Computer shows a QR with `{v:1, sid, epc, s}` (hex fields).
3. Phone scans it, checks `epc` matches the pending session, treats the scan
   as consent (no second Allow), computes `qrKey` and `proof_phone`, and marks
   the session ready. The phone shows the pending session's name/IP at scan
   time and offers immediate Disconnect/Forget (flaw F6).
4. Computer polls `GET /pair/poll?sid=…&epc=…` or receives the result on the
   WebSocket, verifies `proof_phone`, and derives `K` exactly as in code mode.
   `s` travelled only by light, so an on-network attacker cannot forge the
   answer. `sid` alone is not enough to poll; `epc` is required (flaw F7).

### 2.3 Trusted reconnect (no code)

1. `POST /session/hello {device_id, epc}` → `{ephone, nonce}` (16 random
   bytes). The session `sid` is the `device_id`.
2. Both compute `T_trust = SHA256(epc ‖ ephone ‖ nonce)`.
3. Computer sends
   `POST /session/confirm {device_id, proof_pc: hex(HMAC(device_secret, utf8("pc") ‖ T_trust ‖ nonce))}`.
4. Phone checks expiry/revocation and the proof in constant time, then replies
   with `proof_phone` keyed the same way with label `"phone"`.
5. Both derive `K_trust`. Unknown/expired/forgotten device → clear
   "pair again" error. Trust expires 30 days from pairing (named constant).

## 3. Sessions and data channel

- Every `/api/*` body and every WS frame is a nonce-protected AEAD envelope.
- Untrusted sessions keep their key in `sessionStorage` only (closing the tab
  ends it). Trusted sessions keep `device_id` + `device_secret` in IndexedDB
  with a 30-day expiry; the live session key is still memory-only.
- Idle sessions end after 12 hours. Max 3 connected computers.
- No CORS headers at all (same origin only).
- Endpoints for Phase 2:

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/pair/hello` | begin code or QR pairing |
| POST | `/pair/confirm` | typed-code proof + Allow gate |
| GET | `/pair/poll` | QR result (`sid` + `epc`) |
| POST | `/session/hello`, `/session/confirm` | trusted reconnect |
| POST | `/api/snapshot` | all rows, encrypted |
| POST | `/api/push` | `{rows}` applied through `store.applyCloudRows` |
| WS | `/api/events` | `changed` messages with rows + tombstones |

Row shape reuses Prompt 2: `{t, id, ua, d, data, device_id, seq}`.
`resolveWinner`: larger `ua` wins, ties by lexicographically larger
`device_id`. Deletes are tombstones (`d=1`). The phone pushes edits through
the same repository path as its own UI; `cloudChangeHook` drives outbound
events and never echoes pulled rows (`cloudApplying`).

## 4. Server hardening

Bind only while "Use on computer" is on. Reject any `Host` header that is not
one of the phone's own addresses (with port) or `dhadda.local`; apply this to
the WS upgrade too. Permit `127.0.0.1`/`localhost` only in debug for
integration tests. Max 3 computers; cap request bodies at 1 MB; global limits
on `/pair/*` and failed proofs. No timers, sockets or wake locks while stopped.

Security headers on every response:

```
Content-Security-Policy: default-src 'self'; connect-src 'self' ws:; img-src 'self' data:
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
Cache-Control: no-store        # API responses
```

Static text assets are gzipped; no service worker and no install prompt.

## 5. Test vectors and how to run them

`design/test-vectors/lan.json` contains:

- KATs: SHA-256 (`abc`), HMAC-SHA256 (RFC 4231 #1), HKDF-SHA256 (RFC 5869 #1),
  PBKDF2-HMAC-SHA256, X25519 (RFC 7748), ChaCha20-Poly1305.
- A full recorded **code-mode** handshake (ephemerals, `sid`, code, `T`,
  stretched code key, both proofs, session key, and one encrypted frame).
- A full **QR-mode** handshake (`s`, `qrKey`, `proof_phone`, session key).
- A full **trusted-reconnect** handshake (`nonce`, `T_trust`, both proofs,
  trusted session key).
- A rejection case: opening the recorded frame with counter 0 must fail.

Run both sides:

```sh
flutter test test/lan_crypto_test.dart   # Dart reproduces every vector
node scripts/lan-vectors.mjs             # the web client code does too
node scripts/lan-simulate.mjs            # wrapper (Phase 2 adds the Dart test server)
dart run tool/gen_lan_vectors.dart       # regenerate from the Dart primitives
```

## 6. Flaws found in Prompt 3 §5 and their resolutions

| # | Flaw | Resolution |
| --- | --- | --- |
| F1 | Offline code recovery from sniffed `proof` + ECDH keys (~39.6-bit code). | PBKDF2 stretch (§1.2). Approved default; conservative alternative would be a longer code. |
| F2 | Trusted reconnect reuses `T` but §5 defines no `sid` for it. | Define `T_trust = SHA256(epc‖ephone‖nonce)` and `sid = device_id` (§2.3). |
| F3 | Counter reset on reconnect would be rejected as a replay. | Fresh session key per WS connection; trust secret stays stable (§3). |
| F4 | AEAD AAD unspecified; cross-context replay possible if keys collide. | Bind context, `sid`, direction and counter into AAD (§1.4). |
| F5 | Global 5-attempt lockout is a LAN DoS knob. | Keep 5 total, add a short cooldown and tell the phone immediately (§1.1). |
| F6 | QR scan = consent; a malicious QR can pair a rogue computer. | Show the pending name/IP at scan time, no second tap, immediate Forget (§2.2). |
| F7 | `/pair/poll` needs only `sid`, which is sniffable. | Require `epc` with `sid`; never return the session key from polling (§2.2). |
| F8 | `connect-src 'self' ws:` permits WS to any host. | Restrict to the phone origin; add `img-src 'self' data:` for QR images (§4). |
| F9 | Host-header check mentioned for HTTP only. | Apply to WS upgrade; debug-only loopback exemption (§4). |
| F10 | "Works once" needs a state machine; double-submit could pair twice. | Consume the code before showing Allow; endpoints gated on active screen (§1.1). |
| F11 | §5's nonce is 9 bytes but ChaCha20-Poly1305 needs 12. | Explicit 3 zero bytes between direction and counter (§1.4). |

None of these weaken the design; all are written into the implementation
contract above. F2 and F11 are pure clarifications, F1 is the one deliberate
deviation from the literal §5 primitive list.
