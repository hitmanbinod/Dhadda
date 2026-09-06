import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'sms_parse.dart';

/// Reads the SMS inbox through the native bridge (opt-in only).
/// Nothing leaves the device; parsed entries are saved only after
/// the user ticks them.
class SmsReader {
  static const _ch = MethodChannel('expense/sms');
  static const _idsKey = 'expense_sms_ids_v1';

  static Future<bool> ensurePermission() async {
    try {
      return await _ch.invokeMethod<bool>('ensurePermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> readInbox(
      {int limit = 100}) async {
    try {
      final raw =
          await _ch.invokeMethod<List>('readInbox', {'limit': limit});
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Set<String>> importedIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList(_idsKey) ?? []).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> markImported(Iterable<String> ids) async {
    try {
      final p = await SharedPreferences.getInstance();
      final cur = (p.getStringList(_idsKey) ?? []).toList();
      cur.addAll(ids);
      while (cur.length > 500) {
        cur.removeAt(0);
      }
      await p.setStringList(_idsKey, cur);
    } catch (_) {}
  }
}