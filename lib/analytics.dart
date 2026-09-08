// Phase 6: database-free monthly analytics over the in-memory working set.
//
// Single-pass, epoch-arithmetic equivalents of ExpenseStore's historical
// triple-scan (monthTxns + monthSpend + monthIncome + spendByCategory).
// Semantics preserved exactly:
//   - month membership identical to comparing local year/month;
//   - per-subset addition order identical, so double sums are bit-identical;
//   - byCategory first-encounter insertion order identical.
// Month bounds use local-midnight DateTimes; DateTime normalizes month 13
// (December -> January of the next year). DST overlap hours stay inside the
// same month under both views, so membership cannot diverge.
import 'models.dart';

/// One month's dashboard aggregates, computed in a single pass.
class MonthlyAnalytics {
  /// Expense total for the month.
  final double spend;

  /// Income total for the month.
  final double income;

  /// Expense totals by category id, first-encounter insertion order.
  final Map<String, double> byCategory;

  /// Transactions falling in the month (newest-first input order kept).
  final int txnCount;

  const MonthlyAnalytics({
    required this.spend,
    required this.income,
    required this.byCategory,
    required this.txnCount,
  });
}

/// Epoch-millis half-open month window `[start, end)`, local time.
(int, int) monthBounds(DateTime month) {
  final start = DateTime(month.year, month.month, 1).millisecondsSinceEpoch;
  final end = DateTime(month.year, month.month + 1, 1).millisecondsSinceEpoch;
  return (start, end);
}

/// Single-pass monthly aggregates over [txns] (any order; order within
/// each subset is preserved, matching the historical implementation).
MonthlyAnalytics computeMonthlyAnalytics(List<Txn> txns, DateTime month) {
  final (start, end) = monthBounds(month);
  var spend = 0.0;
  var income = 0.0;
  final byCategory = <String, double>{};
  var count = 0;
  for (final t in txns) {
    if (t.date < start || t.date >= end) continue;
    count++;
    if (t.isExpense) {
      spend += t.amount;
      byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount;
    } else {
      income += t.amount;
    }
  }
  return MonthlyAnalytics(
    spend: spend,
    income: income,
    byCategory: byCategory,
    txnCount: count,
  );
}
