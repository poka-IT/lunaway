import 'package:flutter/material.dart';

/// The two typefaces. Fraunces (SIL OFL 1.1), the brand's serif, carries the
/// display, the titles, the place names and the prominent numbers, in light
/// weights with its optical size axis; Atkinson Hyperlegible Next (SIL OFL
/// 1.1) with a plain zero, drawn for low-vision readers, carries everything
/// read at length.
abstract final class LunaType {
  static const display = 'Fraunces';
  static const body = 'Atkinson';

  /// A Fraunces style at [size] and weight [weight] (100 to 900, any value:
  /// the engine drives the variable weight axis from it). The optical size
  /// is never set by the engine, so it follows the size here: small titles
  /// stay open, large ones refined.
  static TextStyle serif(double size, double weight, {double height = 1.18, double? spacing}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        height: height,
        letterSpacing: spacing ?? (size >= 24 ? -0.3 : -0.1),
        // FontWeight alone: an explicit weight variation below a bold
        // FontWeight would make the engine embolden the outlines on top.
        fontWeight: FontWeight(weight.round()),
        fontVariations: [FontVariation.opticalSize(size.clamp(9, 72))],
      );

  static TextStyle _sans(
    double size,
    FontWeight weight, {
    double height = 1.35,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: body,
    fontSize: size,
    height: height,
    letterSpacing: spacing,
    fontWeight: weight,
  );

  /// The scale, a notch above the Material defaults for the text read most:
  /// the app is read at arm's length, often by older eyes. Every size still
  /// follows the system text size, since widgets read these styles. [dense]
  /// is the desktop scale, a point smaller: read at a desk, closer to the
  /// eyes, and still above the Material sizes.
  static TextTheme textTheme(Color onSurface, {bool dense = false}) {
    double size(double touch, double desk) => dense ? desk : touch;
    return TextTheme(
      displayLarge: serif(44, 360, height: 1.08),
      displayMedium: serif(36, 370, height: 1.1),
      displaySmall: serif(30, 390, height: 1.12),
      headlineLarge: serif(size(28, 26), 400),
      headlineMedium: serif(size(25, 23), 420),
      headlineSmall: serif(size(22.5, 21), 440, height: 1.2),
      titleLarge: serif(size(20, 19), 460, height: 1.22),
      titleMedium: _sans(size(17, 16), FontWeight.w600, height: 1.3),
      titleSmall: _sans(size(15, 14.5), FontWeight.w600, height: 1.3),
      bodyLarge: _sans(size(17, 16), FontWeight.w400, height: 1.45, spacing: 0.1),
      bodyMedium: _sans(size(15.5, 14.5), FontWeight.w400, height: 1.42, spacing: 0.1),
      bodySmall: _sans(size(13.5, 13), FontWeight.w400, height: 1.38, spacing: 0.1),
      labelLarge: _sans(size(15.5, 14.5), FontWeight.w600, height: 1.25, spacing: 0.1),
      labelMedium: _sans(size(13.5, 13), FontWeight.w600, height: 1.25, spacing: 0.15),
      labelSmall: _sans(12, FontWeight.w600, height: 1.25, spacing: 0.3),
    ).apply(bodyColor: onSurface, displayColor: onSurface);
  }

  /// A prominent number (a distance, a height, a count) in Fraunces, whose
  /// figures are lining by default.
  static TextStyle number(double size, {double weight = 460, Color? color}) =>
      serif(size, weight, height: 1.1).copyWith(color: color);
}
