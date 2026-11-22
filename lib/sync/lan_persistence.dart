// App-private persistence for trusted computers (Prompt 3).
// Only {id, name, secret, created, expires} is stored - never expense data.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'lan_server.dart';

const String kLanTrustedKey = 'expense_lan_trusted_v1';

class PrefsLanTrustStore implements LanTrustStore {
  final Map<String, LanTrustedDevice> _items = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kLanTrustedKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final d = LanTrustedDevice.fromJson(e);
        if (d.id.isNotEmpty && d.secret.length == 32) _items[d.id] = d;
      }
    } catch (_) {
      // Corrupt trust data is dropped; the phone's expense data is untouched.
    }
  }

  Future<void> _flush() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLanTrustedKey,
        jsonEncode(_items.values.map((d) => d.toJson()).toList()));
  }

  @override
  LanTrustedDevice? find(String id) => _items[id];

  @override
  List<LanTrustedDevice> all() => _items.values.toList(growable: false);

  @override
  void save(LanTrustedDevice device) {
    _items[device.id] = device;
    unawaitedFlush();
  }

  @override
  void remove(String id) {
    _items.remove(id);
    unawaitedFlush();
  }

  void unawaitedFlush() {
    _flush().catchError((_) {});
  }
}
