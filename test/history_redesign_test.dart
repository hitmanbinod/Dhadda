import 'package:expense/screens/history_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 3 History: large title with a live count, segmented tabs, day
/// groups, flat search + quiet filter pills, and swipe-delete with Undo.
/// Editing, drill-down, CSV and events stay covered by the feature tests;
/// this file pins the redesigned surface.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    await store.addTransaction(
      type: 'expense',
      amount: 250,
      categoryId: 'food',
      date: today,
      note: 'Momo',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'expense',
      amount: 700,
      categoryId: 'travel',
      date: today.subtract(const Duration(days: 1)),
      note: 'Bus',
      mode: 'card',
    );
    await store.addTransaction(
      type: 'income',
      amount: 2000,
      categoryId: 'other',
      date: today.subtract(const Duration(days: 2)),
      note: 'Salary',
      mode: 'bank',
    );
    return store;
  }

  Widget shell(
    ExpenseStore store, {
    Brightness brightness = Brightness.light,
    VoidCallback? onOpenSync,
  }) {
    return ChangeNotifierProvider<ExpenseStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.build(const Color(0xFF009688), brightness),
        home: Scaffold(body: HistoryScreen(onOpenSync: onOpenSync)),
      ),
    );
  }

  testWidgets('large title, count, tabs, and day groups', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('History'), findsOneWidget);
    expect(find.text('3 entries'), findsOneWidget);
    expect(find.text('Entries'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);

    // Newest-first day groups: today, then yesterday, then the older day.
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Bus'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets('type and category pills filter the day groups', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Momo'), findsNothing);
    expect(find.text('Bus'), findsNothing);
    expect(find.text('1 of 3 entries'), findsOneWidget);
    expect(find.text('Today'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);

    // Category moves into a menu, but still narrows the list. The pill row
    // scrolls horizontally, so bring the chip into view first.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Bus'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Bus'), findsOneWidget);
  });

  testWidgets('search is flat, debounced, and clearable', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('history-search')), 'momo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Bus'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Bus'), findsOneWidget);
  });

  testWidgets('entry rows swipe-delete with Undo', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final momo = store.transactions.firstWhere((t) => t.note == 'Momo');

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey(momo.id));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.transactions.any((t) => t.id == momo.id), isFalse);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.transactions.any((t) => t.id == momo.id), isTrue);
  });

  testWidgets('categories and events keep their management views', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final trek = await store.addProject('Trek', 'Annapurna');
    await store.addTransaction(
      type: 'expense',
      amount: 900,
      categoryId: 'travel',
      date: DateTime.now(),
      note: 'Jeep',
      projectId: trek,
    );

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Categories & budgets'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.text('Events'), findsWidgets);
    expect(find.text('Trek'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete event'), findsOneWidget);
  });

  testWidgets('sync action is wired only when the shell provides it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    var opened = 0;

    await tester.pumpWidget(shell(store, onOpenSync: () => opened++));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sync'));
    expect(opened, 1);

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sync'), findsNothing);
  });

  testWidgets('history lays out at phone and desktop widths in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();

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
