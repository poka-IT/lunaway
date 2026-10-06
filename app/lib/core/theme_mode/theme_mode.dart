import 'dart:ui' show Brightness;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/sun/sun_times.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';

/// The brightness the app shows for [preference] at [now]: the user's choice,
/// or with [ThemePreference.auto] light while the sun is up at [position]
/// (the last known one), else at the typical place of the device's time
/// zone ([standardOffset]).
Brightness brightnessFor(
  ThemePreference preference, {
  required DateTime now,
  required Duration standardOffset,
  LatLng? position,
}) => switch (preference) {
  ThemePreference.light => Brightness.light,
  ThemePreference.dark => Brightness.dark,
  ThemePreference.auto =>
    isNightAt(now.toUtc(), lat: position?.lat, lon: position?.lon, standardOffset: standardOffset)
        ? Brightness.dark
        : Brightness.light,
};
