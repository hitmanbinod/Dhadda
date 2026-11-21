import 'package:expense/models.dart';
import 'package:expense/screens/accounts_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ExpenseStore> ready() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    return store;
  }

  Widget shell(ExpenseStore store) => ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.build(const Color(0xFF009688), Brightness.light),
          home: const AccountsScreen(),
        ),
      );

  testWidgets('delete unused account with confirm; blocked when it has entries',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await ready();
    final spare = await store.addAccount('Khalti', 'wallet');
    await store.addTransaction(
      type: 'expense',
      amount: 50,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      accountId: 'acct_cash',
    );
    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    // Unused account: delete opens a confirm.
    await tester.tap(find.byKey(Key('account-delete-$spare')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-delete-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-delete-confirm')));
    await tester.pumpAndSettle();
    expect(store.accounts.any((a) => a.id == spare), isFalse);

    // An account with entries explains why it cannot be deleted.
    await tester.tap(find.byKey(const Key('account-delete-acct_cash')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Has 1 entry'), findsOneWidget);
    expect(find.byKey(const Key('account-delete-confirm')), findsNothing);
    expect(
      find.textContaining('archive it or merge it'),
      findsOneWidget,
    );
  });

  testWidgets('archive and unarchive; last active account is guarded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await ready();
    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    // Archive a spare account via the store (guard is store-level too).
    final extra = await store.addAccount('Nabil', 'bank');
    expect(await store.archiveAccount(extra), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsOneWidget);
    expect(find.textContaining('Nabil'), findsWidgets);

    // Unarchive returns it to the active list.
    final unarchive = find.widgetWithText(TextButton, 'Unarchive').first;
    await tester.tap(unarchive);
    await tester.pumpAndSettle();
    expect(store.accountOf(extra).archived, isFalse);

    // Last active account cannot be archived.
    for (final a in [...store.accounts]) {
      if (a.id != 'acct_cash') {
        await store.updateAccount(a.copyWith(archived: true));
      }
    }
    expect(await store.archiveAccount('acct_cash'), isFalse);
    expect(await store.deleteAccount('acct_cash'), isFalse);
  });

  testWidgets('optional colour swatches persist on an account', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final store = await ready();
    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    // Open the edit dialog for the first account.
    final edit = find.widgetWithIcon(IconButton, Icons.edit_outlined).first;
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Colour (optional)'), findsOneWidget);

    final swatch = find.byKey(Key('account-color-${kColorChoices.first}'));
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(store.activeAccounts.first.color, kColorChoices.first);
  });

  test('entry count includes archived accounts history', () async {
    final store = await ready();
    await store.addTransaction(
      type: 'expense',
      amount: 50,
      categoryId: 'food',
      date: DateTime(2026, 11, 20),
      accountId: 'acct_cash',
    );
    expect(store.accountEntryCount('acct_cash'), 1);
    await store.archiveAccount('acct_cash');
    expect(store.accountEntryCount('acct_cash'), 1);
  });
}
