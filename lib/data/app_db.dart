// Drift/SQLite schema for Dhadda domain data (Phase 2).
//
// Tables mirror lib/models.dart 1:1 — same fields, same semantics, same IDs.
// Money stays REAL (Dart double round-trips bit-exact; see docs/PERSISTENCE.md).
// Category list order is preserved via an explicit sort_order column.
// Schema version 1 was the Phase 2 baseline; version 2 (Phase 4) added the
// per-record rev/rev_by columns and the tombstones table. The upgrade step is
// written to be resumable — see [_ensureColumns] and onUpgrade below.
import 'package:drift/drift.dart';

import '../models.dart';

part 'app_db.g.dart';

/// Round 3: user-made payment accounts. No balance is stored here.
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get color => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  IntColumn get rev => integer().withDefault(const Constant(0))();
  TextColumn get revBy => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Round 3: receipt photos are files on this phone; only their metadata is
/// indexed here. Never included in sync or JSON backups.
@DataClassName('ReceiptRow')
class Receipts extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text()();
  TextColumn get fileName => text()();
  IntColumn get addedAt => integer()();
  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

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
@TableIndex(name: 'idx_transactions_account', columns: {#accountId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get categoryId => text().references(Categories, #id)();
  // Nullable during migration: old rows are backfilled to a deterministic id.
  TextColumn get accountId => text().nullable()();
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

/// Tables that exist in the database right now, lowercased as SQLite
/// stores them.
Future<Set<String>> _existingTables(Migrator m) async {
  final rows = await m.database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )
      .get();
  return rows.map((r) => r.read<String>('name').toLowerCase()).toSet();
}

/// Adds [columns] to [table], skipping any that are already present.
///
/// Drift writes `user_version` only after onUpgrade returns, so an upgrade
/// interrupted part-way (process killed, crash, battery pull) leaves the
/// database still claiming the old version with half of the new columns
/// applied. A bare `addColumn` would then throw "duplicate column name" on
/// every launch and drift caches that error, leaving the file permanently
/// unreadable. Checking first makes the step idempotent, so the retry simply
/// finishes whatever the interrupted run had not applied yet.
Future<void> _ensureColumns(
  Migrator m,
  TableInfo<Table, Object?> table,
  List<GeneratedColumn> columns,
) async {
  final info = await m.database
      .customSelect('PRAGMA table_info(${table.actualTableName})')
      .get();
  final present = info.map((r) => r.read<String>('name').toLowerCase()).toSet();
  for (final column in columns) {
    if (present.contains(column.name.toLowerCase())) continue;
    await m.addColumn(table, column);
  }
}

@DriftDatabase(
  tables: [
    Accounts,
    Receipts,
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
  static const dbSchemaVersion = 3;

  @override
  int get schemaVersion => dbSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // NOT NULL WITH DEFAULT: pre-v2 rows stay valid (rev 0 baseline).
        // Every step is guarded so an interrupted upgrade resumes instead of
        // failing forever — see [_ensureColumns].
        await _ensureColumns(m, categories, [categories.rev, categories.revBy]);
        await _ensureColumns(
          m,
          transactions,
          [transactions.rev, transactions.revBy],
        );
        await _ensureColumns(m, projects, [projects.rev, projects.revBy]);
        await _ensureColumns(m, loans, [loans.rev, loans.revBy]);
        await _ensureColumns(m, loanTopups, [loanTopups.rev, loanTopups.revBy]);
        await _ensureColumns(m, loanRepayments, [
          loanRepayments.rev,
          loanRepayments.revBy,
        ]);
        if (!(await _existingTables(m)).contains('tombstones')) {
          await m.createTable(tombstones);
        }
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
      if (from < 3) {
        // Round 3 accounts + receipts. Every step is guarded so an
        // interrupted upgrade resumes instead of failing forever.
        final tables = await _existingTables(m);
        if (!tables.contains('accounts')) await m.createTable(accounts);
        if (!tables.contains('receipts')) await m.createTable(receipts);
        await _ensureColumns(m, transactions, [transactions.accountId]);
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_account '
          'ON transactions (account_id)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_receipts_entry '
          'ON receipts (entry_id)',
        );
        // Deterministic defaults: identical on every device, so independent
        // migrations converge and sync never creates duplicates.
        for (final a in defaultAccounts()) {
          await m.database.customStatement(
            "INSERT OR IGNORE INTO accounts "
            "(id, name, type, color, sort_order, archived, rev, rev_by) "
            "VALUES ('${a.id}', '${a.name}', '${a.type}', ${a.color}, "
            "${a.sortOrder}, 0, 0, '')",
          );
        }
        // Backfill only NULL account ids; never touch an existing choice or
        // the legacy mode value.
        await m.database.customStatement(
          "UPDATE transactions SET account_id = "
          "CASE mode WHEN 'bank' THEN 'acct_bank' "
          "WHEN 'card' THEN 'acct_card' "
          "WHEN 'ewallet' THEN 'acct_ewallet' ELSE 'acct_cash' END "
          "WHERE account_id IS NULL",
        );
      }
    },
  );
}
