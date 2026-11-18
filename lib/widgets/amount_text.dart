import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/palette.dart';
import '../theme/typography.dart';

/// A money amount with tabular figures and a muted expense/income colour.
/// Uses the app's currency helper, so the symbol always follows the
/// user's selected currency.
class AmountText extends StatelessWidget {
  final double value;
  final String type;
  final bool signed;
  final bool colored;
  final TextStyle? style;
  final String? symbol;
  final TextAlign? textAlign;

  const AmountText(
    this.value, {
    super.key,
    this.type = 'expense',
    this.signed = true,
    this.colored = true,
    this.style,
    this.symbol,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final income = type == 'income';
    final sign = signed ? (income ? '+' : '\u2212') : '';
    final base = style ?? AppType.amount;
    final color = colored
        ? (income ? colors.income : colors.expense)
        : (base.color ?? colors.textPrimary);

    return Text(
      '$sign${money(value, symbol)}',
      textAlign: textAlign,
      maxLines: 1,
      softWrap: false,
      style: base.copyWith(color: color, fontFeatures: AppType.tabular),
    );
  }
}
