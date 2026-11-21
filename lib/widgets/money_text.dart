import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/palette.dart';
import '../theme/typography.dart';

/// A money value with the Quiet Ledger symbol treatment: the currency symbol
/// is small, light and text-secondary; the digits stay bold and tabular.
/// [digitsStyle] owns size/weight/colour for the number.
class MoneyText extends StatelessWidget {
  final double value;
  final TextStyle digitsStyle;
  final String? symbol;
  final String? semanticsLabel;

  const MoneyText({
    super.key,
    required this.value,
    required this.digitsStyle,
    this.symbol,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: semanticsLabel ?? '${displaySymbol(symbol)} ${moneyNumber(value)}',
      child: ExcludeSemantics(
        child: RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: '${symbol ?? displaySymbol()} ',
                style: digitsStyle.copyWith(
                  fontSize: (digitsStyle.fontSize ?? 16) * 0.62,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                  fontFeatures: const <FontFeature>[],
                ),
              ),
              TextSpan(
                text: moneyNumber(value),
                style: digitsStyle.copyWith(fontFeatures: AppType.tabular),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
