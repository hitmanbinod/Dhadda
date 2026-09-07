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
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxnRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get date => integer()();
  TextColumn get note => text()();
  TextColumn get mode => text()();
  TextColumn get projectId => text()();
  @override
  Set<Column> get primaryKey => {id};

  // Justified by actual queries: monthTxns() filters date on every Home
  // build, spendByCategory() filters categoryId, projectTxns() projectId.
  List<Index> get indexes => [
        Index('idx_transactions_date',
            'CREATE INDEX idx_transactions_date ON transactions (date)'),
        Index('idx_transactions_category',
            'CREATE INDEX idx_transactions_category ON transactions (categoryId)'),
        Index('idx_transactions_project',
            'CREATE INDEX idx_transactions_project ON transactions (projectId)'),
      ];
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get note => text()();
  IntColumn get created => integer()();
  IntColumn get icon => integer()();
  IntColumn get color => integer()();
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
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Categories,
  Transactions,
  Projects,
  Loans,
  LoanTopups,
  LoanRepayments,
])
class AppDb extends _$AppDb {
  AppDb(super.executor);

  @override
  int get schemaVersion => 1;
}
