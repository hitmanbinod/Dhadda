// Phase 0 baseline fixtures: validity, legacy migration, corruption
// behavior, and export -> import equivalence (Steps 5-8, 10).
// Fixture data lives in test/fixtures/phase0/ (all synthetic).
// Pure model/store level: no UI, no platform channels.
import 'dart:io';

import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _read(String name) =>
    File('test/fixtures/phase0/$name').readAsStringSync();

double _expenseTotal(Snapshot s) => s.transactions
    .where((t) => t.isExpense)
    .fold(0, (sum, t) => sum + t.amount);

double _incomeTotal(Snapshot s) => s.transactions
    .where((t) => !t.isExpense)
    .fold(0, (sum, t) => sum + t.amount);

void main() {
  test('empty fixture decodes to empty collections', () {
    final s = Snapshot.decode(_read('snapshot_empty.json'));
    expect(s.version, 1);
    expect(s.transactions, isEmpty);
    expect(s.categories, isEmpty);
    expect(s.loans, isEmpty);
    expect(s.projects, isEmpty);
  });

  test('single fixture decodes to one expense', () {
    final s = Snapshot.decode(_read('snapshot_single.json'));
    expect(s.transactions, hasLength(1));
    final t = s.transactions.single;
    expect(t.id, 'single-txn-1');
    expect(t.isExpense, isTrue);
    expect(t.amount, 500);
  });

  test('canonical populated fixture keeps counts, totals, relations', () {
    final s = Snapshot.decode(_read('snapshot_populated.json'));
    expect(s.version, 1);
    expect(s.deviceId, 'phase0-device-a');
    expect(s.categories, hasLength(9));
    expect(s.categories.first.id, 'travel'); // reordered fixture
    expect(s.categories.last.id, 'other'); // other stays last
    expect(
      s.categories.firstWhere((c) => c.id == 'health').name,
      'Health & Fitness',
    ); // rename
    expect(s.categories.firstWhere((c) => c.id == 'pets').budget, 2000);
    expect(s.transactions, hasLength(8));
    expect(_expenseTotal(s), 2506699.5);
    expect(_incomeTotal(s), 97000);
    expect(s.loans, hasLength(3));
    final l1 = s.loans.firstWhere((l) => l.id == 'loan-0001');
    expect(l1.pending, 4000); // 5000 + 2000 topup - 3000 repaid
    expect(l1.remindAt, 1789084800000);
    final l2 = s.loans.firstWhere((l) => l.id == 'loan-0002');
    expect(l2.isBorrowed, isTrue);
    expect(l2.pending, 6000); // partial repayment
    final l3 = s.loans.firstWhere((l) => l.id == 'loan-0003');
    expect(l3.settled, isTrue);
    expect(s.projects, hasLength(2));
    final trek = s.projects.firstWhere((p) => p.id == 'proj-trek');
    expect(trek.name, 'Annapurna Trek');
    expect(
      s.transactions.firstWhere((t) => t.id == 'txn-0005').projectId,
      trek.id,
    ); // project-linked transaction
    expect(
      s.transactions.where((t) => t.projectId == 'proj-empty'),
      isEmpty,
    ); // project with no transactions
  });

  test('bulk fixture decodes 300 transactions', () {
    final s = Snapshot.decode(_read('snapshot_bulk.json'));
    expect(s.transactions, hasLength(300));
    expect(s.transactions.first.id, 'bulk-txn-0000');
    expect(s.transactions.where((t) => !t.isExpense), hasLength(30));
  });

  test('unicode fixture preserves notes and edge amounts', () {
    final s = Snapshot.decode(_read('snapshot_unicode.json'));
    expect(s.transactions, hasLength(3));
    expect(s.transactions[0].note, contains('दाल भात'));
    final amounts = s.transactions.map((t) => t.amount).toList();
    expect(amounts, contains(0.01));
    expect(amounts, contains(99999999.99));
  });

  test('legacy fixture decodes and migrates remindFreq', () {
    final s = Snapshot.decode(_read('snapshot_legacy.json'));
    // Pre-fuel category set passes through untouched at decode level.
    expect(s.categories.any((c) => c.id == 'fuel'), isFalse);
    // Old repeating reminder becomes a one-time timestamp (> 0).
    final loan = s.loans.single;
    expect(loan.remindAt, greaterThan(0));
    // Missing txn optionals fall back to defaults.
    final t = s.transactions.firstWhere((t) => t.id == 'leg-txn-2');
    expect(t.type, 'expense');
    expect(t.note, '');
    expect(t.mode, 'cash');
    expect(t.categoryId, 'other');
    expect(t.projectId, '');
    // Missing category optionals fall back to defaults.
    final rent = s.categories.firstWhere((c) => c.id == 'rent');
    expect(rent.budget, 0);
    final health = s.categories.firstWhere((c) => c.id == 'health');
    expect(health.name, 'Other');
  });

  test('malformed and wrong-type fixtures throw on decode', () {
    expect(
      () => Snapshot.decode(_read('corrupt_malformed.json')),
      throwsA(anything),
    );
    expect(
      () => Snapshot.decode(_read('corrupt_wrongtype.json')),
      throwsA(anything),
    );
  });

  test('lenient fixture documents defaulting behavior', () {
    final s = Snapshot.decode(_read('corrupt_lenient.json'));
    expect(s.version, 1); // missing version defaults
    expect(s.deviceName, 'Phase0Lenient');
    expect(s.categories.single.name, 'Other'); // missing name defaults
    expect(s.transactions, hasLength(2)); // duplicate IDs are NOT deduped
    final first = s.transactions.first;
    expect(first.type, 'expense'); // unknown type falls back
    expect(first.amount, 0); // non-numeric amount falls back
    expect(first.date, greaterThan(0)); // non-int date falls back to now
    expect(first.mode, 'crypto'); // unknown mode passes through as-is
    expect(s.projects, isEmpty); // non-list collection falls back
  });

  test('decode -> encode -> decode round-trip preserves meaning', () {
    final a = Snapshot.decode(_read('snapshot_populated.json'));
    final b = Snapshot.decode(a.encode());
    expect(
      b.transactions.map((t) => t.id),
      orderedEquals(a.transactions.map((t) => t.id)),
    );
    expect(_expenseTotal(b), _expenseTotal(a));
    expect(_incomeTotal(b), _incomeTotal(a));
    expect(
      b.categories.map((c) => c.id),
      orderedEquals(a.categories.map((c) => c.id)),
    );
    expect(
      b.loans.map((l) => l.pending),
      orderedEquals(a.loans.map((l) => l.pending)),
    );
  });

  test('store export -> import restores equivalent state (Step 10)', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    final raw = _read('snapshot_populated.json');
    expect(await a.importSnapshotString(raw, force: true), contains('Synced'));
    final exported = a.exportJson();

    SharedPreferences.setMockInitialValues({});
    final b = ExpenseStore();
    await b.load();
    expect(
      await b.importSnapshotString(exported, force: true),
      contains('Synced'),
    );

    expect(
      b.transactions.map((t) => t.id),
      orderedEquals(a.transactions.map((t) => t.id)),
    );
    final sep2026 = DateTime.utc(2026, 9);
    expect(b.monthSpend(sep2026), a.monthSpend(sep2026));
    expect(
      b.monthSpend(DateTime.utc(2026, 8)),
      a.monthSpend(DateTime.utc(2026, 8)),
    );
    expect(
      b.categories.map((c) => c.id),
      orderedEquals(a.categories.map((c) => c.id)),
    );
    expect(b.pendingLoansTotal, a.pendingLoansTotal);
    expect(b.pendingBorrowedTotal, a.pendingBorrowedTotal);
    final bTrek = b.projects.firstWhere((p) => p.id == 'proj-trek');
    expect(b.projectTxns(bTrek.id).map((t) => t.id), ['txn-0005']);
  });
}
