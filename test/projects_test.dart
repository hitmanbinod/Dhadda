import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('projects: totals, counts, delete untags entries', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    await store.addProject('Trekking', 'Annapurna');
    final id = store.projects.single.id;

    await store.addTransaction(
        type: 'expense',
        amount: 5000,
        categoryId: 'travel',
        date: DateTime.utc(2026, 9, 1),
        projectId: id);
    await store.addTransaction(
        type: 'expense',
        amount: 2000,
        categoryId: 'food',
        date: DateTime.utc(2026, 9, 2),
        projectId: id);
    await store.addTransaction(
        type: 'income',
        amount: 99999,
        categoryId: 'other',
        date: DateTime.utc(2026, 9, 2),
        projectId: id);
    await store.addTransaction(
        type: 'expense',
        amount: 100,
        categoryId: 'food',
        date: DateTime.utc(2026, 9, 2));

    expect(store.projectSpend(id), 7000); // income excluded
    expect(store.projectTxns(id).length, 3);

    await store.deleteProject(id);
    expect(store.projects, isEmpty);
    // Entries survive, just untagged.
    expect(store.transactions.length, 4);
    expect(store.projectTxns(id), isEmpty);
  });

  test('snapshot carries projects; legacy txn loads untagged', () {
    final s = Snapshot(
      version: kSnapshotVersion,
      updatedAt: DateTime.utc(2026, 9, 3).toIso8601String(),
      deviceId: 'd',
      deviceName: 'x',
      categories: defaultCategories(),
      transactions: const [],
      loans: const [],
      projects: [
        Project(
            id: 'p1',
            name: 'Outing',
            created:
                DateTime.utc(2026, 9, 1).millisecondsSinceEpoch),
      ],
    );
    final back = Snapshot.decode(s.encode());
    expect(back.projects.single.name, 'Outing');

    final legacy = Txn.fromJson({'id': 't', 'amount': 10});
    expect(legacy.projectId, '');
  });

  test('borrowed ledger mirrors lent with split totals', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    await a.addLoan(
        person: 'Asha',
        amount: 1000,
        date: DateTime.utc(2026, 9, 1));
    await a.addBorrow(
        person: 'Sandesh',
        amount: 600,
        date: DateTime.utc(2026, 9, 2));
    expect(a.pendingLoansTotal, 1000);
    expect(a.pendingBorrowedTotal, 600);

    final borrowed = a.loans.singleWhere((l) => l.isBorrowed);
    await a.addRepayment(
        borrowed.id, 200, DateTime.utc(2026, 9, 3), '');
    expect(a.pendingBorrowedTotal, 400);
    await a.lendMore(
        borrowed.id, 100, DateTime.utc(2026, 9, 4), '');
    expect(a.pendingBorrowedTotal, 500);

    // Round-trips with kind intact.
    final back = Snapshot.decode(a.exportJson());
    expect(back.loans.length, 2);
    expect(
        back.loans.where((l) => l.isBorrowed).single.pending,
        500);

    // Legacy loans without kind/reminders load as lent + off.
    final old = Loan.fromJson({'id': 'x', 'lent': 50});
    expect(old.kind, 'lent');
    expect(old.isBorrowed, isFalse);
    expect(old.remindAt, 0);
    final odd = Loan.fromJson(
        {'id': 'y', 'kind': 'zzz', 'remindFreq': 'hourly'});
    expect(odd.kind, 'lent');
    expect(odd.remindAt, 0);
  });

  test('one-time reminder sticks, legacy repeats migrate once', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    await a.addLoan(
        person: 'Asha', amount: 100, date: DateTime.utc(2026, 9, 1));
    final id = a.loans.single.id;
    expect(a.loans.single.remindAt, 0);
    final when = DateTime.utc(2026, 9, 10, 9);
    await a.setReminderAt(id, when);
    expect(a.loans.single.remindAt,
        when.millisecondsSinceEpoch);
    final b = ExpenseStore();
    await b.load();
    expect(b.loans.single.remindAt,
        when.millisecondsSinceEpoch);
    await b.setReminderAt(id, null);
    expect(b.loans.single.remindAt, 0);
    await b.setReminderAt('missing', when); // no crash

    // Legacy repeating schedules become one future nudge.
    final legacy =
        Loan.fromJson({'id': 'l', 'lent': 10, 'remindFreq': 'daily'});
    expect(legacy.remindAt,
        greaterThan(DateTime.now().millisecondsSinceEpoch));
    final junk = Loan.fromJson({'id': 'm', 'remindFreq': 'hourly'});
    expect(junk.remindAt, 0);
    final plain = Loan.fromJson({'id': 'n'});
    expect(plain.remindAt, 0);
  });

  test('categories reorder and Other stays last', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    final first = a.categories.first.id;
    await a.moveCategory(first, 1);
    expect(a.categories[1].id, first);
    await a.moveCategory(first, -1); // back
    expect(a.categories.first.id, first);
    expect(a.categories.last.id, 'other');
    await a.moveCategory('missing', 1); // no crash
    await a.moveCategory(a.categories.first.id, -5); // clamped
    expect(a.categories.length, defaultCategories().length);
  });

  test('moveCategoryTo jumps and clamps, persists order', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    final first = a.categories.first.id;
    await a.moveCategoryTo(first, 999); // clamps to end
    expect(a.categories.last.id, first);
    await a.moveCategoryTo(first, 0);
    expect(a.categories.first.id, first);
    await a.moveCategoryTo(first, 0); // no-op, no crash
    await a.moveCategoryTo('missing', 2); // no crash
    final b = ExpenseStore();
    await b.load();
    expect(b.categories.first.id, first);
  });
}