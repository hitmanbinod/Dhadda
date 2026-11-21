import 'package:expense/analytics.dart';
import 'package:expense/screens/history_screen.dart';
import 'package:expense/screens/insights_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ExpenseStore> storeWith({bool withExpense = true}) async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    if (withExpense) {
      final now = DateTime.now();
      await store.addTransaction(
        type: 'expense',
        amount: 250,
        categoryId: 'food',
        date: DateTime(now.year, now.month, 3, 12),
        note: 'Lunch',
        mode: 'bank',
        accountId: 'acct_bank',
      );
    }
    return store;
  }

  Widget shell(ExpenseStore store, ValueChanged<String>? onOpenAccount) =>
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.build(const Color(0xFF009688), Brightness.light),
          home: Scaffold(
            body: InsightsScreen(onOpenAccount: onOpenAccount),
          ),
        ),
      );

  testWidgets('How you pay shows account shares and opens History filtered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await storeWith();
    final opened = <String>[];
    await tester.pumpWidget(shell(store, opened.add));
    await tester.pumpAndSettle();

    expect(find.text('How you pay'), findsOneWidget);
    expect(find.byKey(const Key('insights-how-you-pay')), findsOneWidget);
    final row = find.byKey(const Key('insights-pay-acct_bank'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(opened, ['acct_bank']);
  });

  testWidgets('How you pay hides with no spend; forecast shows on open month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final empty = await storeWith(withExpense: false);
    await tester.pumpWidget(shell(empty, null));
    await tester.pumpAndSettle();

    expect(find.text('How you pay'), findsNothing);
    expect(find.byKey(const Key('insights-how-you-pay')), findsNothing);

    final store = await storeWith();
    await tester.pumpWidget(shell(store, null));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-forecast-card')), findsOneWidget);
  });

  testWidgets('History honors an account request from Insights', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await storeWith();
    final now = DateTime.now();
    await store.addTransaction(
      type: 'expense',
      amount: 80,
      categoryId: 'food',
      date: DateTime(now.year, now.month, 4, 12),
      note: 'Tea',
      mode: 'cash',
      accountId: 'acct_cash',
    );
    final request = HistoryDayRequest()..openAccount('acct_bank');
    addTearDown(request.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.build(const Color(0xFF009688), Brightness.light),
          home: Scaffold(body: HistoryScreen(dayRequest: request)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Tea'), findsNothing);
    expect(find.text('Bank'), findsWidgets);
  });

  test('store memoizes the account split like the other insights', () async {
    final store = await storeWith();
    final first = store.howYouPay(InsightPeriod.month);
    expect(identical(store.howYouPay(InsightPeriod.month), first), isTrue);
    expect(first.total, 250);
    expect(first.slices.single.id, 'acct_bank');
  });
}
