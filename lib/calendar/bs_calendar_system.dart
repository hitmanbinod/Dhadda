// BS implementation of the CalendarSystem interface. All BS facts come from
// bs_data.dart through bs_calendar.dart; no numbers live here.
import 'bs_calendar.dart' as bs;
import 'period.dart';

class BsCalendarSystem extends CalendarSystem {
  const BsCalendarSystem();

  @override
  String get id => 'bs';

  @override
  bool get isBs => true;

  @override
  bool supports(DateTime date) => bs.isSupported(date);

  @override
  Period periodByIndex(int index) {
    final year = index ~/ 12;
    final month = index % 12 + 1;
    final start = bs.bsMonthStartAd(year, month);
    final length = bs.daysInBsMonth(year, month);
    final last = bs.bsToAd(bs.BsDate(year, month, length));
    final end = DateTime(last.year, last.month, last.day + 1);
    return Period(
      start: start,
      end: end,
      label: '${bs.bsMonthName(month)} $year',
      daysInPeriod: length,
      index: index,
    );
  }

  @override
  Period periodOf(DateTime date) {
    final d = bs.adToBs(date);
    return periodByIndex(d.year * 12 + d.month - 1);
  }

  @override
  Period yearPeriod(DateTime date) {
    final year = bs.adToBs(date).year;
    final start = periodByIndex(year * 12).start;
    final end = periodByIndex((year + 1) * 12).start;
    return Period(
      start: start,
      end: end,
      label: '$year',
      daysInPeriod: daysBetween(start, end),
      index: year * 12,
    );
  }
}
