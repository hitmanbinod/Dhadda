// Pure-Dart Bikram Sambat conversion. The ONLY calendar facts here come from
// bs_data.dart — no number is invented, estimated or regenerated in this file.
// Dates are local, date-only midnights; day counts use UTC midnights so DST
// transitions can never shift a result. No I/O, no time-zone lookups.
import 'bs_data.dart';

/// A BS calendar date. Ranges 2070..2086 / 1..12 / 1..daysInBsMonth are
/// validated by the converter; callers should prefer isSupported where a
/// graceful AD fallback is wanted.
class BsDate {
  final int year;
  final int month;
  final int day;

  const BsDate(this.year, this.month, this.day);

  @override
  bool operator ==(Object other) =>
      other is BsDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'BsDate($year-$month-$day)';
}

const List<String> bsMonthNames = [
  'Baisakh',
  'Jestha',
  'Asar',
  'Shrawan',
  'Bhadra',
  'Aswin',
  'Kartik',
  'Mangsir',
  'Poush',
  'Magh',
  'Falgun',
  'Chaitra',
];

String bsMonthName(int month) => bsMonthNames[month - 1];

DateTime _localDay(DateTime d) => DateTime(d.year, d.month, d.day);

int _utcDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

int _daysBetween(DateTime from, DateTime to) => _utcDay(to) - _utcDay(from);

int _yearLength(int year) {
  var total = 0;
  for (final length in bsMonthLengths[year - bsFirstYear]) {
    total += length;
  }
  return total;
}

int _totalDays() {
  var total = 0;
  for (var year = bsFirstYear; year <= bsLastYear; year++) {
    total += _yearLength(year);
  }
  return total;
}

/// Days from 1 Baisakh 2070 to [bs], exclusive of the month/day itself.
int _bsOffset(BsDate bs) {
  var offset = 0;
  for (var year = bsFirstYear; year < bs.year; year++) {
    offset += _yearLength(year);
  }
  for (var month = 1; month < bs.month; month++) {
    offset += bsMonthLengths[bs.year - bsFirstYear][month - 1];
  }
  return offset + bs.day - 1;
}

/// The AD midnight of 1 Baisakh 2070 plus [offset] whole days, rebuilt from
/// UTC components so a DST change cannot introduce a 23/25-hour day.
DateTime _adFromOffset(int offset) {
  final base = bsFirstYearStartAd;
  final utc = DateTime.utc(base.year, base.month, base.day)
      .add(Duration(days: offset));
  return DateTime(utc.year, utc.month, utc.day);
}

bool _validYear(int year) => year >= bsFirstYear && year <= bsLastYear;
bool _validMonth(int month) => month >= 1 && month <= 12;

/// Number of days in one BS month (29-32 per the source table).
int daysInBsMonth(int year, int month) {
  if (!_validYear(year) || !_validMonth(month)) {
    throw RangeError('BS month out of range: $year-$month');
  }
  return bsMonthLengths[year - bsFirstYear][month - 1];
}

/// The AD date of day 1 of a BS month.
DateTime bsMonthStartAd(int year, int month) =>
    _adFromOffset(_bsOffset(BsDate(year, month, 1)));

/// False outside BS 2070-2086 so callers can fall back to Gregorian. Total
/// and never throwing, including for extreme DateTime values.
bool isSupported(DateTime ad) {
  try {
    final offset = _daysBetween(bsFirstYearStartAd, _localDay(ad));
    return offset >= 0 && offset < _totalDays();
  } catch (_) {
    return false;
  }
}

/// True for years after the last officially published BS year.
bool isProvisional(int year) => year > bsLastOfficialYear;

/// Convert an AD date to BS. Check isSupported first for out-of-range dates.
BsDate adToBs(DateTime ad) {
  final day = _localDay(ad);
  final total = _totalDays();
  var remaining = _daysBetween(bsFirstYearStartAd, day);
  if (remaining < 0 || remaining >= total) {
    throw RangeError('AD date outside BS $bsFirstYear-$bsLastYear: $day');
  }

  var year = bsFirstYear;
  while (year <= bsLastYear) {
    final length = _yearLength(year);
    if (remaining < length) break;
    remaining -= length;
    year++;
  }
  var month = 1;
  while (month <= 12) {
    final length = bsMonthLengths[year - bsFirstYear][month - 1];
    if (remaining < length) break;
    remaining -= length;
    month++;
  }
  return BsDate(year, month, remaining + 1);
}

/// Convert a BS date back to AD local midnight.
DateTime bsToAd(BsDate bs) {
  if (!_validYear(bs.year) ||
      !_validMonth(bs.month) ||
      bs.day < 1 ||
      bs.day > daysInBsMonth(bs.year, bs.month)) {
    throw RangeError('Invalid BS date: $bs');
  }
  return _adFromOffset(_bsOffset(bs));
}
