// Owning controller for phone-hosted LAN sync. Survives screen navigation and
// is the seam Phase 7's foreground service will talk to.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../store.dart';
import 'lan_foreground.dart';
import 'lan_persistence.dart';
import 'permissions.dart';
import 'lan_server.dart';
import 'lan_store_adapter.dart';

/// Shared controller: one phone-hosted server per app process.
final LanHostController lanHost = LanHostController();

class LanHostController extends ChangeNotifier {
  LanServer? _server;
  ExpenseStore? _store;
  PrefsLanTrustStore? _trust;
  String? _code;
  DateTime? _codeAt;
  bool _starting = false;
  String _networkName = '';
  bool _hasAddress = false;
  Timer? _connectionTimer;
  bool _foregroundStarted = false;

  bool get running => _server != null;
  bool get starting => _starting;
  String? get url => _server?.baseUrl;
  String? get code => _code;
  DateTime? get codeAt => _codeAt;
  String get networkName => _networkName;
  bool get hasAddress => _hasAddress;
  List<LanSession> get sessions => _server?.sessions ?? const [];
  List<Map<String, dynamic>> get pendingApprovals =>
      _server?.pendingApprovals ?? const [];
  List<LanTrustedDevice> get trusted => _trust?.all() ?? const [];

  Future<void> prepare() async {
    final trust = PrefsLanTrustStore();
    await trust.load();
    _trust = trust;
    await _refreshNetwork();
    notifyListeners();
  }

  Future<void> _refreshNetwork() async {
    try {
      final ifs = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 2));
      var found = false;
      var name = '';
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (a.address.startsWith('192.168.') ||
              a.address.startsWith('10.') ||
              a.address.startsWith('172.')) {
            found = true;
            name = i.name;
            break;
          }
        }
        if (found) break;
      }
      _hasAddress = found;
      _networkName = name;
    } catch (_) {
      _hasAddress = false;
      _networkName = '';
    }
  }

  Future<void> refreshNetwork() async {
    await _refreshNetwork();
    notifyListeners();
  }

  Future<void> start(ExpenseStore store, {int port = 8765}) async {
    if (_server != null || _starting) return;
    _starting = true;
    notifyListeners();
    try {
      _store = store;
      configureLanAssetLoader((name) async {
        final data = await rootBundle.load(name);
        return data.buffer.asUint8List(
            data.offsetInBytes, data.lengthInBytes);
      });
      await prepare();
      final server = LanServer(
        data: ExpenseLanDataStore(store),
        trust: _trust,
        options: LanServerOptions(port: port, allowLoopback: port == 0),
      );
      await server.start();
      _server = server;
      _code = server.newCode();
      _codeAt = DateTime.now();
      await _refreshNetwork();
      // Phone edits reach the computer within a second.
      store.addListener(_onStoreChanged);
      // Phase 7: keep the process alive while serving. Never required for the
      // app-open version; failures simply leave the foreground server running.
      if (port != 0) {
        await Permissions.ensureNotifications();
        LanForeground.onStopRequested(() => stop());
        _foregroundStarted = await LanForeground.start();
        _connectionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          LanForeground.updateConnected(sessions.isNotEmpty);
        });
        await LanForeground.updateConnected(false);
      }
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  void _onStoreChanged() {
    final server = _server;
    if (server == null || (store?.cloudApplying ?? false)) return;
    server.notifyRowsChanged(ExpenseLanDataStore(store!).rows());
  }

  Future<void> stop() async {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    if (_foregroundStarted) {
      _foregroundStarted = false;
      await LanForeground.stop();
    }
    final store = _store;
    if (store != null) {
      try {
        store.removeListener(_onStoreChanged);
      } catch (_) {}
    }
    final server = _server;
    _server = null;
    _code = null;
    _codeAt = null;
    _store = null;
    await server?.stop();
    notifyListeners();
  }

  String newCode() {
    final code = _server?.newCode() ?? '';
    _code = code.isEmpty ? null : code;
    _codeAt = code.isEmpty ? null : DateTime.now();
    notifyListeners();
    return code;
  }

  void disconnect(String sid) {
    _server?.disconnect(sid);
    notifyListeners();
  }

  void approve(String sid) => _server?.approve(sid);
  void deny(String sid) => _server?.deny(sid);
  void approveQr(String sid, List<int> epc) =>
      _server?.approveQr(sid, Uint8List.fromList(epc));

  Future<void> forget(String deviceId) async {
    _server?.forget(deviceId);
    _trust?.remove(deviceId);
    notifyListeners();
  }

  Future<void> forgetAll() async {
    _server?.forgetAll();
    for (final d in [...?_trust?.all()]) {
      _trust?.remove(d.id);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  ExpenseStore? get store => _store;
}
