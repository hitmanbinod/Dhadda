import 'package:flutter/material.dart';

import '../theme/haptics.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

/// Shared anatomy for the Settings screen. Nothing here stores state: the
/// screen keeps every existing action and only supplies content/controls.

/// 16dp card padding + 36dp badge + 12dp gap: where row text starts.
const double kSettingsTextInset = Spacing.lg + Sizes.iconTile + Spacing.md;

/// Bold section title above a card, mirroring Home's "By category" headers.
class SettingsSectionTitle extends StatelessWidget {
  final String title;

  const SettingsSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xs,
        Spacing.xl,
        Spacing.xs,
        Spacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppType.title.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// A card whose dividers start at the row text, not at the card edge.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Padding(
                padding: const EdgeInsets.only(
                  left: kSettingsTextInset,
                  right: Spacing.lg,
                ),
                child: Divider(height: 1, thickness: 1, color: colors.hairline),
              ),
          ],
        ],
      ),
    );
  }
}

/// Soft-tinted 36dp rounded-square icon badge used by every standard row.
class SettingsIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final bool destructive;

  const SettingsIconBadge(
    this.icon, {
    super.key,
    this.color,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tint = color ?? (destructive ? colors.expense : colors.accent);
    return Container(
      width: Sizes.iconTile,
      height: Sizes.iconTile,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: destructive ? 0.13 : 0.14),
        borderRadius: Radii.iconRadius,
      ),
      child: Icon(icon, size: Sizes.iconGlyph, color: tint),
    );
  }
}

/// One setting row: 16dp inner padding, badge, 12dp gap, text column,
/// trailing control. [content] lets complex rows (backup, SMS, About) keep
/// the same anatomy while hosting their own widgets under the text.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final bool destructive;
  final String title;
  final String? subtitle;
  final String? note;
  final Widget? trailing;
  final Widget? content;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.destructive = false,
    this.subtitle,
    this.note,
    this.trailing,
    this.content,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            SettingsIconBadge(
              icon,
              color: iconColor,
              destructive: destructive,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: destructive
                          ? colors.expense
                          : colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      style: AppType.caption.copyWith(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (content != null) ...[
                    const SizedBox(height: Spacing.md),
                    content!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Spacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

/// A switch row whose whole surface toggles the value (like SwitchListTile),
/// while keeping the badge/text/switch anatomy identical to every other row.
class SettingsSwitchRow extends StatelessWidget {
  final Key? switchKey;
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? note;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchRow({
    super.key,
    this.switchKey,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.iconColor,
    this.subtitle,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: switchKey,
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      note: note,
      // The Switch is visual here; the InkWell on the row owns the tap so a
      // hit anywhere on the toggles row changes the value exactly once.
      trailing: IgnorePointer(child: Switch(value: value, onChanged: (_) {})),
      onTap: () => onChanged(!value),
    );
  }
}

/// Trailing chevron for navigation/action rows.
class SettingsChevron extends StatelessWidget {
  final bool destructive;

  const SettingsChevron({super.key, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Icon(
      Icons.chevron_right,
      size: 20,
      color: destructive ? colors.expense : colors.textSecondary,
    );
  }
}

/// Pill-shaped segmented control with the active pill bound to the app accent
/// and contrasting [AppColors.onAccent] label. Used for the 3-way theme
/// selector and the inline 2-way choices (calendar, SMS mode).
class PillSegments extends StatelessWidget {
  final List<String> labels;
  final List<Key?>? keys;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool compact;
  final bool fullWidth;

  const PillSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.keys,
    this.compact = false,
    this.fullWidth = false,
  }) : assert(keys == null || keys.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final duration = Motion.of(context, Motion.fast);

    Widget segment(int i) {
      final active = i == selected;
      return Semantics(
        button: true,
        selected: active,
        label: labels[i],
        child: InkWell(
          key: keys?[i],
          borderRadius: Radii.pillRadius,
          onTap: () {
            if (active) return;
            Haptics.selection();
            onChanged(i);
          },
          child: AnimatedContainer(
            duration: duration,
            curve: Motion.ease,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? Spacing.md : Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: active ? colors.accent : Colors.transparent,
              borderRadius: Radii.pillRadius,
            ),
            child: Text(
              labels[i],
              maxLines: 1,
              style: AppType.caption.copyWith(
                fontSize: compact ? 12 : 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? colors.onAccent : colors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: compact ? 36 : Sizes.segmentedHeight,
      padding: const EdgeInsets.all(Radii.segmentInset),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            if (fullWidth)
              Expanded(child: segment(i))
            else
              segment(i),
        ],
      ),
    );
  }
}
