import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:meta/meta.dart';

/// What a country allows an app to carry about speed cameras
/// (docs/speed-cameras.md, "The rules by country").
enum EnforcementMode {
  /// Nothing at all.
  off('OFF', 3),

  /// Camera points for a vehicle that does not move: nothing during
  /// guidance.
  offWhileDriving('OFF_WHILE_DRIVING', 2),

  /// Danger zones only: a stretch of road, never a camera's point.
  zones('ZONES', 1),

  /// Camera points with their kind and limit.
  exact('EXACT', 0);

  new(this.wire, this.strictness);

  /// The API's name.
  final String wire;

  /// The stricter of two rules applies where they meet.
  final int strictness;

  /// Off for a value this app does not know: the strictest reading.
  static EnforcementMode fromWire(Object? wire) {
    final key = '$wire'.toUpperCase();
    return values.where((m) => m.wire == key).firstOrNull ?? off;
  }

  /// Whether the guidance shows something of a camera here.
  bool get showsWhileDriving => this == zones || this == exact;
}

/// The table of the rules by country, as the API last sent it or as the app
/// was built with it. A country it does not name is off.
@immutable
final class EnforcementRules {
  const new({required this.version, required this.countries, this.reviewedOn});

  static const none = EnforcementRules(version: 0, countries: {});

  final int version;
  final String? reviewedOn;

  /// ISO 3166-1 alpha-2 to its mode.
  final Map<String, EnforcementMode> countries;

  EnforcementMode modeOf(String? country) => country == null
      ? EnforcementMode.off
      : countries[country.toUpperCase()] ?? EnforcementMode.off;

  /// The strictest rule of [near] (the country the vehicle is in and those
  /// within a kilometre of it); off without any country (at sea, or no
  /// boundary known).
  EnforcementMode strictestOf(Iterable<String> near) {
    var mode = near.isEmpty ? EnforcementMode.off : EnforcementMode.exact;
    for (final c in near) {
      final m = modeOf(c);
      if (m.strictness > mode.strictness) mode = m;
    }
    return mode;
  }
}

/// A zone (a stretch of road) or a camera (a point).
enum EnforcementKind { zone, camera }

/// One item of the API's `enforcement` delta.
@immutable
final class EnforcementItem {
  const new({
    required this.id,
    required this.kind,
    required this.category,
    required this.country,
    this.line = const [],
    this.position,
    this.bearingDeg,
    this.limitKmh,
    this.sourceIds = const [],
  });

  final String id;
  final EnforcementKind kind;

  /// `FIXED`, `RED_LIGHT`, `SECTION_CONTROL`, `LEVEL_CROSSING`.
  final String category;

  /// The country whose rule it follows.
  final String country;

  /// A zone's road, or an average speed section's; empty for a point.
  final List<LatLng> line;

  /// A camera's point.
  final LatLng? position;

  /// The direction of travel a camera controls, degrees from north.
  final double? bearingDeg;
  final int? limitKmh;
  final List<String> sourceIds;

  /// Whether its own country's rule lets the device keep it at all: a zone
  /// where zones or points are allowed, a camera's point only where points
  /// are. A second guard behind the server, which sends nothing else.
  bool keptUnder(EnforcementRules rules) {
    final own = rules.modeOf(country);
    return switch (kind) {
      EnforcementKind.zone => own.showsWhileDriving,
      EnforcementKind.camera => own == EnforcementMode.exact,
    };
  }

  /// Whether the guidance may show it while the vehicle is where [here]
  /// rules: a zone where zones or points are allowed, a camera where points
  /// are; and its own country's rule allows it too.
  bool shownUnder(EnforcementMode here, EnforcementRules rules) {
    final own = rules.modeOf(country);
    return switch (kind) {
      EnforcementKind.zone => here.showsWhileDriving && own.showsWhileDriving,
      EnforcementKind.camera => here == EnforcementMode.exact && own == EnforcementMode.exact,
    };
  }
}

/// A list the items come from, credited with the items shown.
@immutable
final class EnforcementSource {
  const new({
    required this.id,
    required this.name,
    required this.attribution,
    required this.fetchedAt,
    this.listUpdatedAt,
  });

  final String id;
  final String name;
  final String attribution;
  final DateTime fetchedAt;

  /// The date the list gives of its own last update; [fetchedAt] stands for
  /// it when the list gives none.
  final DateTime? listUpdatedAt;
}

/// The rule the vehicle drives under, from the countries around each fix:
/// a stricter rule applies at once, a looser one only once it has held for
/// [settle] (two fixes that far apart), so a road along a border does not
/// switch back and forth (docs/speed-cameras.md: "the stricter rule at
/// once at a border").
final class RuleTracker {
  new({this.settle = const Duration(seconds: 30)});

  final Duration settle;
  EnforcementMode? _mode;
  EnforcementMode? _looser;
  DateTime? _looserSince;

  EnforcementMode get mode => _mode ?? EnforcementMode.off;

  /// The rule after a fix where [observed] applies, at [at].
  EnforcementMode update(EnforcementMode observed, DateTime at) {
    final current = _mode;
    if (current == null || observed.strictness >= current.strictness) {
      _mode = observed;
      _looser = null;
      _looserSince = null;
      return observed;
    }
    if (_looser != observed) {
      _looser = observed;
      _looserSince = at;
    } else if (!at.isBefore(_looserSince!.add(settle))) {
      _mode = observed;
      _looser = null;
      _looserSince = null;
    }
    return mode;
  }

  void reset() {
    _mode = null;
    _looser = null;
    _looserSince = null;
  }
}

/// Where an item lies on a route: from [startM] to [endM] metres from its
/// start (the same for a camera's point).
@immutable
final class ItemOnRoute {
  const new({required this.item, required this.startM, required this.endM});

  final EnforcementItem item;
  final double startM;
  final double endM;
}

/// A vehicle follows a zone's line within this, metres: a chord of 50 m
/// strays at most 18 m from its road at a right-angled corner.
const zoneToleranceM = 25.0;

/// A camera stands on the route within this, metres.
const cameraToleranceM = 30.0;

/// The items of [items] the route [line] drives through, in driving order.
/// A zone counts where four of its points (150 m of its road), or half of
/// a shorter one, lie within [zoneToleranceM] of the route, in either
/// direction: a road crossing the route at a junction touches it at one or
/// two points only. A camera counts where its
/// point lies within [cameraToleranceM] and the route heads the way it
/// controls (60 degrees either side) when it says which.
List<ItemOnRoute> itemsOnRoute(List<LatLng> line, Iterable<EnforcementItem> items) {
  if (line.length < 2) return const [];
  final index = _SegmentIndex(line);
  final found = <ItemOnRoute>[];
  for (final item in items) {
    final points = item.line;
    if (points.isNotEmpty) {
      final hits = [
        for (final p in points)
          if (index.nearest(p, maxM: zoneToleranceM) case final n?) n.alongM,
      ];
      if (hits.isEmpty || hits.length < math.min(4, (points.length + 1) ~/ 2)) continue;
      found.add(
        ItemOnRoute(item: item, startM: hits.reduce(math.min), endM: hits.reduce(math.max)),
      );
      continue;
    }
    final at = item.position;
    if (at == null) continue;
    final n = index.nearest(at, maxM: cameraToleranceM);
    if (n == null) continue;
    final bearing = item.bearingDeg;
    if (bearing != null && _angle(bearing, n.headingDeg) > 60) continue;
    found.add(ItemOnRoute(item: item, startM: n.alongM, endM: n.alongM));
  }
  // Ties keep the order of [items]: Dart's sort is not stable.
  final order = {for (final (i, f) in found.indexed) f: i};
  return found..sort((a, b) {
    final by = a.startM.compareTo(b.startM);
    return by != 0 ? by : order[a]!.compareTo(order[b]!);
  });
}

/// The items of a trip's countries, bucketed once by the coarse cells
/// their points fall in, so a new route tests in full only the few hundred
/// items near it. France alone holds about 2,600 zones and 110,000 points:
/// matching them all against a long route took 35 ms on a desktop at each
/// new route, against 7 to 8 ms through the index.
final class EnforcementIndex {
  new(List<EnforcementItem> items) : _items = items, _buckets = {} {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final points = item.line.isNotEmpty ? item.line : [?item.position];
      final cells = <int>{for (final p in points) _key(_coarse(p.lon), _coarse(p.lat))};
      for (final c in cells) {
        (_buckets[c] ??= []).add(i);
      }
    }
  }

  final List<EnforcementItem> _items;
  final Map<int, List<int>> _buckets;

  /// About 2 km of latitude: smaller cells leave fewer items to test in
  /// full, and past this size the gain stops (measured on the French list).
  static const _size = 0.02;

  /// Further than any tolerance of [itemsOnRoute] (30 m), so an item just
  /// across a cell's edge from the route is still a candidate: 0.002 degree
  /// of longitude is still 30 m at 82 degrees north.
  static const _margin = 0.002;

  static int _coarse(double degrees) => (degrees / _size).floor();

  /// [itemsOnRoute] over the items near [line] only: the same result as
  /// over all of them, in the same order.
  List<ItemOnRoute> onRoute(List<LatLng> line) {
    if (line.length < 2 || _buckets.isEmpty) return const [];
    final near = <int>{};
    final crossed = <int>{};
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1];
      final b = line[i];
      final south = _coarse(math.min(a.lat, b.lat) - _margin);
      final north = _coarse(math.max(a.lat, b.lat) + _margin);
      final west = _coarse(math.min(a.lon, b.lon) - _margin);
      final east = _coarse(math.max(a.lon, b.lon) + _margin);
      for (var y = south; y <= north; y++) {
        for (var x = west; x <= east; x++) {
          final key = _key(x, y);
          if (crossed.add(key)) near.addAll(_buckets[key] ?? const <int>[]);
        }
      }
    }
    // In the order of the list, so items at the same distance keep the
    // order a full pass gives them.
    final candidates = near.toList()..sort();
    return itemsOnRoute(line, [for (final i in candidates) _items[i]]);
  }
}

/// One integer for a cell of a grid, cheaper to hash than a record: cells
/// of 0.01 degree run to 36,000 across, well inside 2^16 either way.
int _key(int x, int y) => (x + 0x8000) << 16 | (y + 0x8000);

double _angle(double a, double b) {
  final d = ((a - b) % 360 + 360) % 360;
  return d > 180 ? 360 - d : d;
}

/// The route's segments in a grid of about a kilometre, so a point finds
/// the few segments near it without walking the whole route.
final class _SegmentIndex {
  new(this.line) {
    var along = 0.0;
    for (var i = 1; i < line.length; i++) {
      _starts.add(along);
      final a = line[i - 1];
      final b = line[i];
      along += a.distanceTo(b);
      final south = math.min(a.lat, b.lat);
      final north = math.max(a.lat, b.lat);
      final west = math.min(a.lon, b.lon);
      final east = math.max(a.lon, b.lon);
      for (var y = _cell(south); y <= _cell(north); y++) {
        for (var x = _cell(west); x <= _cell(east); x++) {
          (_cells[_key(x, y)] ??= []).add(i - 1);
        }
      }
    }
  }

  final List<LatLng> line;
  final List<double> _starts = [];
  final Map<int, List<int>> _cells = {};

  static const _size = 0.01;

  static int _cell(double degrees) => (degrees / _size).floor();

  /// The nearest point of the route to [p] within [maxM]: where it lies
  /// along the route and the route's heading there.
  ({double alongM, double headingDeg})? nearest(LatLng p, {required double maxM}) {
    final cx = _cell(p.lon);
    final cy = _cell(p.lat);
    const metresPerDegree = 111195.0;
    final cosLat = math.cos(p.lat * math.pi / 180);
    double? best;
    ({double alongM, double headingDeg})? found;
    final seen = <int>{};
    for (var y = cy - 1; y <= cy + 1; y++) {
      for (var x = cx - 1; x <= cx + 1; x++) {
        for (final i in _cells[_key(x, y)] ?? const <int>[]) {
          if (!seen.add(i)) continue;
          final a = line[i];
          final b = line[i + 1];
          final ax = (a.lon - p.lon) * metresPerDegree * cosLat;
          final ay = (a.lat - p.lat) * metresPerDegree;
          final dx = (b.lon - a.lon) * metresPerDegree * cosLat;
          final dy = (b.lat - a.lat) * metresPerDegree;
          final len2 = dx * dx + dy * dy;
          final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
          final ex = ax + t * dx;
          final ey = ay + t * dy;
          final d = math.sqrt(ex * ex + ey * ey);
          if (d <= maxM && (best == null || d < best)) {
            best = d;
            final heading = (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
            found = (alongM: _starts[i] + t * math.sqrt(len2), headingDeg: heading);
          }
        }
      }
    }
    return found;
  }
}
