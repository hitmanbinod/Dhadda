// Dhadda LAN sync primitives (Prompt 3, Phase 1).
//
// Pure, dependency-free glue over the existing `cryptography` package. Every
// function here has an exact twin in webapp/lan-crypto.js; both are checked
// against design/test-vectors/lan.json. Never log keys, codes or proofs.
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Look-alike-free pairing alphabet (31 characters).
const lanCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// PBKDF2 stretch for the typed code. See design/LAN_PLAN.md §5 flaw 1.
const lanKdfIterations = 210000;

const lanPairingInfo = 'dhadda-pair-v1';
const lanQrInfo = 'dhadda-qr-v1';
const lanSessionInfo = 'dhadda-session-v1';
const lanTrustedInfo = 'dhadda-trusted-session-v1';
const lanAeadContext = 'dhadda-lan-v1';

/// Direction byte used in the AEAD nonce and AAD.
const lanDirPcToPhone = 0x00;
const lanDirPhoneToPc = 0x01;

class LanCrypto {
  static final Sha256 _sha256 = Sha256();
  static final Hmac _hmac = Hmac.sha256();
  static final X25519 _x25519 = X25519();
  static final Chacha20 _chacha = Chacha20.poly1305Aead();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Pbkdf2 _pbkdf2 = Pbkdf2.hmacSha256(
    iterations: lanKdfIterations,
    bits: 256,
  );

  static Uint8List utf8(String value) =>
      Uint8List.fromList(convert.utf8.encode(value));

  static String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List unhex(String value) {
    final s = value.replaceAll(RegExp(r'[\s:-]'), '');
    if (s.length.isOdd) throw const FormatException('odd hex length');
    return Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);
  }

  static Uint8List concat(List<List<int>> parts) =>
      Uint8List.fromList(parts.expand((p) => p).toList());

  static Future<Uint8List> sha256(List<int> data) async =>
      Uint8List.fromList((await _sha256.hash(data)).bytes);

  static Future<Uint8List> hmac(List<int> key, List<int> message) async =>
      Uint8List.fromList(
        (await _hmac.calculateMac(message, secretKey: SecretKey(key))).bytes,
      );

  static Future<Uint8List> hkdfSha256({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
  }) async =>
      Uint8List.fromList(
        await (await _hkdf.deriveKey(
          secretKey: SecretKey(ikm),
          nonce: salt,
          info: info,
        )).extractBytes(),
      );

  static Future<Uint8List> pbkdf2Sha256({
    required List<int> password,
    required List<int> salt,
  }) async =>
      Uint8List.fromList(
        await (await _pbkdf2.deriveKeyFromPassword(
          password: convert.utf8.decode(password),
          nonce: salt,
        )).extractBytes(),
      );

  /// X25519 public key for a 32-byte private seed.
  static Future<Uint8List> x25519Public(List<int> seed) async {
    final pair = await _x25519.newKeyPairFromSeed(seed);
    return Uint8List.fromList((await pair.extractPublicKey()).bytes);
  }

  /// X25519 shared secret for a 32-byte private seed and a peer public key.
  static Future<Uint8List> x25519Shared(
    List<int> seed,
    List<int> peerPublic,
  ) async {
    final pair = await _x25519.newKeyPairFromSeed(seed);
    return Uint8List.fromList(
      await (await _x25519.sharedSecretKey(
        keyPair: pair,
        remotePublicKey: SimplePublicKey(
          peerPublic,
          type: KeyPairType.x25519,
        ),
      )).extractBytes(),
    );
  }

  /// Accepts `ABCD-EFGH`, `abcd efgh`, `abcdefgh`; rejects look-alikes.
  static String normalizeCode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (cleaned.length != 8) throw const FormatException('code length');
    for (final c in cleaned.codeUnits) {
      if (!lanCodeAlphabet.codeUnits.contains(c)) {
        throw const FormatException('code character');
      }
    }
    return cleaned;
  }

  /// Code verifier key: PBKDF2-HMAC-SHA256(code, salt=T).
  static Future<Uint8List> codeKey(String code, List<int> t) =>
      pbkdf2Sha256(password: utf8(normalizeCode(code)), salt: t);

  /// Transcript for code mode and QR mode: SHA256(epc || ephone || sid).
  static Future<Uint8List> transcript(
    List<int> epc,
    List<int> ephone,
    String sid,
  ) =>
      sha256(concat([epc, ephone, utf8(sid)]));

  /// Trusted reconnect transcript: SHA256(epc || ephone || nonce).
  static Future<Uint8List> trustedTranscript(
    List<int> epc,
    List<int> ephone,
    List<int> nonce,
  ) =>
      sha256(concat([epc, ephone, nonce]));

  /// HMAC(key, label || transcript [|| suffix]).
  static Future<Uint8List> proof(
    List<int> key,
    String label,
    List<int> t, [
    List<int>? suffix,
  ]) =>
      hmac(key, concat([utf8(label), t, ?suffix]));

  /// QR answer key: HKDF(s, salt=T, info="dhadda-qr-v1").
  static Future<Uint8List> qrKey(List<int> s, List<int> t) =>
      hkdfSha256(ikm: s, salt: t, info: utf8(lanQrInfo));

  /// Session key for code/QR pairing: HKDF(Z, salt=T, info=...).
  static Future<Uint8List> sessionKey(List<int> z, List<int> t) =>
      hkdfSha256(ikm: z, salt: t, info: utf8(lanSessionInfo));

  /// Trusted session key mixes the long-lived device secret into the HKDF IKM.
  static Future<Uint8List> trustedSessionKey(
    List<int> z,
    List<int> t,
    List<int> deviceSecret,
  ) =>
      hkdfSha256(
        ikm: concat([z, deviceSecret]),
        salt: t,
        info: utf8(lanTrustedInfo),
      );

  /// 1 direction byte + 3 reserved zero bytes + 8-byte big-endian counter.
  /// ChaCha20-Poly1305 requires a 12-byte nonce; §5's 9-byte sketch is padded
  /// explicitly so both sides agree byte for byte.
  static Uint8List nonce(int direction, int counter) {
    if (counter < 0) throw ArgumentError.value(counter, 'counter');
    final out = Uint8List(12);
    out[0] = direction;
    for (var i = 0; i < 8; i++) {
      out[4 + i] = (counter >> (8 * (7 - i))) & 0xFF;
    }
    return out;
  }

  /// Binds the session and direction to every frame (cross-context replay).
  static Uint8List aad(String sid, int direction, int counter) => concat([
        utf8(lanAeadContext),
        utf8(sid),
        [direction],
        nonce(0, counter).sublist(4),
      ]);

  /// AES-equivalent AEAD output: ciphertext || 16-byte Poly1305 tag.
  static Future<Uint8List> seal({
    required List<int> key,
    required List<int> nonceBytes,
    required List<int> aadBytes,
    required List<int> plaintext,
  }) async {
    final box = await _chacha.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonceBytes,
      aad: aadBytes,
    );
    return concat([box.cipherText, box.mac.bytes]);
  }

  /// Throws on tampering or wrong key.
  static Future<Uint8List> open({
    required List<int> key,
    required List<int> nonceBytes,
    required List<int> aadBytes,
    required List<int> sealed,
  }) async {
    if (sealed.length < 16) throw const FormatException('short frame');
    final box = SecretBox(
      sealed.sublist(0, sealed.length - 16),
      nonce: nonceBytes,
      mac: Mac(sealed.sublist(sealed.length - 16)),
    );
    return Uint8List.fromList(
      await _chacha.decrypt(box, secretKey: SecretKey(key), aad: aadBytes),
    );
  }

  /// Constant-time equality for proofs and HMACs.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
