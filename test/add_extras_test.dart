import 'package:expense/models.dart';
import 'package:expense/repeat_suggestions.dart';
import 'package:expense/screens/add_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 5: Repeat chips come from frequent recent note+category pairings,
/// and the in-app keypad feeds the same strict amount field.
void main() {
  final now = DateTime(2026, 11, 19, 12);

  Txn txn({
    required String note,
    String categoryId = 'food',
    String type = 'expense',
    String mode = 'cash',
    double amount = 250,
    int daysAgo = 1,
  }) {
    return Txn(
      id: '$note-$daysAgo-$categoryId-$type',
      type: type,
      amount: amount,
      categoryId: categoryId,
      date: now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch,
      note: note,
      mode: mode,
    );
  }

  group('repeatSuggestions', () {
    test('empty history gives no chips', () {
      expect(repeatSuggestions([], now: now), isEmpty);
    });

    test('normalises notes and groups by type, category and note', () {
      final result = repeatSuggestions([
        txn(note: '  Momo  ', daysAgo: 1),
        txn(note: 'momo', daysAgo: 2),
        txn(note: 'MOMO', daysAgo: 3),
        txn(note: 'momo   again', daysAgo: 4),
        txn(note: 'Momo', categoryId: 'travel', daysAgo: 5),
        txn(note: 'Momo', type: 'income', daysAgo: 1),
      ], now: now);
      expect(result.length, 4);
      expect(result.first.note, 'Momo');
      expect(result.first.count, 3);
      expect(result[1].isExpense, isFalse);
    });

    test('ignores empty notes and entries older than 60 days', () {
      final result = repeatSuggestions([
        txn(note: '   ', daysAgo: 1),
        txn(note: 'Old', daysAgo: 61),
        txn(note: 'Fresh', daysAgo: 60),
      ], now: now);
      expect(result.map((s) => s.note), ['Fresh']);
    });

    test('most frequent first, at most four, deterministic ties', () {
      final result = repeatSuggestions([
        txn(note: 'Z', categoryId: 'a', daysAgo: 1),
        txn(note: 'A', categoryId: 'b', daysAgo: 1),
        txn(note: 'B', categoryId: 'c', daysAgo: 1),
        txn(note: 'C', categoryId: 'd', daysAgo: 1),
        txn(note: 'D', categoryId: 'e', daysAgo: 1),
        txn(note: 'E', categoryId: 'f', daysAgo: 1),
      ], now: now);
      expect(result.length, 4);
      expect(result.take(4).map((s) => s.note), ['A', 'B', 'C', 'D']);
    });
  });

  group('Add screen', () {
    Future<ExpenseStore> seededStore() async {
      SharedPreferences.setMockInitialValues({});
      final store = ExpenseStore();
      await store.load();
      for (var i = 0; i < 3; i++) {
        await store.addTransaction(
          type: 'expense',
          amount: 250,
          categoryId: 'food',
          date: now.subtract(Duration(days: i + 1)),
          note: 'Momo',
          mode: 'ewallet',
        );
      }
      return store;
    }

    testWidgets('repeat chip pre-fills the form', (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await seededStore();
      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: MaterialApp(home: AddScreen(onSaved: () {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Repeat'), findsOneWidget);
      final chip = find.byKey(const Key('add-repeat-food-Momo'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.first.controller!.text, '250');
      expect(fields.last.controller!.text, 'Momo');
      final food = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Food'),
      );
      expect(food.selected, isTrue);
    });

    testWidgets('same note in two categories gets unique repeat chips', (
      tester,
    ) async {
      final store = await seededStore();
      await store.addTransaction(
        type: 'expense',
        amount: 120,
        categoryId: 'travel',
        date: now.subtract(const Duration(days: 1)),
        note: 'Momo',
        mode: 'cash',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: MaterialApp(home: AddScreen(onSaved: () {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-repeat-food-Momo')), findsOneWidget);
      expect(find.byKey(const Key('add-repeat-travel-Momo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keypad writes strict amounts and Save stays visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await seededStore();
      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: MaterialApp(home: AddScreen(onSaved: () {})),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-keypad-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-key-7')), findsOneWidget);
      expect(find.byKey(const Key('add-save')), findsOneWidget);
      // 52 dp rows keep Save inside the viewport.
      final save = tester.getRect(find.byKey(const Key('add-save')));
      expect(save.bottom, lessThanOrEqualTo(720));

      await tester.tap(find.byKey(const Key('add-key-7')));
      await tester.tap(find.byKey(const Key('add-key-.')));
      await tester.tap(find.byKey(const Key('add-key-5')));
      await tester.tap(find.byKey(const Key('add-key-0')));
      await tester.pumpAndSettle();
      final amount = tester.widget<TextField>(find.byType(TextField).first);
      expect(amount.controller!.text, '7.50');
      // A second dot is ignored; backspace removes the last character.
      await tester.tap(find.byKey(const Key('add-key-.')));
      await tester.tap(find.byKey(const Key('add-key-back')));
      await tester.pumpAndSettle();
      expect(amount.controller!.text, '7.5');
    });
  });
}
