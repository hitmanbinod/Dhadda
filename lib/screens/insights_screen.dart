import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/page.dart' show kPageMaxWidth, tabScrollBottomPadding;
import '../widgets/profile_avatar.dart';

/// Insights tab placeholder. The analytics land in the next step; the shell,
/// title row and settings shortcut are wired now so navigation is final.
class InsightsScreen extends StatelessWidget {
  final VoidCallback? onOpenSettings;

  const InsightsScreen({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = math.max(
          Spacing.screen,
          (constraints.maxWidth - kPageMaxWidth) / 2,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            hPad,
            Spacing.sm,
            hPad,
            tabScrollBottomPadding(context),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Insights',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.largeTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Based on your data',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsAvatarButton(
                  name: store.userName,
                  onTap: onOpenSettings,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xl),
            AppCard(
              child: EmptyState(
                icon: Icons.bar_chart_outlined,
                message: 'Your spending patterns will appear here.',
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
              ),
            ),
          ],
        );
      },
    );
  }
}
