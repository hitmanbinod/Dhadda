import 'package:expense/format.dart';
import 'package:expense/screens/lent_screen.dart';
import 'package:expense/screens/settings_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/link_sync.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 5: Lent uses grouped, animated cards; Settings is grouped lists with
/// a destructive Erase row at the bottom.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.addLoan(
      person: 'Sita',
      amount: 5000,
      date: DateTime.now().subtract(const Duration(days: 10)),
      note: 'Rent share',
    );
    await store.addRepayment(
      store.loans.first.id,
      2000,
      DateTime.now().subtract(const Duration(days: 2)),
      '',
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

  testWidgets('Lent card expands and collapses without leaving a gap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    await tester.pumpWidget(shell(store, const LentScreen()));
    await tester.pumpAndSettle();

    final header = find.byKey(Key('loan-header-${store.loans.first.id}'));
    expect(header, findsOneWidget);
    expect(find.text('Lent ${money(5000)}'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('Lent ${money(5000)}'), findsOneWidget);
    expect(find.text('Note: Rent share'), findsOneWidget);
    expect(find.text('Returned ${money(2000)}'), findsOneWidget);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('Lent ${money(5000)}'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lent summary fits at a narrow web width', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    await tester.pumpWidget(shell(store, const LentScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(Key('account-delete-${store.loans.first.id}')), findsNothing);
    expect(find.text('To receive'), findsOneWidget);
  });

  testWidgets('Settings shows grouped lists with Erase at the bottom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final engine = LinkEngine(store);
    addTearDown(engine.stop);
    await tester.pumpWidget(shell(store, SettingsScreen(engine: engine)));
    await tester.pumpAndSettle();

    for (final group in [
      'Appearance',
      'Money',
      'Security',
      'Data',
      'Sync',
      'SMS',
      'About',
    ]) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    final erase = find.text('Erase all data');
    expect(erase, findsOneWidget);
    final aboutY = tester.getTopLeft(find.text('About')).dy;
    expect(tester.getTopLeft(erase).dy, greaterThan(aboutY));
  });
}
