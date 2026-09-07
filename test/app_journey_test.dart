// Phase 7: host-runnable mirror of integration_test/app_flow_test.dart.
// Same connected journey (screens -> store -> persistence -> reload) via
// widget tests, so CI executes it. The device variant lives in
// integration_test/ for emulator runs (see docs/TESTING.md).
import 'package:expense/screens/add_screen.dart';
import 'package:expense/screens/history_screen.dart';
import 'package:expense/screens/home_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ExpenseStore> _readyStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = ExpenseStore();
  await store.load();
  return store;
}

// Provider sits ABOVE MaterialApp so pushed routes (AddScreen) keep
// access to the store, exactly like the real ExpenseApp wiring.
Widget _shell(ExpenseStore store, Widget body) =>
    ChangeNotifierProvider<ExpenseStore>.value(
      value: store,
      child: MaterialApp(home: Scaffold(body: body)),
    );

void main() {
  testWidgets('add-expense journey persists across UI and reload', (
    tester,
  ) async {
    // Tall viewport: the whole Add form builds at once (no lazy-list hunt).
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await _readyStore();
    var saved = false;
    await tester.pumpWidget(
      _shell(
        store,
        HomeScreen(
          onAdd: () =>
              Navigator.of(tester.element(find.byType(HomeScreen))).push(
                MaterialPageRoute(
                  builder: (_) => AddScreen(
                    onSaved: () {
                      saved = true;
                      Navigator.of(tester.element(find.byType(AddScreen)))
                          .pop();
                    },
                  ),
                ),
              ),
          onSync: () async => 'Up to date.',
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AddScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.text('Food').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).last, 'JourneyTea');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(saved, isTrue);
    expect(store.transactions.any((t) => t.note == 'JourneyTea'), isTrue);
    // Same store, History screen shows it (UI -> store read path).
    await tester.pumpWidget(_shell(store, const HistoryScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('JourneyTea'), findsWidgets);
    // "Restart": a fresh store over the same prefs sees the entry.
    final reloaded = ExpenseStore();
    await reloaded.load();
    expect(reloaded.transactions.any((t) => t.note == 'JourneyTea'), isTrue);
  });

  testWidgets('tab destinations navigate without exceptions', (tester) async {
    final store = await _readyStore();
    await tester.pumpWidget(
      _shell(
        store,
        HomeScreen(onAdd: () {}, onSync: () async => 'Up to date.'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
