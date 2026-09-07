// Phase 2: DriftDomainStore against real in-memory SQLite (VM-only test;
// never compiled to web). Proves schema, CRUD, children handling, ordering,
// cascades, indexes, and transactional replaceAll at the backend level.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/domain_store.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/models.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) =>
    File('test/fixtures/phase0/$name').readAsStringSync();

DomainData _populated() {
  final s = Snapshot.decode(_fixture('snapshot_populated.json'));
  return DomainData(
    categories: s.categories,
    transactions: s.transactions,
    loans: s.loans,
    projects: s.projects,
  );
}

Future<DriftDomainStore> _open() async {
  final backend = DriftDomainStore(AppDb(NativeDatabase.memory()));
  addTearDown(backend.close);
  return backend;
}

Future<Set<String>> _indexNames(AppDb db) async {
  final rows = await db
      .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'")
      .get();
  return {for (final r in rows) r.read<String>('name')};
}

void main() {
  test('schema creates tables and justified indexes', () async {
    final backend = await _open();
    final db = backend.db;
    final tables = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        .get();
    final names = {for (final r in tables) r.read<String>('name')};
    expect(
        names,
        containsAll([
          'categories',
          'transactions',
          'projects',
          'loans',
          'loan_topups',
          'loan_repayments',
        ]));
    expect(
        await _indexNames(db),
        containsAll([
          'idx_transactions_date',
          'idx_transactions_category',
          'idx_transactions_project',
        ]));
  });

  test('replaceAll then load round-trips the populated fixture', () async {
    final backend = await _open();
    final source = _populated();
    await backend.replaceAll(source);
    final back = await backend.loadDomain();
    expect(source.summarize().matches(back.summarize()), isTrue);
    // Relations survive: project link, top-ups, repayments, reminder.
    final trek =
        back.projects.firstWhere((p) => p.id == 'proj-trek');
    expect(
        back.transactions
            .firstWhere((t) => t.id == 'txn-0005')
            .projectId,
        trek.id);
    final l1 = back.loans.firstWhere((l) => l.id == 'loan-0001');
    expect(l1.pending, 4000);
    expect(l1.topups, hasLength(1));
    expect(l1.repayments, hasLength(1));
    expect(l1.remindAt, 1789084800000);
    // Category order survives via sort_order.
    expect(back.categories.map((c) => c.id),
        orderedEquals(source.categories.map((c) => c.id)));
  });

  test('transaction upsert inserts then updates', () async {
    final backend = await _open();
    const t = Txn(
        id: 'u1',
        type: 'expense',
        amount: 100,
        categoryId: 'food',
        date: 1788220800000);
    await backend.upsertTransaction(t);
    await backend.upsertTransaction(
        const Txn(
            id: 'u1',
            type: 'expense',
            amount: 250,
            categoryId: 'food',
            date: 1788220800000,
            note: 'edited') );
    final back = await backend.loadDomain();
    expect(back.transactions, hasLength(1));
    expect(back.transactions.single.amount, 250);
    expect(back.transactions.single.note, 'edited');
    await backend.deleteTransaction('u1');
    expect(await backend.counts(), containsPair('transactions', 0));
  });

  test('loan upsert replaces children, delete cascades', () async {
    final backend = await _open();
    await backend.replaceAll(_populated());
    final l1 =
        (await backend.loadDomain()).loans.firstWhere((l) => l.id == 'loan-0001');
    // Upsert with different children: old ones must be gone.
    await backend.upsertLoan(Loan(
      id: l1.id,
      person: l1.person,
      kind: l1.kind,
      lent: l1.lent,
      dateLent: l1.dateLent,
      repayments: const [
        Repayment(id: 'new-r1', amount: 500, date: 1788652800000)
      ],
      topups: const [],
    ));
    final after =
        (await backend.loadDomain()).loans.firstWhere((l) => l.id == 'loan-0001');
    expect(after.repayments.map((r) => r.id), ['new-r1']);
    expect(after.topups, isEmpty);
    expect(after.pending, 4500);
    // Delete removes the loan and its children.
    await backend.deleteLoan('loan-0001');
    final gone = await backend.loadDomain();
    expect(gone.loans.any((l) => l.id == 'loan-0001'), isFalse);
    final kids = await backend.db
        .customSelect(
            "SELECT COUNT(*) AS c FROM loan_repayments WHERE loan_id = 'loan-0001'")
        .getSingle();
    expect(kids.read<int>('c'), 0);
  });

  test('saveCategories preserves explicit order', () async {
    final backend = await _open();
    await backend.replaceAll(_populated());
    final reversed =
        (await backend.loadDomain()).categories.reversed.toList();
    await backend.saveCategories(reversed);
    final back = await backend.loadDomain();
    expect(back.categories.map((c) => c.id),
        orderedEquals(reversed.map((c) => c.id)));
  });

  test('doubles round-trip bit-exact through REAL columns', () async {
    final backend = await _open();
    const tricky = [0.01, 0.1 + 0.2, 99999999.99, 1e15 + 0.5];
    for (var i = 0; i < tricky.length; i++) {
      await backend.upsertTransaction(Txn(
          id: 'dbl-$i',
          type: 'expense',
          amount: tricky[i],
          categoryId: 'other',
          date: 1788220800000));
    }
    final back = await backend.loadDomain();
    for (var i = 0; i < tricky.length; i++) {
      expect(
          back.transactions
              .firstWhere((t) => t.id == 'dbl-$i')
              .amount,
          tricky[i]);
    }
  });
}
