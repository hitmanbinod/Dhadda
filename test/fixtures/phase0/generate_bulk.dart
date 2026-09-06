// Phase 0 bulk-fixture generator. Pure Dart (dart:convert + dart:math +
// dart:io only) so it runs with plain `dart`, no Flutter needed:
//   dart test/fixtures/phase0/generate_bulk.dart
// Deterministic: fixed seed, fixed timestamps. Writes snapshot_bulk.json
// (300 transactions) next to itself.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() {
  final rand = Random(42);
  const cats = [
    'food',
    'travel',
    'fuel',
    'rent',
    'shopping',
    'bills',
    'health',
    'other'
  ];
  const modes = ['cash', 'bank', 'card', 'ewallet'];
  const base = 1785542400000; // 2026-08-01T00:00:00Z
  const day = 86400000;
  final txns = <Map<String, dynamic>>[];
  for (var i = 0; i < 300; i++) {
    txns.add({
      'id': 'bulk-txn-${i.toString().padLeft(4, '0')}',
      'type': i % 10 == 0 ? 'income' : 'expense',
      'amount':
          double.parse((10 + rand.nextDouble() * 5000).toStringAsFixed(2)),
      'categoryId': cats[i % cats.length],
      'date': base + i * day,
      'note': 'bulk note $i',
      'mode': modes[i % modes.length],
      'projectId': '',
    });
  }
  final doc = {
    'version': 1,
    'updatedAt': '2026-09-06T12:00:00.000Z',
    'deviceId': 'phase0-device-bulk',
    'deviceName': 'Phase0Bulk',
    'categories': [
      for (final c in cats)
        {'id': c, 'name': c, 'icon': 0, 'color': 4284513675, 'budget': 0},
    ],
    'transactions': txns,
    'loans': [],
    'projects': [],
  };
  final out =
      File('${Platform.script.resolve('.').toFilePath()}snapshot_bulk.json');
  out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(doc));
  // ignore: avoid_print
  print('wrote ${out.path} (${txns.length} transactions)');
}
