import 'package:expense/analytics.dart';
import 'package:expense/app_dates.dart';
import 'package:expense/calendar/bs_calendar.dart';
import 'package:expense/calendar/bs_calendar_system.dart';
import 'package:expense/calendar/bs_data.dart';
import 'package:expense/calendar/period.dart';
import 'package:expense/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Txn txn(String id, double amount, DateTime date) => Txn(
        id: id,
        type: 'expense',
        amount: amount,
        categoryId: 'food',
        date: date.millisecondsSinceEpoch,
      );

  double periodSpend(List<Txn> txns, Period p) => computeMonthlyAnalytics(
        txns,
        p.start,
        periodStart: p.start,
        periodEnd: p.end,
      ).spend;

  group('AD equivalence', () {
    test('Gregorian periods reproduce Round 1 month bounds exactly', () {
      const cal = GregorianCalendarSystem();
      for (final month in [
        DateTime(2024, 2),
        DateTime(2024, 12),
        DateTime(2026, 11),
      ]) {
        final p = cal.periodOf(month);
        final (start, end) = monthBounds(month);
        expect(p.start.millisecondsSinceEpoch, start);
        expect(p.end.millisecondsSinceEpoch, end);
        expect(p.daysInPeriod, daysInMonth(month));
      }
      expect(cal.periodOf(DateTime(2026, 11, 20)).label, monthStr(DateTime(2026, 11, 20)));
      expect(cal.previous(cal.periodOf(DateTime(2026, 1, 1))).start, DateTime(2025, 12, 1));
      expect(cal.next(cal.periodOf(DateTime(2026, 12, 1))).start, DateTime(2027, 1, 1));
    });

    test('AD formatter is unchanged after setAppCalendar', () {
      setAppCalendar('ad');
      expect(appDayStr(DateTime(2026, 11, 20)), dayStr(DateTime(2026, 11, 20)));
      expect(appMonthStr(DateTime(2026, 11, 20)), monthStr(DateTime(2026, 11, 20)));
      expect(appDayHead(DateTime(2026, 11, 20), sameYear: true), 'Fri, Nov 20');
      setAppCalendar('ad');
    });
  });

  group('BS periods', () {
    const cal = BsCalendarSystem();

    test('month label and period boundaries', () {
      final p = cal.periodOf(DateTime(2026, 11, 20));
      expect(p.label, 'Mangsir 2083');
      expect(p.start, DateTime(2026, 11, 17));
      expect(p.daysInPeriod, daysInBsMonth(2083, 8));
      expect(cal.previous(p).label, 'Kartik 2083');
      expect(cal.next(p).label, 'Poush 2083');
    });

    test('totals split on the Asar/Shrawan and Chaitra/Baisakh seams', () {
      final txns = [
        txn('asar-last', 100, DateTime(2026, 7, 16)),
        txn('shrawan-first', 200, DateTime(2026, 7, 17)),
        txn('chaitra-last', 300, DateTime(2026, 4, 13)),
        txn('baisakh-first', 400, DateTime(2026, 4, 14)),
      ];
      expect(periodSpend(txns, cal.periodOf(DateTime(2026, 7, 16))), 100);
      expect(periodSpend(txns, cal.periodOf(DateTime(2026, 7, 17))), 200);
      expect(periodSpend(txns, cal.periodOf(DateTime(2026, 4, 13))), 300);
      expect(periodSpend(txns, cal.periodOf(DateTime(2026, 4, 14))), 400);
    });

    test('the twelve BS months of a year sum to the year total', () {
      final txns = [
        for (var i = 0; i < 12; i++)
          txn('m$i', (i + 1) * 10, bsMonthStartAd(2083, i + 1)),
      ];
      final year = cal.yearPeriod(DateTime(2026, 7, 17));
      var months = 0.0;
      for (var i = 0; i < 12; i++) {
        months += periodSpend(txns, cal.periodByIndex(year.index + i));
      }
      expect(months, 780);
      expect(periodSpend(txns, year), 780);
      expect(year.daysInPeriod, 365);
    });

    test('windows are made of BS months', () {
      final three = cal.window(DateTime(2026, 11, 20), 3);
      expect(three.map((p) => p.label), [
        'Aswin 2083',
        'Kartik 2083',
        'Mangsir 2083',
      ]);
      final six = cal.window(DateTime(2026, 11, 20), 6);
      expect(six.length, 6);
      final year = cal.yearPeriod(DateTime(2026, 11, 20));
      expect(year.start, bsToAd(const BsDate(2083, 1, 1)));
    });

    test('BS formatter uses the central month names', () {
      setAppCalendar('bs');
      expect(appMonthStr(DateTime(2026, 11, 20)), 'Mangsir 2083');
      expect(appDayShort(DateTime(2026, 11, 20)), '4 Mangsir');
      expect(appDayStr(DateTime(2026, 11, 20)), 'Fri 4 Mangsir 2083');
      setAppCalendar('ad');
    });
  });

  group('fiscal year and forecast', () {
    test('FY 2083/84 runs 1 Shrawan 2083 to last day of Asar 2084', () {
      final fy = const GregorianCalendarSystem().fiscalYearOf(DateTime(2026, 11, 20));
      expect(fy.label, 'FY 2083/84');
      expect(fy.start, DateTime(2026, 7, 17));
      expect(fy.end, DateTime(2027, 7, 17));
      final bsFy = const BsCalendarSystem().fiscalYearOf(DateTime(2026, 11, 20));
      expect(bsFy.label, fy.label);
      expect(bsFy.start, fy.start);
      expect(bsFy.end, fy.end);
      // Baisakh 2084 still belongs to FY 2083/84.
      expect(
        const BsCalendarSystem()
            .fiscalYearOf(DateTime(2027, 4, 20))
            .label,
        'FY 2083/84',
      );
    });

    test('forecast scales with 29/30/31/32-day periods', () {
      final seen = <int>{};
      for (var year = bsFirstYear; year <= bsLastYear; year++) {
        for (var month = 1; month <= 12; month++) {
          final p = const BsCalendarSystem().periodByIndex(year * 12 + month - 1);
          seen.add(p.daysInPeriod);
          final now = DateTime(p.start.year, p.start.month, p.start.day + 4);
          final projected = projectPeriodEndSpend(100, p, asOf: now);
          expect(projected, closeTo(100 / 5 * p.daysInPeriod, 1e-9));
        }
      }
      expect(seen, containsAll([29, 30, 31, 32]));
      expect(
        projectPeriodEndSpend(
          100,
          const BsCalendarSystem().periodOf(DateTime(2026, 11, 20)),
          asOf: DateTime(2026, 11, 17),
        ),
        isNull,
      );
    });
  });
}
