import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/sun/sun_times.dart';
import 'package:lunaway/core/theme_mode/theme_mode.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'appearance_providers.g.dart';

/// The device's UTC offset without summer time: the fallback the automatic
/// theme uses before any position is known.
// keepAlive: a constant of the run (the time zone does not change under a
// running app often enough to matter for a theme).
@Riverpod(keepAlive: true)
Duration standardOffset(Ref ref) => standardUtcOffset(ref.watch(clockProvider));

/// Light or dark, now: the user's choice, or the sun at the last known
/// position. Re-evaluated every minute, so the map darkens at sunset.
@riverpod
Brightness appBrightness(Ref ref) {
  final preference = ref.watch(settingsProvider.select((s) => s.theme));
  final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
  return brightnessFor(
    preference,
    now: now,
    position: ref.watch(sunPositionProvider),
    standardOffset: ref.watch(standardOffsetProvider),
  );
}
