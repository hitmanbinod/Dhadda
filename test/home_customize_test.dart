import 'dart:convert';

import 'package:expense/analytics.dart';
import 'package:expense/format.dart';
import 'package:expense/home_layout.dart';
import 'package:expense/screens/edit_home_screen.dart';
import 'package:expense/screens/home_screen.dart';
import 'package:expense/screens/settings_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/link_sync.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 4: Home sections render in the saved order, the hide-balance eye
/// masks only the hero/stats/budget amounts, and optional sections stay off
/// until the user enables them.
void main() {
  Future<ExpenseStore> readyStore({bool withToday = false}) async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    final now = DateTime.now();
    await store.addTransaction(
      type: 'expense',
      amount: 500,
      categoryId: 'food',
      date: DateTime(now.year, now.month, 4),
      note: 'Daal',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'expense',
      amount: 300,
      categoryId: 'travel',
      date: withToday
          ? DateTime(now.year, now.month, now.day)
          : DateTime(now.year, now.month, 3),
      note: 'Bus',
      mode: 'cash',
    );
    await store.addTransaction(
      type: 'income',
      amount: 2000,
      categoryId: 'other',
      date: DateTime(now.year, now.month, 2),
      note: 'Salary',
      mode: 'bank',
    );
    await store.setBudget('food', 100);
    return store;
  }

  Widget homeShell(
    ExpenseStore store, {
    Brightness brightness = Brightness.light,
    ValueChanged<DateTime>? onOpenDay,
  }) {
    return ChangeNotifierProvider<ExpenseStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.build(const Color(0xFF009688), brightness),
        home: Scaffold(
          body: HomeScreen(
            onAdd: () {},
            onSync: () async => 'Up to date.',
            onOpenDay: onOpenDay,
          ),
        ),
      ),
    );
  }

  List<HomeSectionSetting> layoutWith({Set<HomeSection> hidden = const {}}) => [
    for (final section in HomeSection.values)
      HomeSectionSetting(section: section, visible: !hidden.contains(section)),
  ];

  group('home layout model', () {
    test('defaults preserve the current clean Home', () {
      final layout = defaultHomeLayout();
      expect(layout.first.section, HomeSection.balance);
      expect(layout.first.visible, isTrue);
      for (final section in [
        HomeSection.stats,
        HomeSection.categories,
        HomeSection.budgets,
        HomeSection.events,
        HomeSection.recent,
      ]) {
        expect(
          layout.firstWhere((s) => s.section == section).visible,
          isTrue,
          reason: section.id,
        );
      }
      for (final section in [
        HomeSection.todayRing,
        HomeSection.rhythm,
        HomeSection.forecast,
      ]) {
        expect(
          layout.firstWhere((s) => s.section == section).visible,
          isFalse,
          reason: section.id,
        );
      }
    });

    test('saved layout decodes as stored; fresh layout shows Events', () {
      final savedOff = decodeHomeLayout(encodeHomeLayout([
        const HomeSectionSetting(section: HomeSection.balance, visible: true),
        const HomeSectionSetting(section: HomeSection.events, visible: false),
      ]));
      expect(
        savedOff.firstWhere((s) => s.section == HomeSection.events).visible,
        isFalse,
      );
      expect(
        defaultHomeLayout()
            .firstWhere((s) => s.section == HomeSection.events)
            .visible,
        isTrue,
      );
    });

    test('store migrates an old Events-off layout once', () async {
      final oldLayout = encodeHomeLayout(layoutWith(
        hidden: const {HomeSection.events},
      ));
      SharedPreferences.setMockInitialValues({
        'expense_meta_v1': jsonEncode({'home_layout_v1': oldLayout}),
      });
      final store = ExpenseStore();
      await store.load();
      expect(
        store.homeLayout
            .firstWhere((s) => s.section == HomeSection.events)
            .visible,
        isTrue,
      );
      await store.setHomeLayout(layoutWith(
        hidden: const {HomeSection.events},
      ));
      final reloaded = ExpenseStore();
      await reloaded.load();
      expect(
        reloaded.homeLayout
            .firstWhere((s) => s.section == HomeSection.events)
            .visible,
        isFalse,
      );
    });

    test('normalize pins balance and appends missing sections hidden', () {
      final normalized = normalizeHomeLayout([
        const HomeSectionSetting(section: HomeSection.forecast, visible: true),
        const HomeSectionSetting(section: HomeSection.stats, visible: false),
        const HomeSectionSetting(section: HomeSection.stats, visible: true),
      ]);
      expect(normalized.first.section, HomeSection.balance);
      expect(normalized[1].section, HomeSection.forecast);
      expect(normalized[1].visible, isTrue);
      final stats = normalized.where((s) => s.section == HomeSection.stats);
      expect(stats.length, 1);
      expect(stats.single.visible, isFalse);
      expect(
        normalized
            .firstWhere((s) => s.section == HomeSection.todayRing)
            .visible,
        isFalse,
      );
      expect(normalized.length, HomeSection.values.length);
    });

    test('encode/decode round-trip ignores unknown ids and corrupt data', () {
      final layout = layoutWith(hidden: {HomeSection.stats});
      final raw = encodeHomeLayout(layout);
      expect(decodeHomeLayout(raw), layout);

      final withUnknown = decodeHomeLayout(
        jsonEncode([
          {'id': 'balance', 'visible': true},
          {'id': 'not-a-section', 'visible': true},
          {'id': 'stats', 'visible': false},
        ]),
      );
      expect(withUnknown.first.section, HomeSection.balance);
      expect(
        withUnknown.firstWhere((s) => s.section == HomeSection.stats).visible,
        isFalse,
      );
      expect(
        withUnknown.firstWhere((s) => s.section == HomeSection.rhythm).visible,
        isFalse,
      );
      expect(decodeHomeLayout('{nope'), defaultHomeLayout());
      expect(decodeHomeLayout(''), defaultHomeLayout());
    });

    test('move uses onReorderItem indices and never moves balance', () {
      final layout = defaultHomeLayout();
      final moved = moveHomeSectionInLayout(layout, 1, 3);
      expect(moved.map((s) => s.section).toList(), [
        HomeSection.balance,
        HomeSection.categories,
        HomeSection.budgets,
        HomeSection.stats,
        HomeSection.events,
        HomeSection.recent,
        HomeSection.todayRing,
        HomeSection.rhythm,
        HomeSection.forecast,
      ]);
      final above = moveHomeSectionInLayout(layout, 2, 0);
      expect(above.map((s) => s.section).take(3).toList(), [
        HomeSection.balance,
        HomeSection.categories,
        HomeSection.stats,
      ]);
      expect(
        moveHomeSectionInLayout(layout, 0, 4).map((s) => s.section).toList(),
        layout.map((s) => s.section).toList(),
      );
    });
  });

  group('home prefs', () {
    test(
      'hide-balance and layout persist per device without touching sync',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = ExpenseStore();
        await store.load();
        final beforeUpdatedAt = store.updatedAt;
        expect(store.hideBalance, isFalse);
        expect(store.homeLayout, defaultHomeLayout());

        await store.setHideBalance(true);
        final reordered = layoutWith(hidden: {HomeSection.recent});
        await store.setHomeLayout(reordered);
        expect(store.updatedAt, beforeUpdatedAt);

        final prefs = await SharedPreferences.getInstance();
        final meta = jsonDecode(
          prefs.getString('expense_meta_v1')!,
        ) as Map<String, dynamic>;
        expect(meta['hideBalance'], isTrue);
        expect(meta['home_layout_v1'], isA<String>());

        final reloaded = ExpenseStore();
        await reloaded.load();
        expect(reloaded.hideBalance, isTrue);
        expect(reloaded.homeLayout, reordered);

        await reloaded.resetHomeLayout();
        expect(reloaded.homeLayout, defaultHomeLayout());
      },
    );
  });

  group('Home UI', () {
    testWidgets('eye masks hero, stats and budgets, not lists', (tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore();

      await tester.pumpWidget(homeShell(store));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Balance ${money(1200)}'),
        findsOneWidget,
      );
      expect(find.byTooltip('Hide balance'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-balance-eye')));
      await tester.pumpAndSettle();

      expect(store.hideBalance, isTrue);
      expect(
        find.bySemanticsLabel('Balance ${money(1200)}'),
        findsNothing,
      );
      // Hero and three stat cells mask; the budget line masks too. Category
      // and entry amounts stay visible.
      expect(find.text(hiddenMoney()), findsNWidgets(4));
      expect(find.textContaining('Over by ${hiddenMoney()}'), findsOneWidget);
      // Spotlight and category row both keep their amounts: only the hero,
      // stats and budget lines mask.
      expect(find.text(money(500)), findsNWidgets(2));
      expect(find.byTooltip('Show balance'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-balance-eye')));
      await tester.pumpAndSettle();
      expect(store.hideBalance, isFalse);
      expect(
        find.bySemanticsLabel('Balance ${money(1200)}'),
        findsOneWidget,
      );
    });

    testWidgets('default Home stays clean and opens Edit Home', (tester) async {
      tester.view.physicalSize = const Size(420, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore();

      await tester.pumpWidget(homeShell(store));
      await tester.pumpAndSettle();
      expect(find.text('Daily rhythm'), findsNothing);
      expect(find.text('Forecast'), findsNothing);
      expect(find.text('Today'), findsNothing);

      final edit = find.byKey(const Key('home-edit-layout'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit-home-balance')), findsOneWidget);
      final balanceSwitch = tester.widget<Switch>(
        find.byKey(const Key('edit-home-switch-balance')),
      );
      expect(balanceSwitch.value, isTrue);
      expect(balanceSwitch.onChanged, isNull);
    });

    testWidgets('saved order and visibility apply to Home', (tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore(withToday: true);
      await store.setHomeLayout([
        const HomeSectionSetting(section: HomeSection.balance, visible: true),
        const HomeSectionSetting(section: HomeSection.recent, visible: true),
        const HomeSectionSetting(
          section: HomeSection.categories,
          visible: true,
        ),
        const HomeSectionSetting(section: HomeSection.stats, visible: false),
        const HomeSectionSetting(section: HomeSection.budgets, visible: false),
        const HomeSectionSetting(section: HomeSection.events, visible: false),
        const HomeSectionSetting(section: HomeSection.todayRing, visible: true),
        const HomeSectionSetting(section: HomeSection.rhythm, visible: true),
        const HomeSectionSetting(section: HomeSection.forecast, visible: true),
      ]);

      await tester.pumpWidget(homeShell(store));
      await tester.pumpAndSettle();

      expect(find.text('Spent'), findsNothing);
      expect(find.text('Budgets'), findsNothing);
      expect(find.text('Daily rhythm'), findsOneWidget);
      expect(find.text('Forecast'), findsOneWidget);
      // Section header plus the card's own label.
      expect(find.text('Today'), findsNWidgets(2));
      expect(find.byKey(const Key('home-today-card')), findsOneWidget);
      expect(find.byKey(const Key('home-forecast-card')), findsOneWidget);

      final recentY = tester.getTopLeft(find.text('Recent')).dy;
      final categoriesY = tester.getTopLeft(find.text('By category')).dy;
      expect(recentY, lessThan(categoriesY));

      // The today section has a budget and a spend dated today, so it can
      // show a real left/over footnote.
      expect(find.textContaining('today'), findsWidgets);
    });

    testWidgets('rhythm tap opens that day in History', (tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore();
      await store.setHomeLayout(
        layoutWith().map((s) {
          return s.section == HomeSection.rhythm
              ? s.copyWith(visible: true)
              : s;
        }).toList(),
      );
      DateTime? opened;
      await tester.pumpWidget(
        homeShell(store, onOpenDay: (day) => opened = day),
      );
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('home-rhythm-chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      final rect = tester.getRect(chart);
      final now = DateTime.now();
      final days = daysInMonth(now);
      await tester.tapAt(
        Offset(rect.left + rect.width * (3.5 / days), rect.center.dy),
      );
      await tester.pump();
      expect(opened, DateTime(now.year, now.month, 4));
    });

    testWidgets('Edit Home toggles live and resets to default', (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore();
      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: MaterialApp(
            theme: AppTheme.build(const Color(0xFF009688), Brightness.light),
            home: const EditHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit-home-switch-stats')));
      await tester.pumpAndSettle();
      expect(
        store.homeLayout
            .firstWhere((s) => s.section == HomeSection.stats)
            .visible,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('edit-home-reset')));
      await tester.pumpAndSettle();
      expect(store.homeLayout, defaultHomeLayout());
      expect(find.text('Home reset to default.'), findsOneWidget);
    });

    testWidgets('Settings exposes the hide switch and Edit Home row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore();
      final engine = LinkEngine(store);
      addTearDown(engine.stop);

      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: MaterialApp(
            theme: AppTheme.build(const Color(0xFF009688), Brightness.light),
            home: SettingsScreen(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Shown in the home'), findsNothing);
      expect(find.textContaining('Shown in your Home'), findsNothing);
      final classic = find.byKey(const Key('settings-avatar-classic'));
      await tester.ensureVisible(classic);
      await tester.pumpAndSettle();
      await tester.tap(classic);
      await tester.pumpAndSettle();
      expect(store.avatarStyle, 'classic');

      final hide = find.byKey(const Key('settings-hide-balance'));
      await tester.ensureVisible(hide);
      await tester.pumpAndSettle();
      await tester.tap(hide);
      await tester.pumpAndSettle();
      expect(store.hideBalance, isTrue);

      final edit = find.byKey(const Key('settings-edit-home'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-home-balance')), findsOneWidget);
    });

    testWidgets('all sections lay out at phone/desktop in both themes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await readyStore(withToday: true);
      await store.setHomeLayout(layoutWith());
      final now = DateTime.now();
      final trek = await store.addProject('Trek', 'Annapurna');
      await store.addTransaction(
        type: 'expense',
        amount: 700,
        categoryId: 'travel',
        date: DateTime(now.year, now.month, 5),
        note: 'Jeep',
        projectId: trek,
      );

      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final size in [const Size(360, 740), const Size(1280, 800)]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(homeShell(store, brightness: brightness));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$size ${brightness.name}',
          );
        }
      }
    });
  });
}
