import 'package:flutter/material.dart';

/// The spacing scale every layout reads. Values are logical pixels; a design
/// pass retunes them here, not in the screens.
abstract final class Space {
  static const double hair = 2;
  static const double xxs = 4;
  static const double xs = 6;
  static const double s = 8;
  static const double sm = 10;
  static const double m = 12;
  static const double ml = 14;
  static const double l = 16;
  static const double lx = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 28;
  static const double huge = 32;
}

/// Durations of the app's motion, from the Material 3 scale.
abstract final class Motion {
  static const Duration short = Durations.short4;
  static const Duration medium = Durations.medium1;
  static const Duration emphasized = Durations.medium2;
  static const Duration pulse = Durations.extralong4;
  static const Duration camera = Duration(milliseconds: 700);
  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve exit = Easing.emphasizedAccelerate;
}

/// Shapes, elevations and the colours with no Material role, per theme.
/// Widgets read them with `LunaTokens.of(context)`; nothing in a feature
/// spells a radius or a colour itself.
@immutable
final class LunaTokens extends ThemeExtension<LunaTokens> {
  const new({
    required this.radiusXs,
    required this.radiusS,
    required this.radiusM,
    required this.radiusL,
    required this.radiusXl,
    required this.radiusSheet,
    required this.onAccent,
    required this.shadow,
    required this.shadowStrong,
    required this.photoBackdrop,
    required this.onPhotoBackdrop,
    required this.onPhotoBackdropMuted,
    required this.floatingElevation,
    required this.sheetElevation,
  });

  static const light = LunaTokens(
    radiusXs: 3,
    radiusS: 8,
    radiusM: 14,
    radiusL: 16,
    radiusXl: 20,
    radiusSheet: 28,
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0x61000000),
    shadowStrong: Color(0x8A000000),
    photoBackdrop: Color(0xFF000000),
    onPhotoBackdrop: Color(0xFFFFFFFF),
    onPhotoBackdropMuted: Color(0x8AFFFFFF),
    floatingElevation: 3,
    sheetElevation: 8,
  );

  static const LunaTokens dark = light;

  /// Handles, small marks.
  final double radiusXs;

  /// Badges, tags.
  final double radiusS;

  /// Snackbars, small chips.
  final double radiusM;

  /// Buttons, thumbnails, tiles.
  final double radiusL;

  /// Cards, panels.
  final double radiusXl;

  /// Bottom sheets, side panels, dialogs.
  final double radiusSheet;

  /// Text and glyphs drawn on a saturated colour (pins, family discs).
  final Color onAccent;

  /// Shadows of what floats over the map.
  final Color shadow;
  final Color shadowStrong;

  /// The full-screen photo viewer.
  final Color photoBackdrop;
  final Color onPhotoBackdrop;
  final Color onPhotoBackdropMuted;

  final double floatingElevation;
  final double sheetElevation;

  static LunaTokens of(BuildContext context) => Theme.of(context).extension<LunaTokens>()!;

  @override
  LunaTokens copyWith() => this;

  @override
  LunaTokens lerp(LunaTokens? other, double t) => t < 0.5 || other == null ? this : other;
}
