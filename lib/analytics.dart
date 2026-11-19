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
import 'dart:math' as math;

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

/// The three trailing windows offered by the Insights tab.
enum InsightPeriod { month, quarter, year }

extension InsightPeriodInfo on InsightPeriod {
  /// Number of calendar months in the selected window.
  int get months => switch (this) {
    InsightPeriod.month => 1,
    InsightPeriod.quarter => 3,
    InsightPeriod.year => 12,
  };

  String get label => switch (this) {
    InsightPeriod.month => 'Month',
    InsightPeriod.quarter => '3 months',
    InsightPeriod.year => '12 months',
  };

  /// "Spent this month" / "Spent in the last 3 months".
  String get spentLabel => switch (this) {
    InsightPeriod.month => 'Spent this month',
    InsightPeriod.quarter => 'Spent in the last 3 months',
    InsightPeriod.year => 'Spent in the last 12 months',
  };

  /// "than last month" / "than the previous 3 months".
  String get compareLabel => switch (this) {
    InsightPeriod.month => 'last month',
    InsightPeriod.quarter => 'the previous 3 months',
    InsightPeriod.year => 'the previous 12 months',
  };

  /// Bars stay readable at six; a full year gets one bar per month.
  int get trendMonths => this == InsightPeriod.year ? 12 : 6;
}

/// One month inside the rhythm strip.
class MonthTotal {
  final DateTime month;
  final double spend;
  final double income;

  const MonthTotal({
    required this.month,
    required this.spend,
    required this.income,
  });
}

/// A trailing-period summary for Insights. All money values are raw sums
/// from [Txn.amount]; display currency is applied by the UI.
class InsightsAnalytics {
  /// First day of the selected window (local midnight).
  final DateTime start;

  /// First day after the selected window (local midnight, exclusive).
  final DateTime end;

  /// The first day of the comparison window.
  final DateTime previousStart;

  final double spend;
  final double income;
  final double previousSpend;
  final double previousIncome;

  /// Expense totals by category id, first-encounter insertion order.
  final Map<String, double> byCategory;

  /// Every transaction in the selected window.
  final int txnCount;

  /// Expenses in the selected window.
  final int expenseCount;

  /// Calendar days in the window, and days elapsed up to [computeInsights]'
  /// `asOf` (clamped to the window).
  final int totalDays;
  final int elapsedDays;

  /// Recent months ending at the anchor, oldest first. Includes empty months.
  final List<MonthTotal> trend;

  /// Largest expenses in the selected window, already sorted and capped.
  final List<Txn> topExpenses;

  const InsightsAnalytics({
    required this.start,
    required this.end,
    required this.previousStart,
    required this.spend,
    required this.income,
    required this.previousSpend,
    required this.previousIncome,
    required this.byCategory,
    required this.txnCount,
    required this.expenseCount,
    required this.totalDays,
    required this.elapsedDays,
    required this.trend,
    required this.topExpenses,
  });

  double get net => income - spend;

  double get averagePerDay => elapsedDays <= 0 ? 0 : spend / elapsedDays;

  /// Fractional change against the previous equal-length window, or null
  /// when there is nothing sensible to compare against.
  double? get spendChange {
    if (previousSpend <= 0) return null;
    return (spend - previousSpend) / previousSpend;
  }
}

/// Count calendar days between two local midnights without DST drift.
int _calendarDays(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Builds the Insights summary in a single pass over [txns].
///
/// The selected window ends with [anchor]'s month. The comparison window is
/// the equally long block immediately before it. [asOf] defaults to now and
/// only affects the per-day average; [topLimit] caps the largest-expense list.
InsightsAnalytics computeInsights(
  List<Txn> txns,
  DateTime anchor,
  InsightPeriod period, {
  DateTime? asOf,
  int topLimit = 8,
}) {
  final now = asOf ?? DateTime.now();
  final start = DateTime(anchor.year, anchor.month - (period.months - 1), 1);
  final end = DateTime(anchor.year, anchor.month + 1, 1);
  final previousStart = DateTime(start.year, start.month - period.months, 1);

  final trendMonths = period.trendMonths;
  final trendStart = DateTime(anchor.year, anchor.month - (trendMonths - 1), 1);

  final startMs = start.millisecondsSinceEpoch;
  final endMs = end.millisecondsSinceEpoch;
  final previousStartMs = previousStart.millisecondsSinceEpoch;
  final trendStartMs = trendStart.millisecondsSinceEpoch;
  final earliestMs = math.min(previousStartMs, trendStartMs);

  int monthKey(DateTime d) => d.year * 12 + d.month - 1;

  final trendSpend = <int, double>{};
  final trendIncome = <int, double>{};
  for (var i = 0; i < trendMonths; i++) {
    final m = DateTime(trendStart.year, trendStart.month + i, 1);
    trendSpend[monthKey(m)] = 0;
    trendIncome[monthKey(m)] = 0;
  }

  var spend = 0.0;
  var income = 0.0;
  var previousSpend = 0.0;
  var previousIncome = 0.0;
  var txnCount = 0;
  var expenseCount = 0;
  final byCategory = <String, double>{};
  final top = <Txn>[];

  int byAmount(Txn a, Txn b) {
    final byValue = b.amount.compareTo(a.amount);
    if (byValue != 0) return byValue;
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  for (final t in txns) {
    if (t.date < earliestMs || t.date >= endMs) continue;

    if (t.date >= startMs) {
      txnCount++;
      if (t.isExpense) {
        spend += t.amount;
        expenseCount++;
        byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount;
        if (topLimit > 0 &&
            (top.length < topLimit || t.amount > top.last.amount)) {
          top.add(t);
          top.sort(byAmount);
          if (top.length > topLimit) top.removeLast();
        }
      } else {
        income += t.amount;
      }
    } else if (t.date >= previousStartMs) {
      if (t.isExpense) {
        previousSpend += t.amount;
      } else {
        previousIncome += t.amount;
      }
    }

    if (t.date >= trendStartMs) {
      final key = monthKey(t.dateTime);
      final bucket = trendSpend[key];
      if (bucket != null) {
        if (t.isExpense) {
          trendSpend[key] = bucket + t.amount;
        } else {
          trendIncome[key] = trendIncome[key]! + t.amount;
        }
      }
    }
  }

  final totalDays = _calendarDays(start, end);
  final today = DateTime(now.year, now.month, now.day);
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  final elapsedDays = today.isBefore(startDay)
      ? 0
      : (today.isBefore(endDay)
            ? _calendarDays(startDay, today) + 1
            : totalDays);

  final trend = <MonthTotal>[];
  for (var i = 0; i < trendMonths; i++) {
    final month = DateTime(trendStart.year, trendStart.month + i, 1);
    final key = monthKey(month);
    trend.add(
      MonthTotal(
        month: month,
        spend: trendSpend[key]!,
        income: trendIncome[key]!,
      ),
    );
  }

  return InsightsAnalytics(
    start: start,
    end: end,
    previousStart: previousStart,
    spend: spend,
    income: income,
    previousSpend: previousSpend,
    previousIncome: previousIncome,
    byCategory: byCategory,
    txnCount: txnCount,
    expenseCount: expenseCount,
    totalDays: totalDays,
    elapsedDays: elapsedDays,
    trend: trend,
    topExpenses: top,
  );
}
