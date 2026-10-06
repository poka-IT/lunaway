import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's motion: short, calm, physical. Sheets move on a spring, so a
/// fling carries its speed instead of snapping on a fixed curve; everything
/// else uses the durations below. With the system's reduce motion setting
/// on, [of] turns every duration to zero.
abstract final class Motion {
  static const Duration short = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration emphasized = Duration(milliseconds: 380);
  static const Duration pulse = Duration(milliseconds: 1100);
  static const Duration camera = Duration(milliseconds: 700);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;

  /// The sheets' spring: just under critical damping, so a sheet settles
  /// with the faintest give and never wobbles.
  static const SpringDescription sheetSpring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 38,
  );

  /// Whether the user asked the system for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when the user asked for less motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// The light touches that confirm an action without a look at the screen:
/// a copy, a save, filters applied.
///
/// Fire and forget: the action a tap stands for never waits on the motor.
abstract final class Haptics {
  static void confirm() => unawaited(HapticFeedback.lightImpact());

  static void select() => unawaited(HapticFeedback.selectionClick());
}
