import 'dart:convert';
import 'dart:io';

import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 2: deterministic default accounts, entry relation and legacy safety.
void main() {
  Future<ExpenseStore> ready() async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    return store;
  }

  group('model', () {
    test('default ids are deterministic and derive correctly from mode', () {
      expect(defaultAccounts().map((a) => a.id), [
        'acct_cash',
        'acct_bank',
        'acct_card',
        'acct_ewallet',
      ]);
      expect(accountIdForMode('cash'), 'acct_cash');
      expect(accountIdForMode('bank'), 'acct_bank');
      expect(accountIdForMode('card'), 'acct_card');
      expect(accountIdForMode('ewallet'), 'acct_ewallet');
      expect(accountIdForMode(''), 'acct_cash');
      expect(modeForAccountType('wallet'), 'ewallet');
      expect(
        Txn(
          id: 'x',
          type: 'expense',
          amount: 1,
          categoryId: 'food',
          date: 0,
          mode: 'bank',
        ).effectiveAccountId,
        'acct_bank',
      );
    });

    test('legacy fixture keeps every entry, sum and mode', () {
      final raw = File('test/fixtures/phase0/snapshot_populated.json')
          .readAsStringSync();
      final snap = Snapshot.decode(raw);
      expect(snap.transactions, isNotEmpty);
      final sum = snap.transactions.fold<double>(
        0,
        (s, t) => s + t.amount,
      );
      for (final t in snap.transactions) {
        expect(t.accountId, '');
        expect(t.effectiveAccountId, accountIdForMode(t.mode));
      }
      // Re-decoding is stable — independent devices converge.
      final again = Snapshot.decode(raw);
      expect(again.transactions.length, snap.transactions.length);
      expect(
        again.transactions.fold<double>(0, (s, t) => s + t.amount),
        sum,
      );
      expect(again.accounts.length, snap.accounts.length);
    });

    test('old-shaped JSON with no accounts decodes without loss', () {
      final jsonMap = jsonDecode(
        File('test/fixtures/phase0/snapshot_single.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      jsonMap.remove('accounts');
      final snap = Snapshot.fromJson(jsonMap);
      expect(snap.accounts, isEmpty);
      expect(snap.transactions.length, 1);
      expect(snap.transactions.first.effectiveAccountId, isNotEmpty);
    });
  });

  group('store', () {
    test('starts with four accounts and persists additive pref', () async {
      final store = await ready();
      expect(store.accounts.map((a) => a.id).toList(), [
        'acct_cash',
        'acct_bank',
        'acct_card',
        'acct_ewallet',
      ]);
      final id = await store.addAccount('Nabil', 'bank');
      expect(id, isNotEmpty);
      final reloaded = ExpenseStore();
      await reloaded.load();
      expect(reloaded.accounts.any((a) => a.name == 'Nabil'), isTrue);
    });

    test('rename keeps entries; archive, merge and delete-if-unused', () async {
      final store = await ready();
      await store.addTransaction(
        type: 'expense',
        amount: 100,
        categoryId: 'food',
        date: DateTime(2026, 11, 20),
        note: 'Tea',
        accountId: 'acct_cash',
      );
      final cash = store.accountOf('acct_cash');
      await store.updateAccount(cash.copyWith(name: 'Pocket cash'));
      expect(store.accountOf('acct_cash').name, 'Pocket cash');
      expect(store.transactions.single.effectiveAccountId, 'acct_cash');

      // In use: hard delete refused, archive allowed.
      expect(await store.deleteAccount('acct_cash'), isFalse);
      expect(await store.archiveAccount('acct_cash'), isTrue);
      await store.mergeAccount('acct_cash', 'acct_bank');
      expect(store.transactions.single.effectiveAccountId, 'acct_bank');
      expect(store.transactions.single.mode, 'bank');
      expect(store.accountOf('acct_cash').archived, isTrue);

      // Unused account can be deleted; last active one cannot.
      final spare = await store.addAccount('Khalti', 'wallet');
      expect(await store.deleteAccount(spare), isTrue);
      for (final a in [...store.accounts]) {
        if (a.id != 'acct_bank') {
          await store.updateAccount(a.copyWith(archived: true));
        }
      }
      expect(await store.deleteAccount('acct_bank'), isFalse);
      expect(await store.archiveAccount('acct_bank'), isFalse);
    });
  });
}
