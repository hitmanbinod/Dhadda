// Phase 6: analytics equivalence. The single-pass epoch implementation in
// lib/analytics.dart must match the historical triple-scan DateTime
// semantics exactly (membership, bit-identical sums, map key order).
// Synthetic + checked-in fixtures only; no real data.
import 'dart:io';
import 'dart:math';

import 'package:expense/analytics.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Independent naive reference mirroring the pre-Phase-6 implementation.
List<Txn> refMonthTxns(List<Txn> all, DateTime month) => all.where((t) {
  final d = t.dateTime;
  return d.year == month.year && d.month == month.month;
}).toList();

double refSpend(List<Txn> inMonth) {
  var sum = 0.0;
  for (final t in inMonth) {
    if (t.isExpense) sum += t.amount;
  }
  return sum;
}

double refIncome(List<Txn> inMonth) {
  var sum = 0.0;
  for (final t in inMonth) {
    if (!t.isExpense) sum += t.amount;
  }
  return sum;
}

Map<String, double> refByCat(List<Txn> inMonth) {
  final map = <String, double>{};
  for (final t in inMonth) {
    if (!t.isExpense) continue;
    map[t.categoryId] = (map[t.categoryId] ?? 0) + t.amount;
  }
  return map;
}

void checkEquivalent(List<Txn> all, DateTime month) {
  final inMonth = refMonthTxns(all, month);
  final got = computeMonthlyAnalytics(all, month);
  expect(got.txnCount, inMonth.length);
  expect(got.spend, refSpend(inMonth));
  expect(got.income, refIncome(inMonth));
  final want = refByCat(inMonth);
  expect(got.byCategory.keys.toList(), want.keys.toList());
  for (final k in want.keys) {
    expect(got.byCategory[k], want[k]);
  }
}

List<Txn> fixtureTxns(String name) {
  final raw = File('test/fixtures/phase0/$name').readAsStringSync();
  return Snapshot.decode(raw).transactions;
}

Txn txn(String id, String type, double amount, String cat, int dateMs) =>
    Txn(id: id, type: type, amount: amount, categoryId: cat, date: dateMs);

void main() {
  test('empty dataset', () {
    checkEquivalent(const [], DateTime(2025, 6, 1));
  });

  test('single transaction on each side of the boundary', () {
    final may31 = DateTime(2025, 5, 31, 23, 59, 59, 999).millisecondsSinceEpoch;
    final jun1 = DateTime(2025, 6, 1).millisecondsSinceEpoch;
    final jun30 = DateTime(2025, 6, 30, 23, 59, 59, 999).millisecondsSinceEpoch;
    final jul1 = DateTime(2025, 7, 1).millisecondsSinceEpoch;
    final all = [
      txn('a', 'expense', 10, 'food', may31),
      txn('b', 'expense', 20, 'food', jun1),
      txn('c', 'income', 30, 'other', jun30),
      txn('d', 'expense', 40, 'travel', jul1),
    ];
    checkEquivalent(all, DateTime(2025, 6, 1));
    final got = computeMonthlyAnalytics(all, DateTime(2025, 6, 1));
    expect(got.txnCount, 2);
    expect(got.spend, 20);
    expect(got.income, 30);
  });

  test('december to january rollover', () {
    final all = [
      txn(
        'dec',
        'expense',
        5,
        'food',
        DateTime(2025, 12, 31, 12).millisecondsSinceEpoch,
      ),
      txn(
        'jan',
        'expense',
        7,
        'food',
        DateTime(2026, 1, 1, 12).millisecondsSinceEpoch,
      ),
    ];
    checkEquivalent(all, DateTime(2025, 12, 1));
    checkEquivalent(all, DateTime(2026, 1, 1));
    expect(computeMonthlyAnalytics(all, DateTime(2025, 12, 1)).spend, 5);
    expect(computeMonthlyAnalytics(all, DateTime(2026, 1, 1)).spend, 7);
  });

  test('leap day belongs to february', () {
    final all = [
      txn(
        'leap',
        'income',
        100,
        'other',
        DateTime(2024, 2, 29, 12).millisecondsSinceEpoch,
      ),
    ];
    checkEquivalent(all, DateTime(2024, 2, 1));
    checkEquivalent(all, DateTime(2024, 3, 1));
    expect(computeMonthlyAnalytics(all, DateTime(2024, 2, 1)).income, 100);
    expect(computeMonthlyAnalytics(all, DateTime(2024, 3, 1)).txnCount, 0);
  });

  test('populated + unicode fixtures, every month of 2024-2026', () {
    final all = [
      ...fixtureTxns('snapshot_populated.json'),
      ...fixtureTxns('snapshot_unicode.json'),
    ];
    for (var y = 2024; y <= 2026; y++) {
      for (var m = 1; m <= 12; m++) {
        checkEquivalent(all, DateTime(y, m, 1));
      }
    }
  });

  test('5k synthetic with mixed kinds, projects, unicode notes', () {
    final rnd = Random(99);
    final base = DateTime(2024, 1, 1).millisecondsSinceEpoch;
    const day = 24 * 3600 * 1000;
    final all = <Txn>[
      for (var i = 0; i < 5000; i++)
        Txn(
          id: 'eq-$i',
          type: rnd.nextDouble() < 0.7 ? 'expense' : 'income',
          amount: (rnd.nextInt(100000) + 1) / 100.0,
          categoryId: 'cat${i % 9}',
          date: base + rnd.nextInt(900) * day,
          note: i % 50 == 0 ? '☕ चिया $i' : 'note $i',
          mode: 'cash',
          projectId: i % 17 == 0 ? 'proj' : '',
        ),
    ];
    for (final month in [
      DateTime(2024, 1, 1),
      DateTime(2025, 6, 1),
      DateTime(2026, 2, 1),
    ]) {
      checkEquivalent(all, month);
    }
  });

  test('store memoizes per data revision and invalidates on write', () async {
    SharedPreferences.setMockInitialValues({});
    final s = ExpenseStore();
    await s.load();
    final month = DateTime(2026, 9, 1);
    final first = s.monthly(month);
    // Same revision + same month: identical cached instance.
    expect(identical(s.monthly(month), first), isTrue);
    await s.addTransaction(
      type: 'expense',
      amount: 250,
      categoryId: 'food',
      date: DateTime(2026, 9, 8),
      note: 'memo-test',
    );
    final after = s.monthly(month);
    expect(identical(after, first), isFalse);
    expect(after.spend, first.spend + 250);
    // Public delegating getters agree with the summary.
    expect(s.monthSpend(month), after.spend);
    expect(s.monthIncome(month), after.income);
    expect(s.spendByCategory(month), after.byCategory);
  });
}
