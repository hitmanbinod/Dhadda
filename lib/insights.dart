// Pure, database-free helpers for the Insights cards.
//
// These functions never read the store, the clock (except via explicit
// arguments) or the filesystem, so they are deterministic and cheap to test.
// The UI owns formatting, colours and navigation.
import 'analytics.dart';
import 'models.dart';

/// Id used for the grouped tail slice when there are more than [top] accounts.
const String kOtherAccountsId = '__other_accounts__';

/// One entry in the "How you pay" bar and legend.
class PaymentSlice {
  /// Account id, or [kOtherAccountsId] for the grouped tail.
  final String id;
  final String label;

  /// ARGB from the account, or 0 when the UI should use its fallback colour.
  final int color;
  final double amount;

  const PaymentSlice({
    required this.id,
    required this.label,
    required this.color,
    required this.amount,
  });
}

/// Account shares of expense spend inside the selected period.
class HowYouPay {
  /// Sorted by amount, descending; the grouped tail (when present) is last.
  final List<PaymentSlice> slices;

  /// Total expense spend in the window, including the grouped tail.
  final double total;

  const HowYouPay({required this.slices, required this.total});
}

/// Groups expense spend in `[start, end)` by effective account.
///
/// Income is excluded, loans are not transactions at all, archived accounts
/// are included when they have spend, and only non-zero accounts appear.
/// Accounts beyond [top] are folded into one "Other accounts" slice. The
/// [accountIdFor] resolver lets callers map legacy mode-only entries onto
/// the user's active accounts without coupling this function to the store.
HowYouPay computeHowYouPay(
  List<Txn> txns, {
  required DateTime start,
  required DateTime end,
  required List<Account> accounts,
  required String Function(Txn) accountIdFor,
  int top = 5,
}) {
  final startMs = start.millisecondsSinceEpoch;
  final endMs = end.millisecondsSinceEpoch;
  final totals = <String, double>{};

  for (final t in txns) {
    if (!t.isExpense) continue;
    if (t.date < startMs || t.date >= endMs) continue;
    final id = accountIdFor(t);
    if (id.isEmpty) continue;
    totals[id] = (totals[id] ?? 0) + t.amount;
  }

  if (totals.isEmpty) return const HowYouPay(slices: <PaymentSlice>[], total: 0);

  final byId = <String, Account>{for (final a in accounts) a.id: a};
  final sorted = totals.entries.toList()
    ..sort((a, b) {
      final byAmount = b.value.compareTo(a.value);
      return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
    });

  final slices = <PaymentSlice>[
    for (final e in sorted.take(top))
      PaymentSlice(
        id: e.key,
        label: byId[e.key]?.name ?? 'Unknown account',
        color: byId[e.key]?.color ?? 0,
        amount: e.value,
      ),
  ];
  if (sorted.length > top) {
    slices.add(
      PaymentSlice(
        id: kOtherAccountsId,
        label: 'Other accounts',
        color: 0,
        amount: sorted.skip(top).fold<double>(0, (sum, e) => sum + e.value),
      ),
    );
  }

  final total = totals.values.fold<double>(0, (sum, value) => sum + value);
  return HowYouPay(slices: slices, total: total);
}

/// Month/period-end projection for an Insights window that is still running.
///
/// Returns null for closed periods so the card can stay quiet on history.
double? projectInsightsEndSpend(
  InsightsAnalytics data, {
  DateTime? asOf,
}) {
  final nowMs = (asOf ?? DateTime.now()).millisecondsSinceEpoch;
  if (nowMs < data.start.millisecondsSinceEpoch ||
      nowMs >= data.end.millisecondsSinceEpoch) {
    return null;
  }
  if (data.elapsedDays <= 0) return null;
  return data.averagePerDay * data.totalDays;
}
