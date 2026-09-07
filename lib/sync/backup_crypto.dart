// Optional password-based encrypted backups (Phase 3, additive).
//
// Plaintext Snapshot v1 export/import is unchanged and remains the default.
// This envelope exists for one realistic exposure: backup files shared
// through chat/mail/drive, where anyone holding the file can read it.
//
// Envelope (JSON, versioned separately from Snapshot v1):
//   {"format":"dhadda-enc-backup","v":1,"kdf":"argon2id",
//    "m":32768,"t":3,"p":1,"salt":b64,"nonce":b64,
//    "cipher":b64,"tag":b64}
//
// Crypto, all established primitives via package:cryptography
// (Apache-2.0, pure Dart: identical on Android and Web, F-Droid clean):
//   - Argon2id(password, 16-byte random salt) -> 32-byte key
//     (32 MiB, 3 passes, 1 lane; parameters travel in the envelope)
//   - XChaCha20-Poly1305 AEAD with a random 24-byte nonce per backup
//     (randomized ciphertext: two encryptions of the same data differ).
//
// Deliberately NOT used: the 4-digit app PIN (10k guesses would fall to an
// offline attack instantly), device Keystore material (backups must be
// portable across devices), any custom construction.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class BackupCrypto {
  static const format = 'dhadda-enc-backup';
  static const version = 1;

  static const kdfMemory = 32768; // 32 MiB
  static const kdfIterations = 3;
  static const kdfParallelism = 1;

  // Envelope DoS bounds (a hostile file must not demand gigabytes).
  static const _maxMemory = 1 << 20; // 1 GiB in KiB blocks
  static const _maxIterations = 10;
  static const _maxParallelism = 4;

  /// True only for a well-marked envelope (never throws). Payload validity
  /// is checked separately by [decrypt].
  static bool isEncrypted(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> &&
          v['format'] == format &&
          v['v'] == version;
    } catch (_) {
      return false;
    }
  }

  static Future<String> encrypt(String plaintext, String password) async {
    if (password.isEmpty) {
      throw ArgumentError('Backup password required.');
    }
    final rand = Random.secure();
    final salt = List<int>.generate(16, (_) => rand.nextInt(256));
    final nonce = List<int>.generate(24, (_) => rand.nextInt(256));
    final key = await _derive(
      password,
      salt,
      m: kdfMemory,
      t: kdfIterations,
      p: kdfParallelism,
    );
    final box = await Xchacha20.poly1305Aead().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'format': format,
      'v': version,
      'kdf': 'argon2id',
      'm': kdfMemory,
      't': kdfIterations,
      'p': kdfParallelism,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
  }

  /// Returns the cleartext snapshot JSON. Throws [FormatException] with a
  /// human message for wrong passwords, tampering, and malformed envelopes.
  /// Never touches app state (callers import the result explicitly).
  static Future<String> decrypt(String raw, String password) async {
    final m = _parseEnvelope(raw);
    final salt = _b64(m, 'salt', 16, 16);
    final nonce = _b64(m, 'nonce', 24, 24);
    final cipher = _b64(m, 'cipher', 1, 64 << 20);
    final tag = _b64(m, 'tag', 16, 16);
    final kdf = _kdfParams(m);
    try {
      final key = await _derive(password, salt, m: kdf.m, t: kdf.t, p: kdf.p);
      final clear = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong password or damaged file.');
    } catch (_) {
      // Any other crypto failure (bad lengths that slipped validation,
      // non-UTF8 cleartext): same safe message, no internals leaked.
      throw const FormatException('Wrong password or damaged file.');
    }
  }

  static Map<String, dynamic> _parseEnvelope(String raw) {
    Map<String, dynamic> m;
    try {
      final v = jsonDecode(raw);
      if (v is! Map<String, dynamic>) {
        throw const FormatException('Not an encrypted Dhadda backup.');
      }
      m = v;
    } catch (e) {
      if (e is FormatException) rethrow;
      throw const FormatException('Not an encrypted Dhadda backup.');
    }
    if (m['format'] != format || m['v'] != version) {
      throw const FormatException('Not an encrypted Dhadda backup.');
    }
    if (m['kdf'] != 'argon2id') {
      throw const FormatException('Unsupported backup crypto.');
    }
    return m;
  }

  static ({int m, int t, int p}) _kdfParams(Map<String, dynamic> e) {
    int param(String k) {
      final v = e[k];
      if (v is! int || v <= 0) {
        throw const FormatException('Damaged backup envelope.');
      }
      return v;
    }

    final m = param('m');
    final t = param('t');
    final p = param('p');
    if (m > _maxMemory || t > _maxIterations || p > _maxParallelism) {
      throw const FormatException('Damaged backup envelope.');
    }
    return (m: m, t: t, p: p);
  }

  static List<int> _b64(Map<String, dynamic> e, String k, int min, int max) {
    try {
      final bytes = base64Decode('${e[k]}');
      if (bytes.length < min || bytes.length > max) {
        throw const FormatException('Damaged backup envelope.');
      }
      return bytes;
    } catch (err) {
      if (err is FormatException) rethrow;
      throw const FormatException('Damaged backup envelope.');
    }
  }

  static Future<SecretKey> _derive(
    String password,
    List<int> salt, {
    required int m,
    required int t,
    required int p,
  }) async {
    final kdf = Argon2id(
      parallelism: p,
      memory: m,
      iterations: t,
      hashLength: 32,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }
}
