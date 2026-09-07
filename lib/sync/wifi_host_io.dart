import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// A short-lived LAN server hosting this device's snapshot.
/// The receiver fetches GET /meta, then GET /snapshot (pull) or
/// POST /snapshot (push its newer snapshot). Guarded by a 6-digit PIN
/// header. Auto-closes after 5 minutes.
///
/// Phase 4: v2-capable senders also serve GET /snapshot-v2 (record-level
/// state). Old receivers never call it; new receivers fall back to
/// /snapshot when it 404s. POST /snapshot accepts either encoding; the
/// receiver only POSTs v2 to senders that proved v2-capable, so old
/// senders (whose whole-replace import would misread v2) never see it.
class HostSession {
  final String url;
  final String pin;
  final Future<void> Function() close;
  HostSession({required this.url, required this.pin, required this.close});
}

const _pinHeader = 'x-sync-pin';

Map<String, String> _cors() => {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, $_pinHeader',
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

Future<HostSession> startSendServer({
  required String Function() currentSnapshot,
  String Function()? currentSnapshotV2,
  required void Function(String snapshotJson) onUpload,
  required String pin,
}) async {
  bool authed(Request req) => req.headers[_pinHeader] == pin;

  final router = Router();
  router.get('/meta', (Request req) {
    if (!authed(req)) {
      return Response.forbidden(
        jsonEncode({'error': 'bad pin'}),
        headers: _cors(),
      );
    }
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
    if (!authed(req)) {
      return Response.forbidden(
        jsonEncode({'error': 'bad pin'}),
        headers: _cors(),
      );
    }
    return Response.ok(currentSnapshot(), headers: _cors());
  });
  router.get('/snapshot-v2', (Request req) {
    if (!authed(req)) {
      return Response.forbidden(
        jsonEncode({'error': 'bad pin'}),
        headers: _cors(),
      );
    }
    final v2 = currentSnapshotV2?.call();
    if (v2 == null || v2.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'no v2'}),
        headers: _cors(),
      );
    }
    return Response.ok(v2, headers: _cors());
  });
  router.post('/snapshot', (Request req) async {
    if (!authed(req)) {
      return Response.forbidden(
        jsonEncode({'error': 'bad pin'}),
        headers: _cors(),
      );
    }
    final body = await req.readAsString();
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
