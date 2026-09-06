import 'package:flutter/services.dart';

/// Result of an mDNS registration attempt.
class MdnsResult {
  final bool ok;
  final String name;
  const MdnsResult({required this.ok, required this.name});
}

/// Tiny bridge to the Android mDNS advertiser (NsdManager).
/// Everything is best-effort: any failure returns ok=false and the
/// caller falls back to plain IP access. Safe to call on any
/// platform (non-Android just fails the channel call).
class Mdns {
  static const MethodChannel _ch = MethodChannel('expense/mdns');

  /// Advertise `name.local` (+ DNS-SD record) for [port].
  /// Returns which name actually stuck (may differ on conflict).
  static Future<MdnsResult> register({
    String name = 'dhadda',
    required int port,
  }) async {
    try {
      final raw = await _ch.invokeMethod<Map>('register', {
        'name': name,
        'type': '_http._tcp.',
        'port': port,
      });
      final m =
          raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
      return MdnsResult(
          ok: m['ok'] == true, name: '${m['name'] ?? name}');
    } catch (_) {
      return MdnsResult(ok: false, name: name);
    }
  }

  /// Withdraw the advertisement. Never throws.
  static Future<void> unregister() async {
    try {
      await _ch.invokeMethod('unregister');
    } catch (_) {}
  }
}