// Persistence boundary for Dhadda domain data (Phase 2).
//
// UI/store code talks only to [DomainStore]. Two backends implement it:
//   - PrefsDomainStore: the Phase 0/1 JSON-in-SharedPreferences behavior,
//     kept for Flutter Web (and as the degraded fallback).
//   - DriftDomainStore: SQLite via Drift, used on Android/desktop.
// Provider/ChangeNotifier and ExpenseStore's public API are unchanged.
import 'dart:convert';

import '../models.dart';

/// The four domain collections as one portable unit. Field-for-field the same
/// content as a Snapshot's collections (but without sync metadata).
class DomainData {
  final List<Category> categories;
  final List<Txn> transactions;
  final List<Loan> loans;
  final List<Project> projects;

  const DomainData({
    required this.categories,
    required this.transactions,
    required this.loans,
    required this.projects,
  });

  factory DomainData.empty() => const DomainData(
    categories: [],
    transactions: [],
    loans: [],
    projects: [],
  );

  DomainSummary summarize() {
    var txnTotal = 0.0;
    for (final t in transactions) {
      txnTotal += t.amount;
    }
    var loanPending = 0.0;
    for (final l in loans) {
      loanPending += l.pending;
    }
    return DomainSummary(
      categoryCount: categories.length,
      transactionCount: transactions.length,
      loanCount: loans.length,
      projectCount: projects.length,
      txnAmountSum: txnTotal,
      loanPendingSum: loanPending,
      categoryOrder: [for (final c in categories) c.id],
      transactionIds: [for (final t in transactions) t.id],
    );
  }
}

/// Deterministic fingerprint of domain state, used to verify migrations and
/// import/export round-trips. Exact double sums (no rounding) so any dropped
/// or altered record changes the summary.
class DomainSummary {
  final int categoryCount;
  final int transactionCount;
  final int loanCount;
  final int projectCount;
  final double txnAmountSum;
  final double loanPendingSum;
  final List<String> categoryOrder;
  final List<String> transactionIds;

  const DomainSummary({
    required this.categoryCount,
    required this.transactionCount,
    required this.loanCount,
    required this.projectCount,
    required this.txnAmountSum,
    required this.loanPendingSum,
    required this.categoryOrder,
    required this.transactionIds,
  });

  bool matches(DomainSummary other) =>
      categoryCount == other.categoryCount &&
      transactionCount == other.transactionCount &&
      loanCount == other.loanCount &&
      projectCount == other.projectCount &&
      txnAmountSum == other.txnAmountSum &&
      loanPendingSum == other.loanPendingSum &&
      _sameOrder(categoryOrder, other.categoryOrder) &&
      _sameOrder(transactionIds, other.transactionIds);

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Backend contract. Multi-record writes must be atomic where the backend
/// supports transactions (Drift); single-key backends apply them as one write.
abstract class DomainStore {
  Future<DomainData> loadDomain();
  Future<void> replaceAll(DomainData data);
  Future<void> saveCategories(List<Category> categories);
  Future<void> saveTransactions(List<Txn> transactions);
  Future<void> upsertTransaction(Txn txn);
  Future<void> deleteTransaction(String id);
  Future<void> upsertLoan(Loan loan);
  Future<void> deleteLoan(String id);
  Future<void> upsertProject(Project project);
  Future<void> deleteProject(String id);
  Future<Map<String, int>> counts();
  Future<void> close();
}

List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw == null || raw.isEmpty) return <T>[];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return <T>[];
    return v.whereType<Map<String, dynamic>>().map(fromJson).toList();
  } catch (_) {
    return <T>[];
  }
}

/// Decodes the four legacy SharedPreferences JSON values with exactly the
/// lenient semantics the app has always used (bad items fall back inside
/// fromJson, corrupt keys decode to empty). Single source for both the legacy
/// load path and migration input.
DomainData decodeLegacyDomain({
  required String? cats,
  required String? txns,
  required String? loans,
  required String? projects,
}) => DomainData(
  categories: _decodeList(cats, Category.fromJson),
  transactions: _decodeList(txns, Txn.fromJson),
  loans: _decodeList(loans, Loan.fromJson),
  projects: _decodeList(projects, Project.fromJson),
);
