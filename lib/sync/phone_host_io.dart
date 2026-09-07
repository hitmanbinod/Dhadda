import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'http_limits.dart';
import 'lan_throttle.dart';
import 'link_store.dart';

/// A serving session of the phone-hosted app.
class PhoneHostSession {
  final String url;
  final ValueNotifier<int> hits;
  final Future<void> Function() close;
  PhoneHostSession({
    required this.url,
    required this.hits,
    required this.close,
  });
}

const _mime = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.css': 'text/css',
  '.map': 'application/json',
  '.webmanifest': 'application/manifest+json',
};

/// This phone's LAN address, preferring common home subnets.
Future<String> phoneLanIp() async {
  try {
    final ifs = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final all = <String>[];
    for (final i in ifs) {
      for (final a in i.addresses) {
        if (!a.isLoopback) all.add(a.address);
      }
    }
    String pick(bool Function(String) t) {
      for (final c in all) {
        if (t(c)) return c;
      }
      return '';
    }

    var ip = pick((s) => s.startsWith('192.168.'));
    if (ip.isEmpty) ip = pick((s) => s.startsWith('10.'));
    if (ip.isEmpty) ip = pick((s) => s.startsWith('172.'));
    if (ip.isEmpty && all.isNotEmpty) ip = all.first;
    return ip;
  } catch (_) {
    return '';
  }
}

Response _json(int code, Map<String, dynamic> obj,
    [Map<String, String>? extraHeaders]) {
  final headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    ...?extraHeaders,
  };
  return Response(code, body: jsonEncode(obj), headers: headers);
}

/// HTTP 429 with Retry-After for throttled scopes.
Response _rateLimited(LanThrottle throttle, String scope) => _json(
      429,
      {'error': 'rate limited, retry later'},
      {'Retry-After': '${throttle.remaining(scope).inSeconds + 1}'},
    );

/// Serves the bundled web UI plus the link-sync API on your WiFi, so
/// any same-network browser can open the tracker straight from
/// this phone. No PC, no cloud. Works while the app stays open.
Future<PhoneHostSession> startPhoneHost() async {
  final mail = LinkStore();
  final hits = ValueNotifier<int>(0);
  // LAN PIN throttle: per link box (boxes already cap at 50 with TTL, so
  // no attacker-growable state). Static assets and /api/ping stay public.
  final throttle = LanThrottle();
  var base = '';

  void bump() {
    try {
      hits.value++;
    } catch (e) {
      debugPrint('phone-host hits bump failed: ${e.runtimeType}');
    }
  }

  Future<Response> asset(String name) async {
    Uint8List? bytes;
    try {
      final data = await rootBundle.load('assets/webapp/$name');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      bytes = null;
    }
    bytes ??= await _indexBytes();
    if (bytes == null) {
      debugPrint('phone-host: assets/webapp bundle missing in this build');
      return Response.notFound('app not bundled in this build');
    }
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot).toLowerCase();
    return Response.ok(
      bytes,
      headers: {
        'Content-Type': _mime[ext] ?? 'application/octet-stream',
        'Cache-Control': 'no-cache',
      },
    );
  }

  final router = Router();
  router.post('/api/sync/link', (Request req) async {
    Map<String, dynamic> b;
    try {
      b = jsonDecode(await readCappedBody(req)) as Map<String, dynamic>;
    } on BodyTooBig {
      return _json(413, {'error': 'too big'});
    } catch (_) {
      return _json(400, {'error': 'bad json'});
    }
    final id = mail.create(
      pin: '${b['pin'] ?? ''}',
      deviceId: '${b['deviceId'] ?? ''}',
      snapshot: '${b['snapshot'] ?? ''}',
      snapshotV2: b['snapshotV2'] is String ? b['snapshotV2'] as String : '',
      name: '${b['name'] ?? 'device'}',
      time: '${b['time'] ?? ''}',
    );
    if (id == null) return _json(400, {'error': 'bad input'});
    return _json(200, {'link': id, 'origin': base});
  });
  router.post('/api/sync/push', (Request req) async {
    Map<String, dynamic> b;
    try {
      b = jsonDecode(await readCappedBody(req)) as Map<String, dynamic>;
    } on BodyTooBig {
      return _json(413, {'error': 'too big'});
    } catch (_) {
      return _json(400, {'error': 'bad json'});
    }
    final scope = 'box:${b['link'] ?? ''}';
    final r = mail.push(
      id: '${b['link'] ?? ''}',
      pin: '${b['pin'] ?? ''}',
      deviceId: '${b['deviceId'] ?? ''}',
      snapshot: '${b['snapshot'] ?? ''}',
      snapshotV2: b['snapshotV2'] is String ? b['snapshotV2'] as String : '',
      name: '${b['name'] ?? 'device'}',
      time: '${b['time'] ?? ''}',
    );
    switch (r) {
      case LinkOutcome.ok:
        throttle.passed(scope);
        return _json(200, {'ok': true});
      case LinkOutcome.gone:
        return _json(404, {'error': 'link gone - pair again'});
      case LinkOutcome.forbidden:
        // Correct credentials always work (checked above by outcome);
        // only failures throttle, so legit users never lock themselves out.
        if (!throttle.allowed(scope)) {
          return _rateLimited(throttle, scope);
        }
        throttle.failed(scope);
        return _json(403, {'error': 'wrong pin'});
      case LinkOutcome.badInput:
        return _json(400, {'error': 'bad input'});
    }
  });
  router.get('/api/sync/pull', (Request req) {
    final q = req.url.queryParameters;
    final scope = 'box:${q['link'] ?? ''}';
    final r = mail.pull(
      id: q['link'] ?? '',
      pin: q['pin'] ?? '',
      deviceId: q['deviceId'] ?? '',
    );
    switch (r.outcome) {
      case LinkOutcome.ok:
        throttle.passed(scope);
        return _json(200, {
          'peers': [
            for (final e in r.peers)
              {
                'deviceId': e.key,
                'snapshot': e.value.snapshot,
                'snapshotV2': e.value.snapshotV2,
                'name': e.value.name,
                'time': e.value.time,
              },
          ],
        });
      case LinkOutcome.gone:
        return _json(404, {'error': 'link gone - pair again'});
      case LinkOutcome.forbidden:
        if (!throttle.allowed(scope)) {
          return _rateLimited(throttle, scope);
        }
        throttle.failed(scope);
        return _json(403, {'error': 'wrong pin'});
      case LinkOutcome.badInput:
        return _json(400, {'error': 'bad input'});
    }
  });
  router.post('/api/sync/unlink', (Request req) async {
    Map<String, dynamic> b = {};
    try {
      b = jsonDecode(await readCappedBody(req)) as Map<String, dynamic>;
    } on BodyTooBig {
      return _json(413, {'error': 'too big'});
    } catch (_) {}
    mail.unlink(id: '${b['link'] ?? ''}', pin: '${b['pin'] ?? ''}');
    return _json(200, {'ok': true});
  });
  router.get('/api/ping', (Request req) {
    return _json(200, {'ok': true, 'serve': base});
  });
  // Explicit root: some shelf_router builds don't match '/' with the
  // wildcard below, which used to surface as a bare 500 in browsers.
  router.get('/', (Request req) async => asset('index.html'));
  router.get('/<path|.*>', (Request req) async {
    final p = req.url.path;
    if (p.isEmpty) return asset('index.html');
    final hit = await _tryAsset(p);
    if (hit != null) return hit;
    return asset('index.html'); // SPA fallback
  });

  final handler = const Pipeline()
      .addMiddleware(
        (inner) => (Request req) async {
          if (req.method == 'OPTIONS') {
            return Response.ok(
              '',
              headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
              },
            );
          }
          debugPrint('phone-host ${req.method} ${req.requestedUri.path}');
          bump();
          Response res;
          try {
            res = await inner(req);
            } catch (e) {
              // Error class only: messages/stacks could echo request bytes.
              debugPrint('phone-host handler threw: ${e.runtimeType}');
              return Response.internalServerError(
                body: 'Dhadda host error (${e.runtimeType}).',
              );
            }
          try {
            return res.change(
              headers: {...res.headers, 'Access-Control-Allow-Origin': '*'},
            );
          } catch (_) {
            return res;
          }
        },
      )
      .addHandler(router.call);

  HttpServer? server;
  Object? lastError;
  for (final port in [8080, 0]) {
    try {
      server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      lastError = null;
      break;
    } catch (e) {
      lastError = e;
    }
  }
  if (server == null) {
    throw StateError('Could not open a port for PC mode ($lastError).');
  }
  var ip = await phoneLanIp();
  ip = ip.isEmpty ? server.address.address : ip;
  base = 'http://$ip:${server.port}';
  final s = server;
  return PhoneHostSession(
    url: base,
    hits: hits,
    close: () async {
      try {
        await s.close(force: true);
      } catch (_) {}
    },
  );
}

Future<Uint8List?> _tryAsset(String name) async {
  try {
    final data = await rootBundle.load('assets/webapp/$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _indexBytes() async => _tryAsset('index.html');
