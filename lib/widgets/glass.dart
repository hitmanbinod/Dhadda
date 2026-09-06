import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass tint box in the current accent colour.
/// A real blur where content sits behind it, a soft tint elsewhere.
class GlassBox extends StatelessWidget {
  final Widget child;
  const GlassBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: scheme.primary.withValues(alpha: 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}