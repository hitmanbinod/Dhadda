// Regenerates design/test-vectors/lan.json from the Dart primitives.
// All values are fixed test constants - no real keys or codes are used.
import 'dart:convert';
import 'dart:io';

import 'package:expense/sync/lan_crypto.dart';

Future<void> main() async {
  final h = LanCrypto.hex;
  final u = LanCrypto.unhex;

  // RFC 7748 X25519 vectors.
  final alicePriv = u('77076d0a7318a57d3c16c17251b26645'
      'df4c2f87ebc0992ab177fba51db92c2a');
  final bobPriv = u('5dab087e624a8a4b79e17f8b83800ee6'
      '6f3bb1292618b6fd1c2f8b27ff88e0eb');
  final alicePub = await LanCrypto.x25519Public(alicePriv);
  final bobPub = await LanCrypto.x25519Public(bobPriv);
  final z = await LanCrypto.x25519Shared(alicePriv, bobPub);

  final shaIn = LanCrypto.utf8('abc');
  final shaOut = await LanCrypto.sha256(shaIn);

  final hmacKey = u('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b');
  final hmacMsg = LanCrypto.utf8('Hi There');
  final hmacOut = await LanCrypto.hmac(hmacKey, hmacMsg);

  final hkdfIkm = u('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b');
  final hkdfSalt = u('000102030405060708090a0b0c');
  final hkdfInfo = u('f0f1f2f3f4f5f6f7f8f9');
  final hkdfOut = await LanCrypto.hkdfSha256(
      ikm: hkdfIkm, salt: hkdfSalt, info: hkdfInfo);

  final pbkdfPass = u('70617373776f7264'); // "password"
  final pbkdfSalt = u('73616c74'); // "salt"
  final pbkdfOut = await LanCrypto.pbkdf2Sha256(
      password: pbkdfPass, salt: pbkdfSalt);

  final aeKey = u('000102030405060708090a0b0c0d0e0f'
      '101112131415161718191a1b1c1d1e1f');
  final aeNonce = u('000000000000004a00000000');
  final aeAad = u('50515253c0c1c2c3c4c5c6c7');
  final aePlain = LanCrypto.utf8('Dhadda LAN test frame');
  final aeSealed = await LanCrypto.seal(
      key: aeKey, nonceBytes: aeNonce, aadBytes: aeAad, plaintext: aePlain);

  // ---------- Full code-mode handshake ----------
  final codeSid = 'sid-code-0001';
  final code = 'ABCD-EFGH';
  final codeT = await LanCrypto.transcript(alicePub, bobPub, codeSid);
  final codeKey = await LanCrypto.codeKey(code, codeT);
  final proofPc = await LanCrypto.proof(codeKey, 'pc', codeT);
  final proofPhone = await LanCrypto.proof(codeKey, 'phone', codeT);
  final sessionK = await LanCrypto.sessionKey(z, codeT);
  final envPlain = LanCrypto.utf8('{"t":"entries","id":"txn-1","d":0}');
  final envNonce = LanCrypto.nonce(lanDirPcToPhone, 1);
  final envAad = LanCrypto.aad(codeSid, lanDirPcToPhone, 1);
  final envSealed = await LanCrypto.seal(
      key: sessionK,
      nonceBytes: envNonce,
      aadBytes: envAad,
      plaintext: envPlain);

  // ---------- Full QR-mode handshake ----------
  final qrSid = 'sid-qr-0002';
  final s = u('0102030405060708090a0b0c0d0e0f10');
  final qrT = await LanCrypto.transcript(alicePub, bobPub, qrSid);
  final qrK = await LanCrypto.qrKey(s, qrT);
  final qrProofPhone = await LanCrypto.proof(qrK, 'phone', qrT);
  final qrSessionK = await LanCrypto.sessionKey(z, qrT);

  // ---------- Full trusted reconnect ----------
  final trustSid = 'dev-7f3a';
  final deviceSecret = u('202122232425262728292a2b2c2d2e2f'
      '303132333435363738393a3b3c3d3e3f');
  final trustNonce = u('aabbccddeeff00112233445566778899');
  final trustT = await LanCrypto.trustedTranscript(alicePub, bobPub, trustNonce);
  final trustProofPc =
      await LanCrypto.proof(deviceSecret, 'pc', trustT, trustNonce);
  final trustProofPhone =
      await LanCrypto.proof(deviceSecret, 'phone', trustT, trustNonce);
  final trustSessionK = await LanCrypto.trustedSessionKey(z, trustT, deviceSecret);

  final map = <String, dynamic>{
    'version': 1,
    'note': 'Fixed test constants only. No real codes, keys or tokens.',
    'constants': {
      'codeAlphabet': lanCodeAlphabet,
      'kdfIterations': lanKdfIterations,
      'pairingInfo': lanPairingInfo,
      'qrInfo': lanQrInfo,
      'sessionInfo': lanSessionInfo,
      'trustedInfo': lanTrustedInfo,
      'aeadContext': lanAeadContext,
      'dirPcToPhone': lanDirPcToPhone,
      'dirPhoneToPc': lanDirPhoneToPc,
    },
    'primitives': {
      'sha256': {'input': h(shaIn), 'sha256': h(shaOut)},
      'hmacSha256': {
        'key': h(hmacKey),
        'message': h(hmacMsg),
        'mac': h(hmacOut),
      },
      'hkdfSha256': {
        'ikm': h(hkdfIkm),
        'salt': h(hkdfSalt),
        'info': h(hkdfInfo),
        'okm': h(hkdfOut),
      },
      'pbkdf2Sha256': {
        'password': h(pbkdfPass),
        'salt': h(pbkdfSalt),
        'iterations': lanKdfIterations,
        'dkLen': 32,
        'dk': h(pbkdfOut),
      },
      'x25519': {
        'alicePrivate': h(alicePriv),
        'alicePublic': h(alicePub),
        'bobPrivate': h(bobPriv),
        'bobPublic': h(bobPub),
        'shared': h(z),
      },
      'chacha20poly1305': {
        'key': h(aeKey),
        'nonce': h(aeNonce),
        'aad': h(aeAad),
        'plaintext': h(aePlain),
        'sealed': h(aeSealed),
      },
    },
    'handshakes': {
      'code': {
        'epcPrivate': h(alicePriv),
        'epcPublic': h(alicePub),
        'ephonePrivate': h(bobPriv),
        'ephonePublic': h(bobPub),
        'sid': codeSid,
        'code': code,
        'name': 'Chrome on Windows',
        'trust': true,
        'z': h(z),
        'transcript': h(codeT),
        'codeKey': h(codeKey),
        'proofPc': h(proofPc),
        'proofPhone': h(proofPhone),
        'sessionKey': h(sessionK),
        'envelope': {
          'direction': lanDirPcToPhone,
          'counter': 1,
          'nonce': h(envNonce),
          'aad': h(envAad),
          'plaintext': h(envPlain),
          'sealed': h(envSealed),
        },
      },
      'qr': {
        'epcPrivate': h(alicePriv),
        'epcPublic': h(alicePub),
        'ephonePrivate': h(bobPriv),
        'ephonePublic': h(bobPub),
        'sid': qrSid,
        's': h(s),
        'transcript': h(qrT),
        'qrKey': h(qrK),
        'proofPhone': h(qrProofPhone),
        'sessionKey': h(qrSessionK),
      },
      'trusted': {
        'epcPrivate': h(alicePriv),
        'epcPublic': h(alicePub),
        'ephonePrivate': h(bobPriv),
        'ephonePublic': h(bobPub),
        'deviceId': 'dev-7f3a',
        'deviceSecret': h(deviceSecret),
        'nonce': h(trustNonce),
        'sid': trustSid,
        'transcript': h(trustT),
        'proofPc': h(trustProofPc),
        'proofPhone': h(trustProofPhone),
        'sessionKey': h(trustSessionK),
      },
    },
    'rejection': {
      'note': 'envelope counter 0 with the code-mode session key must fail to open',
      'sessionKey': h(sessionK),
      'sid': codeSid,
      'direction': lanDirPcToPhone,
      'counter': 0,
      'sealed': h(envSealed),
    },
  };

  final file = File('design/test-vectors/lan.json');
  await file.parent.create(recursive: true);
  final encoded = const JsonEncoder.withIndent('  ').convert(map);
  await file.writeAsString('$encoded\n');
  stdout.writeln('wrote ${file.path} (${file.lengthSync()} bytes)');
}
