import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Profile picture. "Minimal" shows an accent-tinted initial ("D" when the
/// name is empty); "classic" shows a person glyph in the same circle.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String style; // minimal | classic

  const ProfileAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.style = 'minimal',
  });

  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'D';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final classic = style == 'classic';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: classic ? 0.2 : 0.14),
        shape: BoxShape.circle,
        border: classic
            ? Border.all(color: colors.accent.withValues(alpha: 0.35))
            : null,
      ),
      child: classic
          ? Icon(
              Icons.person_rounded,
              size: size * 0.62,
              color: colors.accent,
            )
          : Text(
              initial,
              style: AppType.title.copyWith(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
    );
  }
}

/// 36 dp avatar with a full 48 dp tap target, used in tab title rows.
class SettingsAvatarButton extends StatelessWidget {
  final String name;
  final String style;
  final VoidCallback? onTap;

  const SettingsAvatarButton({
    super.key,
    required this.name,
    required this.onTap,
    this.style = 'minimal',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Settings',
      child: Semantics(
        button: true,
        label: 'Open settings',
        child: SizedBox(
          width: Sizes.minTap,
          height: Sizes.minTap,
          child: Material(
            type: MaterialType.transparency,
            child: InkResponse(
              onTap: onTap,
              radius: Sizes.minTap / 2,
              child: Center(
                child: ProfileAvatar(name: name, size: 36, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
