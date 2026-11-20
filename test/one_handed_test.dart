import 'dart:convert';

import 'package:expense/screens/history_screen.dart';
import 'package:expense/screens/insights_screen.dart';
import 'package:expense/screens/lent_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:expense/widgets/segmented_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ExpenseStore> ready({bool oneHanded = true}) async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    if (!oneHanded) await store.setOneHanded(false);
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

  test('one-handed mode is on by default and persists an explicit choice',
      () async {
    final store = await ready();
    expect(store.oneHanded, isTrue);
    await store.setOneHanded(false);
    final reloaded = ExpenseStore();
    await reloaded.load();
    expect(reloaded.oneHanded, isFalse);
    await reloaded.setOneHanded(true);
    expect(reloaded.oneHanded, isTrue);
  });

  test('an old stored false migrates to the new default once', () async {
    SharedPreferences.setMockInitialValues({
      'expense_meta_v1': jsonEncode({'one_handed_mode': false}),
    });
    final store = ExpenseStore();
    await store.load();
    expect(store.oneHanded, isTrue);
  });

  testWidgets('History tabs move to the bottom in one-handed mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    for (final oneHanded in [false, true]) {
      final store = await ready(oneHanded: oneHanded);
      await tester.pumpWidget(shell(store, const HistoryScreen()));
      await tester.pumpAndSettle();
      final tabsY = tester.getTopLeft(find.byType(SegmentedTabs)).dy;
      if (oneHanded) {
        expect(tabsY, greaterThan(500));
      } else {
        expect(tabsY, lessThan(200));
      }
    }
  });

  testWidgets('Insights period bar moves to the bottom', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await ready(oneHanded: true);
    await tester.pumpWidget(shell(store, const InsightsScreen()));
    await tester.pumpAndSettle();
    final titleY = tester.getTopLeft(find.text('Insights')).dy;
    final tabsY = tester.getTopLeft(find.byType(SegmentedTabs)).dy;
    expect(tabsY, greaterThan(titleY));
  });

  testWidgets('Lent toggles move to the bottom', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await ready(oneHanded: true);
    await tester.pumpWidget(shell(store, const LentScreen()));
    await tester.pumpAndSettle();
    final titleY = tester.getTopLeft(find.text('Lent').first).dy;
    final tabsY = tester.getTopLeft(find.byType(SegmentedTabs).first).dy;
    expect(tabsY, greaterThan(titleY));
    expect(tester.takeException(), isNull);
  });
}
