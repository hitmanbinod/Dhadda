import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Accent-tinted initial avatar. "D" is the fallback for an empty name.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final double size;

  const ProfileAvatar({super.key, required this.name, this.size = 44});

  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'D';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
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
  final VoidCallback? onTap;

  const SettingsAvatarButton({
    super.key,
    required this.name,
    required this.onTap,
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
              child: Center(child: ProfileAvatar(name: name, size: 36)),
            ),
          ),
        ),
      ),
    );
  }
}
