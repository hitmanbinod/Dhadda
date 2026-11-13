import 'package:expense/screens/history_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The History search+filter block must hand its space to the entries as
/// the list scrolls: fully laid out at rest, collapsed to zero height
/// once the list has scrolled past the collapse distance. Paint is
/// clipped, so the fading filters cannot ghost behind the rows.
void main() {
  testWidgets('search + filters collapse away as the list scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(400, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    for (var i = 0; i < 30; i++) {
      await store.addTransaction(
        type: 'expense',
        amount: 10.0 + i,
        categoryId: 'food',
        date: DateTime(2026, 9, 1).add(Duration(days: i)),
        note: 'Entry $i',
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: const Scaffold(body: HistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double listTop() => tester
        .getTopLeft(find.byType(ListView).first)
        .dy;

    final restTop = listTop();
    // At rest the list starts below search + filters.
    expect(restTop, greaterThan(200));

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    // Scrolled: the block has collapsed to nothing and the list now
    // starts just under the view chips.
    final scrolledTop = listTop();
    expect(scrolledTop, lessThan(120));
    expect(scrolledTop, lessThan(restTop - 100));

    // Scrolling back restores the block.
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(listTop(), restTop);
  });
}
