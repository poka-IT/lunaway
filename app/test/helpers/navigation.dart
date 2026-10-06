import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/app_foreground.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/danger_zones.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

/// The motorhome the recorded routes were computed for: 3.30 m high,
/// 2.30 m wide, 7.4 m long, 3.5 t.
const motorhome = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.3,
  widthM: 2.3,
  lengthM: 7.4,
  weightT: 3.5,
);

/// The body of a recorded answer of the API's `route` query
/// (`test/fixtures/navigation/route_<name>.json`, 2026-10-06).
Map<String, dynamic> routeAnswer(String name) {
  final body = jsonDecode(
    File('test/fixtures/navigation/route_$name.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['route'] as Map<String, dynamic>;
}

/// A recorded answer, parsed as the app parses it, shapes and steps
/// included; [edit] changes the answer first.
RoutePlan routeFixture(String name, {void Function(Map<String, dynamic> answer)? edit}) {
  final answer = routeAnswer(name);
  edit?.call(answer);
  final plan = routePlanFromJson(answer);
  final json = plan.osrmJson;
  if (json == null) return plan;
  final shapes = readOsrmShapes(json);
  return plan.withRoutes([
    for (final r in plan.routes)
      r.withShape(line: shapes[r.index].line, steps: shapes[r.index].steps),
  ]);
}

/// Route answers given in turn; the last one repeats. An exception in the
/// list is thrown at its turn.
final class FakeRouteService implements RouteService {
  new(this.answers, {this.routingInfo});

  final List<Object> answers;
  final RoutingInfo? routingInfo;
  final List<RouteRequest> requests = [];

  /// Holds the answers back until completed, for the loading states.
  Completer<void>? gate;

  @override
  Future<RoutePlan> route(RouteRequest request) async {
    requests.add(request);
    final g = gate;
    if (g != null) await g.future;
    final answer = answers[math.min(requests.length - 1, answers.length - 1)];
    if (answer is Exception) throw answer;
    return answer as RoutePlan;
  }

  @override
  Future<RoutingInfo> info() async =>
      routingInfo ??
      const RoutingInfo(
        available: true,
        disclaimerKey: 'routing.disclaimer.v1',
        coveredArea: GeoBounds(south: 41, west: -5.8, north: 51.6, east: 10),
        maxAlternatives: 2,
        bounds: VehicleBounds(),
      );
}

/// A position the test sets, and fixes it sends one by one.
final class FakeLocationFeed implements LocationFeed {
  new({this.position});

  LatLng? position;
  StreamController<Fix> _fixes = StreamController.broadcast();
  final List<BackgroundNotice> notices = [];

  bool get listening => _fixes.hasListener;

  void send(Fix fix) => _fixes.add(fix);

  /// The stream fails and ends, as geolocator's does when location is
  /// turned off; the guidance must ask for it again.
  void fail(Object error) {
    final failed = _fixes;
    _fixes = StreamController.broadcast();
    failed.addError(error);
    unawaited(failed.close());
  }

  @override
  Future<Fix?> current() async =>
      position == null ? null : Fix(position: position!, accuracyM: 5, at: DateTime.utc(2026));

  @override
  Stream<Fix> guidance(BackgroundNotice notice) {
    notices.add(notice);
    return _fixes.stream;
  }
}

/// The voice, recorded.
final class RecordingVoice implements VoiceOutput {
  new({this.readiness = VoiceReadiness.ready});

  VoiceReadiness readiness;
  final List<String> said = [];
  final List<String> queued = [];
  int stops = 0;
  int installs = 0;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async => readiness;

  @override
  Future<void> say(String text, {bool queue = false}) async {
    said.add(text);
    if (queue) queued.add(text);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<bool> installVoices() async {
    installs++;
    return true;
  }
}

final class FakeScreenWake implements ScreenWake {
  bool on = false;

  @override
  Future<void> keepOn({required bool on}) async => this.on = on;
}

/// Road event deltas given in turn; the last one repeats with no change.
final class ScriptedRoadEvents implements RoadEventsSource {
  new(this.deltas);

  final List<Object> deltas;
  final List<String?> cursors = [];

  @override
  Future<RoadEventsDelta> delta({String? cursor}) async {
    cursors.add(cursor);
    final i = cursors.length - 1;
    if (i >= deltas.length) {
      return RoadEventsDelta(cursor: cursor ?? 'c', asOf: DateTime.utc(2026, 10, 6, 9));
    }
    final d = deltas[i];
    if (d is Exception) throw d;
    return d as RoadEventsDelta;
  }
}

/// Route settings kept in memory.
final class MemoryRouteSettings implements RouteSettingsStore {
  new([this.value = const NavigationSettings()]);

  NavigationSettings value;
  int saves = 0;

  @override
  Future<NavigationSettings> load() async => value;

  @override
  Future<void> save(NavigationSettings settings) async {
    saves++;
    value = settings;
  }
}

/// A guidance track in Dart, for tests that run without the Rust library:
/// a fix is projected on the route's line; off the route beyond 40 m, one
/// fix late as Ferrostar is; the step is the one whose stretch holds the
/// vehicle; its instruction is spoken in its last 300 m.
final class LineTrack implements GuidanceTrack {
  new(this.route, {this.eventHits});

  final RouteOption route;

  /// What [eventsAhead] answers; the events' first point otherwise, at
  /// its distance along the route.
  final List<EventHit> Function(double fromM, List<EventShape> events)? eventHits;
  bool disposed = false;
  final List<Fix> fixes = [];
  double? _lastOff;

  late final List<double> _along = () {
    final out = <double>[0];
    for (var i = 1; i < route.line.length; i++) {
      out.add(out.last + route.line[i - 1].distanceTo(route.line[i]));
    }
    return out;
  }();

  double get length => _along.last;

  /// The point [metres] along the line.
  LatLng at(double metres) {
    for (var i = 1; i < _along.length; i++) {
      if (_along[i] >= metres) {
        final span = _along[i] - _along[i - 1];
        final t = span == 0 ? 0.0 : (metres - _along[i - 1]) / span;
        final a = route.line[i - 1];
        final b = route.line[i];
        return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      }
    }
    return route.line.last;
  }

  (double along, double off) _project(LatLng p) {
    var best = (0.0, double.infinity);
    for (var i = 1; i < route.line.length; i++) {
      final a = route.line[i - 1];
      final b = route.line[i];
      final k = math.cos(a.lat * math.pi / 180);
      final ax = (a.lon - p.lon) * k;
      final ay = a.lat - p.lat;
      final dx = (b.lon - a.lon) * k;
      final dy = b.lat - a.lat;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      final q = LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      final d = q.distanceTo(p);
      if (d < best.$2) best = (_along[i - 1] + t * (_along[i] - _along[i - 1]), d);
    }
    return best;
  }

  @override
  GuidanceSnapshot update(Fix fix) {
    fixes.add(fix);
    final (along, off) = _project(fix.position);
    final wasOff = _lastOff != null && _lastOff! > 40;
    _lastOff = off;
    final remaining = math.max<double>(0, length - along);
    if (remaining < 15 && off < 40) {
      return GuidanceSnapshot(
        status: GuidanceStatus.arrived,
        position: route.line.last,
        stepIndex: route.steps.length - 1,
        distanceToManeuverM: 0,
        distanceRemainingM: 0,
        durationRemainingS: 0,
        distanceAlongM: length,
      );
    }
    var stepStart = 0.0;
    var index = 0;
    for (var i = 0; i < route.steps.length; i++) {
      if (stepStart + route.steps[i].distanceM > along || i == route.steps.length - 1) {
        index = i;
        break;
      }
      stepStart += route.steps[i].distanceM;
    }
    final toManeuver = stepStart + route.steps[index].distanceM - along;
    final next = index + 1 < route.steps.length ? route.steps[index + 1] : null;
    return GuidanceSnapshot(
      status: GuidanceStatus.navigating,
      position: at(along),
      courseDeg: fix.courseDeg,
      stepIndex: index,
      distanceToManeuverM: toManeuver,
      distanceRemainingM: remaining,
      durationRemainingS: route.durationS * remaining / length,
      distanceAlongM: along,
      offRouteM: wasOff ? off : null,
      // A step's banner describes the maneuver that ends it, as in the
      // OSRM format.
      banner: next == null
          ? null
          : ManeuverBanner(
              primary: route.steps[index].banner ?? next.roadName ?? next.instruction,
              maneuverType: next.maneuverType,
              modifier: next.modifier,
              lanes: route.steps[index].lanes,
            ),
      instruction: next != null && toManeuver < 300
          ? SpokenInstruction(id: 'step-${index + 1}', text: next.instruction)
          : null,
      speedLimitKmh: 50,
    );
  }

  @override
  List<EventHit> eventsAhead(double fromM, List<EventShape> events) {
    final hits = eventHits;
    if (hits != null) return hits(fromM, events);
    return [
      for (final e in events)
        if (_project(e.points.first) case (final along, final off) when off < 15 && along >= fromM)
          EventHit(id: e.id, startM: along, endM: along, at: e.points.first),
    ];
  }

  @override
  void dispose() => disposed = true;
}

/// An engine that starts [LineTrack]s over the plans it is given.
final class LineEngine implements GuidanceEngine {
  new(this.plans, {this.eventHits});

  /// The plans whose OSRM answer a track may be started on.
  final List<RoutePlan> plans;
  final List<EventHit> Function(double fromM, List<EventShape> events)? eventHits;
  final List<LineTrack> tracks = [];

  @override
  bool get available => true;

  @override
  GuidanceTrack start(String osrmJson, int routeIndex) {
    final plan = plans.firstWhere((p) => p.osrmJson == osrmJson);
    final track = LineTrack(
      plan.routes.firstWhere((r) => r.index == routeIndex),
      eventHits: eventHits,
    );
    tracks.add(track);
    return track;
  }
}

/// The route map as tests draw it: the routes in their box, the marks as
/// dots, the vehicle as an arrow. Platform views do not render in tests,
/// and the goldens show the route this way.
final class SchematicRouteMap extends StatelessWidget {
  const new(this.props, {super.key});

  final RouteMapProps props;

  /// The props of the last map built, for the tests to read.
  static RouteMapProps? last;

  @override
  Widget build(BuildContext context) {
    last = props;
    final dark = props.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF0E2340) : const Color(0xFFF1E7D2),
      child: CustomPaint(painter: _SchematicPainter(props), size: Size.infinite),
    );
  }
}

Widget schematicRouteMap(BuildContext context, RouteMapProps props) => SchematicRouteMap(props);

class _SchematicPainter extends CustomPainter {
  new(this.props);

  final RouteMapProps props;

  Color _hex(String hex) => Color(int.parse('ff${hex.substring(1)}', radix: 16));

  @override
  void paint(Canvas canvas, Size size) {
    final camera = props.camera;
    final bounds = switch (camera) {
      FitCamera(:final bounds) => bounds,
      FollowCamera(:final position) => GeoBounds(
        south: position.lat - 0.004,
        west: position.lon - 0.006,
        north: position.lat + 0.004,
        east: position.lon + 0.006,
      ),
    };
    final pad = props.padding;
    final box = Rect.fromLTRB(
      pad.left + 24,
      pad.top + 24,
      size.width - pad.right - 24,
      size.height - pad.bottom - 24,
    );
    if (box.width <= 0 || box.height <= 0) return;
    final w = math.max(bounds.east - bounds.west, 1e-6);
    final h = math.max(bounds.north - bounds.south, 1e-6);
    final scale = math.min(box.width / w, box.height / h);
    Offset project(LatLng p) => Offset(
      box.center.dx + (p.lon - bounds.center.lon) * scale,
      box.center.dy - (p.lat - bounds.center.lat) * scale,
    );
    for (final selected in [false, true]) {
      for (final l in props.lines.where((l) => l.selected == selected)) {
        if (l.points.length < 2) continue;
        final path = Path()..moveTo(project(l.points.first).dx, project(l.points.first).dy);
        for (final p in l.points.skip(1)) {
          final o = project(p);
          path.lineTo(o.dx, o.dy);
        }
        canvas
          ..drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = selected ? RouteLook.casingWidth : RouteLook.alternativeWidth + 3
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = _hex(
                selected
                    ? RouteLook.casing(dark: props.dark)
                    : RouteLook.alternativeCasing(dark: props.dark),
              ),
          )
          ..drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = selected ? RouteLook.lineWidth : RouteLook.alternativeWidth
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = _hex(
                selected
                    ? RouteLook.line(dark: props.dark)
                    : RouteLook.alternative(dark: props.dark),
              ),
          );
      }
    }
    for (final m in props.marks) {
      final o = project(m.position);
      canvas
        ..drawCircle(
          o,
          RouteLook.markRadius(m.kind) + 2.5,
          Paint()..color = _hex(RouteLook.markStroke),
        )
        ..drawCircle(
          o,
          RouteLook.markRadius(m.kind),
          Paint()..color = _hex(RouteLook.markFill(m.kind)),
        );
    }
    final v = props.vehicle;
    if (v != null) {
      final o = project(v.position);
      canvas
        ..save()
        ..translate(o.dx, o.dy)
        ..rotate((v.course ?? 0) * math.pi / 180)
        ..drawPath(
          Path()
            ..moveTo(0, -13)
            ..lineTo(11, 11)
            ..lineTo(0, 5)
            ..lineTo(-11, 11)
            ..close(),
          Paint()..color = _hex(RouteLook.vehicleFill),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_SchematicPainter old) => old.props != props;
}

/// The navigation's fakes, for `pumpLunaway(overrides: ...)` or a
/// `ProviderContainer`.
List<Override> navigationOverrides({
  required FakeRouteService routes,
  FakeLocationFeed? feed,
  GuidanceEngine? engine,
  RecordingVoice? voice,
  FakeScreenWake? wake,
  RoadEventsSource? events,
  MemoryRouteSettings? settings,
  Vehicle? vehicle = motorhome,
  Duration poll = const Duration(hours: 1),
  CountedNotificationAccess? notifications,
  DateTime Function()? clock,
  List<PlaceSummary> placesNearRoute = const [],
  FuelStationsSource? fuel,
  DangerZoneSource? zones,
  // The service in place of [routes], when a test wraps it (in the cache).
  RouteService? service,
}) => [
  if (clock != null) clockProvider.overrideWithValue(clock),
  placesNearRouteProvider.overrideWith((ref, line) async => placesNearRoute),
  fuelStationsProvider.overrideWithValue(fuel ?? FakeFuelStations(const [])),
  dangerZonesProvider.overrideWithValue(zones ?? const NoDangerZones()),
  routeServiceProvider.overrideWithValue(service ?? routes),
  locationFeedProvider.overrideWithValue(
    feed ?? FakeLocationFeed(position: const LatLng(45.84719, 1.28476)),
  ),
  guidanceEngineProvider.overrideWith((ref) async => engine),
  voiceOutputProvider.overrideWithValue(voice ?? RecordingVoice()),
  screenWakeProvider.overrideWithValue(wake ?? FakeScreenWake()),
  roadEventsSourceProvider.overrideWithValue(events ?? ScriptedRoadEvents(const [])),
  roadEventsPollProvider.overrideWithValue(poll),
  routeMapBuilderProvider.overrideWithValue(schematicRouteMap),
  routeSettingsStoreProvider.overrideWithValue(settings ?? MemoryRouteSettings()),
  vehicleProvider.overrideWith((ref) => Stream.value(vehicle)),
  appForegroundProvider.overrideWithValue(const InFront()),
  notificationAccessProvider.overrideWithValue(notifications ?? CountedNotificationAccess()),
];

/// Stations given in advance; the queries recorded.
final class FakeFuelStations implements FuelStationsSource {
  new(this.offers);

  final List<FuelOffer> offers;
  final List<({double fromM, FuelType fuel})> queries = [];

  @override
  Future<List<FuelOffer>> along({
    required List<LatLng> route,
    required double fromM,
    required FuelType fuel,
    double maxDetourM = defaultMaxDetourM,
  }) async {
    queries.add((fromM: fromM, fuel: fuel));
    return offers;
  }
}

/// One danger zone, from [startM] for [lengthM] metres.
final class OneDangerZone implements DangerZoneSource {
  const new({required this.startM, this.lengthM = 1000});

  final double startM;
  final double lengthM;

  @override
  List<DangerZone> ahead({
    required List<LatLng> line,
    required double fromM,
    double reachM = 2000,
  }) => [
    if (startM + lengthM >= fromM && startM - fromM <= reachM)
      DangerZone(id: 'zone', startM: startM, lengthM: lengthM),
  ];
}

/// The notification permission, asked and counted.
final class CountedNotificationAccess implements NotificationAccess {
  int asked = 0;

  @override
  Future<void> ask() async => asked++;
}

/// The app always in front.
final class InFront implements AppForeground {
  const new();

  @override
  Future<void> resumed() async {}
}
