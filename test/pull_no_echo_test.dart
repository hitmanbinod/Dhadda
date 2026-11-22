import 'dart:convert';

import 'package:expense/data/prefs_domain_store.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('applied cloud rows never echo to the outbox and are idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = PrefsDomainStore(prefs);
    final store = ExpenseStore(domainOverride: backend);
    await store.load();

    // Pair locally; attach the hook exactly as the app does.
    await prefs.setString('expense_cloud_vault_v1', 'v-test');
    await prefs.setString('expense_cloud_token_v1', 't-test');
    await prefs.setString('expense_cloud_key_v1', base64.encode(List<int>.filled(32, 1)));
    final cloud = CloudSync(store, workerUrl: 'http://127.0.0.1:1');
    await cloud.load();
    cloud.attach();

    final cat = store.categories.first;
    final rows = <Map<String, dynamic>>[
      {'t': 'categories', 'id': cat.id, 'd': 0, 'data': cat.toJson()},
      {
        't': 'entries',
        'id': 'cloud-e1',
        'd': 0,
        'data': {
          'id': 'cloud-e1',
          'type': 'expense',
          'amount': 123.0,
          'categoryId': cat.id,
          'date': DateTime(2026, 11, 22).millisecondsSinceEpoch,
          'note': 'from cloud',
          'mode': 'cash',
          'projectId': '',
        },
      },
      {'t': 'settings', 'id': 'userName', 'd': 0, 'data': {'value': 'Cloud User'}},
    ];

    String outbox() => prefs.getString('expense_cloud_outbox_v1') ?? '[]';
    expect(jsonDecode(outbox()) as List, isEmpty, reason: 'outbox starts empty');

    await store.applyCloudRows(rows);
    expect(jsonDecode(outbox()) as List, isEmpty,
        reason: 'applying pulled rows must not enqueue anything');

    String fingerprint() => jsonEncode({
          'txns': [for (final t in store.transactions) t.id],
          'cats': [for (final c in store.categories) c.id],
          'name': store.userName,
          'amount': store.transactions
              .where((t) => t.id == 'cloud-e1')
              .fold<double>(0, (s, t) => s + t.amount),
        });
    final first = fingerprint();

    await store.applyCloudRows(rows);
    expect(fingerprint(), first, reason: 'applying the same pull twice changed state');
    expect(jsonDecode(outbox()) as List, isEmpty,
        reason: 'second apply must not echo either');

    cloud.dispose();
  });
}
