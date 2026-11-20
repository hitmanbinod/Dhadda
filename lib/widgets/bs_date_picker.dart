import 'package:flutter/material.dart';

import '../calendar/bs_calendar.dart' as bs;
import '../calendar/bs_data.dart' as data;
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Built-in BS date picker: year stepper, month grid and a day grid whose
/// first-column offset comes from the weekday of day 1. No new packages.
Future<DateTime?> showBsDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  var current = bs.isSupported(initialDate)
      ? bs.adToBs(initialDate)
      : bs.adToBs(data.bsFirstYearStartAd);
  final colors = AppColors.of(context);

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final length = bs.daysInBsMonth(current.year, current.month);
        final firstWeekday = bs.bsToAd(bs.BsDate(current.year, current.month, 1)).weekday;
        final lastSupported = bs.bsToAd(
          bs.BsDate(data.bsLastYear, 12, bs.daysInBsMonth(data.bsLastYear, 12)),
        );
        final lo = firstDate.isBefore(data.bsFirstYearStartAd)
            ? data.bsFirstYearStartAd
            : firstDate;
        final hi = lastDate.isAfter(lastSupported) ? lastSupported : lastDate;
        final minYear = bs.adToBs(lo).year;
        final maxYear = bs.adToBs(hi).year;

        return AlertDialog(
          title: Text(helpText ?? 'Choose date', style: AppType.sectionTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous year',
                        onPressed: current.year <= minYear
                            ? null
                            : () => setState(() => current = bs.BsDate(
                                current.year - 1, current.month, 1)),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          '${bs.bsMonthName(current.month)} ${current.year}',
                          textAlign: TextAlign.center,
                          style: AppType.title,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next year',
                        onPressed: current.year >= maxYear
                            ? null
                            : () => setState(() => current = bs.BsDate(
                                current.year + 1, current.month, 1)),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xs,
                    children: [
                      for (var m = 1; m <= 12; m++)
                        SizedBox(
                          width: 76,
                          child: ChoiceChip(
                            label: Text(
                              bs.bsMonthName(m),
                              overflow: TextOverflow.ellipsis,
                            ),
                            showCheckmark: false,
                            selected: current.month == m,
                            onSelected: (_) => setState(() => current =
                                bs.BsDate(current.year, m, 1)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  Row(
                    children: [
                      for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: AppType.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xs),
                  for (var row = 0; row < (firstWeekday - 1 + length + 6) ~/ 7; row++)
                    Row(
                      children: [
                        for (var col = 1; col <= 7; col++)
                          Expanded(
                            child: () {
                              final day = row * 7 + col - (firstWeekday - 1);
                              if (day < 1 || day > length) {
                                return const SizedBox(height: 44);
                              }
                              return SizedBox(
                                height: 44,
                                child: InkWell(
                                  onTap: () => Navigator.of(ctx).pop(
                                    bs.bsToAd(
                                      bs.BsDate(current.year, current.month, day),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('$day', style: AppType.body),
                                  ),
                                ),
                              );
                            }(),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );
}
