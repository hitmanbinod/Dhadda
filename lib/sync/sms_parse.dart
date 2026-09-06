import '../models.dart';

/// Parses bank / wallet transaction SMS into expense candidates.
/// Pure Dart: fully unit-tested. Supported shapes (NP + generic):
/// "Rs.1,000 debited ...", "debited by 500.00 ...", "NPR 2,000 credited".
class SmsCandidate {
  final String id;
  final String sender;
  final String body;
  final DateTime date;
  final double amount;
  final bool isIncome;
  final String merchant;
  final String mode; // bank | ewallet | cash

  const SmsCandidate({
    required this.id,
    required this.sender,
    required this.body,
    required this.date,
    required this.amount,
    required this.isIncome,
    required this.merchant,
    required this.mode,
  });
}

double? _firstAmount(String text) {
  final m = RegExp(
    r'(?:Rs\.?|NPR|Nrs\.?|INR|रू)\s?([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

bool _hasAny(String text, List<String> words) {
  final l = text.toLowerCase();
  for (final w in words) {
    if (l.contains(w)) return true;
  }
  return false;
}

const _expenseWords = [
  'debited',
  'debit',
  'spent',
  'paid',
  'purchase',
  'withdrawn',
  'withdrawal',
  'charged',
  'payment',
];

const _incomeWords = [
  'credited',
  'credit',
  'received',
  'deposited',
  'cashback',
  'refund',
];

String _merchant(String text) {
  final m = RegExp(
    r'(?:\bat\b|\bto\b|\bfrom\b)\s+([A-Za-z0-9 .&-]{3,30})',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return '';
  return m.group(1)!.trim().replaceAll(RegExp(r'[. ]+$'), '');
}

String _modeFor(String sender) {
  final s = sender.toLowerCase();
  if (s.contains('esewa') ||
      s.contains('khalti') ||
      s.contains('fonepay') ||
      s.contains('imepay')) {
    return 'ewallet';
  }
  return 'bank';
}

/// Keyword hints mapping remarks to well-known category names.
const _catKeywords = {
  'bhatbhateni': 'Shopping',
  'daraz': 'Shopping',
  'sastodeal': 'Shopping',
  'thamel': 'Shopping',
  'mall': 'Shopping',
  'mart': 'Shopping',
  'foodmandu': 'Food',
  'restaurant': 'Food',
  'cafe': 'Food',
  'bakery': 'Food',
  'petrol': 'Fuel',
  'fuel': 'Fuel',
  'hospital': 'Health',
  'clinic': 'Health',
  'pharmacy': 'Health',
  'medicine': 'Health',
  'school': 'Bills',
  'college': 'Bills',
  'electricity': 'Bills',
  'internet': 'Bills',
  'recharge': 'Bills',
  'topup': 'Bills',
  'bus': 'Travel',
  'taxi': 'Travel',
  'pathao': 'Travel',
  'indrive': 'Travel',
  'hotel': 'Travel',
  'flight': 'Travel',
  'airlines': 'Travel',
  'rent': 'Rent',
};

/// Picks a category for an SMS: first any custom category name found
/// in the merchant/remarks, then the keyword table, else Other.
String categorizeSms({
  required String merchant,
  required String body,
  required List<Category> candidates,
}) {
  if (candidates.isEmpty) return '';
  final hay = '${merchant.toLowerCase()} ${body.toLowerCase()}';
  for (final c in candidates) {
    final n = c.name.trim().toLowerCase();
    if (n.length > 2 && n != 'other' && hay.contains(n)) {
      return c.id;
    }
  }
  for (final e in _catKeywords.entries) {
    if (hay.contains(e.key)) {
      for (final c in candidates) {
        if (c.name.toLowerCase() == e.value.toLowerCase()) {
          return c.id;
        }
      }
    }
  }
  for (final c in candidates) {
    if (c.id == 'other') return c.id;
  }
  return candidates.first.id;
}

/// Returns null when the SMS is not a recognizable transaction.
/// When [allowedSenders] is non-empty, anything else is junk.
SmsCandidate? parseSms({
  required String id,
  required String sender,
  required String body,
  required int dateMs,
  List<String> allowedSenders = const [],
}) {
  if (allowedSenders.isNotEmpty) {
    final s = sender.toLowerCase();
    final ok = allowedSenders.any((a) {
      final t = a.trim().toLowerCase();
      return t.length >= 2 && (s.contains(t) || t.contains(s));
    });
    if (!ok) return null;
  }
  final amount = _firstAmount(body);
  if (amount == null || amount <= 0) return null;
  final looksExpense = _hasAny(body, _expenseWords);
  final looksIncome = _hasAny(body, _incomeWords);
  if (!looksExpense && !looksIncome) return null;
  return SmsCandidate(
    id: id,
    sender: sender,
    body: body,
    date: DateTime.fromMillisecondsSinceEpoch(dateMs),
    amount: amount,
    isIncome: looksIncome && !looksExpense,
    merchant: _merchant(body),
    mode: _modeFor(sender),
  );
}