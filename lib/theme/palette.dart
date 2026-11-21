import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// Semantic colour roles for the whole app. Screens read these through
/// [AppColors.of] instead of picking raw Material colours, so light and
/// dark stay in step and the accent keeps following the user's seed.
///
/// Values are the "Quiet Ledger" tokens from design/tokens.json; keep the two
/// in sync (scripts/sync_tokens.py regenerates lib/theme/tokens.g.dart).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.surface2,
    required this.cardBorder,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.expense,
    required this.income,
    required this.warn,
    required this.lent,
    required this.track,
    required this.field,
    required this.selectedFill,
  });

  final Color background;
  final Color card;
  final Color surface2;
  final Color cardBorder;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color expense;
  final Color income;
  final Color warn;
  final Color lent;
  final Color track;
  final Color field;
  final Color selectedFill;

  /// Dark "Ink" palette from the mock: deep green-black surfaces, mint accent.
  static const AppColors dark = AppColors(
    background: DesignTokens.darkBg,
    card: DesignTokens.darkSurface,
    surface2: DesignTokens.darkSurfaceTwo,
    cardBorder: DesignTokens.darkHairline,
    hairline: DesignTokens.darkHairline,
    textPrimary: DesignTokens.darkText,
    textSecondary: DesignTokens.darkTextTwo,
    accent: DesignTokens.darkAccent,
    onAccent: DesignTokens.darkOnAccent,
    expense: DesignTokens.darkExpense,
    income: DesignTokens.darkIncome,
    warn: DesignTokens.darkWarn,
    lent: DesignTokens.darkLent,
    track: Color(0x1AFFFFFF),
    field: Color(0x12FFFFFF),
    selectedFill: Color(0x24FFFFFF),
  );

  /// Light "Paper" palette: warm paper background, deep teal accent.
  static const AppColors light = AppColors(
    background: DesignTokens.lightBg,
    card: DesignTokens.lightSurface,
    surface2: DesignTokens.lightSurfaceTwo,
    cardBorder: DesignTokens.lightHairline,
    hairline: DesignTokens.lightHairline,
    textPrimary: DesignTokens.lightText,
    textSecondary: DesignTokens.lightTextTwo,
    accent: DesignTokens.lightAccent,
    onAccent: DesignTokens.lightOnAccent,
    expense: DesignTokens.lightExpense,
    income: DesignTokens.lightIncome,
    warn: DesignTokens.lightWarn,
    lent: DesignTokens.lightLent,
    track: Color(0x14000000),
    field: Color(0x0D000000),
    selectedFill: Color(0x1414201D),
  );

  /// Category swatches from the mock. Dark tones are darkened 25% in light.
  static const List<Color> categoryPalette = DesignTokens.category;

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
    Color? surface2,
    Color? cardBorder,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? expense,
    Color? income,
    Color? warn,
    Color? lent,
    Color? track,
    Color? field,
    Color? selectedFill,
  }) {
    return AppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      surface2: surface2 ?? this.surface2,
      cardBorder: cardBorder ?? this.cardBorder,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      expense: expense ?? this.expense,
      income: income ?? this.income,
      warn: warn ?? this.warn,
      lent: lent ?? this.lent,
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
      surface2: Color.lerp(surface2, other.surface2, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      lent: Color.lerp(lent, other.lent, t)!,
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
