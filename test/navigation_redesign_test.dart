import 'package:expense/main.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:expense/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 1 shell: Home / Insights / History / Lent, a pushed Settings route,
/// and the profile shortcut. Every tab is laid out at phone and wide widths
/// in both themes.
void main() {
  Future<ExpenseStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.setUserName('Ram');
    final now = DateTime.now();
    await store.addTransaction(
      type: 'expense',
      amount: 250,
      categoryId: 'food',
      date: DateTime(now.year, now.month, 4, 12),
      note: 'Momo',
      mode: 'cash',
    );
    return store;
  }

  Widget shell(ExpenseStore store, Brightness brightness) {
    return ChangeNotifierProvider<ExpenseStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.build(const Color(0xFF009688), brightness),
        home: const RootShell(),
      ),
    );
  }

  Finder navLabel(String label) {
    final bar = find.byType(NavigationBar);
    final rail = find.byType(NavigationRail);
    return find.descendant(
      of: bar.evaluate().isNotEmpty ? bar : rail,
      matching: find.text(label),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester,
    ExpenseStore store, {
    Size size = const Size(360, 740),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(shell(store, brightness));
    await tester.pumpAndSettle();
  }

  testWidgets('four tabs, no Menu tab, Settings is a pushed route', (
    tester,
  ) async {
    final store = await readyStore();
    await pumpApp(tester, store);

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Home', 'Insights', 'History', 'Lent']) {
      expect(navLabel(label), findsOneWidget);
    }
    expect(navLabel('Menu'), findsNothing);

    // Insights owns a large title and the small settings avatar.
    await tester.tap(navLabel('Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Based on your data'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    // The small avatar opens Settings.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const Key('settings-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(find.text('Based on your data'), findsOneWidget);

    await tester.tap(navLabel('History'));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Lent'));
    await tester.pumpAndSettle();

    // Back to Home: the profile row opens the same route.
    await tester.tap(navLabel('Home'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.text('Ram'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-profile')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every tab lays out at 360 dp and 1280 px, light and dark', (
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
        final wide = size.width > 900;
        expect(
          wide ? find.byType(NavigationRail) : find.byType(NavigationBar),
          findsOneWidget,
        );
        for (final label in ['Insights', 'History', 'Lent', 'Home']) {
          await tester.tap(navLabel(label));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$label at $size ${brightness.name}',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('avatar initials fall back to D', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ProfileAvatar(name: ''),
              ProfileAvatar(name: 'ram'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('D'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
  });
}
