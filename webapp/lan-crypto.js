// Dhadda LAN primitives - browser twin of lib/sync/lan_crypto.dart.
// Plain HTTP on a LAN is not a secure context: crypto.subtle is unavailable.
// All crypto comes from the vendored, audited noble ES module bundle.
import {
  chacha20poly1305,
  hkdf,
  hmac,
  pbkdf2,
  sha256,
  x25519,
} from './vendor/noble-1.x-min.js';

export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const KDF_ITERATIONS = 210000;
export const PAIRING_INFO = 'dhadda-pair-v1';
export const QR_INFO = 'dhadda-qr-v1';
export const SESSION_INFO = 'dhadda-session-v1';
export const TRUSTED_INFO = 'dhadda-trusted-session-v1';
export const AEAD_CONTEXT = 'dhadda-lan-v1';
export const DIR_PC_TO_PHONE = 0x00;
export const DIR_PHONE_TO_PC = 0x01;

const enc = new TextEncoder();
const dec = new TextDecoder();

export const utf8 = s => enc.encode(s);
export const text = b => dec.decode(b);
export const concat = (...parts) => {
  const n = parts.reduce((a, p) => a + p.length, 0);
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
};
export const hex = b => Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
export const unhex = s => {
  const t = String(s).replace(/[\s:-]/g, '');
  if (t.length % 2) throw new Error('odd hex length');
  const out = new Uint8Array(t.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(t.substr(i * 2, 2), 16);
  return out;
};

export const sha256Bytes = data => sha256(data);
export const hmacSha256 = (key, msg) => hmac(sha256, key, msg);
export const hkdfSha256 = (ikm, salt, info) => hkdf(sha256, ikm, salt, info, 32);
export const pbkdf2Sha256 = (password, salt) =>
  pbkdf2(sha256, password, salt, { c: KDF_ITERATIONS, dkLen: 32 });

export const x25519Public = seed => x25519.getPublicKey(seed);
export const x25519Shared = (seed, peerPublic) => x25519.getSharedSecret(seed, peerPublic);

/** Accepts ABCD-EFGH, abcd efgh, abcdefgh; rejects look-alikes and O/0/I/1. */
export function normalizeCode(input) {
  const s = String(input).toUpperCase().replace(/[\s\-_]/g, '');
  if (s.length !== 8) throw new Error('code length');
  for (const c of s) if (!CODE_ALPHABET.includes(c)) throw new Error('code character');
  return s;
}

export const codeKey = (code, t) => pbkdf2Sha256(utf8(normalizeCode(code)), t);
export const transcript = (epc, ephone, sid) => sha256Bytes(concat(epc, ephone, utf8(sid)));
export const trustedTranscript = (epc, ephone, nonce) => sha256Bytes(concat(epc, ephone, nonce));
export const proof = (key, label, t, suffix) =>
  hmacSha256(key, concat(utf8(label), t, suffix || new Uint8Array(0)));
export const qrKey = (s, t) => hkdfSha256(s, t, utf8(QR_INFO));
export const sessionKey = (z, t) => hkdfSha256(z, t, utf8(SESSION_INFO));
export const trustedSessionKey = (z, t, deviceSecret) =>
  hkdfSha256(concat(z, deviceSecret), t, utf8(TRUSTED_INFO));

/** 1 direction byte + 3 reserved zero bytes + 8-byte big-endian counter (12 bytes). */
export function nonce(direction, counter) {
  if (!Number.isSafeInteger(counter) || counter < 0) throw new Error('bad counter');
  const out = new Uint8Array(12);
  out[0] = direction;
  for (let i = 0; i < 8; i++) out[4 + i] = Number((BigInt(counter) >> BigInt(8 * (7 - i))) & 0xffn);
  return out;
}

export const aad = (sid, direction, counter) =>
  concat(utf8(AEAD_CONTEXT), utf8(sid), new Uint8Array([direction]), nonce(0, counter).subarray(4));

/** ciphertext || 16-byte Poly1305 tag. */
export function seal(key, nonceBytes, aadBytes, plaintext) {
  return chacha20poly1305(key, nonceBytes, aadBytes).encrypt(plaintext);
}
export function open(key, nonceBytes, aadBytes, sealed) {
  if (sealed.length < 16) throw new Error('short frame');
  return chacha20poly1305(key, nonceBytes, aadBytes).decrypt(sealed);
}

export function constantTimeEquals(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** CSPRNG helper for ephemeral keys / session ids (getRandomValues works on LAN HTTP). */
export function randomBytes(n) {
  return crypto.getRandomValues(new Uint8Array(n));
}

// Expose to the classic app.js script as well; modules are loaded before it.
if (typeof window !== 'undefined') {
  window.LanCrypto = {
    CODE_ALPHABET, KDF_ITERATIONS, PAIRING_INFO, QR_INFO, SESSION_INFO, TRUSTED_INFO,
    AEAD_CONTEXT, DIR_PC_TO_PHONE, DIR_PHONE_TO_PC,
    utf8, text, concat, hex, unhex, sha256Bytes, hmacSha256, hkdfSha256,
    pbkdf2Sha256, x25519Public, x25519Shared, normalizeCode, codeKey, transcript,
    trustedTranscript, proof, qrKey, sessionKey, trustedSessionKey, nonce, aad,
    seal, open, constantTimeEquals, randomBytes,
  };
}
