import 'package:lunaway/core/geo/geo.dart';
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
  const new({required this.id, required this.points});

  final String id;

  /// One point, or the line of the road it covers.
  final List<LatLng> points;
}

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

  /// Where the route, from [fromM] metres onwards, drives along each of
  /// [events] (the server's corridor rule), in driving order.
  List<EventHit> eventsAhead(double fromM, List<EventShape> events, {double toleranceM = 12});

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
