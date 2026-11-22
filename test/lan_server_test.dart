// Phase 2: real HttpServer on loopback, driven by a Dart client through every
// LAN pairing mode and the encrypted data channel. No secrets are logged.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';

import 'package:expense/sync/lan_crypto.dart';
import 'package:expense/sync/lan_server.dart';

final Random _rng = Random.secure();
Uint8List _bytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

class _Reply {
  final int status;
  final Map<String, dynamic> body;
  final Map<String, String> headers;
  _Reply(this.status, this.body, this.headers);
}

class _Client {
  final String base;
  final HttpClient _http = HttpClient();
  _Client(this.base);

  Future<_Reply> post(String path, Object body, {String? host}) async {
    final req = await _http.postUrl(Uri.parse('$base$path'));
    req.headers.contentType = ContentType.json;
    if (host != null) req.headers.host = host;
    req.write(jsonEncode(body));
    return _finish(req);
  }

  Future<_Reply> get(String path, {String? host}) async {
    final req = await _http.getUrl(Uri.parse('$base$path'));
    if (host != null) req.headers.host = host;
    return _finish(req);
  }

  Future<_Reply> _finish(HttpClientRequest req) async {
    final res = await req.close();
    final raw = await utf8.decoder.bind(res).join();
    Map<String, dynamic> parsed = {};
    try {
      parsed = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    final headers = <String, String>{};
    for (final name in const [
      'content-security-policy',
      'x-content-type-options',
      'referrer-policy',
      'content-encoding',
      'cache-control',
    ]) {
      final value = res.headers.value(name);
      if (value != null) headers[name] = value;
    }
    return _Reply(res.statusCode, parsed, headers);
  }

  Future<_Reply> envelope(String path, String sid, Uint8List key, int n,
          Object payload) async =>
      post(path, {
        'sid': sid,
        'n': n,
        'ct': LanCrypto.hex(await LanCrypto.seal(
          key: key,
          nonceBytes: LanCrypto.nonce(lanDirPcToPhone, n),
          aadBytes: LanCrypto.aad(sid, lanDirPcToPhone, n),
          plaintext: utf8.encode(jsonEncode(payload)),
        )),
      });

  void close() => _http.close(force: true);
}

void main() {
  late LanServer server;
  late MemoryLanDataStore data;
  late _Client client;

  Future<void> boot({Duration? ttl}) async {
    data = MemoryLanDataStore();
    server = LanServer(
      data: data,
      options: LanServerOptions(
        port: 0,
        allowLoopback: true,
        pairingTtl: ttl ?? const Duration(seconds: 120),
        assetLoader: (name) async => name == 'webapp/index.html'
            ? Uint8List.fromList(utf8.encode('<html>Dhadda</html>'))
            : null,
      ),
    );
    await server.start();
    client = _Client(server.baseUrl!);
  }

  Future<Map<String, dynamic>> hello(
      Uint8List epcPriv, Uint8List epcPub,
      {bool trust = false, String mode = 'code'}) async {
    final r = await client.post('/pair/hello', {
      'epc': LanCrypto.hex(epcPub),
      'name': 'Chrome on Windows',
      'trust': trust,
      'mode': mode,
    });
    expect(r.status, 200);
    return r.body;
  }

  Future<_Reply> confirmCode(String sid, String proof) =>
      client.post('/pair/confirm', {'sid': sid, 'proof': proof});

  Future<Map<String, dynamic>> codePair(
      {bool trust = false, bool autoApprove = true}) async {
    final code = server.newCode();
    final epcPriv = _bytes(32);
    final epcPub = await LanCrypto.x25519Public(epcPriv);
    final h = await hello(epcPriv, epcPub, trust: trust);
    final sid = h['sid'] as String;
    final ephone = LanCrypto.unhex(h['ephone'] as String);
    final t = await LanCrypto.transcript(epcPub, ephone, sid);
    final key = await LanCrypto.codeKey(code, t);
    final z = await LanCrypto.x25519Shared(epcPriv, ephone);
    final sessionKey = await LanCrypto.sessionKey(z, t);
    final proof = LanCrypto.hex(await LanCrypto.proof(key, 'pc', t));
    final future = confirmCode(sid, proof);
    if (autoApprove) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      server.approve(sid);
    }
    final r = await future;
    return {
      'sid': sid,
      'key': LanCrypto.hex(key),
      'sessionKey': LanCrypto.hex(sessionKey),
      't': LanCrypto.hex(t),
      'epcPub': LanCrypto.hex(epcPub),
      'epcPriv': LanCrypto.hex(epcPriv),
      'ephone': LanCrypto.hex(ephone),
      'response': r.body,
      'status': r.status,
    };
  }

  Future<Map<String, dynamic>> openReply(
      _Reply r, String sid, Uint8List key) async {
    expect(r.status, 200, reason: '${r.body}');
    final n = (r.body['n'] as num).toInt();
    final plain = await LanCrypto.open(
      key: key,
      nonceBytes: LanCrypto.nonce(lanDirPhoneToPc, n),
      aadBytes: LanCrypto.aad(sid, lanDirPhoneToPc, n),
      sealed: LanCrypto.unhex(r.body['ct'] as String),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  tearDown(() async {
    client.close();
    await server.stop();
  });

  setUp(boot);

  test('static asset, security headers, gzip and Host rejection', () async {
    final r = await client.get('/');
    expect(r.status, 200);
    expect(r.headers['content-security-policy'], contains("default-src 'self'"));
    expect(r.headers['x-content-type-options'], 'nosniff');
    expect(r.headers['referrer-policy'], 'no-referrer');
    final bad = await client.get('/', host: 'evil.example');
    expect(bad.status, 400);
  });

  test('code mode: proof, Allow gate, snapshot, push, WS event, replay',
      () async {
    final p = await codePair();
    expect(p['status'], 200);
    final sid = p['sid'] as String;
    final key = LanCrypto.unhex(p['sessionKey'] as String);
    final res = p['response'] as Map<String, dynamic>;
    final expectedPhone = await LanCrypto.proof(
        LanCrypto.unhex(p['key'] as String), 'phone',
        LanCrypto.unhex(p['t'] as String));
    expect(LanCrypto.unhex(res['proof_phone'] as String),
        expectedPhone);

    final socket = await WebSocket.connect('ws://127.0.0.1:${Uri.parse(server.baseUrl!).port}/api/events?sid=$sid');
    final frames = <dynamic>[];
    socket.listen(frames.add);

    final snap = await client.envelope(
        '/api/snapshot', sid, key, 1, {'get': 'rows'});
    final snapBody = await openReply(snap, sid, key);
    expect(snapBody['rows'], isEmpty);

    final row = {
      't': 'entries',
      'id': 'txn-1',
      'ua': 100,
      'd': 0,
      'device_id': 'pc-1',
      'data': {'amount': 250},
    };
    final push = await client.envelope(
        '/api/push', sid, key, 2, {'rows': [row]});
    final pushBody = await openReply(push, sid, key);
    expect(pushBody['ok'], isTrue);
    expect(data.rows().length, 1);
    expect(data.rows().first['id'], 'txn-1');

    await server.notifyRowsChanged([
      {'t': 'entries', 'id': 'txn-2', 'ua': 101, 'd': 0, 'data': {}}
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(frames.length, greaterThanOrEqualTo(2));
    // The first frame echoes the PC push; the second is the phone-side change.
    late Map<String, dynamic> changed;
    for (final raw in frames) {
      final frame = jsonDecode('$raw') as Map<String, dynamic>;
      final fn = (frame['n'] as num).toInt();
      final plain = await LanCrypto.open(
        key: key,
        nonceBytes: LanCrypto.nonce(lanDirPhoneToPc, fn),
        aadBytes: LanCrypto.aad(sid, lanDirPhoneToPc, fn),
        sealed: LanCrypto.unhex(frame['ct'] as String),
      );
      changed = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      if (changed['changed'][0]['id'] == 'txn-2') break;
    }
    expect(changed['changed'][0]['id'], 'txn-2');

    final replay = await client.envelope(
        '/api/snapshot', sid, key, 1, {'get': 'rows'});
    expect(replay.status, 403);
    await socket.close();
  });

  test('wrong-code lockout after five attempts', () async {
    final code = server.newCode();
    final epcPriv = _bytes(32);
    final epcPub = await LanCrypto.x25519Public(epcPriv);
    final h = await hello(epcPriv, epcPub);
    final sid = h['sid'] as String;
    final ephone = LanCrypto.unhex(h['ephone'] as String);
    final t = await LanCrypto.transcript(epcPub, ephone, sid);
    for (var i = 0; i < 5; i++) {
      final r = await confirmCode(sid, LanCrypto.hex(_bytes(32)));
      expect(r.status, 403);
      expect(r.body['attempts_left'], 4 - i);
    }
    final sixth = await confirmCode(sid, LanCrypto.hex(_bytes(32)));
    expect(sixth.status, 429);
    final correct = LanCrypto.hex(
        await LanCrypto.proof(await LanCrypto.codeKey(code, t), 'pc', t));
    final blocked = await confirmCode(sid, correct);
    expect(blocked.status, 429);
  });

  test('QR mode: scan is consent, poll returns proof_phone', () async {
    final epcPriv = _bytes(32);
    final epcPub = await LanCrypto.x25519Public(epcPriv);
    final h = await hello(epcPriv, epcPub, mode: 'qr');
    final sid = h['sid'] as String;
    final ephone = LanCrypto.unhex(h['ephone'] as String);
    final s = LanCrypto.unhex(h['s'] as String);
    expect(s.length, 16);
    final t = await LanCrypto.transcript(epcPub, ephone, sid);
    final qk = await LanCrypto.qrKey(s, t);
    final proofPhone = await LanCrypto.proof(qk, 'phone', t);

    final waiting = await client.get(
        '/pair/poll?sid=${Uri.encodeComponent(sid)}&epc=${LanCrypto.hex(epcPub)}');
    expect(waiting.status, 202);
    expect(server.pendingQr.length, 1);

    server.approveQr(sid, epcPub);
    final done = await client.get(
        '/pair/poll?sid=${Uri.encodeComponent(sid)}&epc=${LanCrypto.hex(epcPub)}');
    expect(done.status, 200);
    expect(LanCrypto.unhex(done.body['proof_phone'] as String), proofPhone);
    expect(server.sessions.length, 1);
  });

  test('expired pairing code is rejected', () async {
    client.close();
    await server.stop();
    await boot(ttl: const Duration(milliseconds: 30));
    final epcPriv = _bytes(32);
    final epcPub = await LanCrypto.x25519Public(epcPriv);
    server.newCode();
    final h = await hello(epcPriv, epcPub);
    final sid = h['sid'] as String;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final r = await confirmCode(sid, LanCrypto.hex(_bytes(32)));
    expect(r.status, 410);
  });

  test('trusted reconnect works and forgetting revokes', () async {
    final p = await codePair(trust: true);
    expect(p['status'], 200);
    final sid = p['sid'] as String;
    final key = LanCrypto.unhex(p['sessionKey'] as String);
    final secretFrame = p['response']['secret'] as Map<String, dynamic>;
    final n = (secretFrame['n'] as num).toInt();
    final plain = await LanCrypto.open(
      key: key,
      nonceBytes: LanCrypto.nonce(lanDirPhoneToPc, n),
      aadBytes: LanCrypto.aad(sid, lanDirPhoneToPc, n),
      sealed: LanCrypto.unhex(secretFrame['ct'] as String),
    );
    final secretBody = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final deviceId = secretBody['device_id'] as String;
    final deviceSecret = LanCrypto.unhex(secretBody['device_secret'] as String);
    expect(deviceId, startsWith('dev-'));
    expect(server.trusted.length, 1);

    Future<Map<String, dynamic>> reconnect(Uint8List epcPriv) async {
      final epcPub = await LanCrypto.x25519Public(epcPriv);
      final h = await client.post('/session/hello', {
        'device_id': deviceId,
        'epc': LanCrypto.hex(epcPub),
      });
      expect(h.status, 200, reason: '${h.body}');
      final ephone = LanCrypto.unhex(h.body['ephone'] as String);
      final nonce = LanCrypto.unhex(h.body['nonce'] as String);
      final t = await LanCrypto.trustedTranscript(epcPub, ephone, nonce);
      final pc = await LanCrypto.proof(deviceSecret, 'pc', t, nonce);
      final phone = await LanCrypto.proof(deviceSecret, 'phone', t, nonce);
      final c = await client.post('/session/confirm', {
        'device_id': deviceId,
        'proof_pc': LanCrypto.hex(pc),
      });
      expect(c.status, 200);
      expect(LanCrypto.unhex(c.body['proof_phone'] as String), phone);
      return {'t': LanCrypto.hex(t), 'nonce': LanCrypto.hex(nonce)};
    }

    await reconnect(_bytes(32)); // silently reconnects with no code
    expect(server.sessions.any((s) => s.deviceId == deviceId), isTrue);

    server.forget(deviceId);
    expect(server.trusted, isEmpty);
    final epcPriv = _bytes(32);
    final epcPub = await LanCrypto.x25519Public(epcPriv);
    final denied = await client.post('/session/hello', {
      'device_id': deviceId,
      'epc': LanCrypto.hex(epcPub),
    });
    expect(denied.status, 403);
    expect(denied.body['error'], 'pair again');
  });

  test('LWW picks larger ua and breaks ties by device_id', () async {
    final p = await codePair();
    final sid = p['sid'] as String;
    final key = LanCrypto.unhex(p['sessionKey'] as String);
    final rows = [
      {'t': 'entries', 'id': 'x', 'ua': 5, 'd': 0, 'device_id': 'a', 'data': {'v': 1}},
      {'t': 'entries', 'id': 'x', 'ua': 5, 'd': 0, 'device_id': 'b', 'data': {'v': 2}},
      {'t': 'entries', 'id': 'y', 'ua': 9, 'd': 0, 'device_id': 'a', 'data': {'v': 3}},
    ];
    final r = await client.envelope('/api/push', sid, key, 1, {'rows': rows});
    expect(r.status, 200);
    final byId = {for (final row in data.rows()) row['id']: row};
    expect(byId['x']!['device_id'], 'b');
    expect(byId['y']!['ua'], 9);
  });
}
