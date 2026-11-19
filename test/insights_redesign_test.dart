import 'package:expense/format.dart';
import 'package:expense/screens/insights_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Insights: period switch, hero summary, category ring, rhythm
/// bars, loan snapshot, lazy largest-expense rows, and settings shortcut.
void main() {
  Future<ExpenseStore> readyStore({String? currency}) async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.setUserName('Ram');
    final now = DateTime.now();
    DateTime day(int monthsAgo, int d) =>
        DateTime(now.year, now.month - monthsAgo, d, 12);

    await store.addTransaction(
      type: 'expense',
      amount: 500,
      categoryId: 'food',
      date: day(0, 4),
      note: 'Momo',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'expense',
      amount: 300,
      categoryId: 'travel',
      date: day(0, 3),
      note: 'Bus',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'income',
      amount: 2000,
      categoryId: 'other',
      date: day(0, 2),
      note: 'Salary',
      mode: 'bank',
    );
    await store.addTransaction(
      type: 'expense',
      amount: 1000,
      categoryId: 'shopping',
      date: day(1, 5),
      note: 'Jacket',
      mode: 'card',
    );
    if (currency != null) await store.setCurrency(currency);
    return store;
  }

  Widget shell(
    ExpenseStore store, {
    Brightness brightness = Brightness.light,
    VoidCallback? onOpenSettings,
  }) {
    return ChangeNotifierProvider<ExpenseStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.build(const Color(0xFF009688), brightness),
        home: Scaffold(body: InsightsScreen(onOpenSettings: onOpenSettings)),
      ),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester,
    ExpenseStore store, {
    Size size = const Size(420, 1600),
    Brightness brightness = Brightness.light,
    VoidCallback? onOpenSettings,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      shell(store, brightness: brightness, onOpenSettings: onOpenSettings),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('month summary, ring, rhythm, loans, and period switch', (
    tester,
  ) async {
    final store = await readyStore();
    var settings = 0;
    await pumpApp(tester, store, onOpenSettings: () => settings++);
    expect(tester.takeException(), isNull);

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Your money at a glance'), findsOneWidget);
    expect(find.text('Ram'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    expect(settings, 1);

    // Hero: 800 spent, 2000 income, 1200 net, 20% less than last month.
    expect(find.text('Spent this month'), findsOneWidget);
    expect(find.text(money(800)), findsWidgets);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text(money(2000)), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(find.text(money(1200)), findsOneWidget);
    expect(find.text('Daily average'), findsOneWidget);
    expect(find.text('20% less than last month'), findsOneWidget);

    // Category ring + legend + rhythm + loan snapshot.
    expect(find.text('Where it went'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('63%'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
    expect(find.text('Monthly rhythm'), findsOneWidget);
    expect(find.text('Last 6 months'), findsOneWidget);
    expect(find.text('Money on loan'), findsOneWidget);
    expect(find.text('To receive'), findsOneWidget);
    expect(find.text('To return'), findsOneWidget);
    expect(find.text('Not counted as spending.'), findsOneWidget);
    expect(find.text('Largest expenses'), findsOneWidget);

    // The chart exposes a readable category summary to screen readers.
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('Spending by category')),
      findsOneWidget,
    );
    semantics.dispose();

    // Switch to the quarter: 1800 spent, shopping leads the ring.
    await tester.tap(find.text('3 months'));
    await tester.pumpAndSettle();
    expect(find.text('Spent in the last 3 months'), findsOneWidget);
    expect(find.text(money(1800)), findsWidgets);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('No previous spending to compare.'), findsOneWidget);

    // Six months is its own window, with its own comparison copy.
    await tester.tap(find.text('6 months'));
    await tester.pumpAndSettle();
    expect(find.text('Spent in the last 6 months'), findsOneWidget);

    // And the trailing year.
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('Spent in the last 12 months'), findsOneWidget);
    expect(find.text('Last 12 months'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Largest expenses include the current and previous month.
    final momo = store.transactions.firstWhere((t) => t.note == 'Momo');
    final bus = store.transactions.firstWhere((t) => t.note == 'Bus');
    await tester.scrollUntilVisible(
      find.byKey(Key('insights-expense-${bus.id}')),
      250,
    );
    expect(find.byKey(Key('insights-expense-${momo.id}')), findsOneWidget);
    expect(find.byKey(Key('insights-expense-${bus.id}')), findsOneWidget);
  });

  testWidgets('empty period shows a quiet state and keeps the loan snapshot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await pumpApp(tester, store, size: const Size(400, 1200));

    expect(find.text('No activity in this period.'), findsOneWidget);
    expect(find.text('Money on loan'), findsOneWidget);
    expect(find.text('Largest expenses'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('No activity in this period.'), findsOneWidget);
  });

  testWidgets('currency follows the store, never a hard-coded symbol', (
    tester,
  ) async {
    final store = await readyStore(currency: 'USD');
    await pumpApp(tester, store);
    expect(find.text(money(800)), findsWidgets);
    expect(find.textContaining('\u0930\u0942'), findsNothing);
  });

  testWidgets('lays out at phone and desktop in both themes, all periods', (
    tester,
  ) async {
    final store = await readyStore();
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final size in [const Size(360, 740), const Size(1280, 800)]) {
        await pumpApp(tester, store, size: size, brightness: brightness);
        expect(
          tester.takeException(),
          isNull,
          reason: '$size ${brightness.name}',
        );
        for (final label in ['Month', '3 months', '6 months', 'Year']) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$label at $size ${brightness.name}',
          );
        }
      }
    }
  });
}
