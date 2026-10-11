import 'package:flutter/material.dart';

/// The typeface: Figtree (SIL OFL 1.1), a plain geometric sans, for every
/// text of the app, titles, place names and figures included. One variable
/// file carries the weights: the engine drives its weight axis from
/// [FontWeight], so any value from 300 to 900 is a real face. The app ships a
/// derivative (tool/fonts/) whose l has a tail, so "Il", "Ille" and "11 l"
/// do not read as identical bars.
///
/// The text weight is that of a face drawn for low vision: at 420 the stem
/// and the ink of Figtree match the regular of Atkinson Hyperlegible Next,
/// which a reader at arm's length needs; Figtree's own 400 is a little
/// thinner. The other weights keep their distance from it.
abstract final class LunaType {
  static const family = 'Figtree';

  /// Text read at length.
  static const double regular = 420;

  /// Labels, buttons and the titles of a row or a card.
  static const double strong = 620;

  /// Headings, from the title of a sheet to the display sizes.
  static const double heading = 650;

  /// Every figure one width, for the styles that carry numbers which change
  /// or stand in columns: the guidance's distances, speeds and times, the
  /// prices and durations, the counts of a list or a chip keep their place
  /// as their figures change. Text read at length keeps Figtree's
  /// proportional figures, where the "1" of "11 lits" stays narrow.
  static const List<FontFeature> figures = [FontFeature.tabularFigures()];

  /// A style at [size] and weight [weight] (300 to 900, any value), with
  /// [figures] when [tabular]. The tracking is Figtree's own at the sizes of
  /// text, whose spacing is drawn for them, and closes a little from the
  /// titles up, where its large sizes read better.
  static TextStyle style(
    double size,
    double weight, {
    double height = 1.2,
    double? spacing,
    bool tabular = true,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height,
    letterSpacing: spacing ?? _tracking(size),
    // FontWeight alone: an explicit weight variation below a bold
    // FontWeight would make the engine embolden the outlines on top.
    fontWeight: FontWeight(weight.round()),
    fontFeatures: tabular ? figures : null,
  );

  static double _tracking(double size) => size >= 36
      ? -0.8
      : size >= 28
      ? -0.5
      : size >= 22
      ? -0.25
      : size >= 19
      ? -0.1
      : 0;

  /// The scale, a notch above the Material defaults for the text read most:
  /// the app is read at arm's length, often by older eyes. Every size still
  /// follows the system text size, since widgets read these styles. [dense]
  /// is the desktop scale, a point smaller: read at a desk, closer to the
  /// eyes, and still above the Material sizes. The body styles, read at
  /// length, keep proportional figures; the display, headline, title and
  /// label styles, where the guidance, the lists and the chips set their
  /// numbers, take tabular ones.
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
      bodyLarge: style(size(17, 16), regular, height: 1.45, tabular: false),
      bodyMedium: style(size(15.5, 14.5), regular, height: 1.42, tabular: false),
      bodySmall: style(size(13.5, 13), regular, height: 1.38, tabular: false),
      labelLarge: style(size(15.5, 14.5), strong, height: 1.25),
      labelMedium: style(size(13.5, 13), strong, height: 1.25),
      // A touch open at the smallest size, no more: the map's credit, in
      // this style, then keeps "OpenStreetMap" on one line in the room left
      // of the guidance's vehicle at large text sizes (languages_test).
      labelSmall: style(12, strong, height: 1.25, spacing: 0.1),
    ).apply(bodyColor: onSurface, displayColor: onSurface);
  }

  /// A prominent number (a distance, a height, a count), by default a
  /// little heavier than the text around it.
  static TextStyle number(double size, {double weight = 500, Color? color}) =>
      style(size, weight, height: 1.1).copyWith(color: color);
}
