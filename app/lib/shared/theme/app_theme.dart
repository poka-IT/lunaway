import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/luna_colors.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Night blue: the sky above a quiet overnight spot.
const nightBlue = Color(0xFF1D3461);

/// Lantern amber: the warm accent, kept for what deserves the eye (the
/// overnight status, the favourite).
const lanternAmber = Color(0xFFF2A33A);

const _fontFamily = 'Atkinson';

/// The Lunaway theme for a brightness. Sizes are a notch above the Material
/// defaults: the app is read at arm's length, often by older eyes. Every size
/// still scales with the system text size, since widgets read these styles.
ThemeData lunaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: nightBlue, brightness: brightness);
  final accent = ColorScheme.fromSeed(seedColor: lanternAmber, brightness: brightness);
  final scheme = base.copyWith(
    primary: dark ? null : nightBlue,
    tertiary: accent.primary,
    onTertiary: accent.onPrimary,
    tertiaryContainer: accent.primaryContainer,
    onTertiaryContainer: accent.onPrimaryContainer,
  );

  final text = _textTheme(Typography.material2021().black)
      .apply(fontFamily: _fontFamily, bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  const radius = 20.0;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [
      if (dark) LunaColors.dark else LunaColors.light,
      if (dark) LunaTokens.dark else LunaTokens.light,
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      selectedLabelTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      side: BorderSide(color: scheme.outlineVariant),
      showCheckmark: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: scheme.surfaceContainerHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: text.bodyLarge?.copyWith(color: scheme.onInverseSurface),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Icon(Icons.check) : null,
      ),
    ),
    sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    tooltipTheme: TooltipThemeData(
      textStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// The Material 2021 scale, one step larger for the body and label styles a
/// user reads most, and with weights that hold up on a sunlit screen.
TextTheme _textTheme(TextTheme base) => base.copyWith(
  displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
  headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
  headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
  titleLarge: base.titleLarge?.copyWith(fontSize: 23, fontWeight: FontWeight.w700),
  titleMedium: base.titleMedium?.copyWith(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  titleSmall: base.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
  bodyLarge: base.bodyLarge?.copyWith(fontSize: 17, height: 1.45, letterSpacing: 0.1),
  bodyMedium: base.bodyMedium?.copyWith(fontSize: 15.5, height: 1.4, letterSpacing: 0.1),
  bodySmall: base.bodySmall?.copyWith(fontSize: 13.5, height: 1.35),
  labelLarge: base.labelLarge?.copyWith(fontSize: 15.5, letterSpacing: 0.1),
  labelMedium: base.labelMedium?.copyWith(fontSize: 13.5, letterSpacing: 0.2),
  labelSmall: base.labelSmall?.copyWith(fontSize: 12, letterSpacing: 0.3),
);
