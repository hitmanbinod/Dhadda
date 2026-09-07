// SQLite backend via Drift, used on Android/desktop. Web never constructs
// this (see db_connection.dart): it imports only drift core + the
// conditional connection, never the sqlite3 native binding.
import 'package:drift/drift.dart';

import '../models.dart';
import 'app_db.dart';
import 'db_connection.dart';
import 'domain_store.dart';

class DriftDomainStore implements DomainStore {
  final AppDb db;
  DriftDomainStore(this.db);

  /// Opens the app-private database file. Throws when SQLite is unavailable;
  /// callers fall back to the prefs backend and retry later.
  static Future<DriftDomainStore> open() async =>
      DriftDomainStore(AppDb(openDbConnection()));

  Future<T> _tx<T>(Future<T> Function() work) =>
      db.transaction(work);

  // ---------- mapping (model <-> row, field for field) ----------

  CategoriesCompanion _catCompanion(Category c, int order) =>
      CategoriesCompanion(
        id: Value(c.id),
        name: Value(c.name),
        icon: Value(c.icon),
        color: Value(c.color),
        budget: Value(c.budget),
        sortOrder: Value(order),
      );

  Category _toCategory(CategoryRow r) => Category(
        id: r.id,
        name: r.name,
        icon: r.icon,
        color: r.color,
        budget: r.budget,
      );

  TransactionsCompanion _txnCompanion(Txn t) => TransactionsCompanion(
        id: Value(t.id),
        type: Value(t.type),
        amount: Value(t.amount),
        categoryId: Value(t.categoryId),
        date: Value(t.date),
        note: Value(t.note),
        mode: Value(t.mode),
        projectId: Value(t.projectId),
      );

  Txn _toTxn(TxnRow r) => Txn(
        id: r.id,
        type: r.type,
        amount: r.amount,
        categoryId: r.categoryId,
        date: r.date,
        note: r.note,
        mode: r.mode,
        projectId: r.projectId,
      );

  ProjectsCompanion _projectCompanion(Project p) => ProjectsCompanion(
        id: Value(p.id),
        name: Value(p.name),
        note: Value(p.note),
        created: Value(p.created),
        icon: Value(p.icon),
        color: Value(p.color),
      );

  Project _toProject(ProjectRow r) => Project(
        id: r.id,
        name: r.name,
        note: r.note,
        created: r.created,
        icon: r.icon,
        color: r.color,
      );

  LoansCompanion _loanCompanion(Loan l) => LoansCompanion(
        id: Value(l.id),
        person: Value(l.person),
        kind: Value(l.kind),
        principal: Value(l.lent),
        dateLent: Value(l.dateLent),
        dueDate: Value(l.dueDate),
        note: Value(l.note),
        remindAt: Value(l.remindAt),
      );

  Future<void> _writeLoanChildren(Loan l) async {
    await (db.delete(db.loanTopups)
          ..where((t) => t.loanId.equals(l.id)))
        .go();
    await (db.delete(db.loanRepayments)
          ..where((t) => t.loanId.equals(l.id)))
        .go();
    for (final t in l.topups) {
      await db.into(db.loanTopups).insert(LoanTopupsCompanion(
            id: Value(t.id),
            loanId: Value(l.id),
            amount: Value(t.amount),
            date: Value(t.date),
            note: Value(t.note),
          ));
    }
    for (final r in l.repayments) {
      await db.into(db.loanRepayments).insert(LoanRepaymentsCompanion(
            id: Value(r.id),
            loanId: Value(l.id),
            amount: Value(r.amount),
            date: Value(r.date),
            note: Value(r.note),
          ));
    }
  }

  Future<Loan> _toLoan(
    LoanRow l,
    List<Topup> topups,
    List<Repayment> repayments,
  ) async =>
      Loan(
        id: l.id,
        person: l.person,
        kind: l.kind,
        lent: l.principal,
        dateLent: l.dateLent,
        dueDate: l.dueDate,
        note: l.note,
        remindAt: l.remindAt,
        topups: topups,
        repayments: repayments,
      );

  Future<List<Loan>> _readLoans() async {
    final rows = await db.select(db.loans).get();
    final topups = await db.select(db.loanTopups).get();
    final repayments = await db.select(db.loanRepayments).get();
    final out = <Loan>[];
    for (final l in rows) {
      out.add(await _toLoan(
        l,
        [
          for (final t in topups.where((t) => t.loanId == l.id))
            Topup(id: t.id, amount: t.amount, date: t.date, note: t.note),
        ],
        [
          for (final r in repayments.where((r) => r.loanId == l.id))
            Repayment(
                id: r.id, amount: r.amount, date: r.date, note: r.note),
        ],
      ));
    }
    return out;
  }

  // ---------- DomainStore ----------

  @override
  Future<DomainData> loadDomain() async {
    final cats = await (db.select(db.categories)
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
    final txns = await db.select(db.transactions).get();
    final projects = await db.select(db.projects).get();
    final loans = await _readLoans();
    return DomainData(
      categories: [for (final r in cats) _toCategory(r)],
      transactions: [for (final r in txns) _toTxn(r)],
      loans: loans,
      projects: [for (final r in projects) _toProject(r)],
    );
  }

  @override
  Future<void> replaceAll(DomainData data) => _tx(() async {
        // Child-first deletes, parent-first inserts: safe under FK checks.
        await db.delete(db.loanRepayments).go();
        await db.delete(db.loanTopups).go();
        await db.delete(db.transactions).go();
        await db.delete(db.loans).go();
        await db.delete(db.projects).go();
        await db.delete(db.categories).go();
        for (var i = 0; i < data.categories.length; i++) {
          await db
              .into(db.categories)
              .insert(_catCompanion(data.categories[i], i));
        }
        for (final p in data.projects) {
          await db.into(db.projects).insert(_projectCompanion(p));
        }
        for (final l in data.loans) {
          await db.into(db.loans).insert(_loanCompanion(l));
          await _writeLoanChildren(l);
        }
        for (final t in data.transactions) {
          await db.into(db.transactions).insert(_txnCompanion(t));
        }
      });

  @override
  Future<void> saveCategories(List<Category> categories) => _tx(() async {
        await db.delete(db.categories).go();
        for (var i = 0; i < categories.length; i++) {
          await db
              .into(db.categories)
              .insert(_catCompanion(categories[i], i));
        }
      });

  @override
  Future<void> saveTransactions(List<Txn> transactions) => _tx(() async {
        await db.delete(db.transactions).go();
        for (final t in transactions) {
          await db.into(db.transactions).insert(_txnCompanion(t));
        }
      });

  @override
  Future<void> upsertTransaction(Txn txn) => _tx(() async {
        await db.into(db.transactions).insertOnConflictUpdate(_txnCompanion(txn));
      });

  @override
  Future<void> deleteTransaction(String id) => _tx(() async {
        await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
      });

  @override
  Future<void> upsertLoan(Loan loan) => _tx(() async {
        await db.into(db.loans).insertOnConflictUpdate(_loanCompanion(loan));
        await _writeLoanChildren(loan);
      });

  @override
  Future<void> deleteLoan(String id) => _tx(() async {
        // Children cascade, but delete explicitly first for clarity.
        await (db.delete(db.loanTopups)..where((t) => t.loanId.equals(id)))
            .go();
        await (db.delete(db.loanRepayments)
              ..where((t) => t.loanId.equals(id)))
            .go();
        await (db.delete(db.loans)..where((t) => t.id.equals(id))).go();
      });

  @override
  Future<void> upsertProject(Project project) => _tx(() async {
        await db
            .into(db.projects)
            .insertOnConflictUpdate(_projectCompanion(project));
      });

  @override
  Future<void> deleteProject(String id) => _tx(() async {
        await (db.delete(db.projects)..where((t) => t.id.equals(id))).go();
      });

  @override
  Future<Map<String, int>> counts() async {
    final cats = await db.managers.categories.count();
    final txns = await db.managers.transactions.count();
    final loans = await db.managers.loans.count();
    final projects = await db.managers.projects.count();
    return {
      'categories': cats,
      'transactions': txns,
      'loans': loans,
      'projects': projects,
    };
  }

  @override
  Future<void> close() => db.close();
}
