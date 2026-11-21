import 'package:expense/screens/settings_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/link_sync.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:expense/widgets/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings now mirrors Home: titled cards, tinted icon badges, accent pills
/// and a single account/avatar sheet. Actions themselves stay unchanged.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    return store;
  }

  Widget shell(ExpenseStore store, LinkEngine engine) =>
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.build(const Color(0xFF009688), Brightness.dark),
          home: SettingsScreen(engine: engine),
        ),
      );

  testWidgets('every section uses a titled card with badge rows', (tester) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final engine = LinkEngine(store);
    addTearDown(engine.stop);
    await tester.pumpWidget(shell(store, engine));
    await tester.pumpAndSettle();

    for (final title in [
      'Appearance',
      'Preferences',
      'Money',
      'Security',
      'Data',
      'Sync',
      'SMS',
      'About',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.byType(SettingsSectionTitle), findsNWidgets(8));
    expect(find.byType(SettingsCard), findsWidgets);
    expect(find.byType(SettingsIconBadge), findsWidgets);
    // Theme selector + calendar toggle + SMS mode, all accent-bound pills.
    expect(find.byType(PillSegments), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('account card opens the single avatar customization sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await readyStore();
    final engine = LinkEngine(store);
    addTearDown(engine.stop);
    await tester.pumpWidget(shell(store, engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-account-card')));
    await tester.pumpAndSettle();
    expect(find.text('Account & avatar'), findsOneWidget);
    expect(find.byKey(const Key('settings-avatar-minimal')), findsOneWidget);
    expect(find.byKey(const Key('settings-avatar-classic')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-avatar-classic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-account-save')));
    await tester.pumpAndSettle();
    expect(store.avatarStyle, 'classic');
  });
}
