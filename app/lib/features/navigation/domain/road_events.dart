import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:meta/meta.dart';

/// What a road event does to traffic, strongest first
/// (`plan/research/20-travaux-temps-reel.md`, 5.1).
enum RoadEventClass {
  /// The road is closed to every vehicle.
  closure,

  /// A temporary height, width, length or weight limit: blocking for a
  /// vehicle above it.
  vehicleLimit,

  /// A lane closed, alternating traffic, narrow lanes: passable, worth a
  /// word.
  laneRestriction,

  /// An official detour; the app never follows its text, which may be
  /// meant for cars.
  detour,

  /// Works with nothing announced.
  works,
}

/// A road event, as the delta of the API carries it.
@immutable
final class RoadEvent {
  const new({
    required this.id,
    required this.eventClass,
    required this.shape,
    required this.source,
    this.maxHeightM,
    this.maxWidthM,
    this.maxLengthM,
    this.maxWeightT,
    this.validFrom,
    this.validTo,
    this.roadName,
    this.text,
  });

  /// Stable across deltas.
  final String id;
  final RoadEventClass eventClass;

  /// One point, or the line of road it covers (as matched to the graph).
  final List<LatLng> shape;

  /// The source, for the attribution (`DIR Centre-Est`, `DiaLog`).
  final String source;
  final double? maxHeightM;
  final double? maxWidthM;
  final double? maxLengthM;
  final double? maxWeightT;
  final DateTime? validFrom;
  final DateTime? validTo;
  final String? roadName;

  /// A short public description, in the source's language.
  final String? text;

  /// Whether it is in force at [at]: an event with no start has begun, one
  /// with no end has not ended.
  bool activeAt(DateTime at) =>
      (validFrom == null || !at.isBefore(validFrom!)) && (validTo == null || at.isBefore(validTo!));

  /// Whether it stops [vehicle]: a closure stops everyone; a limit stops a
  /// vehicle over it (a limit equal to the vehicle's figure lets it pass,
  /// as the server's rule does). The other classes never block.
  bool blocks(VehicleProfile vehicle) => switch (eventClass) {
    RoadEventClass.closure => true,
    RoadEventClass.vehicleLimit => _over(vehicle),
    _ => false,
  };

  bool _over(VehicleProfile v) {
    bool exceeds(double? limit, double value) => limit != null && value > limit + 1e-9;
    final length = v.lengthM + (v.trailer?.lengthM ?? 0);
    final weight = v.weightT + (v.trailer?.weightT ?? 0);
    return exceeds(maxHeightM, v.heightM) ||
        exceeds(maxWidthM, v.widthM) ||
        exceeds(maxLengthM, length) ||
        exceeds(maxWeightT, weight);
  }
}

/// The events changed since a cursor.
@immutable
final class RoadEventsDelta {
  const new({
    required this.cursor,
    required this.asOf,
    this.upserts = const [],
    this.removals = const [],
  });

  /// What to send next time.
  final String cursor;

  /// When the server last read its sources.
  final DateTime asOf;
  final List<RoadEvent> upserts;
  final List<String> removals;
}

/// Road events for the area the router covers. Asked without any position:
/// the phone receives every event and checks its own route
/// (`plan/research/20-travaux-temps-reel.md`, 5.6).
abstract interface class RoadEventsSource {
  /// The events changed since [cursor]; every event when null.
  Future<RoadEventsDelta> delta({String? cursor});
}

/// What the check found on the route ahead.
@immutable
final class RoadEventFinding {
  const new({required this.event, required this.hit, required this.aheadM});

  final RoadEvent event;
  final EventHit hit;

  /// Metres from the vehicle to where the route meets it.
  final double aheadM;
}

/// The road events known during one guidance, kept between polls, and the
/// check of the route ahead against them.
final class RoadEventsTracker {
  final Map<String, RoadEvent> _events = {};
  final Set<String> _handled = {};
  String? _cursor;
  DateTime? _asOf;

  /// The cursor to ask the next delta with.
  String? get cursor => _cursor;

  /// When the server last read its sources, after the latest delta.
  DateTime? get asOf => _asOf;

  int get count => _events.length;

  void apply(RoadEventsDelta delta) {
    for (final id in delta.removals) {
      _events.remove(id);
      _handled.remove(id);
    }
    for (final e in delta.upserts) {
      _events[e.id] = e;
    }
    _cursor = delta.cursor;
    _asOf = delta.asOf;
  }

  /// A new route: an event handled on the old one may lie on the new one
  /// only if the server could not avoid it, and is then announced again.
  void resetHandled() => _handled.clear();

  /// The events ahead on [track], from [alongM] metres: those that stop
  /// [vehicle] and that the guidance has not acted on yet (`blocking`), and
  /// those worth a word (`alerts`). Only events in force at [at].
  ({List<RoadEventFinding> blocking, List<RoadEventFinding> alerts}) check({
    required GuidanceTrack track,
    required double alongM,
    required VehicleProfile vehicle,
    required DateTime at,
  }) {
    final active = [
      for (final e in _events.values)
        if (e.activeAt(at) && e.shape.isNotEmpty) e,
    ];
    if (active.isEmpty) return (blocking: const [], alerts: const []);
    final hits = track.eventsAhead(alongM, [
      for (final e in active) EventShape(id: e.id, points: e.shape),
    ]);
    final blocking = <RoadEventFinding>[];
    final alerts = <RoadEventFinding>[];
    final seen = <String>{};
    for (final hit in hits) {
      // The first place the route meets an event is the one that matters.
      if (!seen.add(hit.id)) continue;
      final event = _events[hit.id];
      if (event == null) continue;
      final finding = RoadEventFinding(
        event: event,
        hit: hit,
        aheadM: (hit.startM - alongM).clamp(0, double.infinity),
      );
      if (event.blocks(vehicle)) {
        if (!_handled.contains(event.id)) blocking.add(finding);
      } else {
        alerts.add(finding);
      }
    }
    return (blocking: blocking, alerts: alerts);
  }

  /// Marks [ids] as acted on: a recalculation was asked for them.
  void markHandled(Iterable<String> ids) => _handled.addAll(ids);
}

/// The source until the API serves road events: nothing to report, ever.
final class NoRoadEventsSource implements RoadEventsSource {
  const new();

  @override
  Future<RoadEventsDelta> delta({String? cursor}) =>
      Future.error(const RoadEventsUnavailable('the API serves no road events yet'));
}

/// The source could not answer; the last known events stay valid.
final class RoadEventsUnavailable implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'RoadEventsUnavailable: $message';
}
