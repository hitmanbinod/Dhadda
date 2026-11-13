import 'package:expense/screens/history_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tapping a category in the Categories tab opens that category's own
/// history: only its entries, with spent/income/counts summary.
void main() {
  testWidgets('category tap shows only that category\'s history',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.addTransaction(
        type: 'expense',
        amount: 250,
        categoryId: 'food',
        date: DateTime(2026, 10, 10, 9),
        note: 'Momo');
    await store.addTransaction(
        type: 'expense',
        amount: 900,
        categoryId: 'rent',
        date: DateTime(2026, 10, 1),
        note: 'October rent');

    await tester.pumpWidget(
      // The real app puts the provider above MaterialApp so pushed
      // routes inherit it; mirror that here.
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          home: const Scaffold(body: HistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    // The pushed screen lists only the food category's entries.
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('October rent'), findsNothing);
    expect(find.text('Spent'), findsOneWidget);
    expect(find.text('Entries'), findsOneWidget);
    // Income is not a meaningful stat per category - deliberately absent.
    expect(find.text('Income'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
