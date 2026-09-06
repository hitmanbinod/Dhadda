import 'package:intl/intl.dart';

export 'models.dart';

/// Display currency symbol. The store sets it at startup and whenever the
/// user picks another currency, so every money() call follows along.
String _displaySymbol = 'रू';
void setDisplaySymbol(String s) {
  if (s.isNotEmpty) _displaySymbol = s;
}

// Cached formatters: NumberFormat construction is expensive and money()
// runs per list row, so one instance per symbol is kept for good.
final _fmtCache = <String, NumberFormat>{};

String money(double v, [String? symbol]) {
  final sym = (symbol == null || symbol.isEmpty) ? _displaySymbol : symbol;
  var f = _fmtCache[sym];
  f ??= _fmtCache[sym] =
      NumberFormat.currency(symbol: '$sym ', decimalDigits: 0);
  return f.format(v);
}

/// Strict cash parser: digits with optional thousand-commas and up to
/// 2 decimals. Returns null for anything else (letters, signs, etc.).
double? parseAmount(String raw) {
  final s = raw.trim().replaceAll(',', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
  final v = double.tryParse(s);
  if (v == null || v <= 0) return null;
  return v;
}

final _dayFmt = DateFormat.yMMMd();
final _monthFmt = DateFormat.yMMMM();

String dayStr(DateTime d) => _dayFmt.format(d);
String monthStr(DateTime m) => _monthFmt.format(m);

/// Daypart for the home greeting. Pure and unit-tested.
String daypartFor(DateTime t) {
  final h = t.hour;
  if (h < 12) return 'morning';
  if (h < 17) return 'afternoon';
  return 'evening';
}

/// "Good evening, Ram" - or just "Good evening" when nameless.
String homeGreeting(String name, DateTime now) {
  final daypart = daypartFor(now);
  final n = name.trim();
  return n.isEmpty ? 'Good $daypart' : 'Good $daypart, $n';
}