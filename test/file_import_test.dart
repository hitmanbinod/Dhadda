import 'dart:convert';

import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression: re-importing your own exported backup used to bounce off
/// "Already up to date (this device is newer)" because the v1 file path
/// gated the whole import on the file's updatedAt stamp. File imports now
/// merge record-level like v2 files, so a file's records always get a
/// chance to land regardless of timestamps.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    return store;
  }

  String v1File({
    required String updatedAt,
    required List<Map<String, dynamic>> transactions,
    String userName = '',
  }) {
    final map = {
      'version': 1,
      'updatedAt': updatedAt,
      'deviceId': 'oldphone',
      'deviceName': 'Old Phone',
      'categories': [
        for (final c in defaultCategories()) c.toJson(),
      ],
      'transactions': transactions,
      'loans': [],
      'projects': [],
    };
    // Older exports carry no userName key at all.
    if (userName.isNotEmpty) map['userName'] = userName;
    return jsonEncode(map);
  }

  test('re-importing your own export no longer claims up-to-date',
      () async {
    final store = await readyStore();
    await store.addTransaction(
        type: 'expense',
        amount: 50,
        categoryId: 'food',
        date: DateTime(2026, 10, 1),
        note: 'Tea');
    final backup = store.exportJson();

    final msg = await store.importFilePayload(backup);

    expect(msg, isNot(contains('Already up to date')));
    expect(msg, 'Nothing new to import - this device already has '
        'everything in the file.');
    expect(store.transactions.length, 1);
    expect(store.transactions.first.note, 'Tea');
  });

  test('a file older than this device still imports its records',
      () async {
    final store = await readyStore();
    await store.addTransaction(
        type: 'expense',
        amount: 10,
        categoryId: 'food',
        date: DateTime(2026, 10, 2),
        note: 'Local');
    final raw = v1File(
      updatedAt: '2026-01-01T00:00:00.000Z',
      transactions: [
        const Txn(
          id: 'old1',
          type: 'expense',
          amount: 123,
          categoryId: 'food',
          date: 1767225600000,
          note: 'From old phone',
        ).toJson(),
      ],
    );

    final msg = await store.importFilePayload(raw);

    expect(msg, 'Imported 1 change from the file.');
    expect(
        store.transactions.any((t) => t.note == 'From old phone'), isTrue);
    expect(store.transactions.length, 2);
  });

  test('importing into an empty device adopts the whole file', () async {
    final store = await readyStore();
    final raw = v1File(
      updatedAt: '2026-01-01T00:00:00.000Z',
      transactions: [
        const Txn(
                id: 'a1', type: 'expense', amount: 1,
                categoryId: 'food', date: 1767225600000, note: 'A')
            .toJson(),
        const Txn(
                id: 'a2', type: 'expense', amount: 2,
                categoryId: 'food', date: 1767225600000, note: 'B')
            .toJson(),
      ],
    );

    final msg = await store.importFilePayload(raw);

    expect(msg, 'Imported 2 changes from the file.');
    expect(store.transactions.length, 2);
  });

  test('file import pulls the display name from the backup', () async {
    final store = await readyStore();
    final raw = v1File(
      updatedAt: '2026-01-01T00:00:00.000Z',
      transactions: [
        const Txn(
                id: 'n1', type: 'expense', amount: 3,
                categoryId: 'food', date: 1767225600000, note: 'Named')
            .toJson(),
      ],
      userName: 'Ram',
    );

    await store.importFilePayload(raw);

    expect(store.userName, 'Ram');
  });

  test('a legacy export without a name leaves the local name alone',
      () async {
    final store = await readyStore();
    await store.setUserName('Local Name');
    final raw = v1File(
      updatedAt: '2026-01-01T00:00:00.000Z',
      transactions: [
        const Txn(
                id: 'n2', type: 'expense', amount: 4,
                categoryId: 'food', date: 1767225600000, note: 'Anon')
            .toJson(),
      ],
    );

    await store.importFilePayload(raw);

    expect(store.userName, 'Local Name');
  });

  test('export carries the display name and restore brings it back',
      () async {
    final store = await readyStore();
    await store.setUserName('Sita');
    await store.addTransaction(
        type: 'expense',
        amount: 7,
        categoryId: 'food',
        date: DateTime(2026, 10, 4),
        note: 'Round trip');
    final backup = store.exportJson();
    expect(backup.contains('"userName":"Sita"'), isTrue);

    // Importing a foreign backup pulls ITS name...
    final foreign = v1File(
      updatedAt: '2026-01-01T00:00:00.000Z',
      transactions: [
        const Txn(
                id: 'g1', type: 'expense', amount: 2,
                categoryId: 'food', date: 1767225600000, note: 'Gita entry')
            .toJson(),
      ],
      userName: 'Gita',
    );
    await store.importFilePayload(foreign);
    expect(store.userName, 'Gita');

    // ...and the rolling backup (pushed before that import) restores the
    // local state, name included.
    final msg = await store.restoreBackup(0);
    expect(msg, startsWith('Synced'));
    expect(store.userName, 'Sita');
    expect(
        store.transactions.any((t) => t.note == 'Round trip'), isTrue);
  });

  test('a file import brings back records this device had deleted',
      () async {
    final store = await readyStore();
    await store.addTransaction(
        type: 'expense',
        amount: 5,
        categoryId: 'food',
        date: DateTime(2026, 10, 3),
        note: 'Doomed');
    final doomed = store.transactions.first.toJson();
    await store.deleteTransaction(doomed['id'] as String);

    final raw = v1File(
      updatedAt: '2026-10-03T00:00:00.000Z',
      transactions: [
        doomed,
        const Txn(
                id: 'extra',
                type: 'expense',
                amount: 9,
                categoryId: 'food',
                date: 1767225600000,
                note: 'Extra')
            .toJson(),
      ],
    );

    final msg = await store.importFilePayload(raw);

    // File-restore UX: everything the file contains is adopted, so the
    // deleted record comes back plus the new one.
    expect(msg, 'Imported 2 changes from the file.');
    expect(store.transactions.any((t) => t.note == 'Doomed'), isTrue);
    expect(store.transactions.any((t) => t.note == 'Extra'), isTrue);
  });

  test('ambient sync still keeps deletions standing (no revive)', () async {
    final store = await readyStore();
    await store.addTransaction(
        type: 'expense',
        amount: 5,
        categoryId: 'food',
        date: DateTime(2026, 10, 3),
        note: 'Doomed');
    final doomed = store.transactions.first.toJson();
    await store.deleteTransaction(doomed['id'] as String);

    final raw = v1File(
      updatedAt: '2026-10-03T00:00:00.000Z',
      transactions: [doomed],
    );

    // Peer ingest (not a user-picked file): the deletion stands.
    final msg = await store.ingestPeerSnapshot(raw, peerName: 'Peer');
    expect(store.transactions.any((t) => t.note == 'Doomed'), isFalse);
    expect(msg, 'Already in sync.');
  });
}
