import 'package:flutter/material.dart';

/// The app's type scale. Keep amounts tabular so columns line up, and
/// express hierarchy through size/weight instead of colour alone.
abstract final class AppType {
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  static const TextStyle heroAmount = TextStyle(
    fontSize: 56,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -2,
    fontFeatures: tabular,
  );

  /// The year beside a large month title: 22/500, quieter than the month.
  static const TextStyle yearTitle = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );

  /// The big amount in the Add/Edit editor.
  static const TextStyle editorAmount = TextStyle(
    fontSize: 48,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    fontFeatures: tabular,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  static const TextStyle amount = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontFeatures: tabular,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  /// Day headers and other small all-caps labels.
  static const TextStyle captionStrong = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );

  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static const TextStyle navLabel = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  /// Material text roles used by older screens, coloured with the
  /// semantic primary/secondary text roles.
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    TextStyle p(TextStyle style) => style.copyWith(color: primary);
    TextStyle s(TextStyle style) => style.copyWith(color: secondary);

    return TextTheme(
      displayLarge: p(heroAmount),
      displayMedium: p(largeTitle),
      displaySmall: p(largeTitle.copyWith(fontSize: 28)),
      headlineLarge: p(sectionTitle),
      headlineMedium: p(sectionTitle),
      headlineSmall: p(sectionTitle.copyWith(fontSize: 18)),
      titleLarge: p(title.copyWith(fontSize: 18)),
      titleMedium: p(title),
      titleSmall: p(title.copyWith(fontSize: 14)),
      bodyLarge: p(body),
      bodyMedium: p(body.copyWith(fontSize: 14, height: 1.4)),
      bodySmall: s(caption),
      labelLarge: p(button.copyWith(fontSize: 14)),
      labelMedium: p(caption.copyWith(fontWeight: FontWeight.w600)),
      labelSmall: s(caption.copyWith(fontSize: 11)),
    );
  }
}
