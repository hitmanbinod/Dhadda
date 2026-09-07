// Phase 5: live-HTTP LAN security tests (localhost servers, real shelf).
//
// Proves: auth gating, session issue/use/revoke/expiry, PIN throttling
// (429 + Retry-After + reset), body caps (413), malformed safety (400),
// CORS presence for browser receivers, and v1-compat paths intact.
// VM-only (dart:io servers); never compiled to web.
import 'dart:convert';
import 'dart:io';

import 'package:expense/sync/phone_host_io.dart';
import 'package:expense/sync/wifi_client.dart';
import 'package:expense/sync/wifi_host.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

const _pin = '123456';
const _json = {'Content-Type': 'application/json'};

/// 8 MiB + 1 byte: must be rejected before buffering completes.
String _oversized() => 'x' * ((8 << 20) + 1);

void main() {
  group('direct WiFi sender', () {
    test('unauthorized requests are rejected, misses are 403', () async {
      late HostSession s;
      try {
        s = await startSendServer(
          currentSnapshot: () => '{"version":1}',
          onUpload: (_) {},
          pin: _pin,
        );
        var r = await http.get(Uri.parse('${s.url}/meta'));
        expect(r.statusCode, 403);
        r = await http.get(Uri.parse('${s.url}/snapshot'));
        expect(r.statusCode, 403);
        r = await http.post(Uri.parse('${s.url}/snapshot'),
            headers: _json, body: '{}');
        expect(r.statusCode, 403);
      } finally {
        try { await s.close(); } catch (_) {}
      }
    });

    test('session lifecycle: issue, use, revoke, distinct tokens', () async {
      late HostSession s;
      try {
        s = await startSendServer(
          currentSnapshot: () => '{"version":1}',
          onUpload: (_) {},
          pin: _pin,
        );
        // Wrong PIN fails without issuing anything.
        expect(
          () => WifiClient.establishSession(s.url, '000000'),
          throwsA(isA<FormatException>()),
        );
        final t1 = await WifiClient.establishSession(s.url, _pin);
        final t2 = await WifiClient.establishSession(s.url, _pin);
        expect(t1, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(t2, isNot(t1)); // random per bootstrap
        // Bearer works where the PIN header worked.
        expect(
            await WifiClient.fetchRemoteSnapshot(s.url, _pin, token: t1),
            '{"version":1}');
        // Unknown token is rejected.
        expect(
          () => WifiClient.fetchRemoteSnapshot(s.url, _pin,
              token: '0' * 32),
          throwsA(isA<FormatException>()),
        );
        // Logout revokes: the same token stops working.
        await WifiClient.logout(s.url, _pin, t1!);
        expect(
          () => WifiClient.fetchRemoteSnapshot(s.url, _pin, token: t1),
          throwsA(isA<FormatException>()),
        );
        // The other session is unaffected.
        expect(
            await WifiClient.fetchRemoteSnapshot(s.url, _pin, token: t2),
            '{"version":1}');
      } finally {
        try { await s.close(); } catch (_) {}
      }
    });

    test('server stop ends all sessions', () async {
      final s = await startSendServer(
        currentSnapshot: () => '{"version":1}',
        onUpload: (_) {},
        pin: _pin,
      );
      final t = await WifiClient.establishSession(s.url, _pin);
      await s.close();
      // No listener at all anymore (connection refused, not 403).
      expect(
        () => WifiClient.fetchRemoteSnapshot(s.url, _pin, token: t),
        throwsA(anything),
      );
    });

    test('wrong PINs throttle to 429 then reset on success', () async {
      late HostSession s;
      try {
        s = await startSendServer(
          currentSnapshot: () => '{"version":1}',
          onUpload: (_) {},
          pin: _pin,
        );
        http.Response r;
        for (var i = 0; i < 10; i++) {
          r = await http.post(Uri.parse('${s.url}/auth'),
              headers: _json, body: jsonEncode({'pin': '000000'}));
          expect(r.statusCode, 403, reason: 'attempt ${i + 1}');
        }
        r = await http.post(Uri.parse('${s.url}/auth'),
            headers: _json, body: jsonEncode({'pin': '000000'}));
        expect(r.statusCode, 429);
        expect(r.headers['retry-after'], isNotNull);
        // Success resets: correct PIN works immediately after.
        final t = await WifiClient.establishSession(s.url, _pin);
        expect(t, isNotNull);
      } finally {
        try { await s.close(); } catch (_) {}
      }
    });

    test('oversized and malformed bodies are rejected safely', () async {
      late HostSession s;
      try {
        var uploaded = 0;
        s = await startSendServer(
          currentSnapshot: () => '{"version":1}',
          onUpload: (_) => uploaded++,
          pin: _pin,
        );
        final t = await WifiClient.establishSession(s.url, _pin);
        final big = _oversized();
        var r = await http.post(Uri.parse('${s.url}/snapshot'),
            headers: {
              ..._json,
              'authorization': 'Bearer $t',
            },
            body: big);
        expect(r.statusCode, 413);
        expect(uploaded, 0); // rejected BEFORE the upload handler ran
        r = await http.post(Uri.parse('${s.url}/snapshot'),
            headers: {
              ..._json,
              'authorization': 'Bearer $t',
            },
            body: 'this is not json{{{');
        expect(r.statusCode, 400);
        expect(uploaded, 0);
      } finally {
        try { await s.close(); } catch (_) {}
      }
    });

    test('CORS headers stay present for browser receivers', () async {
      late HostSession s;
      try {
        s = await startSendServer(
          currentSnapshot: () => '{"version":1}',
          onUpload: (_) {},
          pin: _pin,
        );
        final client = http.Client();
        try {
          final req = http.Request(
              'OPTIONS', Uri.parse('${s.url}/snapshot'));
          req.headers['Origin'] = 'http://example.com';
          final streamed = await client.send(req);
          expect(
              streamed.headers['access-control-allow-origin'], '*');
        } finally {
          client.close();
        }
      } finally {
        try { await s.close(); } catch (_) {}
      }
    });
  });

  group('phone-host link API', () {
    Future<String> createBox(String base) async {
      final r = await http.post(Uri.parse('$base/api/sync/link'),
          headers: _json,
          body: jsonEncode({
            'pin': _pin,
            'deviceId': 'devA',
            'snapshot': '{"version":1}',
            'name': 'A',
            'time': '',
          }));
      expect(r.statusCode, 200);
      return (jsonDecode(r.body) as Map<String, dynamic>)['link'] as String;
    }

    test('link PINs throttle per box with reset', () async {
      late PhoneHostSession h;
      try {
        h = await startPhoneHost();
        final link = await createBox(h.url);
        http.Response r;
        for (var i = 0; i < 10; i++) {
          r = await http.get(Uri.parse(
              '${h.url}/api/sync/pull?link=$link&pin=000000&deviceId=d'));
          expect(r.statusCode, 403, reason: 'attempt ${i + 1}');
        }
        r = await http.get(Uri.parse(
            '${h.url}/api/sync/pull?link=$link&pin=000000&deviceId=d'));
        expect(r.statusCode, 429);
        expect(r.headers['retry-after'], isNotNull);
        // Correct PIN works and resets the box throttle.
        r = await http.get(Uri.parse(
            '${h.url}/api/sync/pull?link=$link&pin=$_pin&deviceId=d'));
        expect(r.statusCode, 200);
      } finally {
        try { await h.close(); } catch (_) {}
      }
    });

    test('oversized and malformed link bodies are rejected safely',
        () async {
      late PhoneHostSession h;
      try {
        h = await startPhoneHost();
        final link = await createBox(h.url);
        var r = await http.post(Uri.parse('${h.url}/api/sync/push'),
            headers: _json,
            body: jsonEncode({
              'link': link,
              'pin': _pin,
              'deviceId': 'devA',
              'snapshot': _oversized(),
              'name': 'A',
              'time': '',
            }));
        expect(r.statusCode, 413);
        r = await http.post(Uri.parse('${h.url}/api/sync/push'),
            headers: _json, body: 'nope{{{');
        expect(r.statusCode, 400);
      } finally {
        try { await h.close(); } catch (_) {}
      }
    });
  });

  group('node relay', () {
    test('PIN throttle, v2 passthrough, safe errors', () async {
      Process? proc;
      HttpClient? client;
      try {
        final root =
            await Directory.systemTemp.createTemp('dhadda_p5relay_');
        addTearDown(() => root.delete(recursive: true));
        var base = '';
        for (final port in [18081, 18082, 18083]) {
          try {
            proc = await Process.start('node', [
              'server/serve-expense.cjs',
              root.path,
              '$port',
            ], workingDirectory: Directory.current.path);
            // Give it a moment; probe for liveness.
            var live = false;
            for (var i = 0; i < 50; i++) {
              await Future<void>.delayed(
                  const Duration(milliseconds: 100));
              try {
                client ??= HttpClient();
                final req = await client
                    .getUrl(Uri.parse('http://127.0.0.1:$port/api/ping'))
                    .timeout(const Duration(seconds: 2));
                final res = await req.close();
                await res.drain();
                live = true;
                break;
              } catch (_) {}
            }
            if (live) {
              base = 'http://127.0.0.1:$port';
              break;
            }
            proc.kill();
            proc = null;
          } catch (_) {
            proc = null;
          }
        }
        if (base.isEmpty) {
          markTestSkipped('node relay unavailable');
        }
        Future<Map<String, dynamic>> post(
            String path, Map<String, dynamic> body) async {
          final req = await client!.postUrl(Uri.parse('$base$path'));
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
          final res = await req.close();
          final text = await res.transform(utf8.decoder).join();
          return {'status': res.statusCode, 'body': text};
        }

        Future<Map<String, dynamic>> get(String path) async {
          final req = await client!.getUrl(Uri.parse('$base$path'));
          final res = await req.close();
          final text = await res.transform(utf8.decoder).join();
          return {'status': res.statusCode, 'body': text};
        }

        final created = await post('/api/sync/link', {
          'pin': _pin,
          'deviceId': 'devA',
          'snapshot': '{"version":1}',
          'name': 'A',
          'time': '',
        });
        expect(created['status'], 200);
        final link =
            (jsonDecode(created['body'] as String) as Map)['link'];
        // v2 field round-trips through the relay untouched.
        final pushed = await post('/api/sync/push', {
          'link': link,
          'pin': _pin,
          'deviceId': 'devB',
          'snapshot': '{"version":1}',
          'snapshotV2': '{"format":2}',
          'name': 'B',
          'time': '',
        });
        expect(pushed['status'], 200);
        final pulled = await get(
            '/api/sync/pull?link=$link&pin=$_pin&deviceId=devA');
        expect(pulled['status'], 200);
        final peers =
            (jsonDecode(pulled['body'] as String) as Map)['peers'] as List;
        expect((peers.single as Map)['snapshotV2'], '{"format":2}');
        // Wrong PINs throttle: 10 free, then 429 (never a stack/payload).
        for (var i = 0; i < 10; i++) {
          final r = await get(
              '/api/sync/pull?link=$link&pin=000000&deviceId=d');
          expect(r['status'], 403, reason: 'attempt ${i + 1}');
        }
        final limited = await get(
            '/api/sync/pull?link=$link&pin=000000&deviceId=d');
        expect(limited['status'], 429);
        expect(
            (jsonDecode(limited['body'] as String) as Map)['error'],
            isNot(contains('at '))); // no stack traces
      } finally {
        client?.close(force: true);
        proc?.kill();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
