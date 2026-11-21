import 'package:expense/analytics.dart';
import 'package:expense/insights.dart';
import 'package:expense/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 6, 1);
  final end = DateTime(2026, 7, 1);

  Txn expense(String id, double amount, DateTime date, {String account = 'a1'}) {
    return Txn(
      id: id,
      type: 'expense',
      amount: amount,
      categoryId: 'food',
      date: date.millisecondsSinceEpoch,
      accountId: account,
    );
  }

  Account account(String id, String name, {int color = 0, bool archived = false}) {
    return Account(
      id: id,
      name: name,
      type: 'cash',
      color: color,
      archived: archived,
    );
  }

  HowYouPay compute(List<Txn> txns, {List<Account>? accounts, int top = 5}) {
    return computeHowYouPay(
      txns,
      start: start,
      end: end,
      accounts: accounts ?? [
        account('a1', 'Cash', color: 0xFF112233),
        account('a2', 'Bank'),
      ],
      accountIdFor: (t) => t.accountId,
      top: top,
    );
  }

  test('groups expenses by account, expenses only, sorted by amount', () {
    final result = compute([
      expense('b', 30, DateTime(2026, 6, 5), account: 'a2'),
      expense('a', 50, DateTime(2026, 6, 2)),
      expense('a2', 20, DateTime(2026, 6, 3)),
      Txn(
        id: 'income',
        type: 'income',
        amount: 999,
        categoryId: 'other',
        date: DateTime(2026, 6, 6).millisecondsSinceEpoch,
        accountId: 'a1',
      ),
      expense('before', 100, DateTime(2026, 5, 31)),
      expense('after', 100, DateTime(2026, 7, 1)),
    ]);

    expect(result.total, 100);
    expect(result.slices.map((s) => s.id), ['a1', 'a2']);
    expect(result.slices.map((s) => s.amount), [70, 30]);
    expect(result.slices.first.label, 'Cash');
    expect(result.slices.first.color, 0xFF112233);
  });

  test('archived accounts with spend stay; unknown ids keep their id', () {
    final result = computeHowYouPay(
      [expense('x', 10, DateTime(2026, 6, 4), account: 'old')],
      start: start,
      end: end,
      accounts: [account('old', 'Old bank', archived: true)],
      accountIdFor: (t) => t.accountId,
    );
    expect(result.slices.single.label, 'Old bank');
    expect(result.slices.single.amount, 10);
  });

  test('tail accounts fold into Other accounts after the top slices', () {
    final txns = [
      for (var i = 1; i <= 7; i++)
        expense('e$i', i * 10.0, DateTime(2026, 6, i), account: 'a$i'),
    ];
    final allAccounts = [for (var i = 1; i <= 7; i++) account('a$i', 'Acc $i')];
    final result = compute(txns, accounts: allAccounts, top: 3);

    expect(result.slices.length, 4);
    expect(result.slices.take(3).map((s) => s.amount), [70, 60, 50]);
    expect(result.slices.last.id, kOtherAccountsId);
    expect(result.slices.last.label, 'Other accounts');
    expect(result.slices.last.amount, 100);
    expect(result.total, 280);
    expect(
      result.slices.fold<double>(0, (sum, s) => sum + s.amount),
      result.total,
    );
  });

  test('empty window has no slices', () {
    final result = compute([
      Txn(
        id: 'income',
        type: 'income',
        amount: 10,
        categoryId: 'other',
        date: DateTime(2026, 6, 2).millisecondsSinceEpoch,
      ),
    ]);
    expect(result.total, 0);
    expect(result.slices, isEmpty);
  });

  test('legacy resolver decides the account for mode-only entries', () {
    final legacy = Txn(
      id: 'legacy',
      type: 'expense',
      amount: 25,
      categoryId: 'food',
      date: DateTime(2026, 6, 2).millisecondsSinceEpoch,
      mode: 'bank',
    );
    final result = computeHowYouPay(
      [legacy],
      start: start,
      end: end,
      accounts: [account('custom_bank', 'My bank')],
      accountIdFor: (t) => t.accountId.isEmpty ? 'custom_bank' : t.accountId,
    );
    expect(result.slices.single.id, 'custom_bank');
    expect(result.slices.single.label, 'My bank');
  });

  test('projection stays quiet on closed windows, scales the open one', () {
    final data = InsightsAnalytics(
      start: start,
      end: end,
      previousStart: DateTime(2026, 5, 1),
      spend: 300,
      income: 0,
      previousSpend: 0,
      previousIncome: 0,
      byCategory: const {'food': 300},
      txnCount: 1,
      expenseCount: 1,
      totalDays: 30,
      elapsedDays: 10,
      trend: const [],
      topExpenses: const [],
    );

    expect(
      projectInsightsEndSpend(data, asOf: DateTime(2026, 6, 5)),
      closeTo(900, 1e-12),
    );
    expect(projectInsightsEndSpend(data, asOf: DateTime(2026, 5, 31)), isNull);
    expect(projectInsightsEndSpend(data, asOf: DateTime(2026, 7, 1)), isNull);
  });
}
