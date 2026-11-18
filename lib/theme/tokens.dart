import 'package:flutter/material.dart';

/// Shared spacing scale. Screens compose these values instead of
/// inventing their own gaps.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page margin on phones.
  static const double screen = 20;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: screen);
}

/// Corner radii. Small surfaces (icon tiles, segmented controls) use
/// tighter corners than cards; buttons and chips are pills.
abstract final class Radii {
  static const double icon = 10;
  static const double chip = 16;
  static const double card = 16;
  static const double segmented = 10;
  static const double segmentInset = 3;
  static const double segment = segmented - segmentInset;
  static const double field = 12;
  static const double sheet = 24;
  static const double pill = 999;

  static const BorderRadius iconRadius = BorderRadius.all(
    Radius.circular(icon),
  );
  static const BorderRadius chipRadius = BorderRadius.all(
    Radius.circular(chip),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius segmentedRadius = BorderRadius.all(
    Radius.circular(segmented),
  );
  static const BorderRadius fieldRadius = BorderRadius.all(
    Radius.circular(field),
  );
  static const BorderRadius sheetRadius = BorderRadius.all(
    Radius.circular(sheet),
  );
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
}

/// Fixed component sizes that keep touch targets and icon tiles
/// consistent across screens.
abstract final class Sizes {
  static const double minTap = 48;
  static const double iconTile = 36;
  static const double iconGlyph = 19;
  static const double navIcon = 22;
  static const double segmentedHeight = 48;
  static const double searchHeight = 40;
  static const double amountColumn = 80;
}

/// Motion constants. Durations stay inside the 150-300 ms band and every
/// animation eases out; reduced-motion users get instant changes.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve ease = Curves.easeOutCubic;

  /// [duration], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, [Duration duration = base]) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? Duration.zero : duration;
  }
}
