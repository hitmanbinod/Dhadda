import 'package:expense/calendar/bs_calendar.dart';
import 'package:expense/calendar/bs_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Step 2: the converter is derived ONLY from bs_data.dart. No BS number is
/// hard-coded in these tests beyond the anchors supplied by the maintainer.
void main() {
  int utcDay(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  group('verified anchors', () {
    test('1 Baisakh for the anchor years', () {
      expect(bsToAd(const BsDate(2080, 1, 1)), DateTime(2023, 4, 14));
      expect(bsToAd(const BsDate(2081, 1, 1)), DateTime(2024, 4, 13));
      expect(bsToAd(const BsDate(2082, 1, 1)), DateTime(2025, 4, 14));
      expect(bsToAd(const BsDate(2083, 1, 1)), DateTime(2026, 4, 14));
      expect(bsToAd(const BsDate(2084, 1, 1)), DateTime(2027, 4, 14));
    });

    test('Shrawan / Asar 2083 boundary', () {
      expect(bsToAd(const BsDate(2083, 4, 1)), DateTime(2026, 7, 17));
      expect(daysInBsMonth(2083, 3), 32);
      expect(bsToAd(const BsDate(2083, 3, 32)), DateTime(2026, 7, 16));
      expect(adToBs(DateTime(2026, 7, 16)), const BsDate(2083, 3, 32));
      expect(adToBs(DateTime(2026, 7, 17)), const BsDate(2083, 4, 1));
    });

    test('a day inside Mangsir and the Chaitra/Baisakh seam', () {
      expect(adToBs(DateTime(2026, 11, 20)), const BsDate(2083, 8, 4));
      expect(
        bsToAd(BsDate(2082, 12, daysInBsMonth(2082, 12))),
        DateTime(2026, 4, 13),
      );
      expect(adToBs(DateTime(2026, 4, 13)).month, 12);
      expect(adToBs(DateTime(2026, 4, 13)).year, 2082);
    });

    test('month start helper and names', () {
      expect(bsMonthStartAd(2083, 1), DateTime(2026, 4, 14));
      expect(bsMonthStartAd(2083, 4), DateTime(2026, 7, 17));
      expect(bsMonthName(1), 'Baisakh');
      expect(bsMonthName(8), 'Mangsir');
      expect(bsMonthName(12), 'Chaitra');
      expect(bsMonthNames.length, 12);
    });
  });

  group('table integrity', () {
    test('every month is 29-32 days and every year 365/366', () {
      final expected = <int, int>{
        2070: 365, 2071: 365, 2072: 365, 2073: 366, 2074: 365,
        2075: 365, 2076: 365, 2077: 366, 2078: 365, 2079: 365,
        2080: 365, 2081: 366, 2082: 365, 2083: 365, 2084: 365,
        2085: 366, 2086: 365,
      };
      var grand = 0;
      for (var year = bsFirstYear; year <= bsLastYear; year++) {
        var total = 0;
        for (var month = 1; month <= 12; month++) {
          final length = daysInBsMonth(year, month);
          expect(length, inInclusiveRange(29, 32), reason: '$year-$month');
          total += length;
        }
        expect(total, expected[year], reason: '$year');
        grand += total;
      }
      expect(grand, 6209);
    });

    test('months and years are contiguous, with no gaps or overlaps', () {
      for (var year = bsFirstYear; year <= bsLastYear; year++) {
        for (var month = 1; month <= 12; month++) {
          final start = bsMonthStartAd(year, month);
          final length = daysInBsMonth(year, month);
          late DateTime next;
          if (month < 12) {
            next = bsMonthStartAd(year, month + 1);
          } else if (year < bsLastYear) {
            next = bsMonthStartAd(year + 1, 1);
          } else {
            continue;
          }
          expect(utcDay(next) - utcDay(start), length, reason: '$year-$month');
        }
      }
    });
  });

  group('round trips', () {
    test('every day from 1 Baisakh 2070 to the last day of 2086', () {
      final last = bsToAd(
        BsDate(bsLastYear, 12, daysInBsMonth(bsLastYear, 12)),
      );
      var day = bsFirstYearStartAd;
      var count = 0;
      while (!day.isAfter(last)) {
        final bs = adToBs(day);
        expect(bsToAd(bs), day, reason: '$day -> $bs');
        expect(adToBs(bsToAd(bs)), bs, reason: '$day -> $bs');
        day = DateTime(day.year, day.month, day.day + 1);
        count++;
      }
      expect(count, 6209);
    });

    test('time of day is ignored, local midnights stay local', () {
      final late = DateTime(2026, 11, 20, 23, 59, 59, 999);
      expect(adToBs(late), const BsDate(2083, 8, 4));
      expect(bsToAd(const BsDate(2083, 8, 4)), DateTime(2026, 11, 20));
    });
  });

  group('range safety', () {
    test('isSupported covers the table and rejects outside dates', () {
      expect(isSupported(bsFirstYearStartAd), isTrue);
      expect(isSupported(DateTime(2026, 11, 20)), isTrue);
      expect(
        isSupported(bsToAd(BsDate(bsLastYear, 12, 30))),
        isTrue,
      );
      for (final d in [
        DateTime(2013, 4, 13),
        DateTime(2010, 1, 1),
        DateTime(2035, 1, 1),
        DateTime(1),
        DateTime(9999, 12, 31),
      ]) {
        expect(isSupported(d), isFalse, reason: '$d');
        expect(() => isSupported(d), returnsNormally, reason: '$d');
      }
    });

    test('isProvisional only after the official table', () {
      expect(isProvisional(bsLastOfficialYear), isFalse);
      expect(isProvisional(bsLastOfficialYear + 1), isTrue);
      expect(isProvisional(bsFirstYear), isFalse);
    });

    test('invalid BS dates throw a clear RangeError', () {
      expect(() => daysInBsMonth(2069, 1), throwsRangeError);
      expect(() => daysInBsMonth(2087, 1), throwsRangeError);
      expect(() => daysInBsMonth(2083, 13), throwsRangeError);
      expect(() => bsToAd(const BsDate(2083, 3, 33)), throwsRangeError);
      expect(() => adToBs(DateTime(2010)), throwsRangeError);
    });
  });
}
