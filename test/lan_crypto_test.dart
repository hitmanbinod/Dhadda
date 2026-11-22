// Phase 1: Dart reproduces every shared LAN vector. No secrets are logged.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense/sync/lan_crypto.dart';

void main() {
  final v = jsonDecode(File('design/test-vectors/lan.json').readAsStringSync())
      as Map<String, dynamic>;
  final p = v['primitives'] as Map<String, dynamic>;
  final hs = v['handshakes'] as Map<String, dynamic>;
  String h(String key, String field) =>
      (p[key] as Map<String, dynamic>)[field] as String;
  String hh(String handshake, String field) =>
      (hs[handshake] as Map<String, dynamic>)[field] as String;

  test('constants and code normalisation', () {
    expect(lanCodeAlphabet, 'ABCDEFGHJKMNPQRSTUVWXYZ23456789');
    expect(lanKdfIterations, 210000);
    expect(LanCrypto.normalizeCode('abcd-efgh'), 'ABCDEFGH');
    expect(LanCrypto.normalizeCode('AB CD EF GH'), 'ABCDEFGH');
    expect(() => LanCrypto.normalizeCode('ABCD0FGH'), throwsFormatException);
    expect(() => LanCrypto.normalizeCode('abcd'), throwsFormatException);
  });

  test('SHA-256 / HMAC / HKDF / PBKDF2 known answers', () async {
    expect(LanCrypto.hex(await LanCrypto.sha256(LanCrypto.unhex(h('sha256', 'input')))),
        h('sha256', 'sha256'));
    expect(
      LanCrypto.hex(await LanCrypto.hmac(
        LanCrypto.unhex(h('hmacSha256', 'key')),
        LanCrypto.unhex(h('hmacSha256', 'message')),
      )),
      h('hmacSha256', 'mac'),
    );
    expect(
      LanCrypto.hex(await LanCrypto.hkdfSha256(
        ikm: LanCrypto.unhex(h('hkdfSha256', 'ikm')),
        salt: LanCrypto.unhex(h('hkdfSha256', 'salt')),
        info: LanCrypto.unhex(h('hkdfSha256', 'info')),
      )),
      h('hkdfSha256', 'okm'),
    );
    expect(
      LanCrypto.hex(await LanCrypto.pbkdf2Sha256(
        password: LanCrypto.unhex(h('pbkdf2Sha256', 'password')),
        salt: LanCrypto.unhex(h('pbkdf2Sha256', 'salt')),
      )),
      h('pbkdf2Sha256', 'dk'),
    );
  });

  test('X25519 RFC 7748 and ChaCha20-Poly1305 known answers', () async {
    expect(
      LanCrypto.hex(await LanCrypto.x25519Public(
          LanCrypto.unhex(h('x25519', 'alicePrivate')))),
      h('x25519', 'alicePublic'),
    );
    expect(
      LanCrypto.hex(await LanCrypto.x25519Shared(
        LanCrypto.unhex(h('x25519', 'alicePrivate')),
        LanCrypto.unhex(h('x25519', 'bobPublic')),
      )),
      h('x25519', 'shared'),
    );
    expect(
      LanCrypto.hex(await LanCrypto.seal(
        key: LanCrypto.unhex(h('chacha20poly1305', 'key')),
        nonceBytes: LanCrypto.unhex(h('chacha20poly1305', 'nonce')),
        aadBytes: LanCrypto.unhex(h('chacha20poly1305', 'aad')),
        plaintext: LanCrypto.unhex(h('chacha20poly1305', 'plaintext')),
      )),
      h('chacha20poly1305', 'sealed'),
    );
  });

  test('code-mode handshake and encrypted frame', () async {
    final epc = LanCrypto.unhex(hh('code', 'epcPublic'));
    final ephone = LanCrypto.unhex(hh('code', 'ephonePublic'));
    final sid = hh('code', 'sid');
    final t = await LanCrypto.transcript(epc, ephone, sid);
    expect(LanCrypto.hex(t), hh('code', 'transcript'));

    final key = await LanCrypto.codeKey(hh('code', 'code'), t);
    expect(LanCrypto.hex(key), hh('code', 'codeKey'));
    expect(LanCrypto.hex(await LanCrypto.proof(key, 'pc', t)),
        hh('code', 'proofPc'));
    expect(LanCrypto.hex(await LanCrypto.proof(key, 'phone', t)),
        hh('code', 'proofPhone'));

    final z = await LanCrypto.x25519Shared(
        LanCrypto.unhex(hh('code', 'epcPrivate')), ephone);
    expect(LanCrypto.hex(z), hh('code', 'z'));
    final k = await LanCrypto.sessionKey(z, t);
    expect(LanCrypto.hex(k), hh('code', 'sessionKey'));

    final env = hs['code']['envelope'] as Map<String, dynamic>;
    final nonce = LanCrypto.nonce(env['direction'] as int, env['counter'] as int);
    final aad = LanCrypto.aad(sid, env['direction'] as int, env['counter'] as int);
    expect(nonce.length, 12); // ChaCha20-Poly1305 needs 12 bytes.
    expect(LanCrypto.hex(nonce), env['nonce'] as String);
    expect(LanCrypto.hex(aad), env['aad'] as String);
    final sealed = await LanCrypto.seal(
      key: k,
      nonceBytes: nonce,
      aadBytes: aad,
      plaintext: LanCrypto.unhex(env['plaintext'] as String),
    );
    expect(LanCrypto.hex(sealed), env['sealed'] as String);
    expect(
      LanCrypto.hex(await LanCrypto.open(
        key: k,
        nonceBytes: nonce,
        aadBytes: aad,
        sealed: sealed,
      )),
      env['plaintext'] as String,
    );
  });

  test('QR-mode handshake', () async {
    final t = await LanCrypto.transcript(
      LanCrypto.unhex(hh('qr', 'epcPublic')),
      LanCrypto.unhex(hh('qr', 'ephonePublic')),
      hh('qr', 'sid'),
    );
    expect(LanCrypto.hex(t), hh('qr', 'transcript'));
    final qk = await LanCrypto.qrKey(LanCrypto.unhex(hh('qr', 's')), t);
    expect(LanCrypto.hex(qk), hh('qr', 'qrKey'));
    expect(LanCrypto.hex(await LanCrypto.proof(qk, 'phone', t)),
        hh('qr', 'proofPhone'));
    final z = await LanCrypto.x25519Shared(
      LanCrypto.unhex(hh('qr', 'epcPrivate')),
      LanCrypto.unhex(hh('qr', 'ephonePublic')),
    );
    expect(LanCrypto.hex(await LanCrypto.sessionKey(z, t)),
        hh('qr', 'sessionKey'));
  });

  test('trusted reconnect handshake', () async {
    final nonce = LanCrypto.unhex(hh('trusted', 'nonce'));
    final t = await LanCrypto.trustedTranscript(
      LanCrypto.unhex(hh('trusted', 'epcPublic')),
      LanCrypto.unhex(hh('trusted', 'ephonePublic')),
      nonce,
    );
    expect(LanCrypto.hex(t), hh('trusted', 'transcript'));
    final secret = LanCrypto.unhex(hh('trusted', 'deviceSecret'));
    expect(LanCrypto.hex(await LanCrypto.proof(secret, 'pc', t, nonce)),
        hh('trusted', 'proofPc'));
    expect(LanCrypto.hex(await LanCrypto.proof(secret, 'phone', t, nonce)),
        hh('trusted', 'proofPhone'));
    // The trusted vector reuses the code-mode ephemerals.
    final z = await LanCrypto.x25519Shared(
      LanCrypto.unhex(hh('code', 'epcPrivate')),
      LanCrypto.unhex(hh('code', 'ephonePublic')),
    );
    expect(
      LanCrypto.hex(await LanCrypto.trustedSessionKey(z, t, secret)),
      hh('trusted', 'sessionKey'),
    );
  });

  test('replay / wrong-counter frame is rejected', () async {
    final r = v['rejection'] as Map<String, dynamic>;
    final sid = r['sid'] as String;
    final nonce = LanCrypto.nonce(r['direction'] as int, r['counter'] as int);
    final aad = LanCrypto.aad(sid, r['direction'] as int, r['counter'] as int);
    expect(
      () => LanCrypto.open(
        key: LanCrypto.unhex(r['sessionKey'] as String),
        nonceBytes: nonce,
        aadBytes: aad,
        sealed: LanCrypto.unhex(r['sealed'] as String),
      ),
      throwsA(anything),
    );
  });

  test('constant-time comparison', () {
    expect(LanCrypto.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(LanCrypto.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(LanCrypto.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });
}
