import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Grouped surface used for every block of content: radius 16, a hairline
/// border and zero elevation. [AppCard.group] stacks rows and draws a
/// separator between them, never after the last one.
class AppCard extends StatelessWidget {
  final Widget? child;

  /// Rows for [AppCard.group]. Ignored by the plain constructor.
  final List<Widget>? children;

  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.onTap,
    this.color,
  }) : children = null,
       assert(child != null);

  const AppCard.group({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.color,
  }) : child = null,
       assert(children != null);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rows = children;
    final content = Padding(
      padding: padding,
      child: rows == null
          ? child
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i != rows.length - 1)
                    Divider(height: 1, thickness: 1, color: colors.hairline),
                ],
              ],
            ),
    );

    return Container(
      decoration: BoxDecoration(
        color: color ?? colors.card,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                hoverColor: colors.accent.withValues(alpha: 0.05),
                focusColor: colors.accent.withValues(alpha: 0.10),
                child: content,
              ),
      ),
    );
  }
}
