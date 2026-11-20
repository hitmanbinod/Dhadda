import 'package:expense/screens/history_screen.dart';
import 'package:expense/screens/home_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Event-tagged entries collect under one collapsible branch per event:
/// expanded in the History entries list (tap the event to collapse), and
/// collapsed by default in a Home "Events" section.
void main() {
  Future<ExpenseStore> storeWithEvent() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    // Home defaults to the current month, so fixtures must live there or
    // the Events section is empty once the calendar rolls over.
    final now = DateTime.now();
    final trekId = await store.addProject('Trek', 'Annapurna');
    await store.addTransaction(
        type: 'expense',
        amount: 700,
        categoryId: 'travel',
        date: DateTime(now.year, now.month, 11, 9),
        note: 'Jeep to Besisahar',
        projectId: trekId);
    await store.addTransaction(
        type: 'expense',
        amount: 250,
        categoryId: 'food',
        date: DateTime(now.year, now.month, 10, 13),
        note: 'Momo',
        projectId: trekId);
    await store.addTransaction(
        type: 'expense',
        amount: 900,
        categoryId: 'rent',
        date: DateTime(now.year, now.month, 12),
        note: 'Monthly rent');
    return store;
  }

  Widget app(ExpenseStore store, Widget body) =>
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(home: Scaffold(body: body)),
      );

  testWidgets('History entries collect event entries under one branch',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await storeWithEvent();

    await tester.pumpWidget(app(store, const HistoryScreen()));
    await tester.pumpAndSettle();

    // Both event entries live inside the group; the header appears once.
    expect(find.text('Trek'), findsOneWidget);
    expect(find.text('Jeep to Besisahar'), findsOneWidget);
    expect(find.text('Momo'), findsOneWidget);
    // The untagged entry stays chronological, outside the branch.
    expect(find.text('Monthly rent'), findsOneWidget);
    expect(find.textContaining('rent  -  Rent'), findsNothing);

    // Tapping the event header collapses the branch.
    await tester.tap(find.text('Trek'));
    await tester.pumpAndSettle();
    expect(find.text('Jeep to Besisahar'), findsNothing);
    expect(find.text('Momo'), findsNothing);
    expect(find.text('Trek'), findsOneWidget);

    // Tapping again re-opens it.
    await tester.tap(find.text('Trek'));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);
  });

  testWidgets('Home shows every tagged event for the month by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await storeWithEvent();
    // A second event proves the section lists all of them, not just one.
    final outingId = await store.addProject('Outing', 'Day trip');
    await store.addTransaction(
      type: 'expense',
      amount: 300,
      categoryId: 'travel',
      date: DateTime(DateTime.now().year, DateTime.now().month, 13, 8),
      note: 'Cab',
      projectId: outingId,
    );
    // No setHomeLayout: Events is visible by default now.

    await tester.pumpWidget(app(
        store,
        HomeScreen(
            onAdd: () {}, onSync: () async => 'Up to date.')));
    await tester.pumpAndSettle();

    // Collapsed by default: both headers visible, entries hidden.
    expect(find.text('Events'), findsWidgets);
    expect(find.text('Trek'), findsOneWidget);
    expect(find.text('Outing'), findsOneWidget);
    expect(find.text('Momo'), findsNothing);

    // Tap to expand the branch.
    await tester.tap(find.text('Trek'));
    await tester.pumpAndSettle();
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Jeep to Besisahar'), findsOneWidget);
  });
}
