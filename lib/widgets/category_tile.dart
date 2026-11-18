import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/tokens.dart';

/// A category's 36x36 tinted icon tile. The tint is the category's own
/// colour at 14%, so stored colours always survive theme changes.
class CategoryTile extends StatelessWidget {
  final Category category;
  final double size;
  final double iconSize;

  const CategoryTile({
    super.key,
    required this.category,
    this.size = Sizes.iconTile,
    this.iconSize = Sizes.iconGlyph,
  });

  @override
  Widget build(BuildContext context) {
    final color = category.colorValue;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.iconRadius,
      ),
      child: Icon(category.iconData, size: iconSize, color: color),
    );
  }
}
