import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'http_limits.dart';
import 'lan_throttle.dart';

/// A short-lived LAN server hosting this device's snapshot.
/// The receiver fetches GET /meta, then GET /snapshot (pull) or
/// POST /snapshot (push its newer snapshot). Guarded by a 6-digit PIN
/// header. Auto-closes after 5 minutes.
///
/// Phase 5 LAN hardening (behavior, not transport confidentiality Ã¢â‚¬â€
/// plain HTTP stays observable on hostile networks, see docs/SECURITY_LAN):
/// - Wrong-PIN attempts are throttled globally (10 free, then HTTP 429
///   with Retry-After for 60 s; any success resets). No per-client state
///   that could grow without bound.
/// - After one PIN bootstrap (POST /auth), the receiver uses a random
///   128-bit session token (TTL = server lifetime, explicit logout
///   revokes). The legacy PIN header keeps working for old receivers.
/// - Request bodies are capped (413 beyond the cap) and JSON-validated;
///   errors are static strings, never echoes. Nothing sensitive is logged.
class HostSession {
  final String url;
  final String pin;
  final Future<void> Function() close;
  HostSession({required this.url, required this.pin, required this.close});
}

const _pinHeader = 'x-sync-pin';
const _authHeader = 'authorization';
const _authPrefix = 'Bearer ';

/// Max live session tokens (bounded; oldest evicted first).
const _maxSessions = 16;

Map<String, String> _cors() => {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, $_pinHeader, $_authHeader',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Content-Type': 'application/json',
};

Future<String> _lanIp() async {
  final candidates = <String>[];
  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in ifaces) {
      for (final a in iface.addresses) {
        if (a.isLoopback) continue;
        candidates.add(a.address);
      }
    }
  } catch (_) {
    return '';
  }
  String pick(bool Function(String) test) {
    for (final c in candidates) {
      if (test(c)) return c;
    }
    return '';
  }

  var ip = pick((s) => s.startsWith('192.168.'));
  if (ip.isEmpty) ip = pick((s) => s.startsWith('10.'));
  if (ip.isEmpty) ip = pick((s) => s.startsWith('172.'));
  if (ip.isEmpty && candidates.isNotEmpty) ip = candidates.first;
  return ip;
}

String _newToken() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<HostSession> startSendServer({
  required String Function() currentSnapshot,
  String Function()? currentSnapshotV2,
  required void Function(String snapshotJson) onUpload,
  required String pin,
}) async {
  final throttle = LanThrottle();
  const scope = 'pin';
  final tokens = <String>{};

  String? bearerOf(Request req) {
    final h = req.headers[_authHeader] ?? '';
    if (!h.startsWith(_authPrefix)) return null;
    final token = h.substring(_authPrefix.length).trim();
    return token.isEmpty ? null : token;
  }

  /// Null when authorized (resets throttle); otherwise the rejection.
  /// PIN failures count toward the throttle; token failures do not
  /// (128-bit tokens are unguessable Ã¢â‚¬â€ counting them would only let
  /// log-spam lock out legitimate users).
  Response? checkAuth(Request req) {
    if (req.headers[_pinHeader] == pin) {
      throttle.passed(scope);
      return null;
    }
    final token = bearerOf(req);
    if (token != null) {
      if (tokens.contains(token)) return null;
      return Response.forbidden(
        jsonEncode({'error': 'bad token'}),
        headers: _cors(),
      );
    }
    if (!throttle.allowed(scope)) {
      return Response(
        429,
        body: jsonEncode({'error': 'rate limited, retry later'}),
        headers: {
          ..._cors(),
          'Retry-After': '${throttle.remaining(scope).inSeconds + 1}',
        },
      );
    }
    throttle.failed(scope);
    return Response.forbidden(
      jsonEncode({'error': 'bad pin'}),
      headers: _cors(),
    );
  }

  final router = Router();
  router.get('/meta', (Request req) {
    final deny = checkAuth(req);
    if (deny != null) return deny;
    try {
      final m = jsonDecode(currentSnapshot()) as Map<String, dynamic>;
      return Response.ok(
        jsonEncode({'updatedAt': m['updatedAt']}),
        headers: _cors(),
      );
    } catch (_) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'bad snapshot'}),
        headers: _cors(),
      );
    }
  });
  router.get('/snapshot', (Request req) {
    final deny = checkAuth(req);
    if (deny != null) return deny;
    return Response.ok(currentSnapshot(), headers: _cors());
  });
  router.get('/snapshot-v2', (Request req) {
    final deny = checkAuth(req);
    if (deny != null) return deny;
    final v2 = currentSnapshotV2?.call();
    if (v2 == null || v2.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'no v2'}),
        headers: _cors(),
      );
    }
    return Response.ok(v2, headers: _cors());
  });
  router.post('/auth', (Request req) async {
    String body;
    try {
      body = await readCappedBody(req);
    } on BodyTooBig {
      return Response(
        413,
        body: jsonEncode({'error': 'too big'}),
        headers: _cors(),
      );
    } catch (_) {
      return Response(
        400,
        body: jsonEncode({'error': 'bad json'}),
        headers: _cors(),
      );
    }
    Map<String, dynamic> m;
    try {
      m = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return Response(
        400,
        body: jsonEncode({'error': 'bad json'}),
        headers: _cors(),
      );
    }
    if ('${m['pin'] ?? ''}' != pin) {
      if (!throttle.allowed(scope)) {
        return Response(
          429,
          body: jsonEncode({'error': 'rate limited, retry later'}),
          headers: {
            ..._cors(),
            'Retry-After': '${throttle.remaining(scope).inSeconds + 1}',
          },
        );
      }
      throttle.failed(scope);
      return Response.forbidden(
        jsonEncode({'error': 'bad pin'}),
        headers: _cors(),
      );
    }
    throttle.passed(scope);
    if (tokens.length >= _maxSessions) {
      tokens.remove(tokens.first);
    }
    final token = _newToken();
    tokens.add(token);
    return Response.ok(jsonEncode({'token': token}), headers: _cors());
  });
  router.post('/logout', (Request req) async {
    final deny = checkAuth(req);
    if (deny != null) return deny;
    try {
      final m = jsonDecode(await readCappedBody(req)) as Map<String, dynamic>;
      tokens.remove('${m['token'] ?? ''}');
    } catch (_) {
      // Idempotent: malformed logout bodies still report ok.
    }
    return Response.ok(jsonEncode({'ok': true}), headers: _cors());
  });
  router.post('/snapshot', (Request req) async {
    final deny = checkAuth(req);
    if (deny != null) return deny;
    final String body;
    try {
      body = await readCappedBody(req);
    } on BodyTooBig {
      return Response(
        413,
        body: jsonEncode({'error': 'too big'}),
        headers: _cors(),
      );
    } catch (_) {
      return Response(
        400,
        body: jsonEncode({'error': 'bad body'}),
        headers: _cors(),
      );
    }
    try {
      jsonDecode(body);
    } catch (_) {
      return Response(
        400,
        body: jsonEncode({'error': 'not json'}),
        headers: _cors(),
      );
    }
    try {
      onUpload(body);
    } catch (_) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'not applied'}),
        headers: _cors(),
      );
    }
    return Response.ok(jsonEncode({'ok': true}), headers: _cors());
  });

  final handler = const Pipeline()
      .addMiddleware(
        (inner) => (Request req) async {
          if (req.method == 'OPTIONS') {
            return Response.ok('', headers: _cors());
          }
          final res = await inner(req);
          return res.change(headers: {...res.headers, ..._cors()});
        },
      )
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
  var ip = await _lanIp();
  if (ip.isEmpty) {
    ip = server.address.address == '0.0.0.0'
        ? '127.0.0.1'
        : server.address.address;
  }
  final url = 'http://$ip:${server.port}';

  Timer? timer;
  Future<void> close() async {
    timer?.cancel();
    tokens.clear();
    try {
      await server.close(force: true);
    } catch (_) {}
  }

  timer = Timer(const Duration(minutes: 5), close);
  return HostSession(url: url, pin: pin, close: close);
}

/// 6-digit numeric PIN shown next to the QR code.
String newPin() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  return '${100000 + (ms % 900000)}';
}
