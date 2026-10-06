import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:meta/meta.dart';

/// What a road event does to traffic (`RoadEventClass` of the API).
enum RoadEventClass {
  /// The road is closed to every vehicle.
  closure,

  /// A temporary height, width, length or weight limit: blocking for a
  /// vehicle above it.
  vehicleLimit,

  /// A lane closed, alternating traffic: passable, worth a word.
  laneRestriction,

  /// An official detour; the app never follows its text, which may be
  /// meant for cars.
  detour,

  /// Works with nothing announced.
  works,
}

/// How the server placed an event on the routing graph (`match`).
enum RoadEventPlacement {
  /// On graph lines, in the direction of traffic: [RoadEvent.lines].
  matched,

  /// A slip road closed at an interchange, located on its axis: the server
  /// applies the slip-road rule when it computes a route.
  ramp,

  /// A point the route must pass within 15 m of.
  point,

  /// Not placed: a word at most, never a recalculation.
  other,
}

/// When an event applies, beyond its validity: weekly windows in a time
/// zone, periods lifted, and the margins the server allows
/// (`plan/research/21-backend-travaux.md`, part 5).
@immutable
final class RoadEventSchedule {
  const new({
    this.windows = const [],
    this.exceptions = const [],
    this.marginMinutes = 15,
    this.widenMinutes = 0,
    this.utc = false,
    this.assumed = false,
    this.unplanned = false,
  });

  /// Days (1 Monday to 7 Sunday) and minutes of the day; a window whose
  /// end is not after its start ends the next day.
  final List<({Set<int> days, int startMinute, int endMinute})> windows;
  final List<({DateTime from, DateTime to})> exceptions;
  final int marginMinutes;
  final int widenMinutes;

  /// The windows are in UTC; in the time of Paris otherwise.
  final bool utc;

  /// The windows were supposed from a label ("de nuit"): outside them the
  /// event only warns.
  final bool assumed;

  /// An incident rather than planned works: it grows old faster.
  final bool unplanned;

  /// Whether [at] falls in a window (or there is none) and in no lifted
  /// period.
  bool inForce(DateTime at) {
    final margin = Duration(minutes: marginMinutes);
    for (final e in exceptions) {
      if (at.isAfter(e.from.add(margin)) && at.isBefore(e.to.subtract(margin))) return false;
    }
    if (windows.isEmpty) return true;
    final local = utc ? at.toUtc() : PlaceZone.central.wallClock(at);
    final widen = marginMinutes + widenMinutes;
    for (final w in windows) {
      // The window of the day before may run into this one.
      for (final dayBack in [0, 1]) {
        final day = local.subtract(Duration(days: dayBack));
        if (!w.days.contains(day.weekday)) continue;
        final dayStart = DateTime.utc(day.year, day.month, day.day);
        final start = dayStart.add(Duration(minutes: w.startMinute - widen));
        final endMinute = w.endMinute > w.startMinute ? w.endMinute : w.endMinute + 24 * 60;
        final end = dayStart.add(Duration(minutes: endMinute + widen));
        final t = DateTime.utc(local.year, local.month, local.day, local.hour, local.minute);
        if (!t.isBefore(start) && t.isBefore(end)) return true;
      }
    }
    return false;
  }
}

/// A road event, as the API's delta carries it.
@immutable
final class RoadEvent {
  const new({
    required this.id,
    required this.eventClass,
    required this.placement,
    required this.source,
    this.mayBlock = false,
    this.lines = const [],
    this.position,
    this.maxHeightM,
    this.maxWidthM,
    this.maxLengthM,
    this.maxWeightT,
    this.validFrom,
    this.validTo,
    this.schedule = const RoadEventSchedule(),
    this.roadNumber,
    this.updatedAt,
  });

  /// Stable across deltas.
  final String id;
  final RoadEventClass eventClass;
  final RoadEventPlacement placement;

  /// The source's id (`dir`, `dialog`, `community`), for its freshness and
  /// attribution.
  final String source;

  /// Placed on the graph, official or confirmed, for every vehicle: the
  /// server's own word that the event may stop a route.
  final bool mayBlock;

  /// The graph lines it covers, each in the direction of traffic.
  final List<List<LatLng>> lines;
  final LatLng? position;
  final double? maxHeightM;
  final double? maxWidthM;
  final double? maxLengthM;
  final double? maxWeightT;
  final DateTime? validFrom;
  final DateTime? validTo;
  final RoadEventSchedule schedule;
  final String? roadNumber;

  /// When the source last changed it: an open event this old stops
  /// blocking.
  final DateTime? updatedAt;

  /// Whether it is in force at [at], margins included.
  bool activeAt(DateTime at) {
    final margin = Duration(minutes: schedule.marginMinutes);
    if (validFrom != null && at.isBefore(validFrom!.subtract(margin))) return false;
    if (validTo != null && at.isAfter(validTo!.add(margin))) return false;
    return true;
  }

  /// Whether, in force, it stops [vehicle] at [at]: the server's rule
  /// (`road_events::assess`). An open event not updated for 30 days (12
  /// hours for an incident) has likely ended unseen; outside its supposed
  /// hours it only warns.
  bool blocks(VehicleProfile vehicle, DateTime at) {
    if (!mayBlock || !activeAt(at) || !schedule.inForce(at)) return false;
    if (validTo == null && updatedAt != null) {
      final age = at.difference(updatedAt!);
      if (age > (schedule.unplanned ? const Duration(hours: 12) : const Duration(days: 30))) {
        return false;
      }
    }
    return switch (eventClass) {
      RoadEventClass.closure => true,
      RoadEventClass.vehicleLimit => _over(vehicle),
      _ => false,
    };
  }

  bool _over(VehicleProfile v) {
    bool exceeds(double? limit, double value) => limit != null && value > limit + 1e-9;
    final length = v.lengthM + (v.trailer?.lengthM ?? 0);
    final weight = v.weightT + (v.trailer?.weightT ?? 0);
    return exceeds(maxHeightM, v.heightM) ||
        exceeds(maxWidthM, v.widthM) ||
        exceeds(maxLengthM, length) ||
        exceeds(maxWeightT, weight);
  }

  /// The shapes the route is checked against: the matched lines (one way),
  /// or the point.
  List<EventShape> get shapes => switch (placement) {
    RoadEventPlacement.matched => [
      for (final (i, l) in lines.indexed)
        if (l.length >= 2) EventShape(id: id, points: l, directed: true, part: i),
    ],
    RoadEventPlacement.point when position != null => [
      EventShape(id: id, points: [position!]),
    ],
    _ => const [],
  };
}

/// How fresh a source's events are.
@immutable
final class RoadEventSourceStatus {
  const new({required this.id, required this.fresh, this.lastReadAt, this.staleAfter});

  final String id;
  final bool fresh;
  final DateTime? lastReadAt;
  final Duration? staleAfter;

  /// Fresh for the server, and not grown stale on the phone since.
  bool freshAt(DateTime at) =>
      fresh &&
      (lastReadAt == null || staleAfter == null || !at.isAfter(lastReadAt!.add(staleAfter!)));
}

/// The events changed since a cursor (`RoadEventDelta`).
@immutable
final class RoadEventsDelta {
  const new({
    required this.cursor,
    required this.asOf,
    this.full = false,
    this.hasMore = false,
    this.upserts = const [],
    this.removals = const [],
    this.sources = const [],
    this.pollInterval,
  });

  /// What to send next time.
  final String cursor;

  /// The whole set: it replaces the local one.
  final bool full;

  /// More pages wait: ask again at once with [cursor].
  final bool hasMore;

  /// When the server answered.
  final DateTime asOf;
  final List<RoadEvent> upserts;
  final List<String> removals;
  final List<RoadEventSourceStatus> sources;

  /// The rhythm the server asks for.
  final Duration? pollInterval;
}

/// Road events for the area the router covers. Asked without any position:
/// the phone receives every event that may block and checks its own route
/// (`plan/research/21-backend-travaux.md`, part 5).
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
  final Map<String, RoadEventSourceStatus> _sources = {};
  final Set<String> _handled = {};
  String? _cursor;
  DateTime? _asOf;

  /// The cursor to ask the next delta with.
  String? get cursor => _cursor;

  /// When the server last answered.
  DateTime? get asOf => _asOf;

  int get count => _events.length;

  /// Forgets the cursor: the next delta brings the whole set (the server
  /// refused the cursor).
  void restart() => _cursor = null;

  void apply(RoadEventsDelta delta) {
    if (delta.full) {
      _events.clear();
      _handled.clear();
    }
    for (final id in delta.removals) {
      _events.remove(id);
      _handled.remove(id);
    }
    for (final e in delta.upserts) {
      _events[e.id] = e;
    }
    for (final s in delta.sources) {
      _sources[s.id] = s;
    }
    _cursor = delta.cursor;
    _asOf = delta.asOf;
  }

  /// A new route: an event handled on the old one lies on the new one only
  /// if the server could not avoid it, and is then announced again.
  void resetHandled() => _handled.clear();

  /// The events ahead on [track], from [alongM] metres, at the vehicle's
  /// arrival there ([now] plus [secondsPerMetre] of the remaining route):
  /// those that stop [vehicle] and that the guidance has not acted on yet
  /// (`blocking`), and those in force worth a word (`alerts`).
  ({List<RoadEventFinding> blocking, List<RoadEventFinding> alerts}) check({
    required GuidanceTrack track,
    required double alongM,
    required VehicleProfile vehicle,
    required DateTime now,
    double secondsPerMetre = 0,
  }) {
    final candidates = [
      for (final e in _events.values)
        if (_sources[e.source]?.freshAt(now) ?? true) e,
    ];
    final shapes = [for (final e in candidates) ...e.shapes];
    if (shapes.isEmpty) return (blocking: const [], alerts: const []);
    final hits = track.eventsAhead(alongM, shapes);
    final blocking = <RoadEventFinding>[];
    final alerts = <RoadEventFinding>[];
    final seen = <String>{};
    for (final hit in hits) {
      // The first place the route meets an event is the one that matters.
      if (!seen.add(hit.id)) continue;
      final event = _events[hit.id];
      if (event == null) continue;
      final aheadM = (hit.startM - alongM).clamp(0, double.infinity).toDouble();
      final arrival = now.add(Duration(seconds: (aheadM * secondsPerMetre).round()));
      final finding = RoadEventFinding(event: event, hit: hit, aheadM: aheadM);
      if (event.blocks(vehicle, arrival)) {
        if (!_handled.contains(event.id)) blocking.add(finding);
      } else if (event.activeAt(arrival) &&
          (event.schedule.inForce(arrival) || event.schedule.assumed)) {
        // Outside hours that were only supposed ("de nuit"), the event
        // still deserves a word.
        alerts.add(finding);
      }
    }
    return (blocking: blocking, alerts: alerts);
  }

  /// Marks [ids] as acted on: a recalculation was asked for them.
  void markHandled(Iterable<String> ids) => _handled.addAll(ids);
}

/// The source could not answer; the last known events stay valid.
final class RoadEventsUnavailable implements Exception {
  const new(this.message, {this.retryAfter, this.cursorRefused = false});

  final String message;

  /// The server asked to wait this long.
  final Duration? retryAfter;

  /// The server refused the cursor: start again from the whole set.
  final bool cursorRefused;

  @override
  String toString() => 'RoadEventsUnavailable: $message';
}
