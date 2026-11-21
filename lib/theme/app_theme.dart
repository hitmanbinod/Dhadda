import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';
import 'typography.dart';

/// The single ThemeData builder. Accent, Material You, light/dark and the
/// no-splash treatment all still come from the store; this only replaces
/// the raw seed theme with the app's semantic roles.
abstract final class AppTheme {
  static ThemeData build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final colors = AppColors.resolve(seed: seed, brightness: brightness);
    final textTheme = AppType.textTheme(
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
    );
    // Component themes set their label styles explicitly, bypassing the
    // family the theme merges in from Typography. Carry that resolved family
    // over so no label falls back to a harness font (solid blocks in tests).
    final resolvedFamily = Typography.material2021().black.labelLarge?.fontFamily;
    TextStyle fam(TextStyle style) =>
        style.copyWith(fontFamily: resolvedFamily);
    final buttonText = fam(AppType.button);

    // Press stays invisible; hover/focus are the only overlays, for web.
    final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) return Colors.transparent;
      if (states.contains(WidgetState.focused)) {
        return colors.accent.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return colors.accent.withValues(alpha: 0.07);
      }
      return null;
    });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      cardColor: colors.card,
      dividerColor: colors.hairline,
      textTheme: textTheme,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: colors.accent.withValues(alpha: 0.07),
      focusColor: colors.accent.withValues(alpha: 0.12),
      splashFactory: NoSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [colors],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: fam(AppType.title.copyWith(
          fontSize: 18,
          color: colors.textPrimary,
        )),
        iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: colors.textPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardRadius,
          side: BorderSide(color: colors.cardBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
        titleTextStyle: fam(AppType.sectionTitle.copyWith(
          color: colors.textPrimary,
        )),
        contentTextStyle: fam(AppType.body.copyWith(
          fontSize: 14,
          color: colors.textSecondary,
        )),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        modalBackgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.card,
        contentTextStyle: fam(AppType.body.copyWith(
          fontSize: 14,
          color: colors.textPrimary,
        )),
        actionTextColor: colors.accent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.chipRadius,
          side: BorderSide(color: colors.cardBorder),
        ),
        insetPadding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.lg,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: colors.background,
        // Quiet selection: accent icon + label only, no heavy pill/blob.
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        overlayColor: overlay,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: Sizes.navIcon,
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return fam(AppType.navLabel.copyWith(
            color: selected ? colors.accent : colors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ));
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.card,
        elevation: 0,
        minWidth: 72,
        minExtendedWidth: 224,
        useIndicator: false,
        selectedIconTheme: IconThemeData(color: colors.accent, size: 22),
        unselectedIconTheme: IconThemeData(
          color: colors.textSecondary,
          size: 22,
        ),
        selectedLabelTextStyle: fam(
          AppType.navLabel.copyWith(color: colors.accent),
        ),
        unselectedLabelTextStyle: fam(
          AppType.navLabel.copyWith(color: colors.textSecondary),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.track,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.accent.withValues(alpha: 0.25),
        selectionHandleColor: colors.accent,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.cardBorder),
        ),
        textStyle: fam(AppType.caption.copyWith(color: colors.textPrimary)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          tapTargetSize: MaterialTapTargetSize.padded,
          overlayColor: overlay,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(colors.accent),
          foregroundColor: WidgetStatePropertyAll(colors.onAccent),
          overlayColor: overlay,
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Spacing.xl),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(buttonText),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.accent),
          overlayColor: overlay,
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Spacing.md),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(buttonText),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.textPrimary),
          overlayColor: overlay,
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: WidgetStatePropertyAll(BorderSide(color: colors.cardBorder)),
          textStyle: WidgetStatePropertyAll(buttonText),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: colors.accent,
        secondarySelectedColor: colors.accent,
        side: BorderSide(color: colors.cardBorder),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipRadius),
        labelStyle: fam(
          AppType.caption.copyWith(color: colors.textSecondary),
        ),
        secondaryLabelStyle: fam(
          AppType.caption.copyWith(color: colors.onAccent),
        ),
        checkmarkColor: colors.onAccent,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: Spacing.xs,
        ),
      ),
    );
  }
}
