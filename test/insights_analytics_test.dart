import 'package:expense/analytics.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Trailing-period Insights maths: window boundaries, comparison block,
/// zero-filled trend months, top expenses, elapsed-day average, and the
/// store-level revision + period cache.
void main() {
  Txn txn(
    String id,
    String type,
    double amount,
    String category,
    DateTime date,
  ) {
    return Txn(
      id: id,
      type: type,
      amount: amount,
      categoryId: category,
      date: date.millisecondsSinceEpoch,
    );
  }

  final anchor = DateTime(2026, 6, 15, 12);
  final asOf = DateTime(2026, 6, 15, 12);

  List<Txn> sample() => [
    txn('may', 'expense', 999, 'bills', DateTime(2026, 5, 31, 23, 59)),
    txn('jun-start', 'expense', 100, 'food', DateTime(2026, 6, 1)),
    txn('jun-income', 'income', 500, 'other', DateTime(2026, 6, 10)),
    txn('jun-end', 'expense', 50, 'travel', DateTime(2026, 6, 30, 23, 59)),
    txn('jul', 'expense', 777, 'shopping', DateTime(2026, 7, 1)),
    txn('apr', 'expense', 200, 'travel', DateTime(2026, 4, 30)),
  ];

  test('month window includes its edges, compares the prior month', () {
    final data = computeInsights(
      sample(),
      anchor,
      InsightPeriod.month,
      asOf: asOf,
    );

    expect(data.start, DateTime(2026, 6, 1));
    expect(data.end, DateTime(2026, 7, 1));
    expect(data.previousStart, DateTime(2026, 5, 1));
    expect(data.spend, 150);
    expect(data.income, 500);
    expect(data.previousSpend, 999);
    expect(data.previousIncome, 0);
    expect(data.txnCount, 3);
    expect(data.expenseCount, 2);
    expect(data.net, 350);
    expect(data.byCategory, {'food': 100, 'travel': 50});
    expect(data.topExpenses.map((t) => t.id), ['jun-start', 'jun-end']);
    expect(data.spendChange, closeTo((150 - 999) / 999, 1e-12));

    // Mid-June: 15 elapsed calendar days, not the full 30.
    expect(data.totalDays, 30);
    expect(data.elapsedDays, 15);
    expect(data.averagePerDay, closeTo(10, 1e-12));
  });

  test('three months spans the anchor and two months back', () {
    final data = computeInsights(
      sample(),
      anchor,
      InsightPeriod.quarter,
      asOf: asOf,
    );

    expect(data.start, DateTime(2026, 4, 1));
    expect(data.end, DateTime(2026, 7, 1));
    expect(data.previousStart, DateTime(2026, 1, 1));
    expect(data.spend, 1349);
    expect(data.income, 500);
    expect(data.previousSpend, 0);
    expect(data.spendChange, isNull);
    expect(data.byCategory, {'food': 100, 'travel': 250, 'bills': 999});
    expect(data.topExpenses.map((t) => t.id), [
      'may',
      'apr',
      'jun-start',
      'jun-end',
    ]);
    expect(data.elapsedDays, 76);
  });

  test('period metadata offers Month, 3, 6, Year and Fiscal year', () {
    expect(InsightPeriod.values.map((p) => p.label), [
      'Month',
      '3 months',
      '6 months',
      'Year',
      'Fiscal year',
    ]);
    expect(InsightPeriod.values.map((p) => p.months), [1, 3, 6, 12, 12]);
    expect(InsightPeriod.half.spentLabel, 'Spent in the last 6 months');
    expect(InsightPeriod.half.compareLabel, 'the previous 6 months');
    expect(InsightPeriod.year.spentLabel, 'Spent in the last 12 months');
    expect(InsightPeriod.fiscal.spentLabel, 'Spent this fiscal year');
    expect(InsightPeriod.fiscal.compareLabel, 'the previous fiscal year');
    expect(InsightPeriod.values.map((p) => p.trendMonths), [
      6,
      6,
      6,
      12,
      12,
    ]);
  });

  test('six months spans the anchor and five months back', () {
    final data = computeInsights(
      [
        ...sample(),
        txn('dec', 'expense', 120, 'food', DateTime(2025, 12, 31)),
      ],
      anchor,
      InsightPeriod.half,
      asOf: asOf,
    );

    expect(data.start, DateTime(2026, 1, 1));
    expect(data.end, DateTime(2026, 7, 1));
    expect(data.previousStart, DateTime(2025, 7, 1));
    expect(data.spend, 1349);
    expect(data.income, 500);
    // December 2025 sits in the comparison block, not the window.
    expect(data.previousSpend, 120);
    expect(data.spendChange, closeTo((1349 - 120) / 120, 1e-12));
    expect(data.trend, hasLength(6));
    expect(data.topExpenses.map((t) => t.id), [
      'may',
      'apr',
      'jun-start',
      'jun-end',
    ]);
    expect(data.elapsedDays, 166);
  });

  test('twelve months rolls across the year boundary', () {
    final data = computeInsights(
      [
        ...sample(),
        txn('dec', 'expense', 120, 'food', DateTime(2025, 12, 31)),
        txn('jan', 'income', 800, 'other', DateTime(2026, 1, 2)),
      ],
      DateTime(2026, 1, 15),
      InsightPeriod.year,
      asOf: DateTime(2026, 1, 15),
    );

    expect(data.start, DateTime(2025, 2, 1));
    expect(data.end, DateTime(2026, 2, 1));
    expect(data.previousStart, DateTime(2024, 2, 1));
    expect(data.byCategory, {'food': 120});
    expect(data.income, 800);
    expect(data.topExpenses.map((t) => t.id), ['dec']);
    expect(data.trend, hasLength(12));
    expect(data.trend.first.month, DateTime(2025, 2, 1));
    expect(data.trend.last.month, DateTime(2026, 1, 1));
    expect(data.trend[10].month, DateTime(2025, 12, 1));
    expect(data.trend[10].spend, 120);
    expect(data.trend.last.income, 800);
  });

  test('trend zero-fills months and includes income', () {
    final data = computeInsights(
      [txn('income', 'income', 700, 'other', DateTime(2026, 6, 10))],
      anchor,
      InsightPeriod.month,
      asOf: asOf,
    );

    expect(data.spend, 0);
    expect(data.income, 700);
    expect(data.topExpenses, isEmpty);
    expect(data.trend, hasLength(6));
    expect(data.trend.map((m) => m.month), [
      DateTime(2026, 1, 1),
      DateTime(2026, 2, 1),
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
      DateTime(2026, 5, 1),
      DateTime(2026, 6, 1),
    ]);
    expect(data.trend.every((m) => m.spend == 0), isTrue);
    expect(data.trend.last.income, 700);
    expect(data.trend.first.income, 0);
  });

  test('top expenses are expense-only, sorted, and capped', () {
    final data = computeInsights(
      [
        txn('a', 'expense', 10, 'food', DateTime(2026, 6, 2)),
        txn('b', 'expense', 50, 'food', DateTime(2026, 6, 3)),
        txn('c', 'expense', 30, 'food', DateTime(2026, 6, 4)),
        txn('d', 'expense', 20, 'food', DateTime(2026, 6, 5)),
        txn('e', 'expense', 40, 'food', DateTime(2026, 6, 6)),
        txn('income', 'income', 10000, 'other', DateTime(2026, 6, 7)),
      ],
      anchor,
      InsightPeriod.month,
      asOf: asOf,
      topLimit: 3,
    );

    expect(data.topExpenses.map((t) => t.id), ['b', 'e', 'c']);
    expect(data.txnCount, 6);
    expect(data.expenseCount, 5);
  });

  test('daily average clamps to the window', () {
    final before = computeInsights(
      sample(),
      anchor,
      InsightPeriod.month,
      asOf: DateTime(2026, 5, 20),
    );
    expect(before.elapsedDays, 0);
    expect(before.averagePerDay, 0);

    final after = computeInsights(
      sample(),
      anchor,
      InsightPeriod.month,
      asOf: DateTime(2026, 8, 2),
    );
    expect(after.elapsedDays, after.totalDays);
    expect(after.averagePerDay, closeTo(150 / 30, 1e-12));
  });

  test('by-category keeps first encounter order', () {
    final data = computeInsights(
      [
        txn('t1', 'expense', 10, 'travel', DateTime(2026, 6, 2)),
        txn('f1', 'expense', 20, 'food', DateTime(2026, 6, 3)),
        txn('t2', 'expense', 5, 'travel', DateTime(2026, 6, 4)),
      ],
      anchor,
      InsightPeriod.month,
      asOf: asOf,
    );

    expect(data.byCategory.keys.toList(), ['travel', 'food']);
    expect(data.byCategory['travel'], 15);
    expect(data.byCategory['food'], 20);
  });

  test(
    'store memoizes by revision and period, settings reuse the cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = ExpenseStore();
      await store.load();
      final now = DateTime.now();
      await store.addTransaction(
        type: 'expense',
        amount: 100,
        categoryId: 'food',
        date: now,
        note: 'first',
      );

      final month = store.insights(InsightPeriod.month);
      expect(identical(store.insights(InsightPeriod.month), month), isTrue);
      expect(identical(store.insights(InsightPeriod.quarter), month), isFalse);
      expect(store.insights(InsightPeriod.quarter).spend, 100);

      // Settings-only writes do not change updatedAt.
      await store.setUserName('Ram');
      expect(identical(store.insights(InsightPeriod.month), month), isTrue);

      await store.addTransaction(
        type: 'expense',
        amount: 50,
        categoryId: 'travel',
        date: now,
        note: 'second',
      );
      final after = store.insights(InsightPeriod.month);
      expect(identical(after, month), isFalse);
      expect(after.spend, month.spend + 50);
    },
  );
}
