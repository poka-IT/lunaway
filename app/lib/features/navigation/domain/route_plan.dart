import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:meta/meta.dart';

/// How a route request ended (`RouteStatus` of the API).
enum RouteStatus {
  /// At least one route the vehicle may drive.
  ok,

  /// No road joins the points.
  noRoute,

  /// A point is too far from any road.
  offNetwork,

  /// Roads exist, but each meets a limit the vehicle exceeds.
  noSafeRoute,
}

/// What a restriction means for the vehicle (`RouteWarningKind`).
enum RouteWarningKind {
  lowClearance,
  unknownClearance,
  narrow,
  tooLong,
  tooHeavy,
  axleLoad,
  motorhomeBan,
  trailerBan,

  /// A weight limit for heavy goods vehicles (a traffic order): it does not
  /// bind a motorhome, the signs say whom it binds.
  goodsVehicleWeight,
}

/// Whether the vehicle may pass.
enum WarningSeverity {
  /// It may not: the route goes round it, or there is none.
  blocking,

  /// It may, with care.
  warning,
}

/// Where a restriction's figure comes from.
enum RestrictionSource { osm, ign, community, dialog }

/// How sure the figure is.
enum RestrictionCertainty {
  /// One figure, or two sources that agree.
  known,

  /// Two sources disagree; the lower figure applies.
  disputed,

  /// Lower than standard, figure unknown.
  unknown,
}

/// What the restricted place is, for the wording.
enum RestrictionPlace { underpass, tunnel, buildingPassage, bridge, barrier, road }

/// A restriction along a route, or one that stopped every route.
@immutable
final class RouteWarning {
  const new({
    required this.kind,
    required this.severity,
    required this.distanceFromStartM,
    required this.geometryIndex,
    required this.position,
    required this.source,
    required this.certainty,
    required this.place,
    required this.externalId,
    this.limit,
    this.vehicleValue,
    this.name,
    this.exceptDestination = false,
  });

  final RouteWarningKind kind;
  final WarningSeverity severity;

  /// Metres or tonnes, when the restriction has a figure.
  final double? limit;

  /// The vehicle's figure it was compared with.
  final double? vehicleValue;

  /// Metres from the start of the route.
  final double distanceFromStartM;

  /// Index of the route's shape point at or before it.
  final int geometryIndex;
  final LatLng position;
  final RestrictionSource source;
  final RestrictionCertainty certainty;
  final RestrictionPlace place;

  /// The road's name, when known.
  final String? name;

  /// The source's identifier (`way/52984577`), to report a wrong figure.
  final String externalId;

  /// Whether the limit spares local access ("sauf desserte" under the
  /// sign): a vehicle above it may drive it only to reach or leave a place
  /// within. False from an API that does not tell.
  final bool exceptDestination;

  /// Whether it limits the height: what a driver checks first.
  bool get isClearance =>
      kind == RouteWarningKind.lowClearance || kind == RouteWarningKind.unknownClearance;

  @override
  bool operator ==(Object other) =>
      other is RouteWarning &&
      other.kind == kind &&
      other.severity == severity &&
      other.limit == limit &&
      other.distanceFromStartM == distanceFromStartM &&
      other.externalId == externalId &&
      other.exceptDestination == exceptDestination;

  @override
  int get hashCode =>
      Object.hash(kind, severity, limit, distanceFromStartM, externalId, exceptDestination);
}

/// A stop the vehicle could not reach where it was put (the road it lay on
/// is closed to the vehicle), which the routes start or end at instead:
/// the nearest road it can reach, up to 150 m away.
@immutable
final class MovedStop {
  const new({required this.stopIndex, required this.position, required this.distanceM});

  /// 0 the origin, then the waypoints in order, the last the destination.
  final int stopIndex;

  /// Where the routes start or end now.
  final LatLng position;

  /// How far from the point asked, metres.
  final double distanceM;

  @override
  bool operator ==(Object other) =>
      other is MovedStop &&
      other.stopIndex == stopIndex &&
      other.position == position &&
      other.distanceM == distanceM;

  @override
  int get hashCode => Object.hash(stopIndex, position, distanceM);
}

/// Why a trip has no route (`NoRouteReasonKind` of the API, and one the
/// app tells before asking).
enum NoRouteReasonKind {
  /// Every way out of the origin passes a limit the vehicle exceeds.
  originUnreachable,

  /// Every way to the destination passes a limit the vehicle exceeds.
  destinationUnreachable,

  /// Every way to the waypoint at the reason's stop passes such a limit.
  waypointUnreachable,

  /// Each stop can be reached, but no way between them suits the vehicle.
  blockedOnTheWay,

  /// No road joins the stop, whatever the vehicle (an island without a car
  /// ferry).
  notConnected,

  /// The stop lies outside the countries routes are computed in.
  outsideCoverage,

  /// No road the vehicle may drive within 5 km of the stop.
  noRoadNearby,

  /// The trip is longer than the server accepts: told by the app from the
  /// server's bound, without asking (the server refuses such a request).
  tripTooLong,
}

/// What a blocking limit limits (`VehicleLimitKind`).
enum VehicleLimitKind { height, width, length, weight, unpaved }

/// A limit that keeps the vehicle out of a stop or a trip.
@immutable
final class BlockingLimit {
  const new({required this.kind, this.limit, this.vehicleValue, this.restriction});

  final VehicleLimitKind kind;

  /// Metres or tonnes, when the restriction is known.
  final double? limit;

  /// The vehicle's figure it was compared with.
  final double? vehicleValue;

  /// The restriction that blocks, when known. Its distance from the start
  /// counts along a route the server drew for its diagnosis, which the app
  /// never receives: only its position, name and source mean something.
  final RouteWarning? restriction;
}

/// One reason a trip has no route.
@immutable
final class NoRouteReason {
  const new({required this.kind, this.stopIndex, this.limits = const [], this.tripKm, this.maxKm});

  final NoRouteReasonKind kind;

  /// The stop concerned: 0 the origin, then the waypoints in order, the
  /// last the destination; null when the reason is the whole trip's.
  final int? stopIndex;

  /// The limits that keep the vehicle out; empty when the reason is not the
  /// vehicle's, or when the server could not tell them.
  final List<BlockingLimit> limits;

  /// With [NoRouteReasonKind.tripTooLong]: the trip's length in a straight
  /// line from stop to stop, and the longest the server accepts.
  final double? tripKm;
  final double? maxKm;
}

/// A ferry crossing of a route (`FerryCrossing`).
@immutable
final class FerryCrossing {
  const new({
    required this.distanceFromStartM,
    required this.distanceM,
    required this.durationS,
    this.name,
    this.ports = const [],
    this.from,
    this.to,
    this.fromCountry,
    this.toCountry,
  });

  /// The line's name as the map gives it (`Nice - Ajaccio`).
  final String? name;

  /// The two ports the name gives, in the name's order, which is not always
  /// the crossing's.
  final List<String> ports;

  /// Where the boat is boarded and left.
  final LatLng? from;
  final LatLng? to;

  /// ISO 3166-1 alpha-2 codes, in driving order.
  final String? fromCountry;
  final String? toCountry;

  final double distanceFromStartM;

  /// Metres and seconds on the boat, as the engine reckons them (the
  /// timetable is not known).
  final double distanceM;
  final double durationS;
}

/// How a road event weighs on a route (`RoadEventSeverity`).
enum RoadEventWeight {
  /// It stops the route: only among the events that stopped every route.
  blocking,

  /// Passable, worth a look (lanes closed, a closure the server could not
  /// place for sure).
  warning,

  /// For information (works beside the road).
  info,
}

/// Why a road event weighs as it does (`RoadEventReason`).
enum RoadEventReason {
  closed,
  limitExceeded,
  nearLimit,
  laneRestriction,
  works,
  detour,

  /// Not placed on the road for sure: it may or may not be on the route.
  unmatched,

  /// Its source has not been read for too long.
  stale,
  outsideAssumedHours,
  goodsVehiclesOnly,

  /// A single user's report.
  unconfirmed,

  /// An open record whose last version is old.
  aged,

  /// The route starts or ends inside it.
  alreadyInside,
}

/// A road event met along a route (`RoadEventWarning` of the API).
@immutable
final class RouteRoadEvent {
  const new({
    required this.event,
    required this.weight,
    required this.reason,
    required this.distanceFromStartM,
    required this.position,
    this.lengthM = 0,
    this.dataAt,
  });

  final RoadEvent event;
  final RoadEventWeight weight;
  final RoadEventReason reason;

  /// Metres from the start of the route where it begins.
  final double distanceFromStartM;

  /// Metres of the route inside it; 0 for a point.
  final double lengthM;

  /// Where the route meets it.
  final LatLng position;

  /// When its source's data was last known current: what the driver is
  /// told the warning is worth.
  final DateTime? dataAt;
}

/// One lane at an intersection.
@immutable
final class LaneHint {
  const new({required this.directions, required this.active, this.follows});

  /// What the lane allows (`left`, `straight`, `slight right`...).
  final List<String> directions;

  /// Whether it leads where the route goes.
  final bool active;

  /// The direction the route takes from this lane, when the router says
  /// which of [directions] it is.
  final String? follows;
}

/// One step of a route: a maneuver, then a road to follow.
@immutable
final class RouteStep {
  const new({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
    required this.position,
    required this.maneuverType,
    this.modifier,
    this.roadName,
    this.banner,
    this.exit,
    this.exitDegrees,
    this.leftHandTraffic = false,
    this.ferry = false,
    this.lanes = const [],
  });

  /// The router's sentence (`Tournez à gauche dans Rue Raphaël.`).
  final String instruction;

  /// Metres and seconds of the road after the maneuver.
  final double distanceM;
  final double durationS;

  /// Where the maneuver is.
  final LatLng position;

  /// The OSRM maneuver type (`turn`, `roundabout`, `arrive`...).
  final String maneuverType;

  /// Its direction (`left`, `slight right`...), when it has one.
  final String? modifier;

  /// The road taken.
  final String? roadName;

  /// The banner's main line, when the router gave one.
  final String? banner;

  /// The exit of a roundabout, counted from the entry.
  final int? exit;

  /// How far round a roundabout its exit lies ([Maneuver.exitDegrees]),
  /// on the step that enters the ring and on the one that leaves it.
  final int? exitDegrees;

  /// Traffic keeps left on this road.
  final bool leftHandTraffic;

  /// This step's road is a ferry crossing.
  final bool ferry;

  /// The lanes at the maneuver that ends this step (the next one's), when
  /// the map has them: what the driver sees while following this step.
  final List<LaneHint> lanes;

  /// The maneuver as its pictogram draws it.
  Maneuver get maneuver => Maneuver(
    type: maneuverType,
    modifier: modifier,
    exitDegrees: exitDegrees,
    exitNumber: exit,
    leftHandTraffic: leftHandTraffic,
    ferry: ferry,
  );
}

/// One route of an answer.
@immutable
final class RouteOption {
  const new({
    required this.index,
    required this.distanceM,
    required this.durationS,
    required this.hasToll,
    required this.hasFerry,
    required this.hasMotorway,
    required this.warnings,
    this.line = const [],
    this.steps = const [],
    this.speedLimits,
    this.roadEvents = const [],
    this.ferries = const [],
  });

  /// Its index in the OSRM answer; 0 is the recommended one.
  final int index;
  final double distanceM;
  final double durationS;
  final bool hasToll;
  final bool hasFerry;
  final bool hasMotorway;

  /// Restrictions passed with little margin, in driving order.
  final List<RouteWarning> warnings;

  /// Road events met on the way that do not block it, in driving order.
  final List<RouteRoadEvent> roadEvents;

  /// The shape, in driving order.
  final List<LatLng> line;
  final List<RouteStep> steps;

  /// The limit for the vehicle along the route, in driving order; null when
  /// the server gave none (an older API, or an engine that did not answer
  /// in time): the guidance then reads the sign the map gives.
  final List<SpeedLimitSpan>? speedLimits;

  /// Each ferry crossing, in driving order (`ROUTE_USES_FERRY` notices);
  /// empty from an API that does not tell them, even when [hasFerry].
  final List<FerryCrossing> ferries;

  GeoBounds? get bounds => GeoBounds.around(line);

  /// The very slow road of the route, summed: its steps of [slowStepM] or
  /// more driven under [slowKmh] on average, when they take [slowAtLeastS]
  /// or more together; null below, or without steps. The router times a
  /// track without a grade at 5 km/h, an unpaved one at 2: a last 1.5 km of
  /// track made 46 of the 54 minutes of an 8.4 km route, which nothing said.
  ({double distanceM, double durationS})? get slowStretch {
    var distance = 0.0;
    var duration = 0.0;
    for (final step in steps) {
      if (step.distanceM < slowStepM || step.durationS <= 0) continue;
      if (step.distanceM / step.durationS * 3.6 < slowKmh) {
        distance += step.distanceM;
        duration += step.durationS;
      }
    }
    return duration >= slowAtLeastS ? (distanceM: distance, durationS: duration) : null;
  }

  RouteOption withShape({required List<LatLng> line, required List<RouteStep> steps}) =>
      RouteOption(
        index: index,
        distanceM: distanceM,
        durationS: durationS,
        hasToll: hasToll,
        hasFerry: hasFerry,
        hasMotorway: hasMotorway,
        warnings: warnings,
        line: line,
        steps: steps,
        speedLimits: speedLimits,
        roadEvents: roadEvents,
        ferries: ferries,
      );
}

/// A step slower than this on average, km/h, is very slow road: a walk's
/// pace, far under a town's.
const slowKmh = 10.0;

/// Steps shorter than this, metres, never count as very slow road: a turn
/// timed with its wait at the junction.
const slowStepM = 200.0;

/// Very slow road worth a word: this many seconds of it, or more.
const slowAtLeastS = 300.0;

/// The routing data a route was computed on.
@immutable
final class RoutingGraphInfo {
  const new({
    required this.id,
    required this.osmDataAt,
    required this.builtAt,
    this.ignFetchedAt,
    this.ignEdition,
  });

  final String id;

  /// The date of the OpenStreetMap data: the date the preview shows.
  final DateTime osmDataAt;
  final DateTime builtAt;
  final DateTime? ignFetchedAt;

  /// The BD TOPO edition, for the attribution "IGN, BD TOPO".
  final DateTime? ignEdition;
}

/// The vehicle and options a route was computed with, as the server applied
/// them: what a recalculation sends again.
@immutable
final class AppliedRequest {
  const new({required this.vehicle, required this.avoid, required this.language, this.topSpeedKph});

  final VehicleProfile vehicle;
  final AvoidOptions avoid;
  final RouteLanguage language;

  /// The speed the times assume at most, km/h: the driver's cruising speed
  /// lowered to the vehicle's legal ceiling. Null when neither applies, or
  /// from an API that does not tell.
  final int? topSpeedKph;

  /// The speed to tell with the times: only when the driver set one, as
  /// the legal ceiling alone is no choice of theirs.
  int? get cruiseShownKph => vehicle.cruiseSpeedKph == null ? null : topSpeedKph;
}

/// The answer to a route request.
@immutable
final class RoutePlan {
  const new({
    required this.status,
    required this.routes,
    required this.blockers,
    required this.recalculations,
    required this.applied,
    required this.graph,
    this.osrmJson,
    this.avoidedRoadEvents = const [],
    this.roadEventBlockers = const [],
    this.roadEventSources = const [],
    this.noRouteReasons = const [],
    this.movedStops = const [],
  });

  final RouteStatus status;

  /// With [RouteStatus.noRoute] or [RouteStatus.offNetwork]: why, one
  /// reason per stop concerned or one for the trip; empty when the server
  /// could not tell in time, or does not tell yet.
  final List<NoRouteReason> noRouteReasons;

  /// The routes, recommended first.
  final List<RouteOption> routes;

  /// With [RouteStatus.noSafeRoute]: the limits that stopped every route.
  final List<RouteWarning> blockers;

  /// How many times the server computed again around a limit.
  final int recalculations;
  final AppliedRequest applied;
  final RoutingGraphInfo graph;

  /// The router's answer, what the guidance engine reads; null unless
  /// [status] is [RouteStatus.ok].
  final String? osrmJson;

  /// The closures and limits the routes go around ("2 closures avoided").
  final List<RoadEvent> avoidedRoadEvents;

  /// With [RouteStatus.noSafeRoute]: the road events that stopped every
  /// route.
  final List<RouteRoadEvent> roadEventBlockers;

  /// The sources of road events and the age of their data.
  final List<RoadEventSourceStatus> roadEventSources;

  /// With [RouteStatus.ok]: the stops the routes do not start or end at,
  /// moved to a road the vehicle can reach; empty from an API that does not
  /// move them.
  final List<MovedStop> movedStops;

  /// Where the stop at [stopIndex] was moved, if it was.
  LatLng? movedTo(int stopIndex) =>
      movedStops.where((m) => m.stopIndex == stopIndex).firstOrNull?.position;

  /// The status of [source], when the answer named it.
  RoadEventSourceStatus? sourceOf(String source) =>
      roadEventSources.where((s) => s.id == source).firstOrNull;

  RoutePlan withRoutes(List<RouteOption> routes) => RoutePlan(
    status: status,
    routes: routes,
    blockers: blockers,
    recalculations: recalculations,
    applied: applied,
    graph: graph,
    osrmJson: osrmJson,
    avoidedRoadEvents: avoidedRoadEvents,
    roadEventBlockers: roadEventBlockers,
    roadEventSources: roadEventSources,
    noRouteReasons: noRouteReasons,
    movedStops: movedStops,
  );
}
