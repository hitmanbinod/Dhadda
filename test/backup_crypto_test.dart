// Phase 3: encrypted-backup tests. KDF cost is real (seconds per op), so
// expensive round-trips are few and envelope-shape tests carry the rest.
// Ciphertext must differ across encryptions; logical content must match.
import 'dart:convert';
import 'dart:io';

import 'package:expense/sync/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/phase0/$name').readAsStringSync();

void main() {
  test('round-trip preserves content exactly', () async {
    const plain = '{"hello":"world","n":42}';
    final enc = await BackupCrypto.encrypt(plain, 'correct horse');
    expect(BackupCrypto.isEncrypted(enc), isTrue);
    expect(await BackupCrypto.decrypt(enc, 'correct horse'), plain);
  });

  test('unicode, empty, and bulk fixtures round-trip', () async {
    for (final name in [
      'snapshot_unicode.json',
      'snapshot_empty.json',
      'snapshot_single.json',
    ]) {
      final plain = _fixture(name);
      final enc = await BackupCrypto.encrypt(plain, 'pässwörd-🔑');
      expect(await BackupCrypto.decrypt(enc, 'pässwörd-🔑'), plain);
    }
  });

  test('populated + bulk fixtures round-trip', () async {
    for (final name in ['snapshot_populated.json', 'snapshot_bulk.json']) {
      final plain = _fixture(name);
      final enc = await BackupCrypto.encrypt(plain, 'another-password');
      expect(await BackupCrypto.decrypt(enc, 'another-password'), plain);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('ciphertext is randomized, plaintext is hidden', () async {
    const plain = '{"secret":1}';
    final a = await BackupCrypto.encrypt(plain, 'pw');
    final b = await BackupCrypto.encrypt(plain, 'pw');
    expect(a == b, isFalse); // random salt + nonce
    expect(a.contains('secret'), isFalse);
    expect(await BackupCrypto.decrypt(a, 'pw'), plain);
    expect(await BackupCrypto.decrypt(b, 'pw'), plain);
  });

  test('wrong password fails with a clear message', () async {
    final enc = await BackupCrypto.encrypt('{"a":1}', 'right');
    expect(
      () => BackupCrypto.decrypt(enc, 'wrong'),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('Wrong password'))),
    );
  });

  test('tampered ciphertext fails authentication', () async {
    final enc = await BackupCrypto.encrypt('{"a":1}', 'pw');
    final m = jsonDecode(enc) as Map<String, dynamic>;
    final cipher = base64Decode(m['cipher'] as String);
    cipher[0] ^= 0xFF; // flip a bit
    m['cipher'] = base64Encode(cipher);
    expect(
      () => BackupCrypto.decrypt(jsonEncode(m), 'pw'),
      throwsA(isA<FormatException>()),
    );
    // Tampered tag fails too.
    final m2 = jsonDecode(enc) as Map<String, dynamic>;
    m2['tag'] = base64Encode(List<int>.filled(16, 0));
    expect(
      () => BackupCrypto.decrypt(jsonEncode(m2), 'pw'),
      throwsA(isA<FormatException>()),
    );
  });

  test('malformed envelopes fail fast without running the KDF', () async {
    // Not marked as encrypted backups at all.
    const unmarked = [
      'not json at all',
      '[1,2,3]',
      '{}',
      '{"format":"dhadda-enc-backup"}', // missing v
      '{"format":"other","v":1}',
    ];
    for (final raw in unmarked) {
      expect(BackupCrypto.isEncrypted(raw), isFalse, reason: raw);
      expect(() => BackupCrypto.decrypt(raw, 'pw'),
          throwsA(isA<FormatException>()),
          reason: raw);
    }
    // Marked but broken: detected by the marker, rejected during parse
    // (before any KDF work) with clear errors.
    const markedBad = [
      '{"format":"dhadda-enc-backup","v":1,"kdf":"scrypt"}',
      '{"format":"dhadda-enc-backup","v":1,"kdf":"argon2id"}',
      '{"format":"dhadda-enc-backup","v":1,"kdf":"argon2id",'
          '"m":32,"t":1,"p":1,"salt":"!!!","nonce":"!!!",'
          '"cipher":"!!!","tag":"!!!"}', // bad base64
      '{"format":"dhadda-enc-backup","v":1,"kdf":"argon2id",'
          '"m":999999999,"t":1,"p":1,"salt":"AA==","nonce":"AA==",'
          '"cipher":"AA==","tag":"AA=="}', // absurd KDF cost
    ];
    for (final raw in markedBad) {
      expect(BackupCrypto.isEncrypted(raw), isTrue, reason: raw);
      expect(() => BackupCrypto.decrypt(raw, 'pw'),
          throwsA(isA<FormatException>()),
          reason: raw);
    }
  });

  test('empty password is rejected for encryption', () async {
    expect(() => BackupCrypto.encrypt('{"a":1}', ''),
        throwsA(isA<ArgumentError>()));
  });
}
