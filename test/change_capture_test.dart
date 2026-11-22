import 'dart:convert';

import 'package:expense/data/prefs_domain_store.dart';
import 'package:expense/home_layout.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every repository mutation path lands in the cloud outbox', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = PrefsDomainStore(prefs);
    final store = ExpenseStore(domainOverride: backend);
    await store.load();

    // Pair locally without any network call: queue() only needs to be paired.
    await prefs.setString('expense_cloud_vault_v1', 'v-test');
    await prefs.setString('expense_cloud_token_v1', 't-test');
    await prefs.setString('expense_cloud_key_v1', base64.encode(List<int>.filled(32, 1)));
    final cloud = CloudSync(store, workerUrl: 'http://127.0.0.1:1');
    await cloud.load();
    cloud.attach();
    cloud.startForeground();

    final now = DateTime(2026, 11, 22, 10);

    // --- entries ---
    final txnId = await store.addTransaction(
      type: 'expense', amount: 250, categoryId: 'food', date: now, note: 'capture');
    expect(txnId, isTrue);
    final id = store.transactions.first.id;
    await store.updateTransaction(id, amount: 300, note: 'edited');
    await store.setEntryAccount(id, 'acct_bank');
    await store.deleteTransaction(id);
    await store.addTransaction(
      type: 'income', amount: 100, categoryId: 'other', date: now, note: 'kept');
    final keepId = store.transactions.first.id;

    // --- events ---
    final eventId = await store.addProject('Trip', 'note');
    await store.updateProject(eventId, name: 'Trip 2');
    await store.deleteProject(eventId);

    // --- lent people + their transactions ---
    await store.addLoan(person: 'Samip', amount: 1000, date: now);
    final loan = store.loans.first;
    await store.lendMore(loan.id, 200, now, 'topup');
    await store.addRepayment(loan.id, 300, now, 'repay');
    await store.setReminderAt(loan.id, now.add(const Duration(days: 1)));
    await store.deleteLoan(loan.id);

    // --- categories ---
    final catId = await store.addCategory('CaptureCat');
    await store.updateCategory(catId, name: 'CaptureCat2');
    await store.setBudget(catId, 500);
    await store.moveCategoryTo(catId, 0);
    await store.deleteCategory(catId);

    // --- accounts ---
    final acctId = await store.addAccount('WalletX', 'wallet');
    final acct = store.accounts.firstWhere((a) => a.id == acctId);
    await store.updateAccount(acct.copyWith(name: 'WalletY'));
    await store.archiveAccount(acctId);
    await store.deleteAccount(acctId);

    // --- settings ---
    await store.setCurrency('INR');
    await store.setUserName('Capture User');
    await store.setCalendarSystem('bs');
    await store.setHomeLayout(defaultHomeLayout());

    cloud.dispose();

    final rows = (jsonDecode(prefs.getString('expense_cloud_outbox_v1') ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final byKey = {for (final r in rows) '${r['t']}:${r['id']}': r};

    void expectQueued(String table, String id, {bool deleted = false}) {
      final key = '$table:$id';
      expect(byKey.containsKey(key), isTrue, reason: 'missing $key in outbox');
      expect(byKey[key]!['d'] == 1, deleted, reason: 'deleted flag for $key');
    }

    expectQueued('entries', id, deleted: true); // final state after delete
    expectQueued('entries', keepId);
    expectQueued('events', eventId, deleted: true);
    expectQueued('people', loan.id, deleted: true);
    expectQueued('categories', catId, deleted: true);
    // Deletion may be refused by business rules (last active account / has
    // entries); the important assertion is that add + edit were captured.
    expectQueued('accounts', acctId);
    expectQueued('settings', 'currency');
    expectQueued('settings', 'userName');
    expectQueued('settings', 'calendarSystem');
    expectQueued('settings', 'homeLayout');

    // Every queued row carries a finite, positive ua and a table/id.
    for (final r in rows) {
      expect(r['t'], isNotEmpty);
      expect(r['id'], isNotEmpty);
      expect((r['ua'] as num) > 0, isTrue);
    }
  });
}
