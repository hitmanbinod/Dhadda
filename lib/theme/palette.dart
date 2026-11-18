import 'package:flutter/material.dart';

/// Semantic colour roles for the whole app. Screens read these through
/// [AppColors.of] instead of picking raw Material colours, so light and
/// dark stay in step and the accent keeps following the user's seed.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.cardBorder,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.expense,
    required this.income,
    required this.track,
    required this.field,
    required this.selectedFill,
  });

  final Color background;
  final Color card;
  final Color cardBorder;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color expense;
  final Color income;
  final Color track;
  final Color field;
  final Color selectedFill;

  /// Dark-first palette from the design brief. The accent default is the
  /// brief's teal; [resolve] replaces it with the user's seed.
  static const AppColors dark = AppColors(
    background: Color(0xFF0E1413),
    card: Color(0xFF141D1C),
    cardBorder: Color(0x0DFFFFFF),
    hairline: Color(0x12FFFFFF),
    textPrimary: Color(0xFFEAF2F0),
    textSecondary: Color(0xFF93A39F),
    accent: Color(0xFF7FD6C8),
    onAccent: Color(0xFF06231F),
    expense: Color(0xFFF0948A),
    income: Color(0xFF86D0A6),
    track: Color(0x1AFFFFFF),
    field: Color(0x12FFFFFF),
    selectedFill: Color(0x26FFFFFF),
  );

  /// Light equivalents of the same roles. Expense/income are darkened
  /// enough to clear 4.5:1 against white.
  static const AppColors light = AppColors(
    background: Color(0xFFF4F7F6),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0x14000000),
    hairline: Color(0x12000000),
    textPrimary: Color(0xFF16211F),
    textSecondary: Color(0xFF5A6A66),
    expense: Color(0xFFB35348),
    income: Color(0xFF2E7D5B),
    accent: Color(0xFF00695C),
    onAccent: Color(0xFFFFFFFF),
    track: Color(0x14000000),
    field: Color(0x0D000000),
    selectedFill: Color(0x14000000),
  );

  /// Builds the roles for [seed]. The accent comes from Material's tonal
  /// palette, which keeps a user-picked colour readable in both themes.
  factory AppColors.resolve({
    required Color seed,
    required Brightness brightness,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final base = brightness == Brightness.dark ? dark : light;
    return base.copyWith(accent: scheme.primary, onAccent: scheme.onPrimary);
  }

  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? cardBorder,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? expense,
    Color? income,
    Color? track,
    Color? field,
    Color? selectedFill,
  }) {
    return AppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      expense: expense ?? this.expense,
      income: income ?? this.income,
      track: track ?? this.track,
      field: field ?? this.field,
      selectedFill: selectedFill ?? this.selectedFill,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
      track: Color.lerp(track, other.track, t)!,
      field: Color.lerp(field, other.field, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
    );
  }
}

/// WCAG relative contrast, used by the theme tests to keep body text
/// readable in both brightnesses.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
