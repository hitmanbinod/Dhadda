import 'models.dart';

/// One "Repeat" chip on the Add screen: a frequent note + category pairing
/// from recent history, with the values needed to pre-fill the form.
class RepeatSuggestion {
  final String note;
  final String categoryId;
  final String mode;
  final double amount;
  final bool isExpense;
  final int count;
  final DateTime lastDate;

  const RepeatSuggestion({
    required this.note,
    required this.categoryId,
    required this.mode,
    required this.amount,
    required this.isExpense,
    required this.count,
    required this.lastDate,
  });

  @override
  String toString() =>
      'RepeatSuggestion($note, $categoryId, $count, $lastDate)';
}

/// Normalises a note for grouping: case-folded, trimmed, inner whitespace
/// collapsed. Empty notes never become a Repeat chip.
String normalizeRepeatNote(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The [limit] most frequent note+category pairings in the last [days] days,
/// most frequent first (then most recent). Pure Dart: no clock reads beyond
/// the injected [now], no I/O, no store access. Expense and income pairings
/// are kept apart so a chip can never pre-fill the wrong entry type.
List<RepeatSuggestion> repeatSuggestions(
  Iterable<Txn> txns, {
  DateTime? now,
  int days = 60,
  int limit = 4,
}) {
  final today = now ?? DateTime.now();
  final cutoff = today.subtract(Duration(days: days));
  final grouped = <String, _Accum>{};

  for (final t in txns) {
    final keyNote = normalizeRepeatNote(t.note);
    if (keyNote.isEmpty) continue;
    final d = t.dateTime;
    if (d.isBefore(cutoff) || d.isAfter(today)) continue;
    final key = '${t.type}|${t.categoryId}|$keyNote';
    final acc = grouped.putIfAbsent(
      key,
      () => _Accum(
        note: t.note.trim(),
        categoryId: t.categoryId,
        mode: t.mode,
        amount: t.amount,
        isExpense: t.isExpense,
        lastDate: d,
      ),
    );
    acc.count++;
    if (d.isAfter(acc.lastDate)) {
      acc
        ..note = t.note.trim()
        ..mode = t.mode
        ..amount = t.amount
        ..lastDate = d;
    }
  }

  final sorted = grouped.values.toList()
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      final byDate = b.lastDate.compareTo(a.lastDate);
      if (byDate != 0) return byDate;
      return a.note.toLowerCase().compareTo(b.note.toLowerCase());
    });
  return [
    for (final a in sorted.take(limit))
      RepeatSuggestion(
        note: a.note,
        categoryId: a.categoryId,
        mode: a.mode,
        amount: a.amount,
        isExpense: a.isExpense,
        count: a.count,
        lastDate: a.lastDate,
      ),
  ];
}

class _Accum {
  String note;
  final String categoryId;
  String mode;
  double amount;
  final bool isExpense;
  DateTime lastDate;
  int count = 0;

  _Accum({
    required this.note,
    required this.categoryId,
    required this.mode,
    required this.amount,
    required this.isExpense,
    required this.lastDate,
  });
}
