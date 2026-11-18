import 'package:expense/format.dart';
import 'package:expense/screens/home_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 2 Home: hero balance, one three-column stat card, category
/// spotlight + stacked bar, over-budget state, recent swipe-delete with
/// Undo, and the floating Add pill.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    final now = DateTime.now();
    await store.addTransaction(
      type: 'expense',
      amount: 500,
      categoryId: 'food',
      date: DateTime(now.year, now.month, 4),
      note: 'Daal',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'expense',
      amount: 300,
      categoryId: 'travel',
      date: DateTime(now.year, now.month, 3),
      note: 'Bus',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'income',
      amount: 2000,
      categoryId: 'other',
      date: DateTime(now.year, now.month, 2),
      note: 'Salary',
      mode: 'bank',
    );
    await store.setBudget('food', 100);
    return store;
  }

  Widget shell(
    ExpenseStore store, {
    Brightness brightness = Brightness.light,
    VoidCallback? onAdd,
    VoidCallback? onSeeAll,
    VoidCallback? onOpenSync,
  }) {
    return ChangeNotifierProvider<ExpenseStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.build(const Color(0xFF009688), brightness),
        home: Scaffold(
          body: HomeScreen(
            onAdd: onAdd ?? () {},
            onSync: () async => 'Up to date.',
            onOpenSync: onOpenSync,
            onSeeAll: onSeeAll,
          ),
        ),
      ),
    );
  }

  testWidgets('hero, stats, spotlight, budget state, and callbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    var added = 0;
    var seeAll = 0;
    var openedSync = 0;

    await tester.pumpWidget(
      shell(
        store,
        onAdd: () => added++,
        onSeeAll: () => seeAll++,
        onOpenSync: () => openedSync++,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // One hero balance (income 2000 - spend 800) and three equal stats.
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text(money(1200)), findsOneWidget);
    expect(find.text('Spent'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Lent out'), findsOneWidget);

    // The top category starts in the spotlight; tapping a row moves it.
    final spotlight = find.byKey(const Key('home-cat-spotlight'));
    expect(
      find.descendant(of: spotlight, matching: find.text('Food')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('home-cat-travel')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: spotlight, matching: find.text('Travel')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: spotlight, matching: find.text(money(300))),
      findsOneWidget,
    );

    // Over-budget state is explicit.
    expect(find.textContaining('Over by'), findsOneWidget);

    await tester.tap(find.byTooltip('Sync'));
    expect(openedSync, 1);

    await tester.tap(find.byKey(const Key('home-add')));
    expect(added, 1);

    await tester.ensureVisible(find.text('See all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all'));
    expect(seeAll, 1);
  });

  testWidgets('recent rows swipe-delete with Undo', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final daal = store.transactions.firstWhere((t) => t.note == 'Daal');

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey('home-recent-${daal.id}'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.transactions.any((t) => t.id == daal.id), isFalse);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.transactions.any((t) => t.id == daal.id), isTrue);
  });

  testWidgets('empty month shows quiet category and recent states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No expenses this month yet.'), findsOneWidget);
    expect(find.text('No entries yet.'), findsOneWidget);
  });

  testWidgets('home lays out at phone and desktop widths in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final now = DateTime.now();
    final trek = await store.addProject('Trek', 'Annapurna');
    await store.addTransaction(
      type: 'expense',
      amount: 700,
      categoryId: 'travel',
      date: DateTime(now.year, now.month, 5),
      note: 'Jeep',
      projectId: trek,
    );

    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final size in [const Size(360, 740), const Size(1280, 800)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(shell(store, brightness: brightness));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$size ${brightness.name}',
        );
      }
    }
  });
}
