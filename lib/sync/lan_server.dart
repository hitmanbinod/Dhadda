// Dhadda phone-hosted LAN server (Prompt 3, Phase 2).
//
// Raw dart:io HttpServer: full control over Host validation, the WS upgrade,
// gzip and security headers. No new dependency. Never logs codes/keys/proofs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'lan_crypto.dart';

/// Supplied by the app (rootBundle.load) at startup; tests inject their own.
typedef LanAssetLoader = Future<Uint8List> Function(String name);
LanAssetLoader _appAssetLoader = (name) async =>
    throw UnsupportedError('LAN asset loader not configured');

/// Called from the Flutter app entry point before hosting starts.
void configureLanAssetLoader(LanAssetLoader loader) => _appAssetLoader = loader;

/// The phone's single source of truth. Phase 3 adapts ExpenseStore to this.
abstract class LanDataStore {
  List<Map<String, dynamic>> rows();
  Future<void> applyRows(List<Map<String, dynamic>> rows);
}

class LanTrustedDevice {
  final String id;
  final String name;
  final Uint8List secret;
  final DateTime created;
  final DateTime expires;
  const LanTrustedDevice({
    required this.id,
    required this.name,
    required this.secret,
    required this.created,
    required this.expires,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'secret': LanCrypto.hex(secret),
        'created': created.toIso8601String(),
        'expires': expires.toIso8601String(),
      };

  static LanTrustedDevice fromJson(Map<String, dynamic> j) => LanTrustedDevice(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Computer'}',
        secret: LanCrypto.unhex('${j['secret'] ?? ''}'),
        created: DateTime.tryParse('${j['created'] ?? ''}') ?? DateTime.now(),
        expires: DateTime.tryParse('${j['expires'] ?? ''}') ?? DateTime.now(),
      );
}

abstract class LanTrustStore {
  LanTrustedDevice? find(String id);
  List<LanTrustedDevice> all();
  void save(LanTrustedDevice device);
  void remove(String id);
}

class MemoryTrustStore implements LanTrustStore {
  final Map<String, LanTrustedDevice> _items = {};
  @override
  LanTrustedDevice? find(String id) => _items[id];
  @override
  List<LanTrustedDevice> all() => _items.values.toList(growable: false);
  @override
  void save(LanTrustedDevice device) => _items[device.id] = device;
  @override
  void remove(String id) => _items.remove(id);
}

class MemoryLanDataStore implements LanDataStore {
  final List<Map<String, dynamic>> _rows = [];
  @override
  List<Map<String, dynamic>> rows() =>
      _rows.map((r) => Map<String, dynamic>.from(r)).toList(growable: false);
  @override
  Future<void> applyRows(List<Map<String, dynamic>> incoming) async {
    for (final r in incoming) {
      final t = '${r['t'] ?? ''}';
      final id = '${r['id'] ?? ''}';
      if (id.isEmpty) continue;
      _rows.removeWhere((x) => x['t'] == t && x['id'] == id);
      if (r['d'] != 1) _rows.add(Map<String, dynamic>.from(r));
    }
  }
}

class LanSession {
  final String sid;
  final Uint8List key;
  final String? deviceId;
  final bool trusted;
  int pcCounter = 0;
  int phoneCounter = 0;
  DateTime lastSeen = DateTime.now();
  WebSocket? socket;
  LanSession({
    required this.sid,
    required this.key,
    required this.deviceId,
    required this.trusted,
  });
}

class LanPendingPair {
  final String sid;
  final Uint8List epc;
  late final Uint8List ephone;
  late final Uint8List z;
  late final Uint8List t;
  final String name;
  final bool trust;
  final bool qr;
  final Uint8List? s;
  final DateTime expires;
  Uint8List? proofKey;
  Completer<bool>? waiter;
  bool approved = false;
  bool used = false;

  LanPendingPair({
    required this.sid,
    required this.epc,
    required this.name,
    required this.trust,
    required this.qr,
    required this.s,
    required this.expires,
  });

  bool get expired => DateTime.now().isAfter(expires);
}

class LanServerOptions {
  final int port;
  final bool allowLoopback;
  final Future<Uint8List?> Function(String name)? assetLoader;
  final Duration pairingTtl;
  final Duration idleTtl;
  final int maxSessions;
  final int maxAttempts;
  const LanServerOptions({
    this.port = 8765,
    this.allowLoopback = false,
    this.assetLoader,
    this.pairingTtl = const Duration(seconds: 120),
    this.idleTtl = const Duration(hours: 12),
    this.maxSessions = 3,
    this.maxAttempts = 5,
  });
}

class LanServer {
  final LanDataStore data;
  final LanTrustStore trust;
  final LanServerOptions options;
  final Random _random = Random.secure();

  HttpServer? _server;
  Timer? _idleTimer;
  String? _base;
  List<String> _privateIps = const [];
  final Map<String, LanPendingPair> _pending = {};
  final Map<String, LanSession> _sessions = {};
  int _failedProofs = 0;
  DateTime _failureWindow = DateTime.now();

  String? _activeCode;
  DateTime? _codeExpires;
  int _codeAttempts = 0;

  LanServer({
    required this.data,
    LanTrustStore? trust,
    this.options = const LanServerOptions(),
  }) : trust = trust ?? MemoryTrustStore();

  String? get baseUrl => _base;
  String? get activeCode => _activeCode;
  List<LanSession> get sessions => _sessions.values.toList(growable: false);
  List<LanTrustedDevice> get trusted => trust.all();
  List<LanPendingPair> get pendingQr => _pending.values
      .where((p) => p.qr && !p.expired)
      .toList(growable: false);

  /// Code-mode sessions whose typed proof passed and are awaiting Allow.
  List<Map<String, dynamic>> get pendingApprovals => _pending.values
      .where((p) => !p.qr && p.waiter != null && !p.approved)
      .map((p) => {'sid': p.sid, 'name': p.name})
      .toList(growable: false);

  /// Creates the code shown on the phone. One code at a time.
  String newCode() {
    final raw = List<int>.generate(
        8, (_) => _random.nextInt(lanCodeAlphabet.length));
    final code = raw.map((i) => lanCodeAlphabet[i]).join();
    _activeCode = code;
    _codeExpires = DateTime.now().add(options.pairingTtl);
    _codeAttempts = 0;
    _pending.removeWhere((key, p) => !p.qr);
    return code;
  }

  Future<void> start() async {
    if (_server != null) return;
    _privateIps = await _privateAddresses();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, options.port);
    _server = server;
    _base = 'http://${options.allowLoopback ? '127.0.0.1' : (_privateIps.isNotEmpty ? _privateIps.first : '127.0.0.1')}:${server.port}';
    server.listen(_handle, onError: (_) {}, cancelOnError: false);
    _idleTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sweep());
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final s = _server;
    _server = null;
    if (s != null) await s.close(force: true);
    for (final session in _sessions.values) {
      try {
        session.socket?.close();
      } catch (_) {}
    }
    _sessions.clear();
    _pending.clear();
    _activeCode = null;
    _codeExpires = null;
    _base = null;
  }

  /// Drops a live computer without revoking its trusted key.
  void disconnect(String sid) {
    final s = _sessions.remove(sid);
    try {
      s?.socket?.close();
    } catch (_) {}
  }

  void forget(String deviceId) {
    trust.remove(deviceId);
    _sessions.removeWhere((key, s) => s.deviceId == deviceId);
  }

  void forgetAll() {
    for (final d in trust.all()) {
      trust.remove(d.id);
    }
    _sessions.removeWhere((key, s) => s.trusted);
  }

  /// Phone UI: Allow on the code-mode sheet.
  void approve(String sid) {
    final p = _pending[sid];
    if (p == null) return;
    p.approved = true;
    p.waiter?.complete(true);
  }

  /// Phone UI: Deny on the code-mode sheet.
  void deny(String sid) {
    final p = _pending[sid];
    if (p == null) return;
    p.waiter?.complete(false);
  }

  /// Phone UI: scanning the computer's QR is consent; epc must match.
  void approveQr(String sid, Uint8List epc) {
    final p = _pending[sid];
    if (p == null || !p.qr || !LanCrypto.constantTimeEquals(p.epc, epc)) return;
    p.approved = true;
  }

  /// Broadcast rows changed on the phone to every connected computer.
  Future<void> notifyRowsChanged(List<Map<String, dynamic>> rows) async {
    for (final s in _sessions.values.toList(growable: false)) {
      final n = ++s.phoneCounter;
      final sealed = await LanCrypto.seal(
        key: s.key,
        nonceBytes: LanCrypto.nonce(lanDirPhoneToPc, n),
        aadBytes: LanCrypto.aad(s.sid, lanDirPhoneToPc, n),
        plaintext: utf8.encode(jsonEncode({'changed': rows})),
      );
      try {
        s.socket?.add(jsonEncode({'n': n, 'ct': LanCrypto.hex(sealed)}));
      } catch (_) {}
    }
  }

  // ---------------- plumbing ----------------

  Future<List<String>> _privateAddresses() async {
    final out = <String>[];
    try {
      final ifs = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final pref in ['192.168.', '10.', '172.']) {
        for (final i in ifs) {
          for (final a in i.addresses) {
            if (a.address.startsWith(pref) && !out.contains(a.address)) {
              out.add(a.address);
            }
          }
        }
      }
    } catch (_) {}
    return out;
  }

  bool _hostOk(HttpRequest req) {
    final host = req.headers.host;
    final port = _server?.port ?? options.port;
    if (options.allowLoopback &&
        (host == '127.0.0.1' ||
            host == 'localhost' ||
            host == '127.0.0.1:$port' ||
            host == 'localhost:$port')) {
      return true;
    }
    if (host == 'dhadda.local:$port' || host == 'dhadda.local') {
      return true;
    }
    return _privateIps.any((ip) => host == '$ip:$port');
  }

  void _headers(HttpResponse res, {bool noStore = false}) {
    res.headers.set('Content-Security-Policy',
        "default-src 'self'; connect-src 'self' ws:; img-src 'self' data:");
    res.headers.set('X-Content-Type-Options', 'nosniff');
    res.headers.set('Referrer-Policy', 'no-referrer');
    if (noStore) res.headers.set('Cache-Control', 'no-store');
  }

  void _json(HttpResponse res, int code, Object body) {
    _headers(res, noStore: true);
    res.statusCode = code;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  void _text(HttpResponse res, int code, String body) {
    _headers(res);
    res.statusCode = code;
    res.headers.contentType = ContentType.text;
    res.write(body);
  }

  Future<String> _body(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) throw const FormatException('too big');
    }
    return utf8.decode(bytes);
  }

  Map<String, dynamic> _obj(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw const FormatException('object');
    return decoded;
  }

  Uint8List _bytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  String _newSid() => 's${DateTime.now().microsecondsSinceEpoch}'
      '${_random.nextInt(1 << 30).toRadixString(16)}';

  bool _sessionCapacityOk() => _sessions.length < options.maxSessions;

  bool _proofLimitOk() {
    final now = DateTime.now();
    if (now.difference(_failureWindow) > const Duration(minutes: 1)) {
      _failureWindow = now;
      _failedProofs = 0;
    }
    return _failedProofs < 20;
  }

  void _failed() => _failedProofs++;

  Future<void> _handle(HttpRequest req) async {
    if (!_hostOk(req)) {
      _text(req.response, HttpStatus.badRequest, 'bad host');
      await req.response.close();
      return;
    }
    final path = req.uri.path;
    try {
      // Debug-only hooks used by scripts/lan-simulate.mjs. Never reachable in
      // production because allowLoopback is false there.
      if (options.allowLoopback && path == '/test/code') {
        _json(req.response, 200, {'code': _activeCode ?? newCode()});
        await req.response.close();
        return;
      }
      if (options.allowLoopback && path == '/test/approve' && req.method == 'POST') {
        final b = _obj(await _body(req));
        approve('${b['sid'] ?? ''}');
        _json(req.response, 200, {'ok': true});
        await req.response.close();
        return;
      }
      if (path == '/api/events' &&
          (req.headers.value('upgrade') ?? '').toLowerCase() == 'websocket') {
        await _websocket(req);
        return;
      }
      if (path.startsWith('/pair/') || path.startsWith('/session/')) {
        await _pairing(req, path);
        return;
      }
      if (path.startsWith('/api/')) {
        await _api(req, path);
        return;
      }
      await _static(req, path);
    } catch (e) {
      _text(req.response, HttpStatus.internalServerError,
          'Dhadda host error (${e.runtimeType}).');
      try { await req.response.close(); } catch (_) {}
    }
  }

  // ---------------- pairing ----------------

  Future<void> _pairing(HttpRequest req, String path) async {
    if (_pending.length > 32) {
      _json(req.response, 429, {'error': 'too many pairings'});
      await req.response.close();
      return;
    }
    if (path == '/pair/hello' && req.method == 'POST') {
      final b = _obj(await _body(req));
      final epc = LanCrypto.unhex('${b['epc'] ?? ''}');
      if (epc.length != 32) throw const FormatException('epc');
      final name = '${b['name'] ?? 'Computer'}';
      if (name.length > 64 || name.isEmpty) throw const FormatException('name');
      final qr = '${b['mode'] ?? ''}' == 'qr';
      final seed = _bytes(32);
      final ephone = await LanCrypto.x25519Public(seed);
      final sid = _newSid();
      final p = LanPendingPair(
        sid: sid,
        epc: epc,
        name: name,
        trust: b['trust'] == true,
        qr: qr,
        s: qr ? _bytes(16) : null,
        expires: DateTime.now().add(options.pairingTtl),
      );
      p.ephone = ephone;
      p.z = await LanCrypto.x25519Shared(seed, epc);
      p.t = await LanCrypto.transcript(epc, ephone, sid);
      _pending[sid] = p;
      _json(req.response, 200, {
        'sid': sid,
        'ephone': LanCrypto.hex(ephone),
        if (qr) 's': LanCrypto.hex(p.s!),
      });
      await req.response.close();
      return;
    }
    if (path == '/pair/confirm' && req.method == 'POST') {
      if (!_proofLimitOk()) {
        _json(req.response, 429, {'error': 'slow down'});
        await req.response.close();
        return;
      }
      final b = _obj(await _body(req));
      final sid = '${b['sid'] ?? ''}';
      final p = _pending[sid];
      if (p == null || p.qr || _activeCode == null) {
        _json(req.response, 404, {'error': 'pair again'});
        await req.response.close();
        return;
      }
      if (_codeExpires == null || DateTime.now().isAfter(_codeExpires!)) {
        _json(req.response, 410, {'error': 'code expired'});
        await req.response.close();
        return;
      }
      if (_codeAttempts >= options.maxAttempts) {
        _json(req.response, 429, {'error': 'too many attempts'});
        await req.response.close();
        return;
      }
      final key = await LanCrypto.codeKey(_activeCode!, p.t);
      final expected = await LanCrypto.proof(key, 'pc', p.t);
      if (!LanCrypto.constantTimeEquals(
          expected, LanCrypto.unhex('${b['proof'] ?? ''}'))) {
        _codeAttempts++;
        _failed();
        _json(req.response, 403, {
          'error': 'wrong code',
          'attempts_left': options.maxAttempts - _codeAttempts,
        });
        await req.response.close();
        return;
      }
      if (p.used) {
        _json(req.response, 409, {'error': 'already used'});
        await req.response.close();
        return;
      }
      p.used = true; // consume before the Allow sheet (flaw F10)
      p.proofKey = key;
      final waiter = Completer<bool>();
      p.waiter = waiter;
      // The UI may approve before PBKDF2 has finished and the waiter exists.
      if (p.approved) waiter.complete(true);
      final allowed = await waiter.future.timeout(
        const Duration(seconds: 120), onTimeout: () => false);
      if (!allowed) {
        _pending.remove(sid);
        _activeCode = null;
        _json(req.response, 403, {'error': 'denied'});
        await req.response.close();
        return;
      }
      if (!_sessionCapacityOk()) {
        _json(req.response, 429, {'error': 'too many computers'});
        await req.response.close();
        return;
      }
      _activeCode = null; // works once
      _json(req.response, 200, await _finishPairing(p));
      await req.response.close();
      return;
    }
    if (path == '/pair/poll' && req.method == 'GET') {
      final sid = req.uri.queryParameters['sid'] ?? '';
      final epc = LanCrypto.unhex(req.uri.queryParameters['epc'] ?? '');
      final p = _pending[sid];
      if (p == null || !p.qr || !LanCrypto.constantTimeEquals(p.epc, epc)) {
        _json(req.response, 404, {'error': 'pair again'});
        await req.response.close();
        return;
      }
      if (p.expired) {
        _json(req.response, 410, {'error': 'code expired'});
        await req.response.close();
        return;
      }
      if (!p.approved) {
        _json(req.response, 202, {'status': 'waiting'});
        await req.response.close();
        return;
      }
      if (!_sessionCapacityOk()) {
        _json(req.response, 429, {'error': 'too many computers'});
        await req.response.close();
        return;
      }
      _json(req.response, 200, await _finishPairing(p));
      await req.response.close();
      return;
    }
    if (path == '/session/hello' && req.method == 'POST') {
      final b = _obj(await _body(req));
      final deviceId = '${b['device_id'] ?? ''}';
      final epc = LanCrypto.unhex('${b['epc'] ?? ''}');
      final device = trust.find(deviceId);
      if (device == null || epc.length != 32 ||
          DateTime.now().isAfter(device.expires)) {
        _json(req.response, 403, {'error': 'pair again'});
        await req.response.close();
        return;
      }
      final seed = _bytes(32);
      final ephone = await LanCrypto.x25519Public(seed);
      final nonce = _bytes(16);
      final p = LanPendingPair(
        sid: deviceId,
        epc: epc,
        name: device.name,
        trust: true,
        qr: false,
        s: nonce,
        expires: DateTime.now().add(options.pairingTtl),
      );
      p.ephone = ephone;
      p.z = await LanCrypto.x25519Shared(seed, epc);
      p.t = await LanCrypto.trustedTranscript(epc, ephone, nonce);
      p.proofKey = device.secret;
      _pending[deviceId] = p;
      _json(req.response, 200, {
        'ephone': LanCrypto.hex(ephone),
        'nonce': LanCrypto.hex(nonce),
      });
      await req.response.close();
      return;
    }
    if (path == '/session/confirm' && req.method == 'POST') {
      if (!_proofLimitOk()) {
        _json(req.response, 429, {'error': 'slow down'});
        await req.response.close();
        return;
      }
      final b = _obj(await _body(req));
      final deviceId = '${b['device_id'] ?? ''}';
      final p = _pending[deviceId];
      final device = trust.find(deviceId);
      if (p == null || device == null ||
          DateTime.now().isAfter(device.expires)) {
        trust.remove(deviceId);
        _json(req.response, 403, {'error': 'pair again'});
        await req.response.close();
        return;
      }
      final expected =
          await LanCrypto.proof(device.secret, 'pc', p.t, p.s!);
      if (!LanCrypto.constantTimeEquals(
          expected, LanCrypto.unhex('${b['proof_pc'] ?? ''}'))) {
        _failed();
        _json(req.response, 403, {'error': 'wrong proof'});
        await req.response.close();
        return;
      }
      if (!_sessionCapacityOk()) {
        _json(req.response, 429, {'error': 'too many computers'});
        await req.response.close();
        return;
      }
      final proofPhone =
          await LanCrypto.proof(device.secret, 'phone', p.t, p.s!);
      final k = await LanCrypto.trustedSessionKey(p.z, p.t, device.secret);
      _sessions[deviceId] = LanSession(
        sid: deviceId,
        key: k,
        deviceId: deviceId,
        trusted: true,
      );
      _pending.remove(deviceId);
      _json(req.response, 200, {'proof_phone': LanCrypto.hex(proofPhone)});
      await req.response.close();
      return;
    }
    _json(req.response, 404, {'error': 'not found'});
    await req.response.close();
  }

  Future<Map<String, dynamic>> _finishPairing(LanPendingPair p) async {
    final key = p.proofKey ?? await LanCrypto.qrKey(p.s!, p.t);
    final proof = await LanCrypto.proof(key, 'phone', p.t);
    final k = await LanCrypto.sessionKey(p.z, p.t);
    final session = LanSession(sid: p.sid, key: k, deviceId: null, trusted: false);
    _sessions[p.sid] = session;
    _pending.remove(p.sid);
    final result = <String, dynamic>{
      'sid': p.sid,
      'proof_phone': LanCrypto.hex(proof),
    };
    if (p.trust) {
      final deviceId = 'dev-${LanCrypto.hex(_bytes(8))}';
      final secret = _bytes(32);
      final expires = DateTime.now().add(const Duration(days: 30));
      trust.save(LanTrustedDevice(
        id: deviceId,
        name: p.name,
        secret: secret,
        created: DateTime.now(),
        expires: expires,
      ));
      result['secret'] = await _encrypt(session, lanDirPhoneToPc, {
        'device_id': deviceId,
        'device_secret': LanCrypto.hex(secret),
        'expires': expires.toIso8601String(),
      });
    }
    return result;
  }

  // ---------------- encrypted API ----------------

  Future<_Opened> _open(String raw) async {
    final b = _obj(raw);
    final sid = '${b['sid'] ?? ''}';
    final s = _sessions[sid];
    if (s == null) throw const FormatException('session');
    final n = (b['n'] as num?)?.toInt() ?? -1;
    if (n <= s.pcCounter) throw const FormatException('replay');
    final plain = await LanCrypto.open(
      key: s.key,
      nonceBytes: LanCrypto.nonce(lanDirPcToPhone, n),
      aadBytes: LanCrypto.aad(sid, lanDirPcToPhone, n),
      sealed: LanCrypto.unhex('${b['ct'] ?? ''}'),
    );
    s.pcCounter = n;
    s.lastSeen = DateTime.now();
    return _Opened(s, _obj(utf8.decode(plain)));
  }

  Future<Map<String, dynamic>> _encrypt(
      LanSession s, int direction, Object payload) async {
    final n = direction == lanDirPhoneToPc ? ++s.phoneCounter : s.pcCounter;
    final sealed = await LanCrypto.seal(
      key: s.key,
      nonceBytes: LanCrypto.nonce(direction, n),
      aadBytes: LanCrypto.aad(s.sid, direction, n),
      plaintext: utf8.encode(jsonEncode(payload)),
    );
    return {'n': n, 'ct': LanCrypto.hex(sealed)};
  }

  Future<void> _api(HttpRequest req, String path) async {
    final raw = await _body(req);
    if (req.method != 'POST') {
      _json(req.response, 405, {'error': 'method'});
      await req.response.close();
      return;
    }
    if (path == '/api/snapshot') {
      try {
        final opened = await _open(raw);
        _json(req.response, 200,
            await _encrypt(opened.session, lanDirPhoneToPc, {'rows': data.rows()}));
      } on FormatException catch (_) {
        _json(req.response, 403, {'error': 'bad frame'});
      }
      await req.response.close();
      return;
    }
    if (path == '/api/push') {
      try {
        final opened = await _open(raw);
        final rows = (opened.body['rows'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        // Apply LWW through the repository path; the adapter performs the
        // same `(ua, device_id)` resolution as CloudSync.resolveWinner.
        final accepted = _resolve(rows, data.rows());
        await data.applyRows(accepted);
        _json(req.response, 200,
            await _encrypt(opened.session, lanDirPhoneToPc, {'ok': true}));
        await notifyRowsChanged(accepted);
      } on FormatException catch (_) {
        _json(req.response, 403, {'error': 'bad frame'});
      }
      await req.response.close();
      return;
    }
    _json(req.response, 404, {'error': 'not found'});
    await req.response.close();
  }

  /// Larger `ua` wins; ties by lexicographically larger `device_id`.
  List<Map<String, dynamic>> _resolve(
    List<Map<String, dynamic>> incoming,
    List<Map<String, dynamic>> current,
  ) {
    final winners = <String, Map<String, dynamic>>{};
    for (final r in [...current, ...incoming]) {
      final key = '${r['t']}/${r['id']}';
      final prev = winners[key];
      if (prev == null) {
        winners[key] = r;
        continue;
      }
      final a = (r['ua'] as num?)?.toInt() ?? 0;
      final b = (prev['ua'] as num?)?.toInt() ?? 0;
      if (a > b ||
          (a == b &&
              '${r['device_id'] ?? ''}'.compareTo('${prev['device_id'] ?? ''}') >
                  0)) {
        winners[key] = r;
      }
    }
    return winners.values.toList(growable: false);
  }

  // ---------------- websocket ----------------

  Future<void> _websocket(HttpRequest req) async {
    final sid = req.uri.queryParameters['sid'] ?? '';
    final session = _sessions[sid];
    if (session == null) {
      _text(req.response, 403, 'session');
      await req.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(req);
    session.socket = socket;
    socket.listen((message) {
      try {
        final b = jsonDecode('$message') as Map<String, dynamic>;
        final n = (b['n'] as num?)?.toInt() ?? -1;
        if (n <= session.pcCounter) throw const FormatException('replay');
        unawaited(LanCrypto.open(
          key: session.key,
          nonceBytes: LanCrypto.nonce(lanDirPcToPhone, n),
          aadBytes: LanCrypto.aad(sid, lanDirPcToPhone, n),
          sealed: LanCrypto.unhex('${b['ct'] ?? ''}'),
        ).then((_) {
          session.pcCounter = n;
          session.lastSeen = DateTime.now();
        }));
      } catch (_) {
        socket.close(1008, 'bad frame');
      }
    }, onDone: () {
      if (session.socket == socket) session.socket = null;
    }, onError: (_) {});
  }

  void _sweep() {
    final cutoff = DateTime.now().subtract(options.idleTtl);
    _sessions.removeWhere((sid, s) {
      if (s.lastSeen.isAfter(cutoff)) return false;
      try { s.socket?.close(); } catch (_) {}
      return true;
    });
    _pending.removeWhere((key, p) => p.expired);
  }

  // ---------------- static files ----------------

  static const _mime = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.webmanifest': 'application/manifest+json',
    '.md': 'text/plain; charset=utf-8',
  };

  Future<void> _static(HttpRequest req, String path) async {
    var name = path == '/' ? 'index.html' : path.replaceFirst(RegExp(r'^/'), '');
    if (name.endsWith('/')) name += 'index.html';
    final loader = options.assetLoader ?? _defaultAssetLoader;
    var bytes = await loader('webapp/$name');
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    bytes ??= await loader('webapp/index.html'); // SPA fallback; ext stays .html
    if (bytes == null) {
      _text(req.response, 404, 'app not bundled in this build');
      await req.response.close();
      return;
    }
    _headers(req.response);
    req.response.headers.contentType =
        ContentType.parse(_mime[ext] ?? 'application/octet-stream');
    final compressible = const ['.html', '.js', '.css', '.json', '.svg', '.md']
        .contains(ext);
    final gzipOk = (req.headers.value('accept-encoding') ?? '')
        .toLowerCase()
        .contains('gzip');
    if (compressible && gzipOk && bytes.length > 512) {
      req.response.headers.set('Content-Encoding', 'gzip');
      req.response.add(gzip.encode(bytes));
    } else {
      req.response.add(bytes);
    }
    await req.response.close();
  }

  Future<Uint8List?> _defaultAssetLoader(String name) async {
    try {
      return await _appAssetLoader(name);
    } catch (_) {
      return null;
    }
  }
}

class _Opened {
  final LanSession session;
  final Map<String, dynamic> body;
  const _Opened(this.session, this.body);
}

