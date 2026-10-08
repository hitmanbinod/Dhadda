import 'package:expense/screens/add_screen.dart';
import 'package:expense/screens/database_problem_screen.dart';
import 'package:expense/screens/history_screen.dart';
import 'package:expense/screens/home_screen.dart';
import 'package:expense/screens/lent_screen.dart';
import 'package:expense/screens/lock_screen.dart';
import 'package:expense/screens/menu_screen.dart';
import 'package:expense/screens/sync_screen.dart';
import 'package:expense/security.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/link_sync.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps every screen at phone + desktop widths and fails on any
/// layout exception (overflow, unbounded height, missing direction).
/// This is the automated padding/spacing audit.
Future<ExpenseStore> _readyStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = ExpenseStore();
  await store.load();
  await store.addTransaction(
      type: 'expense',
      amount: 500,
      categoryId: 'food',
      date: DateTime(2026, 9, 4),
      note: 'Daal',
      mode: 'cash');
  await store.addLoan(
      person: 'Sandesh', amount: 1000, date: DateTime(2026, 9, 3));
  return store;
}

Future<void> _pumpScreen(
    WidgetTester tester, ExpenseStore store, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('all screens lay out cleanly on a phone (360x740)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await _readyStore();
    final engine = LinkEngine(store);

    await _pumpScreen(
        tester,
        store,
        HomeScreen(
            onAdd: () {}, onSync: () async => 'Up to date.'));
    await _pumpScreen(tester, store, const HistoryScreen());
    await _pumpScreen(tester, store, const LentScreen());
    await _pumpScreen(tester, store, MenuScreen(engine: engine));
    await _pumpScreen(
        tester, store, SyncScreen(engine: engine));
    await _pumpScreen(
        tester,
        store,
        AddScreen(onSaved: () {}));
    await _pumpScreen(
        tester,
        store,
        LockScreen(
            vault: PinVault(
                await SharedPreferences.getInstance()),
            onUnlock: () {}));
    await _pumpScreen(
        tester,
        store,
        DatabaseProblemScreen(
          message: "Dhadda couldn't open the file holding your transactions.",
          onRetry: () {},
          onStartEmpty: () {},
        ));
    engine.stop();
  });

  testWidgets('the recovery screen offers both ways out and reports the tap',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    var retried = 0;
    var startedEmpty = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseProblemScreen(
          message: "Dhadda couldn't open the file holding your transactions.",
          onRetry: () => retried++,
          onStartEmpty: () => startedEmpty++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The user must be able to tell what happened and that nothing was lost.
    expect(find.text('Your data could not be opened'), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retried, 1);

    await tester.tap(find.text('Start with an empty tracker'));
    await tester.pumpAndSettle();
    expect(startedEmpty, 1);
  });

  testWidgets('home + history lay out cleanly on desktop (1280x800)',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await _readyStore();
    await _pumpScreen(
        tester,
        store,
        HomeScreen(
            onAdd: () {}, onSync: () async => 'Up to date.'));
    await _pumpScreen(tester, store, const HistoryScreen());
  });
}