import 'package:expense/format.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:expense/theme/palette.dart';
import 'package:expense/theme/typography.dart';
import 'package:expense/widgets/amount_text.dart';
import 'package:expense/widgets/app_card.dart';
import 'package:expense/widgets/category_tile.dart';
import 'package:expense/widgets/segmented_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const seed = Color(0xFF009688);

  test('theme exposes readable light/dark roles and grouped cards', () {
    final dark = AppTheme.build(seed, Brightness.dark);
    final darkColors = dark.extension<AppColors>()!;
    final light = AppTheme.build(seed, Brightness.light);
    final lightColors = light.extension<AppColors>()!;

    expect(dark.scaffoldBackgroundColor, const Color(0xFF0E1413));
    expect(darkColors.background, const Color(0xFF0E1413));
    expect(darkColors.card, const Color(0xFF141D1C));
    expect(darkColors.expense, const Color(0xFFF0948A));
    expect(darkColors.income, const Color(0xFF86D0A6));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF4F7F6));

    for (final colors in [darkColors, lightColors]) {
      expect(
        contrastRatio(colors.textPrimary, colors.card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.textSecondary, colors.card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.expense, colors.card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.income, colors.card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.onAccent, colors.accent),
        greaterThanOrEqualTo(4.5),
      );
    }

    final card = dark.cardTheme.shape! as RoundedRectangleBorder;
    expect(card.borderRadius, BorderRadius.circular(16));
    expect(card.side.color, darkColors.cardBorder);
    expect(
      AppType.heroAmount.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    expect(dark.textTheme.bodyLarge?.fontSize, 16);
    expect(
      dark.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<FadeForwardsPageTransitionsBuilder>(),
    );
  });

  testWidgets('AppCard groups rows and SegmentedTabs changes selection', (
    tester,
  ) async {
    var selected = 0;
    final food = Category(
      id: 'food',
      name: 'Food',
      icon: Icons.restaurant.codePoint,
      color: 0xFFEF6C00,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(seed, Brightness.dark),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard.group(
                      children: [
                        ListTile(title: const Text('One')),
                        ListTile(title: const Text('Two')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SegmentedTabs(
                      labels: const ['Entries', 'Categories', 'Events'],
                      selectedIndex: selected,
                      onChanged: (i) => setState(() => selected = i),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CategoryTile(category: food),
                        const SizedBox(width: 12),
                        const AmountText(1200),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('\u2212${money(1200)}'), findsOneWidget);

    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}
