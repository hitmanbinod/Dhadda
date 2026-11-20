// Calendar abstraction for month/period maths. Period bounds are local
// midnights, inclusive start / exclusive end. Gregorian behaviour is exactly
// the Round 1 behaviour, so AD-mode results stay bit-identical.
import 'package:intl/intl.dart';

import 'bs_calendar.dart' as bs;

/// One calendar period (normally a month, sometimes a fiscal year).
class Period {
  final DateTime start;
  final DateTime end;
  final String label;
  final int daysInPeriod;

  /// Calendar-specific month index, used for previous/next/window maths.
  final int index;

  const Period({
    required this.start,
    required this.end,
    required this.label,
    required this.daysInPeriod,
    required this.index,
  });

  bool contains(DateTime d) =>
      !d.isBefore(start) && d.isBefore(end);

  /// 0-based day number inside the period.
  int dayIndex(DateTime d) => daysBetween(start, d);

  @override
  String toString() => 'Period($label, $start..$end, $daysInPeriod days)';
}

int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Interface implemented by both calendar systems.
abstract class CalendarSystem {
  const CalendarSystem();

  String get id;
  bool get isBs;

  Period periodOf(DateTime date);
  Period periodByIndex(int index);

  Period previous(Period period) => periodByIndex(period.index - 1);
  Period next(Period period) => periodByIndex(period.index + 1);

  /// [count] consecutive periods ending with the one containing [anchor].
  List<Period> window(DateTime anchor, int count) {
    final last = periodOf(anchor).index;
    return [
      for (var i = count - 1; i >= 0; i--) periodByIndex(last - i),
    ];
  }

  /// For AD this is a trailing 12-month window (Round 1 semantics). For BS it
  /// is the Baisakh-Chaitra year containing [date].
  Period yearPeriod(DateTime date);

  /// Nepal fiscal year: 1 Shrawan to the last day of Asar of the next BS year.
  Period fiscalYearOf(DateTime date) => buildFiscalPeriod(date);

  bool supports(DateTime date);
  String labelFor(DateTime date) => periodOf(date).label;
}

final _monthFmt = DateFormat.yMMMM();

/// Fiscal year is defined in BS terms in both modes, so it lives here rather
/// than in either calendar system.
Period buildFiscalPeriod(DateTime date) => _fiscalFromAnchor(date);

Period _fiscalFromAnchor(DateTime date) {
  final bsDate = bs.adToBs(date);
  final startYear = bsDate.month >= 4 ? bsDate.year : bsDate.year - 1;
  final start = bs.bsToAd(bs.BsDate(startYear, 4, 1));
  final lastAsar = bs.BsDate(startYear + 1, 3, bs.daysInBsMonth(startYear + 1, 3));
  final lastDay = bs.bsToAd(lastAsar);
  final end = DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
  return Period(
    start: start,
    end: end,
    daysInPeriod: daysBetween(start, end),
    label: 'FY $startYear/${(startYear + 1) % 100}',
    index: startYear * 12 + 3,
  );
}

/// Gregorian system: drop-in replacement for the Round 1 month maths.
class GregorianCalendarSystem extends CalendarSystem {
  const GregorianCalendarSystem();

  @override
  String get id => 'ad';

  @override
  bool get isBs => false;

  @override
  bool supports(DateTime date) => true;

  @override
  Period periodByIndex(int index) {
    final year = index ~/ 12;
    final month = index % 12 + 1;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return Period(
      start: start,
      end: end,
      label: _monthFmt.format(start),
      daysInPeriod: DateTime(year, month + 1, 0).day,
      index: index,
    );
  }

  @override
  Period periodOf(DateTime date) =>
      periodByIndex(date.year * 12 + date.month - 1);

  @override
  Period yearPeriod(DateTime date) {
    final p = periodOf(date);
    return Period(
      start: periodByIndex(p.index - 11).start,
      end: p.end,
      label: p.label,
      daysInPeriod: daysBetween(periodByIndex(p.index - 11).start, p.end),
      index: p.index,
    );
  }

  @override
  Period fiscalYearOf(DateTime date) {
    if (!bs.isSupported(date)) {
      // Outside the BS table: a calm Gregorian fallback (July-June).
      final year = date.month >= 7 ? date.year : date.year - 1;
      final start = DateTime(year, 7, 1);
      final end = DateTime(year + 1, 7, 1);
      return Period(
        start: start,
        end: end,
        daysInPeriod: daysBetween(start, end),
        label: 'FY ${year + 1}',
        index: year * 12 + 6,
      );
    }
    return buildFiscalPeriod(date);
  }
}
