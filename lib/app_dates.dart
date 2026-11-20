// One central date layer. AD mode delegates to the exact Round 1 formatters;
// BS mode derives labels from bs_data.dart through the active calendar system.
// Stored dates stay Gregorian everywhere — this file only formats and picks.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'calendar/bs_calendar.dart' as bs;
import 'calendar/bs_calendar_system.dart';
import 'calendar/period.dart';
import 'widgets/bs_date_picker.dart';

CalendarSystem _active = const GregorianCalendarSystem();
CalendarSystem get appCalendar => _active;
bool get appIsBs => _active.isBs;

/// Called by the store when `calendar_system` loads or changes.
void setAppCalendar(String id) {
  _active = id == 'bs'
      ? const BsCalendarSystem()
      : const GregorianCalendarSystem();
}

final _dayFmt = DateFormat.yMMMd();
final _monthFmt = DateFormat.yMMMM();
final _shortFmt = DateFormat.MMM();
final _headFmt = DateFormat('EEE, MMM d');
final _headYearFmt = DateFormat('MMM d, yyyy');
final _weekdayFmt = DateFormat.E();

/// Long day label. AD: "Nov 20, 2026". BS: "Fri 4 Mangsir 2083".
String appDayStr(DateTime d) {
  if (!_active.isBs) return _dayFmt.format(d);
  final b = bs.adToBs(d);
  return '${_weekdayFmt.format(d)} ${b.day} ${bs.bsMonthName(b.month)} ${b.year}';
}

/// Short label: AD "Nov 20", BS "4 Mangsir".
String appDayShort(DateTime d) {
  if (!_active.isBs) return DateFormat('MMM d').format(d);
  final b = bs.adToBs(d);
  return '${b.day} ${bs.bsMonthName(b.month)}';
}

/// Month title: AD "November 2026", BS "Mangsir 2083".
String appMonthStr(DateTime d) {
  if (!_active.isBs) return _monthFmt.format(d);
  final b = bs.adToBs(d);
  return '${bs.bsMonthName(b.month)} ${b.year}';
}

/// History day header. [sameYear] keeps the Round 1 short form in AD mode.
String appDayHead(DateTime d, {required bool sameYear}) {
  if (!_active.isBs) {
    return sameYear ? _headFmt.format(d) : _headYearFmt.format(d);
  }
  return appDayStr(d);
}

String appTrendMonthShort(DateTime d) =>
    _active.isBs ? bs.bsMonthName(bs.adToBs(d).month) : _shortFmt.format(d);

String appTrendMonthFull(DateTime d) => appMonthStr(d);

/// The fiscal-year range line under the chip: AD dates in AD mode, BS dates
/// in BS mode, with the same "FY 2083/84" label in both.
String appFiscalRange(Period p) {
  final last = DateTime(p.end.year, p.end.month, p.end.day - 1);
  if (!_active.isBs) {
    final f = DateFormat('d MMM y');
    return '${p.label} · ${f.format(p.start)} to ${f.format(last)}';
  }
  final first = bs.adToBs(p.start);
  final end = bs.adToBs(last);
  return '${p.label} · ${first.day} ${bs.bsMonthName(first.month)} ${first.year}'
      ' to ${end.day} ${bs.bsMonthName(end.month)} ${end.year}';
}

/// FY is defined from the BS table, so hide the chip outside that range.
bool appFiscalSupported(DateTime date) => bs.isSupported(date);

/// Dispatches to the built-in BS picker in BS mode, else the platform picker.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  if (_active.isBs) {
    return showBsDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    );
  }
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
  );
}
