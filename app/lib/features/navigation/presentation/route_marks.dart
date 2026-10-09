import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/road_reports.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// A mark of a route map and what it stands for: the map draws [mark], the
/// tooltip, the callout and the legend read [subject].
@immutable
final class RouteMarker {
  const new(this.mark, this.subject);

  final RouteMapMark mark;
  final MarkSubject subject;

  String get id => mark.id;
}

/// What a mark stands for.
@immutable
sealed class MarkSubject {
  const new();

  /// Whether a row of the preview's list shows it: "Voir dans la liste"
  /// leads there.
  bool get listed => false;
}

final class OriginSubject extends MarkSubject {
  const new();
}

final class DestinationSubject extends MarkSubject {
  const new({this.label, this.distanceM});

  final String? label;

  /// The route's length, when one is drawn.
  final double? distanceM;
}

final class StopSubject extends MarkSubject {
  const new(this.index, this.stop);

  final int index;
  final RouteStop stop;
}

final class PlaceSubject extends MarkSubject {
  const new(this.place);

  final PlaceSummary place;
}

final class FuelSubject extends MarkSubject {
  const new(this.offer);

  final FuelOffer offer;
}

/// A limit of the route ([fromStart]), or one that stopped every route or
/// a stop, whose distance means nothing on the route drawn.
final class WarningSubject extends MarkSubject {
  const new(this.warning, {this.fromStart = true});

  final RouteWarning warning;
  final bool fromStart;

  @override
  bool get listed => true;
}

/// A road event met on the route, or one that stopped every route.
final class EventSubject extends MarkSubject {
  const new(this.event);

  final RouteRoadEvent event;

  @override
  bool get listed => true;
}

/// A closure the routes go around.
final class AvoidedSubject extends MarkSubject {
  const new(this.event);

  final RoadEvent event;

  @override
  bool get listed => true;
}

/// A speed camera of the route, where its country lets its position be
/// shown.
final class CameraSubject extends MarkSubject {
  const new(this.camera);

  final CameraOnRoute camera;
}

/// The kind of mark a restriction makes.
RouteMarkKind warningMarkKind(RouteWarningKind kind) => switch (kind) {
  RouteWarningKind.lowClearance || RouteWarningKind.unknownClearance => RouteMarkKind.clearance,
  RouteWarningKind.tooHeavy ||
  RouteWarningKind.axleLoad ||
  RouteWarningKind.goodsVehicleWeight => RouteMarkKind.weight,
  RouteWarningKind.narrow ||
  RouteWarningKind.tooLong ||
  RouteWarningKind.motorhomeBan ||
  RouteWarningKind.trailerBan => RouteMarkKind.limit,
};

SignGlyph _signOf(RouteWarningKind kind) => switch (kind) {
  RouteWarningKind.lowClearance || RouteWarningKind.unknownClearance => SignGlyph.height,
  RouteWarningKind.tooHeavy ||
  RouteWarningKind.axleLoad ||
  RouteWarningKind.goodsVehicleWeight => SignGlyph.weight,
  RouteWarningKind.narrow => SignGlyph.width,
  RouteWarningKind.tooLong => SignGlyph.length,
  RouteWarningKind.motorhomeBan => SignGlyph.motorhome,
  RouteWarningKind.trailerBan => SignGlyph.trailer,
};

/// The mark of a restriction: its sign, the figure beside it.
RouteMarker warningMarker(
  String id,
  RouteWarning w,
  Translations t, {
  bool blocking = false,
  bool fromStart = true,
}) => RouteMarker(
  RouteMapMark(
    id: id,
    position: w.position,
    kind: warningMarkKind(w.kind),
    badge: RouteBadge.sign(
      _signOf(w.kind),
      blocking: blocking || w.severity == WarningSeverity.blocking,
    ),
    // A weight limit for goods vehicles does not bind a motorhome.
    minor: w.kind == RouteWarningKind.goodsVehicleWeight,
    side: w.limit == null ? null : t.limitFigure(w.kind, w.limit!),
  ),
  WarningSubject(w, fromStart: fromStart),
);

/// The kind of mark a road event makes, and its sign when it limits a size.
(RouteMarkKind, RouteBadge) eventLook(RoadEvent e, {required bool blocking}) =>
    switch (e.eventClass) {
      RoadEventClass.closure || RoadEventClass.detour => (
        RouteMarkKind.closure,
        blocking ? RouteBadge.closureBlocking : RouteBadge.closure,
      ),
      RoadEventClass.works => (RouteMarkKind.works, RouteBadge.works),
      RoadEventClass.laneRestriction => (RouteMarkKind.lanes, RouteBadge.lanes),
      RoadEventClass.vehicleLimit when e.maxWeightT != null && e.maxHeightM == null => (
        RouteMarkKind.weight,
        RouteBadge.sign(SignGlyph.weight, blocking: blocking),
      ),
      RoadEventClass.vehicleLimit when e.maxHeightM == null && e.maxWidthM != null => (
        RouteMarkKind.limit,
        RouteBadge.sign(SignGlyph.width, blocking: blocking),
      ),
      RoadEventClass.vehicleLimit when e.maxHeightM == null && e.maxLengthM != null => (
        RouteMarkKind.limit,
        RouteBadge.sign(SignGlyph.length, blocking: blocking),
      ),
      RoadEventClass.vehicleLimit => (
        RouteMarkKind.clearance,
        RouteBadge.sign(SignGlyph.height, blocking: blocking),
      ),
    };

/// The mark of a road event met on the route; [blocking] when it stopped
/// every route.
RouteMarker eventMarker(String id, RouteRoadEvent e, {bool blocking = false}) {
  final stops = blocking || e.weight == RoadEventWeight.blocking;
  final (kind, badge) = eventLook(e.event, blocking: stops);
  return RouteMarker(
    RouteMapMark(
      id: id,
      position: e.position,
      kind: kind,
      badge: badge,
      // Lanes closed, works beside the road, a limit for goods vehicles:
      // worth knowing, not about the vehicle.
      minor:
          !stops &&
          (kind == RouteMarkKind.lanes ||
              e.weight == RoadEventWeight.info ||
              e.reason == RoadEventReason.goodsVehiclesOnly),
    ),
    EventSubject(e),
  );
}

/// The mark of a camera of the route: its badge, its limit beside it in
/// the user's units. Null for an item without a place, which no route
/// meets.
RouteMarker? cameraMarker(CameraOnRoute c, Translations t, {required DistanceUnits units}) {
  final at = c.item.markAt;
  if (at == null) return null;
  final limit = c.item.limitKmh;
  return RouteMarker(
    RouteMapMark(
      id: cameraMarkId(c.item.id),
      position: at,
      kind: RouteMarkKind.camera,
      badge: RouteBadge.camera,
      side: limit == null ? null : t.speedLimit(limit, units),
    ),
    CameraSubject(c),
  );
}

/// The marks of the route preview: the tappable [points] (places, stations,
/// stops), the ends, the limits and road events of the chosen [route] only
/// (an alternative's show once it is chosen), the closures the routes go
/// around, and what stopped every route or a stop.
List<RouteMarker> previewMarkers({
  required Translations t,
  required LatLng destination,
  required List<RouteMarker> points,
  LatLng? origin,
  String? destinationLabel,
  RouteOption? route,
  RoutePlan? plan,
  List<NoRouteReason> noRouteReasons = const [],
  List<CameraOnRoute> cameras = const [],
  DistanceUnits units = DistanceUnits.metric,
}) => [
  ...points,
  if (origin != null)
    RouteMarker(
      RouteMapMark(
        id: 'origin',
        position: origin,
        kind: RouteMarkKind.origin,
        badge: RouteBadge.origin,
      ),
      const OriginSubject(),
    ),
  RouteMarker(
    RouteMapMark(
      id: 'destination',
      position: destination,
      kind: RouteMarkKind.destination,
      badge: RouteBadge.destination,
    ),
    DestinationSubject(label: destinationLabel, distanceM: route?.distanceM),
  ),
  if (route != null) ...[
    for (final (i, w) in route.warnings.indexed) warningMarker(warningMarkId(route.index, i), w, t),
    for (final e in route.roadEvents) eventMarker(eventMarkId(route.index, e.event.id), e),
    for (final c in cameras) ?cameraMarker(c, t, units: units),
  ],
  if (plan != null) ...[
    for (final (i, b) in plan.blockers.indexed)
      warningMarker(blockerMarkId(i), b, t, blocking: true, fromStart: false),
    for (final e in plan.roadEventBlockers)
      eventMarker(eventBlockerMarkId(e.event.id), e, blocking: true),
    for (final e in plan.avoidedRoadEvents)
      if (e.position case final at?) avoidedMarker(e, at),
  ],
  // What keeps the vehicle out of a stop, where the server knows it; a
  // restriction that keeps out two stops is one mark.
  for (final w in _restrictions(noRouteReasons))
    warningMarker(limitMarkId(w), w, t, blocking: true, fromStart: false),
];

/// The restrictions behind [reasons], each once.
Iterable<RouteWarning> _restrictions(List<NoRouteReason> reasons) {
  final byId = <String, RouteWarning>{};
  for (final r in reasons) {
    for (final l in r.limits) {
      final w = l.restriction;
      if (w != null) byId.putIfAbsent(limitMarkId(w), () => w);
    }
  }
  return byId.values;
}

// The ids of the marks a row of the list stands for: the rows and the
// marks are built apart and meet through them.
String warningMarkId(int route, int index) => 'warning:$route:$index';
String eventMarkId(int route, String event) => 'event:$route:$event';
String blockerMarkId(int index) => 'blocker:$index';
String eventBlockerMarkId(String event) => 'eventblocker:$event';
String avoidedMarkId(String event) => 'avoided:$event';
String limitMarkId(RouteWarning restriction) => 'limit:${restriction.externalId}';
String cameraMarkId(String item) => 'camera:$item';

/// The mark of a closure the routes go around.
RouteMarker avoidedMarker(RoadEvent e, LatLng at) {
  final (kind, badge) = eventLook(e, blocking: false);
  return RouteMarker(
    RouteMapMark(id: avoidedMarkId(e.id), position: at, kind: kind, badge: badge),
    AvoidedSubject(e),
  );
}

/// The words of a mark: what it is, which one, where on the route, and
/// where the data comes from and how recent it is.
@immutable
final class MarkWords {
  const new({required this.category, required this.title, this.lines = const [], this.source});

  final String category;
  final String title;
  final List<String> lines;
  final String? source;
}

/// What a kind of mark is called, in the legend and above a tooltip.
String markKindName(Translations t, RouteMarkKind kind) => switch (kind) {
  RouteMarkKind.origin => t.navigation.marks.kindOrigin,
  RouteMarkKind.destination => t.navigation.marks.kindDestination,
  RouteMarkKind.stop => t.navigation.marks.kindStop,
  RouteMarkKind.closure => t.navigation.marks.kindClosure,
  RouteMarkKind.works => t.navigation.marks.kindWorks,
  RouteMarkKind.lanes => t.navigation.marks.kindLanes,
  RouteMarkKind.clearance => t.navigation.marks.kindClearance,
  RouteMarkKind.weight => t.navigation.marks.kindWeight,
  RouteMarkKind.limit => t.navigation.marks.kindLimit,
  RouteMarkKind.camera => t.navigation.marks.kindCamera,
  RouteMarkKind.fuel => t.navigation.marks.kindFuel,
  RouteMarkKind.place => t.navigation.marks.kindPlace,
};

/// The words of [marker], for its tooltip or its callout.
MarkWords markWords(
  RouteMarker marker,
  Translations t, {
  required DistanceUnits units,
  required DateTime now,
  RoutePlan? plan,
}) {
  final kind = markKindName(t, marker.mark.kind);
  String fromStart(double m) =>
      t.navigation.roadEvents.atDistance(distance: t.routeDistance(m, units));
  return switch (marker.subject) {
    OriginSubject() => MarkWords(category: kind, title: t.navigation.marks.origin),
    DestinationSubject(:final label, :final distanceM) => MarkWords(
      category: kind,
      title: label ?? t.navigation.stops.point,
      lines: [if (distanceM != null) fromStart(distanceM)],
    ),
    StopSubject(:final index, :final stop) => MarkWords(
      category: t.navigation.marks.stop(n: '${index + 1}'),
      title: stop.label ?? t.navigation.stops.point,
    ),
    PlaceSubject(:final place) => MarkWords(
      category: t.kind(place.kind),
      title: t.summaryTitle(place),
      lines: [t.navigation.marks.nearRoute],
    ),
    FuelSubject(:final offer) => MarkWords(
      category: kind,
      title: offer.name ?? offer.brand ?? t.navigation.fuel.station,
      lines: ['${t.fuelType(offer.fuel)} ${t.litrePrice(offer.priceEur)}', fromStart(offer.alongM)],
      source: '${t.navigation.fuel.attribution}, ${t.priceAge(offer.priceUpdatedAt, now)}',
    ),
    WarningSubject(:final warning, fromStart: final onRoute) => MarkWords(
      category: kind,
      title: t.warningTitle(warning),
      lines: [
        if (onRoute) fromStart(warning.distanceFromStartM),
        ?t.warningVehicle(warning),
        ?warning.name,
      ],
      source: t.warningSource(warning),
    ),
    EventSubject(:final event) => MarkWords(
      category: kind,
      title: [
        [?event.event.road, t.roadEventWhat(event.event.eventClass)].join(' · '),
        ?t.roadEventQualifier(event.reason),
      ].join(', '),
      lines: [
        if (event.weight == RoadEventWeight.blocking)
          t.navigation.marks.blocking
        else
          fromStart(event.distanceFromStartM),
      ],
      source: roadEventSource(
        t,
        plan,
        event.event.source,
        // A community report is as old as its last report.
        event.event.source == communityRoadSource
            ? event.event.updatedAt ?? event.dataAt
            : event.dataAt,
        now,
      ),
    ),
    AvoidedSubject(:final event) => MarkWords(
      category: kind,
      title: [?event.road, t.roadEventWhat(event.eventClass)].join(' · '),
      lines: [t.navigation.marks.avoided],
      source: roadEventSource(t, plan, event.source, null, now),
    ),
    CameraSubject(:final camera) => MarkWords(
      category: kind,
      title: t.cameraTitle(camera.item, units),
      lines: [
        fromStart(camera.onRoute.startM),
        if (camera.item.isSection)
          t.navigation.marks.sectionLength(
            distance: t.routeDistance(camera.onRoute.endM - camera.onRoute.startM, units),
          ),
        // A camera meets the route only where it controls the way the
        // route goes: a direction known is the driver's.
        if (camera.item.bearingDeg != null) t.navigation.marks.cameraDirection,
      ],
      source: camera.sources.isEmpty
          ? null
          : [for (final s in camera.sources) t.enforcementSource(s)].join('\n'),
    ),
  };
}

/// Where a road event comes from and how recent its source's data is:
/// "DIR, Bison Futé, données de 22 h 38".
String roadEventSource(Translations t, RoutePlan? plan, String id, DateTime? at, DateTime now) {
  final status = plan?.sourceOf(id);
  return t.roadDataSource(
    status?.attribution ?? status?.name ?? id,
    at ?? status?.dataAt ?? status?.lastReadAt,
    now,
  );
}

/// The words of a group of marks: how many, of which kinds.
MarkWords groupWords(Translations t, Map<RouteMarkKind, int> counts) {
  final total = counts.values.fold(0, (a, b) => a + b);
  return MarkWords(
    category: t.navigation.marks.group(n: total),
    title: [
      for (final e in counts.entries)
        t.navigation.marks.count(kind: markKindName(t, e.key), n: '${e.value}'),
    ].join(' · '),
    lines: [t.navigation.marks.groupHint],
  );
}

/// One row of the legend: a kind of mark on this route, and its badge as
/// the map draws it.
@immutable
final class LegendRow {
  const new(this.kind, this.badge, {this.label, this.count = 1});

  /// Null for the row of the groups.
  final RouteMarkKind? kind;
  final RouteBadge badge;

  /// Written on the badge, as on the map.
  final String? label;

  /// How many marks of the kind the route has.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is LegendRow &&
      other.kind == kind &&
      other.badge == badge &&
      other.label == label &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, badge, label, count);
}

/// The legend's words for [row]: the kind, and for the cameras how many
/// the route has ("3 radars").
String legendText(Translations t, LegendRow row) => switch (row.kind) {
  null => t.navigation.marks.groupLegend,
  RouteMarkKind.camera => t.navigation.marks.cameras(n: row.count),
  final kind => markKindName(t, kind),
};

/// The legend of [marks]: only the kinds present, in a fixed order, each
/// with the badge of its first mark and how many there are; then the
/// group badge when marks may gather into one.
List<LegendRow> legendRows(List<RouteMapMark> marks) {
  final first = <RouteMarkKind, RouteMapMark>{};
  final counts = <RouteMarkKind, int>{};
  for (final m in marks) {
    first.putIfAbsent(m.kind, () => m);
    counts[m.kind] = (counts[m.kind] ?? 0) + 1;
  }
  final groupable = marks.where((m) => !m.kind.anchor).toList();
  final tone = groupable.isEmpty
      ? MarkTone.info
      : groupable.map((m) => m.kind.tone).reduce((a, b) => a.rank >= b.rank ? a : b);
  return [
    for (final k in RouteMarkKind.values)
      if (first[k] case final m?) LegendRow(k, m.badge, label: m.label, count: counts[k]!),
    if (groupable.length > 1) LegendRow(null, RouteBadge.cluster(tone), label: '3'),
  ];
}
