import 'dart:convert';
import 'dart:io';

import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/file_sync.dart';
import 'package:expense/sync/sync_v2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 3: additive payloads are ignored by old readers and preserve all
/// existing data in both directions.
void main() {
  Future<ExpenseStore> ready() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    return store;
  }

  test('v1 snapshot with no accounts imports with deterministic defaults', () async {
    final raw = File('test/fixtures/phase0/snapshot_populated.json')
        .readAsStringSync();
    final old = Snapshot.decode(raw);
    final store = await ready();
    final msg = await store.importSnapshotString(raw, force: true);
    expect(msg, isNot(contains('failed')));
    expect(store.transactions.length, old.transactions.length);
    expect(
      store.transactions.fold<double>(0, (s, t) => s + t.amount),
      old.transactions.fold<double>(0, (s, t) => s + t.amount),
    );
    expect(store.accounts.map((a) => a.id).toList(), [
      'acct_cash',
      'acct_bank',
      'acct_card',
      'acct_ewallet',
    ]);
    for (final t in store.transactions) {
      expect(t.mode, old.transactions.firstWhere((x) => x.id == t.id).mode);
      expect(t.effectiveAccountId, accountIdForMode(t.mode));
    }
  });

  test('new v1 snapshot round-trips accounts and account ids', () async {
    final store = await ready();
    final id = await store.addAccount('Nabil', 'bank');
    await store.addTransaction(
      type: 'expense',
      amount: 42,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      accountId: id,
    );
    final raw = store.exportJson();
    final decoded = Snapshot.decode(raw);
    expect(decoded.accounts.any((a) => a.name == 'Nabil'), isTrue);
    expect(decoded.transactions.first.accountId, id);

    // An old app ignores unknown keys: stripping them must not drop records.
    final map = jsonDecode(raw) as Map<String, dynamic>;
    map.remove('accounts');
    for (final t in map['transactions'] as List) {
      (t as Map).remove('accountId');
    }
    final oldShaped = Snapshot.fromJson(map);
    expect(oldShaped.accounts, isEmpty);
    expect(oldShaped.transactions.length, decoded.transactions.length);
    expect(oldShaped.transactions.first.mode, decoded.transactions.first.mode);
  });

  test('v2 export carries acct records; old peers skip unknown types', () async {
    final store = await ready();
    await store.addTransaction(
      type: 'expense',
      amount: 15,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      accountId: 'acct_card',
    );
    final v2 = V2Snapshot.tryDecode(store.exportSnapshotV2());
    expect(v2, isNotNull);
    expect(v2!.records.any((r) => r.type == SyncType.acct), isTrue);
    final txn = v2.records.firstWhere((r) => r.type == SyncType.txn);
    expect(txn.data!.containsKey('accountId'), isTrue);

    // Simulate an old decoder: only the six original known types are kept.
    final oldKnown = {
      SyncType.txn,
      SyncType.cat,
      SyncType.proj,
      SyncType.loan,
      SyncType.topup,
      SyncType.repay,
    };
    final kept = v2.records.where((r) => oldKnown.contains(r.type)).toList();
    expect(kept.length, lessThan(v2.records.length));
    expect(kept.any((r) => r.type == SyncType.acct), isFalse);
    // Old peers still understand every txn record in the payload.
    expect(kept.where((r) => r.type == SyncType.txn).length,
        v2.records.where((r) => r.type == SyncType.txn).length);
  });

  test('v1 -> v2 conversion includes accounts and account ids', () async {
    final raw = File('test/fixtures/phase0/snapshot_single.json')
        .readAsStringSync();
    final records = ExpenseStore.v1ToRev0Records(Snapshot.decode(raw));
    expect(records.any((r) => r.type == SyncType.acct), isFalse);
    // The old snapshot has no accounts, so defaults are seeded on import;
    // an explicitly account-bearing v1 snapshot converts them.
    final store = await ready();
    final converted = ExpenseStore.v1ToRev0Records(store.toSnapshot());
    expect(converted.where((r) => r.type == SyncType.acct).length, 4);
  });

  test('account records merge with rev ordering and tombstones', () {
    const base = SyncRecord(
      type: SyncType.acct,
      id: 'acct_bank',
      rev: 2,
      by: 'A',
      data: {'id': 'acct_bank', 'name': 'Bank', 'type': 'bank', 'sortOrder': 1},
    );
    final merged = mergeRecords(
      localRecords: const {},
      localTombs: const {},
      remote: [base],
    );
    expect(merged.records['acct/acct_bank']!.data!['name'], 'Bank');
    final withTomb = mergeRecords(
      localRecords: const {'acct/acct_bank': base},
      localTombs: const {},
      remote: [
        const SyncRecord(
          type: SyncType.acct,
          id: 'acct_bank',
          rev: 5,
          by: 'B',
          dead: true,
        ),
      ],
    );
    expect(withTomb.records.containsKey('acct/acct_bank'), isFalse);
    expect(withTomb.tombs.containsKey('acct/acct_bank'), isTrue);
  });

  test('CSV keeps six original columns and appends account last', () async {
    final store = await ready();
    await store.addTransaction(
      type: 'expense',
      amount: 10,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      accountId: 'acct_card',
    );
    final csv = FileSync.buildCsv(
      (id) => 'Food',
      store.transactions,
      accountName: (t) => store.accountName(t.effectiveAccountId),
    );
    final header = csv.split('\n').first;
    expect(header, 'date,type,amount,category,mode,note,account');
    expect(csv.split('\n')[1].endsWith(',Card'), isTrue);
    // Old callers keep the exact original six-column header.
    expect(
      FileSync.buildCsv((id) => 'Food', store.transactions).split('\n').first,
      'date,type,amount,category,mode,note',
    );
  });
}
