import 'package:expense/screens/home_screen.dart';
import 'package:expense/screens/insights_screen.dart';
import 'package:expense/screens/settings_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/link_sync.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 3 widget coverage: the BS switch, the Home pager and the built-in
/// BS date picker. AD mode is covered by the unchanged Round 1 suite.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.addTransaction(
      type: 'expense',
      amount: 250,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      note: 'Momo',
      mode: 'cash',
    );
    return store;
  }

  Widget shell(ExpenseStore store, Widget child) =>
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.build(const Color(0xFF009688), Brightness.light),
          home: Scaffold(body: SafeArea(child: child)),
        ),
      );

  String monthLabel(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(const Key('home-month-label')));
    return text.data ?? text.textSpan!.toPlainText();
  }

  testWidgets('BS pager swipes between months and keeps AD dates stored', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    await store.setCalendarSystem('bs');
    await tester.pumpWidget(
      shell(store, HomeScreen(onAdd: () {}, onSync: () async => 'ok')),
    );
    await tester.pumpAndSettle();

    expect(monthLabel(tester), 'Mangsir 2083');
    final title = find.byKey(const Key('home-month-title'));
    final center = tester.getCenter(title);
    await tester.dragFrom(center + const Offset(60, 0), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(monthLabel(tester), 'Poush 2083');
    await tester.dragFrom(center - const Offset(60, 0), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(monthLabel(tester), 'Mangsir 2083');

    // Data stays Gregorian: the entry's stored date is untouched.
    expect(store.transactions.single.date, DateTime(2026, 11, 20).millisecondsSinceEpoch);
  });

  testWidgets('tapping the month opens the built-in BS picker', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    await store.setCalendarSystem('bs');
    await tester.pumpWidget(
      shell(store, HomeScreen(onAdd: () {}, onSync: () async => 'ok')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-month-title')));
    await tester.pumpAndSettle();
    expect(find.text('Jump to month'), findsOneWidget);
    expect(find.text('Mangsir'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Kartik').last);
    await tester.pumpAndSettle();
    expect(find.text('Kartik 2083'), findsWidgets);
  });

  testWidgets('Insights fiscal chip works in both calendar modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    for (final mode in ['ad', 'bs']) {
      final store = await readyStore();
      await store.setCalendarSystem(mode);
      await tester.pumpWidget(shell(store, const InsightsScreen()));
      await tester.pumpAndSettle();

      final chip = find.bySemanticsLabel('Fiscal year');
      expect(chip, findsOneWidget, reason: mode);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.textContaining('FY 2083/84'), findsWidgets, reason: mode);
      expect(tester.takeException(), isNull, reason: mode);
    }
  });

  testWidgets('Settings toggles AD/BS and persists the choice', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final engine = LinkEngine(store);
    addTearDown(engine.stop);
    await tester.pumpWidget(shell(store, SettingsScreen(engine: engine)));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Calendar data for 2084 onward is an estimate and may be corrected '
        'in an update.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('settings-calendar-bs')));
    await tester.pumpAndSettle();
    expect(store.calendarSystem, 'bs');

    final reloaded = ExpenseStore();
    await reloaded.load();
    expect(reloaded.calendarSystem, 'bs');
    await reloaded.setCalendarSystem('ad');
    expect(reloaded.calendarSystem, 'ad');
  });
}
