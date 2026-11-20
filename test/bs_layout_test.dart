import 'package:expense/screens/add_screen.dart';
import 'package:expense/screens/history_screen.dart';
import 'package:expense/screens/home_screen.dart';
import 'package:expense/screens/insights_screen.dart';
import 'package:expense/screens/lent_screen.dart';
import 'package:expense/screens/menu_screen.dart';
import 'package:expense/screens/settings_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/link_sync.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Final QA: BS-mode layout at phone/desktop, light/dark and 1.3x text.
void main() {
  testWidgets('every tab survives BS mode at both sizes and 1.3x text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.setCalendarSystem('bs');
    await store.addTransaction(
      type: 'expense',
      amount: 500,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      note: 'Momo',
      mode: 'cash',
    );
    final engine = LinkEngine(store);
    addTearDown(engine.stop);

    for (final size in [const Size(360, 740), const Size(1280, 800)]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        tester.view.physicalSize = size;
        final screens = <Widget>[
          HomeScreen(onAdd: () {}, onSync: () async => 'ok'),
          const HistoryScreen(),
          const InsightsScreen(),
          const LentScreen(),
          MenuScreen(engine: engine),
          SettingsScreen(engine: engine),
          AddScreen(onSaved: () {}),
        ];
        for (final screen in screens) {
          await tester.pumpWidget(
            ChangeNotifierProvider<ExpenseStore>.value(
              value: store,
              child: MaterialApp(
                theme: AppTheme.build(const Color(0xFF009688), brightness),
                home: Scaffold(body: SafeArea(child: screen)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'BS $size ${brightness.name} $screen',
          );
        }
      }
    }
  });
}
