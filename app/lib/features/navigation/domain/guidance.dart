import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:meta/meta.dart';

/// A position fix of the device.
@immutable
final class Fix {
  const new({
    required this.position,
    required this.accuracyM,
    required this.at,
    this.courseDeg,
    this.speedMps,
  });

  final LatLng position;

  /// Radius of the confidence circle, metres.
  final double accuracyM;
  final DateTime at;

  /// Course over ground, degrees from north, when moving.
  final double? courseDeg;

  /// Metres per second, when known.
  final double? speedMps;

  @override
  String toString() => 'Fix(${position.lat}, ${position.lon}, ±$accuracyM m)';
}

/// The fastest speed worked out between two fixes that is believed,
/// metres per second (252 km/h, twice a motorhome's top speed): beyond, the
/// position jumped (out of a tunnel, the satellites back, a browser placed
/// by its network then by its GPS), and 9 km in 3 s are no 11 000 km/h.
const maxDerivedSpeedMps = 70.0;

/// A walk, metres per second: a position that moves faster than this between
/// two fixes is not standing still, whatever speed the fix gives.
const _walkMps = 1.5;

/// A browser's clock and the page's may disagree by this much before the
/// browser's time of a fix is set aside.
const _browserClockSkew = Duration(minutes: 1);

/// When a browser's fix was taken: the time the browser gives it,
/// milliseconds since the epoch, unless that time lies more than a minute
/// from [came], the page's clock when the fix came; then [came]. Measured
/// on 2026-10-10 with Playwright's WebKit 26.6, whose positions count their
/// time in microseconds (a date 1 000 times too far), and its Firefox 155,
/// whose positions lie a day ahead: the speed worked out between two such
/// fixes was none (WebKit showed no speed while guiding).
DateTime browserFixTime(num timestampMs, DateTime came) {
  final ms = timestampMs.isFinite ? timestampMs.round() : null;
  final at = ms == null || ms.abs() > 8640000000000000
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: came.isUtc);
  return at == null || at.difference(came).abs() > _browserClockSkew ? came : at;
}

/// A fix less precise than this gives no speed nor course worked out from
/// it, metres: a computer placed by its network moves by hundreds of metres
/// standing still.
const maxDerivedAccuracyM = 100.0;

/// [fix] with the speed and course it lacks worked out from [previous]: a
/// browser on a computer, and some phones' browsers, give neither. Over a
/// gap of 0.2 to 10 s, the distance covered gives the speed, and a move
/// longer than the fixes' own uncertainty gives the course; a fix that has
/// them keeps its own, except a speed of 0 while the position moved at a
/// walk or faster, which a browser gives for an unknown one. A jump faster
/// than [maxDerivedSpeedMps], or fixes vaguer than [maxDerivedAccuracyM],
/// give neither: no speed is shown rather than a false one.
Fix withMotion(Fix fix, Fix? previous) {
  if (previous == null || (fix.speedMps != null && fix.speedMps! > 0 && fix.courseDeg != null)) {
    return fix;
  }
  final seconds = fix.at.difference(previous.at).inMilliseconds / 1000;
  if (seconds < 0.2 || seconds > 10) return fix;
  final moved = previous.position.distanceTo(fix.position);
  final derived = moved / seconds;
  final believed =
      derived <= maxDerivedSpeedMps &&
      math.max(fix.accuracyM, previous.accuracyM) <= maxDerivedAccuracyM;
  final stillWhileMoving =
      fix.speedMps == 0 && believed && derived >= _walkMps && moved > fix.accuracyM;
  final speed = stillWhileMoving ? derived : fix.speedMps ?? (believed ? derived : null);
  final course =
      fix.courseDeg ??
      (believed && moved > math.max(5, math.min(fix.accuracyM, 30)) && derived > 0.5
          ? _bearing(previous.position, fix.position)
          : null);
  return Fix(
    position: fix.position,
    accuracyM: fix.accuracyM,
    at: fix.at,
    courseDeg: course,
    speedMps: speed,
  );
}

/// A last fix older than this, by the wall clock, is said on screen: the
/// arrival time rests on it.
const positionStaleAfter = Duration(minutes: 1);

/// A speed older than this, by the wall clock, is no longer shown: a
/// browser gives a position only when it changes, so a vehicle that stops
/// would keep its last speed on screen, and a phone in a tunnel gets none.
/// A phone gives a position a second; the position's own age is said from
/// [positionStaleAfter] on.
const speedStaleAfter = Duration(seconds: 5);

/// The speed shown at [now]: that of [fix], which came at [cameAt] by the
/// same clock, while it is younger than [speedStaleAfter]; none after.
double? speedShown({required Fix? fix, required DateTime? cameAt, required DateTime now}) =>
    fix != null && cameAt != null && now.difference(cameAt) < speedStaleAfter ? fix.speedMps : null;

/// When the vehicle arrives, [leftS] seconds from the later of [now] and
/// [lastFixAt], when the last fix came by the same clock: a position that
/// stopped coming never puts the arrival in the past, and a clock read at
/// the start of its minute does not hold back a fix that came since.
DateTime arrivalAt({required DateTime now, required DateTime? lastFixAt, required double leftS}) {
  final from = lastFixAt != null && lastFixAt.isAfter(now) ? lastFixAt : now;
  return from.add(Duration(seconds: leftS.round()));
}

double _bearing(LatLng a, LatLng b) {
  final la = a.lat * math.pi / 180;
  final lb = b.lat * math.pi / 180;
  final dl = (b.lon - a.lon) * math.pi / 180;
  final y = math.sin(dl) * math.cos(lb);
  final x = math.cos(la) * math.sin(lb) - math.sin(la) * math.cos(lb) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// What the banner shows: the next maneuver.
@immutable
final class ManeuverBanner {
  const new({
    required this.primary,
    this.secondary,
    this.maneuverType,
    this.modifier,
    this.roundaboutExitDegrees,
    this.lanes = const [],
  });

  /// The road to take, or what to do.
  final String primary;
  final String? secondary;

  /// The OSRM maneuver type (`turn`, `roundabout`, `arrive`...).
  final String? maneuverType;

  /// Its direction (`left`, `slight right`, `uturn`...).
  final String? modifier;
  final int? roundaboutExitDegrees;
  final List<LaneHint> lanes;
}

/// The maneuver the banner shows while the vehicle follows step
/// [stepIndex] of [steps]: the engine's [banner], completed by the step it
/// announces (the next one), which knows the exit's rank, the side traffic
/// keeps to and a ferry. In a roundabout the banner announces the way out,
/// and the step being driven is the one that counted the exits.
Maneuver bannerManeuver({
  required ManeuverBanner? banner,
  required List<RouteStep> steps,
  required int stepIndex,
}) {
  final current = stepIndex >= 0 && stepIndex < steps.length ? steps[stepIndex] : null;
  final next = stepIndex + 1 < steps.length && stepIndex + 1 >= 0 ? steps[stepIndex + 1] : null;
  final type = banner?.maneuverType ?? next?.maneuverType;
  final leaving = type == 'exit roundabout' || type == 'exit rotary';
  final counted = leaving ? current : next;
  return Maneuver(
    type: type,
    modifier: banner?.modifier ?? next?.modifier,
    exitDegrees: banner?.roundaboutExitDegrees ?? next?.exitDegrees,
    exitNumber: counted != null && counted.maneuver.isRoundabout ? counted.exit : null,
    leftHandTraffic: (next ?? current)?.leftHandTraffic ?? false,
    ferry: next?.ferry ?? false,
  );
}

/// An instruction to speak; [id] is stable for one instruction of one
/// route, so each is said once.
@immutable
final class SpokenInstruction {
  const new({required this.id, required this.text});

  final String id;
  final String text;
}

/// Navigating, or arrived.
enum GuidanceStatus { navigating, arrived }

/// The guidance after one fix.
@immutable
final class GuidanceSnapshot {
  const new({
    required this.status,
    required this.position,
    required this.stepIndex,
    required this.distanceToManeuverM,
    required this.distanceRemainingM,
    required this.durationRemainingS,
    required this.distanceAlongM,
    this.courseDeg,
    this.offRouteM,
    this.banner,
    this.instruction,
    this.speedLimitKmh,
  });

  final GuidanceStatus status;

  /// The vehicle on the route (snapped).
  final LatLng position;

  /// The route's heading there, degrees from north.
  final double? courseDeg;

  /// The step being driven, in the route's order.
  final int stepIndex;
  final double distanceToManeuverM;
  final double distanceRemainingM;
  final double durationRemainingS;

  /// Metres driven along the route.
  final double distanceAlongM;

  /// Metres from the route's line once the vehicle has left it.
  final double? offRouteM;
  final ManeuverBanner? banner;
  final SpokenInstruction? instruction;

  /// km/h, where the map has it.
  final double? speedLimitKmh;

  bool get offRoute => offRouteM != null;
}

/// A road event's shape, for the check of the route ahead.
@immutable
final class EventShape {
  const new({
    required this.id,
    required this.points,
    this.directed = false,
    this.part = 0,
    this.headingDeg,
    this.headingToleranceDeg = 0,
  });

  /// The event's id; several shapes of one event share it.
  final String id;

  /// One point, or the line of the road it covers.
  final List<LatLng> points;

  /// The line runs in the direction of the traffic it concerns: a route
  /// meets it only by following it that way (one carriageway).
  final bool directed;

  /// Which line of the event, for the log.
  final int part;

  /// For a point: the course of the traffic it concerns, degrees from
  /// north; a route passing it on another course does not meet it.
  final double? headingDeg;

  /// How far the route's course may stray from [headingDeg].
  final double headingToleranceDeg;
}

/// The server's tolerances for road events: a route follows a matched line
/// within 12 m, passes a point within 15 m
/// (`plan/research/21-backend-travaux.md`, part 5).
const eventLineToleranceM = 12.0;
const eventPointToleranceM = 15.0;

/// Where the route ahead drives through an event.
@immutable
final class EventHit {
  const new({required this.id, required this.startM, required this.endM, required this.at});

  final String id;

  /// Metres from the start of the route.
  final double startM;
  final double endM;

  /// Where the route enters it.
  final LatLng at;
}

/// Guidance along one route: Ferrostar's core through the bridge on Android
/// and iOS, a fake in tests.
abstract interface class GuidanceTrack {
  /// The guidance after [fix].
  GuidanceSnapshot update(Fix fix);

  /// Where the route, from [fromM] metres onwards, meets each of [events]
  /// (the server's corridor rule for lines, its distance for points), in
  /// driving order.
  List<EventHit> eventsAhead(double fromM, List<EventShape> events);

  /// Releases the native side.
  void dispose();
}

/// Starts guidance tracks; one per route, a recalculation starts a new one
/// (Ferrostar's controller is bound to its route).
abstract interface class GuidanceEngine {
  /// Whether this device can guide: the Rust library is built for Android
  /// and iOS only.
  bool get available;

  /// Guidance along route [routeIndex] of [osrmJson] (the API's `osrmJson`).
  GuidanceTrack start(String osrmJson, int routeIndex);
}

/// Why guidance could not start.
final class GuidanceUnavailable implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'GuidanceUnavailable: $message';
}
