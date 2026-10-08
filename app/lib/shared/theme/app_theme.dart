import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/luna_scheme.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// The Lunaway theme for a brightness: "Aube" by day, "Minuit" by night.
/// Every component the app uses is themed here, so no widget falls back to
/// a stock Material look: no elevation shadows (surfaces separate by tone),
/// no tinted surfaces, amber for actions and selection only.
///
/// [pointer] is the desktop look (`pointerDensity`): a mouse aims finer
/// than a finger, so controls lose a notch of height (the compact visual
/// density takes 8 off every button and field) and the text a point, still
/// in Atkinson Hyperlegible and still above the Material desktop sizes.
ThemeData lunaTheme(Brightness brightness, {bool pointer = false}) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? LunaScheme.minuit : LunaScheme.aube;
  final tokens = dark ? LunaTokens.minuitTheme : LunaTokens.aube;
  final text = LunaType.textTheme(scheme.onSurface, dense: pointer);

  RoundedRectangleBorder rounded(double r, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);
  WidgetStateProperty<T> states<T>(T Function(Set<WidgetState> s) resolve) =>
      WidgetStateProperty.resolveWith(resolve);
  const noElevation = WidgetStatePropertyAll<double>(0);
  final buttonText = text.labelLarge!.copyWith(fontSize: pointer ? 15 : 16);
  final disabledFg = scheme.onSurface.withValues(alpha: 0.38);
  final disabledBg = scheme.onSurface.withValues(alpha: 0.08);
  // The ink of a press: the content's own colour, faint, never a grey wash.
  Color overlay(Color on, Set<WidgetState> s) => s.contains(WidgetState.pressed)
      ? on.withValues(alpha: 0.12)
      : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
      ? on.withValues(alpha: 0.08)
      : Colors.transparent;
  // The pointing hand over everything that reacts to a click, the arrow
  // when it is disabled, on every platform. Material shows the hand only on
  // the web and the arrow on desktop builds. The app chose the hand for its
  // desktop builds too: the same app in a browser and in a window, for
  // users who look for what can be clicked. One rule is also one the
  // widget tests (headless, never the web) can check. A widget with no
  // theme (InkWell, a chip, a gesture detector) sets it itself.
  const clickable = WidgetStateMouseCursor.clickable;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: LunaType.body,
    textTheme: text,
    primaryTextTheme: text,
    visualDensity: pointer ? VisualDensity.compact : VisualDensity.standard,
    materialTapTargetSize: pointer
        ? MaterialTapTargetSize.shrinkWrap
        : MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    extensions: [tokens],
    iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineMedium,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickable,
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.xl)),
        shape: WidgetStatePropertyAll(rounded(LunaTokens.radiusL)),
        elevation: noElevation,
        textStyle: WidgetStatePropertyAll(buttonText),
        backgroundColor: states(
          (s) => s.contains(WidgetState.disabled) ? disabledBg : scheme.primary,
        ),
        foregroundColor: states(
          (s) => s.contains(WidgetState.disabled) ? disabledFg : scheme.onPrimary,
        ),
        overlayColor: states((s) => overlay(scheme.onPrimary, s)),
        iconSize: const WidgetStatePropertyAll(22),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickable,
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.l)),
        shape: WidgetStatePropertyAll(rounded(LunaTokens.radiusL)),
        elevation: noElevation,
        textStyle: WidgetStatePropertyAll(buttonText),
        side: states(
          (s) => BorderSide(
            color: s.contains(WidgetState.disabled) ? disabledBg : scheme.outline,
            width: 1.2,
          ),
        ),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: states(
          (s) => s.contains(WidgetState.disabled) ? disabledFg : scheme.onSurface,
        ),
        overlayColor: states((s) => overlay(scheme.onSurface, s)),
        iconSize: const WidgetStatePropertyAll(22),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickable,
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.m)),
        shape: WidgetStatePropertyAll(rounded(LunaTokens.radiusM)),
        textStyle: WidgetStatePropertyAll(buttonText),
        foregroundColor: states((s) => s.contains(WidgetState.disabled) ? disabledFg : tokens.link),
        overlayColor: states((s) => overlay(tokens.link, s)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickable,
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: WidgetStatePropertyAll(rounded(LunaTokens.radiusL)),
        elevation: noElevation,
        textStyle: WidgetStatePropertyAll(buttonText),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
        overlayColor: states((s) => overlay(scheme.onSurface, s)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickable,
        // Material 3 icon buttons keep the standard density unless told.
        visualDensity: pointer ? VisualDensity.compact : null,
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        iconSize: const WidgetStatePropertyAll(24),
        foregroundColor: states(
          (s) => s.contains(WidgetState.disabled) ? disabledFg : scheme.onSurface,
        ),
        overlayColor: states((s) => overlay(scheme.onSurface, s)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tokens.floatingSurface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: rounded(LunaTokens.radiusL),
      mouseCursor: clickable,
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge!.copyWith(color: scheme.onSurface),
      secondaryLabelStyle: text.labelLarge!.copyWith(color: scheme.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.s),
      labelPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.outlineVariant,
          width: s.contains(WidgetState.selected) ? 1.5 : 1,
        ),
      ),
      color: states(
        (s) => s.contains(WidgetState.selected)
            ? scheme.primaryContainer
            : s.contains(WidgetState.disabled)
            ? disabledBg
            : scheme.surfaceContainerLow,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 20),
      showCheckmark: false,
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: rounded(LunaTokens.radiusXl),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      modalBackgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      // Sheets open through showSheet, which draws its own handle: the
      // mouse cannot be given a cursor over Material's.
      showDragHandle: false,
      modalBarrierColor: scheme.scrim.withValues(alpha: 0.42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      // Material's widest dialog: a question with a long text otherwise
      // spread over the whole width of a desktop window, one line of 1300 px.
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
      shape: rounded(LunaTokens.radiusSheet),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: scheme.scrim.withValues(alpha: 0.42),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: scheme.inverseSurface,
      actionTextColor: scheme.inversePrimary,
      closeIconColor: scheme.onInverseSurface,
      shape: rounded(LunaTokens.radiusL),
      contentTextStyle: text.bodyLarge!.copyWith(color: scheme.onInverseSurface),
      insetPadding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: Space.m,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
      leadingAndTrailingTextStyle: text.labelLarge,
      iconColor: scheme.onSurfaceVariant,
      selectedColor: scheme.onSurface,
      selectedTileColor: scheme.primaryContainer,
      shape: rounded(LunaTokens.radiusL),
      // A tile with no tap of its own (the row of a menu item) is not a
      // control: it leaves the cursor to what holds it, where Material
      // would draw the arrow over most of a clickable menu item.
      mouseCursor: WidgetStateMouseCursor.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? MouseCursor.defer : SystemMouseCursors.click,
      ),
    ),
    switchTheme: SwitchThemeData(
      mouseCursor: clickable,
      thumbColor: states(
        (s) => s.contains(WidgetState.selected)
            ? scheme.onPrimary
            : (dark ? scheme.onSurfaceVariant : scheme.outline),
      ),
      trackColor: states(
        (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: states(
        (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
      ),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    checkboxTheme: CheckboxThemeData(
      mouseCursor: clickable,
      fillColor: states((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      side: BorderSide(color: scheme.outline, width: 1.6),
      shape: rounded(LunaTokens.radiusXs),
    ),
    radioTheme: RadioThemeData(
      mouseCursor: clickable,
      fillColor: states((s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.outline),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.16),
      valueIndicatorColor: scheme.inverseSurface,
      valueIndicatorTextStyle: text.labelLarge!.copyWith(color: scheme.onInverseSurface),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      elevation: 0,
      indicatorColor: scheme.primary,
      indicatorShape: const StadiumBorder(),
      selectedIconTheme: IconThemeData(color: scheme.onPrimary, size: 24),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      selectedLabelTextStyle: text.labelLarge!.copyWith(color: scheme.onSurface),
      unselectedLabelTextStyle: text.labelLarge!.copyWith(color: scheme.onSurfaceVariant),
      useIndicator: true,
      minWidth: 88,
      minExtendedWidth: 232,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.dockSurface,
      indicatorColor: tokens.dockSelected,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickable,
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        backgroundColor: states(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : Colors.transparent,
        ),
        foregroundColor: states(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.ml),
      labelStyle: text.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: text.bodyMedium!.copyWith(color: scheme.onSurface),
      hintStyle: text.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
      helperStyle: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
      errorStyle: text.bodySmall!.copyWith(color: scheme.error),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LunaTokens.radiusM),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LunaTokens.radiusM),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LunaTokens.radiusM),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LunaTokens.radiusM),
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.onSurface,
      selectionColor: scheme.primary.withValues(alpha: 0.35),
      selectionHandleColor: scheme.primary,
    ),
    popupMenuTheme: PopupMenuThemeData(
      mouseCursor: clickable,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: rounded(LunaTokens.radiusL, BorderSide(color: scheme.outlineVariant)),
      textStyle: text.bodyLarge,
      labelTextStyle: WidgetStatePropertyAll(text.bodyLarge),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: noElevation,
        shape: WidgetStatePropertyAll(
          rounded(LunaTokens.radiusL, BorderSide(color: scheme.outlineVariant)),
        ),
      ),
    ),
    menuButtonTheme: const MenuButtonThemeData(style: ButtonStyle(mouseCursor: clickable)),
    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.primary,
      textColor: scheme.onPrimary,
      textStyle: text.labelSmall,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      textStyle: text.bodyMedium!.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(LunaTokens.radiusS),
      ),
      waitDuration: const Duration(milliseconds: 600),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0.28)),
      radius: const Radius.circular(LunaTokens.radiusPill),
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
