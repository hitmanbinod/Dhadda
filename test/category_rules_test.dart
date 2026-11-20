import 'package:expense/category_rules.dart';
import 'package:expense/screens/add_screen.dart';
import 'package:expense/screens/category_rules_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 5: ordered, per-device note rules with a pure matching core.
void main() {
  const ids = {'food', 'travel', 'other'};
  CategoryRule rule(String id, String text, String categoryId,
          {CategoryRuleType type = CategoryRuleType.any, bool enabled = true}) =>
      CategoryRule(
        id: id,
        text: text,
        categoryId: categoryId,
        type: type,
        enabled: enabled,
      );

  CategoryRule? match(List<CategoryRule> rules, String note,
          {String type = 'expense', Set<String> valid = ids}) =>
      matchCategoryRule(
        rules,
        note: note,
        type: type,
        validCategoryIds: valid,
      );

  group('matching core', () {
    test('first enabled rule wins, order matters', () {
      final rules = [
        rule('1', 'momo', 'food'),
        rule('2', 'momo', 'travel'),
        rule('3', 'momo', 'other', enabled: false),
      ];
      expect(match(rules, 'Momo')?.categoryId, 'food');
      expect(
        match([rule('2', 'momo', 'travel'), rule('1', 'momo', 'food')], 'momo')
            ?.categoryId,
        'travel',
      );
      expect(
        match([rule('1', 'momo', 'food', enabled: false), rules[1]], 'momo')
            ?.categoryId,
        'travel',
      );
    });

    test('case, inner whitespace and substring matching', () {
      final rules = [rule('1', 'momo', 'food')];
      expect(match(rules, '  MOMO  '), isNotNull);
      expect(match(rules, 'momo   special'), isNotNull);
      expect(match(rules, 'extraMomodinner'), isNotNull);
      expect(match(rules, 'mom'), isNull);
    });

    test('type filter and empty/one-character notes', () {
      final rules = [
        rule('1', 'momo', 'food', type: CategoryRuleType.expense),
        rule('2', 'salary', 'other', type: CategoryRuleType.income),
      ];
      expect(match(rules, 'momo', type: 'expense')?.categoryId, 'food');
      expect(match(rules, 'momo', type: 'income'), isNull);
      expect(match(rules, 'salary', type: 'income')?.categoryId, 'other');
      expect(match(rules, 'a'), isNull);
      expect(match(rules, ''), isNull);
      expect(match([rule('x', 'a', 'food')], 'abc'), isNull);
    });

    test('deleted category disables but does not delete the rule', () {
      final rules = [rule('1', 'momo', 'travel')];
      expect(match(rules, 'momo', valid: {'food'}), isNull);
      // A renamed category keeps its id, so the rule still matches.
      expect(match(rules, 'momo', valid: {'travel'}), isNotNull);
    });

    test('Unicode notes and encode/decode round-trip', () {
      final rules = [
        rule('1', ' chai ', 'food'),
        rule('2', 'दाल भात', 'food'),
      ];
      expect(match(rules, 'CHAI at 5')?.categoryId, 'food');
      expect(match(rules, 'दाल   भात')?.categoryId, 'food');
      expect(decodeCategoryRules(encodeCategoryRules(rules)), rules);
      expect(decodeCategoryRules('{nope'), isEmpty);
      expect(decodeCategoryRules(null), isEmpty);
    });

    test('reorder clamps and preserves all rules', () {
      final rules = [
        rule('1', 'a', 'food'),
        rule('2', 'b', 'travel'),
        rule('3', 'c', 'other'),
      ];
      expect(
        moveCategoryRule(rules, 0, 2).map((r) => r.id),
        ['2', '3', '1'],
      );
      expect(moveCategoryRule(rules, 5, 0), rules);
    });
  });

  group('store persistence', () {
    Future<ExpenseStore> ready() async {
      SharedPreferences.setMockInitialValues({});
      final store = ExpenseStore();
      await store.load();
      await store.addTransaction(
        type: 'expense',
        amount: 100,
        categoryId: 'travel',
        date: DateTime(2026, 11, 20),
        note: 'Momo',
        mode: 'cash',
      );
      return store;
    }

    test('rules are additive prefs and never applied retroactively', () async {
      final store = await ready();
      final before = store.updatedAt;
      await store.addCategoryRule(text: 'momo', categoryId: 'food');
      expect(store.updatedAt, before);
      expect(store.transactions.single.categoryId, 'travel');
      expect(store.categoryRuleFor('Momo', 'expense')?.categoryId, 'food');

      final reloaded = ExpenseStore();
      await reloaded.load();
      expect(reloaded.categoryRules.single.text, 'momo');
      expect(reloaded.categoryRules.single.categoryId, 'food');
    });

    testWidgets('Add suggests a rule chip without changing the category', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final store = await ready();
      await store.addCategoryRule(text: 'momo', categoryId: 'food');
      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: MaterialApp(home: AddScreen(onSaved: () {})),
        ),
      );
      await tester.pumpAndSettle();
      final noteField = find.byType(TextField).last;
      await tester.enterText(noteField, 'Momo special');
      await tester.pumpAndSettle();
      final chip = find.byKey(const Key('add-category-suggestion'));
      expect(chip, findsOneWidget);
      expect(find.text('Food?'), findsOneWidget);
      expect(store.transactions.single.categoryId, 'travel');

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-category-suggestion')), findsNothing);
    });

    testWidgets('rules screen lists, toggles and tests rules', (tester) async {
      final store = await ready();
      await store.addCategoryRule(text: 'momo', categoryId: 'food');
      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseStore>.value(
          value: store,
          child: const MaterialApp(home: CategoryRulesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rules are saved on this phone only.'), findsOneWidget);
      expect(find.byKey(const Key('rules-test')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('rules-test')), 'momo');
      await tester.pumpAndSettle();
      expect(find.text('Matches: Food'), findsOneWidget);
    });
  });
}
