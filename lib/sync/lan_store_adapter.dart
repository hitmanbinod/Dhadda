// Adapts the real ExpenseStore to the LAN server's row interface.
// Reuses the existing v2 record protocol (rev/by/tombstones) and the store's
// repository merge path, so validation and derived totals stay consistent.
import 'dart:convert';

import '../home_layout.dart';
import '../store.dart';
import 'lan_server.dart';
import 'sync_v2.dart';

class ExpenseLanDataStore implements LanDataStore {
  final ExpenseStore store;
  ExpenseLanDataStore(this.store);

  @override
  List<Map<String, dynamic>> rows() {
    final decoded = jsonDecode(store.exportSnapshotV2());
    final list = (decoded['records'] as List? ?? const []);
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      final type = '${e['t'] ?? ''}';
      final id = '${e['id'] ?? ''}';
      if (type.isEmpty || id.isEmpty) continue;
      final row = <String, dynamic>{
        't': type,
        'id': id,
        'ua': e['rev'] ?? 0,
        'device_id': '${e['by'] ?? ''}',
        'd': e['dead'] == true ? 1 : 0,
        'data': e['d'] is Map<String, dynamic> ? e['d'] : <String, dynamic>{},
      };
      final parent = '${e['parent'] ?? ''}';
      if (parent.isNotEmpty) row['parent'] = parent;
      out.add(row);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in {
      'userName': store.userName,
      'currency': store.currency,
      'calendarSystem': store.calendarSystem,
      'homeLayout': encodeHomeLayout(store.homeLayout),
    }.entries) {
      out.add({
        't': 'settings',
        'id': entry.key,
        'ua': now,
        'device_id': store.deviceId,
        'd': 0,
        'data': {'value': entry.value},
      });
    }
    return out;
  }

  @override
  Future<void> applyRows(List<Map<String, dynamic>> incoming) async {
    if (incoming.isEmpty) return;
    final settings = incoming.where((r) => r['t'] == 'settings').toList();
    if (settings.isNotEmpty) await store.applyCloudRows(settings);
    final records = <SyncRecord>[];
    for (final r in incoming) {
      final type = '${r['t'] ?? ''}';
      final id = '${r['id'] ?? ''}';
      if (!SyncType.known.contains(type) || id.isEmpty) continue;
      records.add(SyncRecord(
        type: type,
        id: id,
        rev: (r['ua'] as num?)?.toInt() ?? 0,
        by: '${r['device_id'] ?? ''}',
        dead: r['d'] == 1,
        parent: '${r['parent'] ?? ''}',
        data: r['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(r['data'] as Map)
            : null,
      ));
    }
    if (records.isEmpty) return;
    final envelope = V2Snapshot(
      deviceId: 'lan-computer',
      deviceName: 'Computer',
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      records: records,
    ).encode();
    await store.ingestPeerSnapshot(envelope, peerName: 'Computer');
  }
}
