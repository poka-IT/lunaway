import 'package:flutter/material.dart';

/// The typeface: Figtree (SIL OFL 1.1), a plain geometric sans, for every
/// text of the app, titles, place names and figures included. One variable
/// file carries the weights: the engine drives its weight axis from
/// [FontWeight], so any value from 300 to 900 is a real face. The app ships a
/// derivative (tool/fonts/) whose l has a tail, so "Il", "Ille" and "11 l"
/// do not read as identical bars.
///
/// The weights are set on the strokes of Atkinson Hyperlegible Next, the
/// face the app was read in until 2026-10: its regular stem is that of
/// Figtree at 420, so text read at length keeps the same ink.
abstract final class LunaType {
  static const family = 'Figtree';

  /// Text read at length.
  static const double regular = 420;

  /// Labels, buttons and the titles of a row or a card.
  static const double strong = 620;

  /// Headings, from the title of a sheet to the display sizes.
  static const double heading = 650;

  /// Every figure has one width: a distance, a speed, a duration or a price
  /// that changes while it is read keeps its place, and the figures of a list
  /// stand in columns.
  static const List<FontFeature> figures = [FontFeature.tabularFigures()];

  /// A style at [size] and weight [weight] (100 to 900, any value). The
  /// tracking is Figtree's own at the sizes of text, opened a little at the
  /// smallest and closed a little from the titles up, where its large
  /// sizes read better.
  static TextStyle style(double size, double weight, {double height = 1.2, double? spacing}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height,
        letterSpacing: spacing ?? _tracking(size),
        // FontWeight alone: an explicit weight variation below a bold
        // FontWeight would make the engine embolden the outlines on top.
        fontWeight: FontWeight(weight.round()),
        fontFeatures: figures,
      );

  static double _tracking(double size) => size >= 36
      ? -0.8
      : size >= 28
      ? -0.5
      : size >= 22
      ? -0.25
      : size >= 19
      ? -0.1
      : size >= 14
      ? 0
      : 0.15;

  /// The scale, a notch above the Material defaults for the text read most:
  /// the app is read at arm's length, often by older eyes. Every size still
  /// follows the system text size, since widgets read these styles. [dense]
  /// is the desktop scale, a point smaller: read at a desk, closer to the
  /// eyes, and still above the Material sizes.
  static TextTheme textTheme(Color onSurface, {bool dense = false}) {
    double size(double touch, double desk) => dense ? desk : touch;
    return TextTheme(
      displayLarge: style(44, heading, height: 1.1),
      displayMedium: style(36, heading, height: 1.12),
      displaySmall: style(30, heading, height: 1.15),
      headlineLarge: style(size(28, 26), heading, height: 1.18),
      headlineMedium: style(size(25, 23), heading, height: 1.18),
      headlineSmall: style(size(22.5, 21), heading),
      titleLarge: style(size(20, 19), heading, height: 1.22),
      titleMedium: style(size(17, 16), strong, height: 1.3),
      titleSmall: style(size(15, 14.5), strong, height: 1.3),
      bodyLarge: style(size(17, 16), regular, height: 1.45),
      bodyMedium: style(size(15.5, 14.5), regular, height: 1.42),
      bodySmall: style(size(13.5, 13), regular, height: 1.38),
      labelLarge: style(size(15.5, 14.5), strong, height: 1.25),
      labelMedium: style(size(13.5, 13), strong, height: 1.25),
      labelSmall: style(12, strong, height: 1.25, spacing: 0.1),
    ).apply(bodyColor: onSurface, displayColor: onSurface);
  }

  /// A prominent number (a distance, a height, a count), a little heavier
  /// than the text around it.
  static TextStyle number(double size, {double weight = 500, Color? color}) =>
      style(size, weight, height: 1.1).copyWith(color: color);
}
