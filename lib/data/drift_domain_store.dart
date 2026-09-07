// SQLite backend via Drift, used on Android/desktop. Web never constructs
// this (see db_connection.dart): it imports only drift core + the
// conditional connection, never the sqlite3 native binding.
//
// Sync revisions travel in the same row write as the data (atomic); bulk
// wholesale writes preserve each row's existing revision unless the caller
// passes explicit metadata (used by merge application).
import 'package:drift/drift.dart';

import '../models.dart';
import '../sync/sync_v2.dart' show SyncType;
import 'app_db.dart';
import 'db_connection.dart';
import 'domain_store.dart';

/// Raw SQL table names (verified against generated $name values).
const _tables = {
  SyncType.cat: 'categories',
  SyncType.txn: 'transactions',
  SyncType.proj: 'projects',
  SyncType.loan: 'loans',
  SyncType.topup: 'loan_topups',
  SyncType.repay: 'loan_repayments',
};

class DriftDomainStore implements DomainStore {
  final AppDb db;
  DriftDomainStore(this.db);

  /// Opens the app-private database file. Throws when SQLite is unavailable;
  /// callers fall back to the prefs backend and retry later.
  static Future<DriftDomainStore> open() async =>
      DriftDomainStore(AppDb(openDbConnection()));

  Future<T> _tx<T>(Future<T> Function() work) => db.transaction(work);

  Future<RecordMeta> _rowMeta(String table, String id) async {
    final row = await db
        .customSelect(
          'SELECT rev, rev_by AS by FROM "$table" WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) return const RecordMeta(rev: 0, by: '');
    return RecordMeta(rev: row.read<int>('rev'), by: row.read<String>('by'));
  }

  // ---------- mapping (model <-> row, field for field) ----------

  CategoriesCompanion _catCompanion(
    Category c,
    int order,
    int rev,
    String by,
  ) => CategoriesCompanion(
    id: Value(c.id),
    name: Value(c.name),
    icon: Value(c.icon),
    color: Value(c.color),
    budget: Value(c.budget),
    sortOrder: Value(order),
    rev: Value(rev),
    revBy: Value(by),
  );

  Category _toCategory(CategoryRow r) => Category(
    id: r.id,
    name: r.name,
    icon: r.icon,
    color: r.color,
    budget: r.budget,
  );

  TransactionsCompanion _txnCompanion(Txn t, int rev, String by) =>
      TransactionsCompanion(
        id: Value(t.id),
        type: Value(t.type),
        amount: Value(t.amount),
        categoryId: Value(t.categoryId),
        date: Value(t.date),
        note: Value(t.note),
        mode: Value(t.mode),
        projectId: Value(t.projectId),
        rev: Value(rev),
        revBy: Value(by),
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

  ProjectsCompanion _projectCompanion(Project p, int rev, String by) =>
      ProjectsCompanion(
        id: Value(p.id),
        name: Value(p.name),
        note: Value(p.note),
        created: Value(p.created),
        icon: Value(p.icon),
        color: Value(p.color),
        rev: Value(rev),
        revBy: Value(by),
      );

  Project _toProject(ProjectRow r) => Project(
    id: r.id,
    name: r.name,
    note: r.note,
    created: r.created,
    icon: r.icon,
    color: r.color,
  );

  LoansCompanion _loanCompanion(Loan l, int rev, String by) => LoansCompanion(
    id: Value(l.id),
    person: Value(l.person),
    kind: Value(l.kind),
    principal: Value(l.lent),
    dateLent: Value(l.dateLent),
    dueDate: Value(l.dueDate),
    note: Value(l.note),
    remindAt: Value(l.remindAt),
    rev: Value(rev),
    revBy: Value(by),
  );

  Future<void> _writeLoanChildren(
    Loan l,
    Future<RecordMeta> Function(String type, String id) metaOf,
  ) async {
    await (db.delete(db.loanTopups)..where((t) => t.loanId.equals(l.id))).go();
    await (db.delete(
      db.loanRepayments,
    )..where((t) => t.loanId.equals(l.id))).go();
    for (final t in l.topups) {
      final m = await metaOf(SyncType.topup, t.id);
      await db
          .into(db.loanTopups)
          .insert(
            LoanTopupsCompanion(
              id: Value(t.id),
              loanId: Value(l.id),
              amount: Value(t.amount),
              date: Value(t.date),
              note: Value(t.note),
              rev: Value(m.rev),
              revBy: Value(m.by),
            ),
          );
    }
    for (final r in l.repayments) {
      final m = await metaOf(SyncType.repay, r.id);
      await db
          .into(db.loanRepayments)
          .insert(
            LoanRepaymentsCompanion(
              id: Value(r.id),
              loanId: Value(l.id),
              amount: Value(r.amount),
              date: Value(r.date),
              note: Value(r.note),
              rev: Value(m.rev),
              revBy: Value(m.by),
            ),
          );
    }
  }

  Future<Loan> _toLoan(
    LoanRow l,
    List<Topup> topups,
    List<Repayment> repayments,
  ) async => Loan(
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
      out.add(
        await _toLoan(
          l,
          [
            for (final t in topups.where((t) => t.loanId == l.id))
              Topup(id: t.id, amount: t.amount, date: t.date, note: t.note),
          ],
          [
            for (final r in repayments.where((r) => r.loanId == l.id))
              Repayment(id: r.id, amount: r.amount, date: r.date, note: r.note),
          ],
        ),
      );
    }
    return out;
  }

  Future<Map<String, RecordMeta>> _currentMeta() => loadRecordMeta();

  // ---------- DomainStore ----------

  @override
  Future<DomainData> loadDomain() async {
    final cats = await (db.select(
      db.categories,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
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
    // Revisions are preserved per id (fresh databases start at 0).
    final meta = await _currentMeta();
    RecordMeta at(String type, String id) =>
        meta['$type/$id'] ?? const RecordMeta(rev: 0, by: '');
    await db.delete(db.loanRepayments).go();
    await db.delete(db.loanTopups).go();
    await db.delete(db.transactions).go();
    await db.delete(db.loans).go();
    await db.delete(db.projects).go();
    await db.delete(db.categories).go();
    for (var i = 0; i < data.categories.length; i++) {
      final c = data.categories[i];
      final m = at(SyncType.cat, c.id);
      await db.into(db.categories).insert(_catCompanion(c, i, m.rev, m.by));
    }
    for (final p in data.projects) {
      final m = at(SyncType.proj, p.id);
      await db.into(db.projects).insert(_projectCompanion(p, m.rev, m.by));
    }
    for (final l in data.loans) {
      final m = at(SyncType.loan, l.id);
      await db.into(db.loans).insert(_loanCompanion(l, m.rev, m.by));
      await _writeLoanChildren(l, (t, id) async => at(t, id));
    }
    for (final t in data.transactions) {
      final m = at(SyncType.txn, t.id);
      await db.into(db.transactions).insert(_txnCompanion(t, m.rev, m.by));
    }
  });

  @override
  Future<void> saveCategories(List<Category> categories) => _tx(() async {
    final meta = await _currentMeta();
    await db.delete(db.categories).go();
    for (var i = 0; i < categories.length; i++) {
      final c = categories[i];
      final m =
          meta['${SyncType.cat}/${c.id}'] ?? const RecordMeta(rev: 0, by: '');
      await db.into(db.categories).insert(_catCompanion(c, i, m.rev, m.by));
    }
  });

  @override
  Future<void> saveTransactions(List<Txn> transactions) => _tx(() async {
    final meta = await _currentMeta();
    await db.delete(db.transactions).go();
    for (final t in transactions) {
      final m =
          meta['${SyncType.txn}/${t.id}'] ?? const RecordMeta(rev: 0, by: '');
      await db.into(db.transactions).insert(_txnCompanion(t, m.rev, m.by));
    }
  });

  @override
  Future<void> upsertTransaction(Txn txn, {int? rev, String? by}) =>
      _tx(() async {
        final m = (rev == null)
            ? await _rowMeta(_tables[SyncType.txn]!, txn.id)
            : RecordMeta(rev: rev, by: by ?? '');
        await db
            .into(db.transactions)
            .insertOnConflictUpdate(_txnCompanion(txn, m.rev, m.by));
      });

  @override
  Future<void> deleteTransaction(String id) => _tx(() async {
    await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
  });

  @override
  Future<void> upsertLoan(Loan loan, {int? rev, String? by}) => _tx(() async {
    final m = (rev == null)
        ? await _rowMeta(_tables[SyncType.loan]!, loan.id)
        : RecordMeta(rev: rev, by: by ?? '');
    await db
        .into(db.loans)
        .insertOnConflictUpdate(_loanCompanion(loan, m.rev, m.by));
    final meta = await _currentMeta();
    await _writeLoanChildren(
      loan,
      (t, id) async => meta['$t/$id'] ?? const RecordMeta(rev: 0, by: ''),
    );
  });

  @override
  Future<void> deleteLoan(String id) => _tx(() async {
    // Children cascade, but delete explicitly first for clarity.
    await (db.delete(db.loanTopups)..where((t) => t.loanId.equals(id))).go();
    await (db.delete(
      db.loanRepayments,
    )..where((t) => t.loanId.equals(id))).go();
    await (db.delete(db.loans)..where((t) => t.id.equals(id))).go();
  });

  @override
  Future<void> upsertProject(Project project, {int? rev, String? by}) =>
      _tx(() async {
        final m = (rev == null)
            ? await _rowMeta(_tables[SyncType.proj]!, project.id)
            : RecordMeta(rev: rev, by: by ?? '');
        await db
            .into(db.projects)
            .insertOnConflictUpdate(_projectCompanion(project, m.rev, m.by));
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

  // ---------- sync metadata (revisions + tombstones) ----------

  @override
  Future<Map<String, RecordMeta>> loadRecordMeta() async {
    final out = <String, RecordMeta>{};
    Future<void> read(String table, String prefix) async {
      final rows = await db
          .customSelect('SELECT id, rev, rev_by AS by FROM "$table"')
          .get();
      for (final r in rows) {
        out['$prefix/${r.read<String>('id')}'] = RecordMeta(
          rev: r.read<int>('rev'),
          by: r.read<String>('by'),
        );
      }
    }

    await read('categories', SyncType.cat);
    await read('transactions', SyncType.txn);
    await read('projects', SyncType.proj);
    await read('loans', SyncType.loan);
    await read('loan_topups', SyncType.topup);
    await read('loan_repayments', SyncType.repay);
    return out;
  }

  @override
  Future<void> saveRecordMeta(
    String type,
    String id,
    int rev,
    String by,
  ) async {
    final table = _tables[type];
    if (table == null) return;
    await db.customStatement(
      'UPDATE "$table" SET rev = ?, rev_by = ? WHERE id = ?',
      [rev, by, id],
    );
  }

  @override
  Future<List<TombEntry>> loadTombstones() async {
    final rows = await db.select(db.tombstones).get();
    return [
      for (final r in rows)
        TombEntry(type: r.type, id: r.recordId, rev: r.rev, by: r.revBy),
    ];
  }

  @override
  Future<void> saveTombstone(TombEntry tomb) => _tx(() async {
    await db
        .into(db.tombstones)
        .insertOnConflictUpdate(
          TombstonesCompanion(
            type: Value(tomb.type),
            recordId: Value(tomb.id),
            rev: Value(tomb.rev),
            revBy: Value(tomb.by),
          ),
        );
  });

  @override
  Future<void> deleteTombstone(String type, String id) => _tx(() async {
    await (db.delete(
      db.tombstones,
    )..where((t) => t.type.equals(type) & t.recordId.equals(id))).go();
  });

  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) => _tx(() async {
    RecordMeta at(String type, String id) =>
        meta['$type/$id'] ?? const RecordMeta(rev: 0, by: '');
    await db.delete(db.tombstones).go();
    await db.delete(db.loanRepayments).go();
    await db.delete(db.loanTopups).go();
    await db.delete(db.transactions).go();
    await db.delete(db.loans).go();
    await db.delete(db.projects).go();
    await db.delete(db.categories).go();
    for (var i = 0; i < data.categories.length; i++) {
      final c = data.categories[i];
      final m = at(SyncType.cat, c.id);
      await db.into(db.categories).insert(_catCompanion(c, i, m.rev, m.by));
    }
    for (final p in data.projects) {
      final m = at(SyncType.proj, p.id);
      await db.into(db.projects).insert(_projectCompanion(p, m.rev, m.by));
    }
    for (final l in data.loans) {
      final m = at(SyncType.loan, l.id);
      await db.into(db.loans).insert(_loanCompanion(l, m.rev, m.by));
      await _writeLoanChildren(l, (t, id) async => at(t, id));
    }
    for (final t in data.transactions) {
      final m = at(SyncType.txn, t.id);
      await db.into(db.transactions).insert(_txnCompanion(t, m.rev, m.by));
    }
    for (final tomb in tombs) {
      await db
          .into(db.tombstones)
          .insert(
            TombstonesCompanion(
              type: Value(tomb.type),
              recordId: Value(tomb.id),
              rev: Value(tomb.rev),
              revBy: Value(tomb.by),
            ),
          );
    }
  });
}
