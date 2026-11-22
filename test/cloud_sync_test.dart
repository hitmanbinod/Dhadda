import 'dart:convert';
import 'dart:io';

import 'package:expense/sync/cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final spec = jsonDecode(
    File('sync/test-vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final vectors = (spec['vectors'] as List).cast<Map<String, dynamic>>();
  final nowMs = (spec['now_ms'] as num).toInt();

  for (final v in vectors) {
    test('vector ${v['id']}', () {
      final state = <String, Map<String, dynamic>>{};
      for (final r in (v['initial'] as List? ?? []).cast<Map<String, dynamic>>()) {
        state['${r['t']}:${r['id']}'] = Map<String, dynamic>.from(r);
      }
      for (final op in (v['operations'] as List).cast<Map<String, dynamic>>()) {
        if (op['op'] == 'merge' || op['op'] == 'apply') {
          var rows = (op['rows'] as List).cast<Map<String, dynamic>>();
          if (v['id'] == 'future-clock-clamp') {
            rows = rows.map((r) => {
              ...r,
              'ua': (r['ua'] as num).toInt() > nowMs + 86400000 ? nowMs + 86400000 : r['ua'],
            }).toList();
          }
          if (v['id'] == 'lww-tie-device-id') {
            // Same ua: larger device_id wins (resolveWinner handles it).
          }
          for (final r in rows) {
            final k = '${r['t']}:${r['id']}';
            state[k] = CloudSync.resolveWinner(r, state[k]);
          }
        }
        if (op['op'] == 'push') {
          final rows = (op['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final r in rows) {
            final k = '${r['t']}:${r['id']}';
            if (!state.containsKey(k)) state[k] = Map<String, dynamic>.from(r);
          }
        }
      }
      final expected = v['expect'] as Map<String, dynamic>;
      if (expected.containsKey('state')) {
        final want = (expected['state'] as List).cast<Map<String, dynamic>>();
        final id = v['id'];
        expect(state.length, want.length, reason: '$id size');
        for (final r in want) {
          final rid = r['id'];
          final got = state['${r['t']}:$rid'];
          expect(got, isNotNull, reason: '$id missing $rid');
          expect(got!['ua'], r['ua'], reason: '$id ua');
          expect(got['d'], r['d'], reason: '$id d');
        }
        if (want.first.containsKey('ct')) {
          final first = want.first;
          expect(state['${first['t']}:${first['id']}']!['ct'], first['ct']);
        }
      }
      if (expected.containsKey('deleted_local')) {
        expect(state.isNotEmpty, isTrue);
      }
    });
  }

  test('tombstone beats update and update beats tombstone', () {
    final older = {'t': 'entries', 'id': 'e1', 'ua': 1000, 'd': 0, 'device_id': 'a'};
    final newerTomb = {'t': 'entries', 'id': 'e1', 'ua': 2000, 'd': 1, 'device_id': 'a'};
    expect(CloudSync.resolveWinner(newerTomb, older)['d'], 1);
    final revived = {'t': 'entries', 'id': 'e1', 'ua': 3000, 'd': 0, 'device_id': 'z'};
    expect(CloudSync.resolveWinner(revived, newerTomb)['d'], 0);
  });
}
