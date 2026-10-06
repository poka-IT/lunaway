import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/profile/application/appearance_providers.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';

/// The app's brightness for [theme] at [now] (UTC), with the previous run's
/// position at [position] and a device in Paris time.
Brightness brightnessAt(ThemePreference theme, DateTime now, {LatLng? position}) {
  final container = ProviderContainer.test(
    overrides: [
      initialSettingsProvider.overrideWithValue(AppSettings(theme: theme)),
      clockProvider.overrideWithValue(() => now),
      minuteTickerProvider.overrideWithValue((_) => const Stream.empty()),
      initialPositionProvider.overrideWithValue(position),
      standardOffsetProvider.overrideWithValue(const Duration(hours: 1)),
    ],
  );
  return container.read(appBrightnessProvider);
}

void main() {
  const annecy = LatLng(45.90, 6.13);
  const reunion = LatLng(-21.11, 55.53);
  // 17:30 UTC on 6 October: after sunset in Annecy (17:05 UTC), night long
  // since on Reunion island (UTC+4).
  final evening = DateTime.utc(2026, 10, 6, 17, 30);
  final noon = DateTime.utc(2026, 10, 6, 11);

  test('auto is light by day and dark after sunset where the user was', () {
    expect(brightnessAt(ThemePreference.auto, noon, position: annecy), Brightness.light);
    expect(brightnessAt(ThemePreference.auto, evening, position: annecy), Brightness.dark);
  });

  test('auto follows the sun at the position, not at the device time zone', () {
    // 05:00 UTC: night in Paris time, day on Reunion where the user is.
    final dawn = DateTime.utc(2026, 10, 6, 5);
    expect(brightnessAt(ThemePreference.auto, dawn, position: reunion), Brightness.light);
    expect(brightnessAt(ThemePreference.auto, dawn), Brightness.dark, reason: 'time zone only');
  });

  test('without any position, auto reads the sun of the device time zone', () {
    expect(brightnessAt(ThemePreference.auto, noon), Brightness.light);
    expect(brightnessAt(ThemePreference.auto, DateTime.utc(2026, 10, 6, 22)), Brightness.dark);
  });

  test('light and dark ignore the sun', () {
    expect(brightnessAt(ThemePreference.light, evening, position: annecy), Brightness.light);
    expect(brightnessAt(ThemePreference.dark, noon, position: annecy), Brightness.dark);
  });
}
