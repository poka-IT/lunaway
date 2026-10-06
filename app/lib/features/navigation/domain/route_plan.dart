import 'package:lunaway/core/geo/geo.dart';
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
      other.externalId == externalId;

  @override
  int get hashCode => Object.hash(kind, severity, limit, distanceFromStartM, externalId);
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

  /// The lanes at the maneuver that ends this step (the next one's), when
  /// the map has them: what the driver sees while following this step.
  final List<LaneHint> lanes;
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

  /// The shape, in driving order.
  final List<LatLng> line;
  final List<RouteStep> steps;

  /// The limit for the vehicle along the route, in driving order; null when
  /// the server gave none (an older API, or an engine that did not answer
  /// in time): the guidance then reads the sign the map gives.
  final List<SpeedLimitSpan>? speedLimits;

  GeoBounds? get bounds => GeoBounds.around(line);

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
      );
}

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

  /// The date of the OpenStreetMap data: the date the disclaimer shows.
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
  const new({required this.vehicle, required this.avoid, required this.language});

  final VehicleProfile vehicle;
  final AvoidOptions avoid;
  final RouteLanguage language;
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
    required this.disclaimerKey,
    this.osrmJson,
  });

  final RouteStatus status;

  /// The routes, recommended first.
  final List<RouteOption> routes;

  /// With [RouteStatus.noSafeRoute]: the limits that stopped every route.
  final List<RouteWarning> blockers;

  /// How many times the server computed again around a limit.
  final int recalculations;
  final AppliedRequest applied;
  final RoutingGraphInfo graph;

  /// The disclaimer's translation key (`routing.disclaimer.v1`).
  final String disclaimerKey;

  /// The router's answer, what the guidance engine reads; null unless
  /// [status] is [RouteStatus.ok].
  final String? osrmJson;

  RoutePlan withRoutes(List<RouteOption> routes) => RoutePlan(
    status: status,
    routes: routes,
    blockers: blockers,
    recalculations: recalculations,
    applied: applied,
    graph: graph,
    disclaimerKey: disclaimerKey,
    osrmJson: osrmJson,
  );
}
