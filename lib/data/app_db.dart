// Drift/SQLite schema for Dhadda domain data (Phase 2).
//
// Tables mirror lib/models.dart 1:1 — same fields, same semantics, same IDs.
// Money stays REAL (Dart double round-trips bit-exact; see docs/PERSISTENCE.md).
// Category list order is preserved via an explicit sort_order column.
// Schema version: 1. No upgrade path yet (first version).
import 'package:drift/drift.dart';

part 'app_db.g.dart';

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get icon => integer()();
  IntColumn get color => integer()();
  RealColumn get budget => real()();
  IntColumn get sortOrder => integer()();
  // Phase 4 sync metadata: per-record logical revision + author device.
  // Defaults keep pre-v2 rows valid (rev 0 = unknown history baseline).
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxnRow')
// Justified by actual queries: monthTxns() filters date on every Home
// build, spendByCategory() filters categoryId, projectTxns() projectId.
@TableIndex(name: 'idx_transactions_date', columns: {#date})
@TableIndex(name: 'idx_transactions_category', columns: {#categoryId})
@TableIndex(name: 'idx_transactions_project', columns: {#projectId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get date => integer()();
  TextColumn get note => text()();
  TextColumn get mode => text()();
  TextColumn get projectId => text()();
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get note => text()();
  IntColumn get created => integer()();
  IntColumn get icon => integer()();
  IntColumn get color => integer()();
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LoanRow')
class Loans extends Table {
  TextColumn get id => text()();
  TextColumn get person => text()();
  TextColumn get kind => text()();
  RealColumn get principal => real()();
  IntColumn get dateLent => integer()();
  IntColumn get dueDate => integer().nullable()();
  TextColumn get note => text()();
  IntColumn get remindAt => integer()();
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TopupRow')
class LoanTopups extends Table {
  TextColumn get id => text()();
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.cascade)();
  RealColumn get amount => real()();
  IntColumn get date => integer()();
  TextColumn get note => text()();
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RepaymentRow')
class LoanRepayments extends Table {
  TextColumn get id => text()();
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.cascade)();
  RealColumn get amount => real()();
  IntColumn get date => integer()();
  TextColumn get note => text()();
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Phase 4 deletion records. Never garbage-collected in Phase 4: a tombstone
/// must outlive every peer that might still hold the deleted record.
@DataClassName('TombstoneRow')
class Tombstones extends Table {
  TextColumn get type => text()();
  TextColumn get recordId => text()();
  IntColumn get rev => integer()();
  TextColumn get revBy => text()();
  @override
  Set<Column> get primaryKey => {type, recordId};
}

@DriftDatabase(
  tables: [
    Categories,
    Transactions,
    Projects,
    Loans,
    LoanTopups,
    LoanRepayments,
    Tombstones,
  ],
)
class AppDb extends _$AppDb {
  AppDb(super.executor);

  /// Single source for the schema version (used by the database and by
  /// privacy-safe diagnostics alike).
  static const dbSchemaVersion = 2;

  @override
  int get schemaVersion => dbSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // NOT NULL WITH DEFAULT: pre-v2 rows stay valid (rev 0 baseline).
        await m.addColumn(categories, categories.rev);
        await m.addColumn(categories, categories.revBy);
        await m.addColumn(transactions, transactions.rev);
        await m.addColumn(transactions, transactions.revBy);
        await m.addColumn(projects, projects.rev);
        await m.addColumn(projects, projects.revBy);
        await m.addColumn(loans, loans.rev);
        await m.addColumn(loans, loans.revBy);
        await m.addColumn(loanTopups, loanTopups.rev);
        await m.addColumn(loanTopups, loanTopups.revBy);
        await m.addColumn(loanRepayments, loanRepayments.rev);
        await m.addColumn(loanRepayments, loanRepayments.revBy);
        await m.createTable(tombstones);
        // @TableIndex entries only build in onCreate; upgraded databases
        // need them explicitly (IF NOT EXISTS for idempotence).
        for (final stmt in [
          'CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (date)',
          'CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions (category_id)',
          'CREATE INDEX IF NOT EXISTS idx_transactions_project ON transactions (project_id)',
        ]) {
          await m.database.customStatement(stmt);
        }
      }
    },
  );
}
