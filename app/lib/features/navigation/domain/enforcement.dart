import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:meta/meta.dart';

/// What a country allows an app to carry about speed cameras
/// (docs/speed-cameras.md, "The rules by country").
enum EnforcementMode {
  /// Nothing at all.
  off('OFF', 3),

  /// The law forbids a warning to the driver while driving (Germany,
  /// §23 Abs. 1c StVO). The app shows nothing, at rest either: a stop at a
  /// light or in a jam with the engine running counts as driving there
  /// (OLG Karlsruhe, 2023), and the app cannot tell such a stop from a
  /// parked vehicle.
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

  /// Whether the app shows anything of a camera where this rule holds, on
  /// a map read at rest as while driving: zones where only they may be
  /// shown, points where the rule is [exact].
  bool get shows => this == zones || this == exact;
}

/// The mode a user may ask for in a country whose default is stricter,
/// where the rules do not say (an API older than `optInMode`, or the table
/// built into the guidance library): the server's own table, which has one
/// line, France's positions for a user who asked for them
/// (docs/speed-cameras.md, "In the app").
const Map<String, EnforcementMode> optInFallback = {'FR': EnforcementMode.exact};

/// The table of the rules by country, as the API last sent it or as the app
/// was built with it. A country it does not name is off.
@immutable
final class EnforcementRules {
  const new({required this.version, required this.countries, this.reviewedOn, this.optIn});

  static const none = EnforcementRules(version: 0, countries: {});

  final int version;
  final String? reviewedOn;

  /// ISO 3166-1 alpha-2 to its mode.
  final Map<String, EnforcementMode> countries;

  /// The mode each country takes for a user who asked for it
  /// (`EnforcementCountryRule.optInMode`); a country absent has no choice.
  /// Null when the table does not say: [optInFallback] stands for it.
  final Map<String, EnforcementMode>? optIn;

  EnforcementMode modeOf(String? country) => country == null
      ? EnforcementMode.off
      : countries[country.toUpperCase()] ?? EnforcementMode.off;

  /// What [country] becomes for a user who asks for it; null where no
  /// choice exists.
  EnforcementMode? optInOf(String country) {
    final key = country.toUpperCase();
    return (optIn ?? optInFallback)[key];
  }

  /// The rules once the user's choices apply: each country of [chosen]
  /// whose table line is zones and whose choice ([optInOf]) is points
  /// takes the points. These rules, never the table alone, decide what is
  /// kept, shown and alerted. The same object when nothing changes, so a
  /// caller may compare by identity.
  EnforcementRules withChoices(Set<String> chosen) {
    Map<String, EnforcementMode>? changed;
    for (final c in chosen) {
      final key = c.toUpperCase();
      final mode = optInOf(key);
      // A choice only ever turns zones into points, as on the server: a
      // country the table turned off, or one the table does not name,
      // stays as it is whatever was chosen.
      if (mode != EnforcementMode.exact || countries[key] != EnforcementMode.zones) continue;
      (changed ??= {...countries})[key] = EnforcementMode.exact;
    }
    return changed == null
        ? this
        : EnforcementRules(
            version: version,
            countries: changed,
            reviewedOn: reviewedOn,
            optIn: optIn,
          );
  }

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

  /// The country among [near] whose rule [strictestOf] applies: [at], the
  /// country the vehicle is in, when its rule is that one; null when no
  /// country is known.
  String? governingOf(Iterable<String> near, {String? at}) {
    final mode = strictestOf(near);
    if (at != null && near.contains(at) && modeOf(at) == mode) return at;
    return near.where((c) => modeOf(c) == mode).firstOrNull;
  }
}

/// A zone (a stretch of road) or a camera (a point).
enum EnforcementKind { zone, camera }

/// What a camera controls (`EnforcementCategory`).
enum CameraCategory {
  /// Speed, at a point.
  fixed('FIXED'),

  /// A red light.
  redLight('RED_LIGHT'),

  /// An average speed section.
  section('SECTION_CONTROL'),

  /// A level crossing.
  levelCrossing('LEVEL_CROSSING');

  new(this.wire);

  final String wire;

  /// Null for a category this app does not know: it is then named as a
  /// camera, without a kind.
  static CameraCategory? fromWire(String wire) =>
      values.where((c) => c.wire == wire.toUpperCase()).firstOrNull;
}

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

  /// What a camera controls; null for a zone, which never says (a zone
  /// shows no kind of camera), and for a category this app does not know.
  CameraCategory? get cameraCategory =>
      kind == EnforcementKind.camera ? CameraCategory.fromWire(category) : null;

  /// Whether it controls speed: a red light or a level crossing camera
  /// does not, whatever limit a list gives it.
  bool get measuresSpeed {
    final category = cameraCategory;
    return category != CameraCategory.redLight && category != CameraCategory.levelCrossing;
  }

  /// The limit a camera controls; none for a zone, or for a camera that
  /// does not measure speed: its limit is never shown, alerted nor said.
  int? get controlledLimitKmh => kind == EnforcementKind.camera && measuresSpeed ? limitKmh : null;

  /// An average speed section whose road is known: alerted along it, from
  /// its start to its end, rather than at a point.
  bool get isSection => cameraCategory == CameraCategory.section && line.length >= 2;

  /// Where a mark of it stands: a camera's point, else the start of its
  /// road.
  LatLng? get markAt => position ?? line.firstOrNull;

  /// Whether its own country's rule lets the device keep it at all: a zone
  /// where zones or points are allowed, a camera's point only where points
  /// are. A second guard behind the server, which sends nothing else. It
  /// reads only the item's own country: a neighbour's camera served as a
  /// point because of a choice is the store's to drop
  /// (`EnforcementState.servedUnder`).
  bool keptUnder(EnforcementRules rules) {
    final own = rules.modeOf(country);
    return switch (kind) {
      EnforcementKind.zone => own.shows,
      EnforcementKind.camera => own == EnforcementMode.exact,
    };
  }

  /// Whether the guidance may show it while the vehicle is where [here]
  /// rules: a zone where zones or points are allowed, a camera where points
  /// are; and its own country's rule allows it too.
  bool shownUnder(EnforcementMode here, EnforcementRules rules) {
    final own = rules.modeOf(country);
    return switch (kind) {
      EnforcementKind.zone => here.shows && own.shows,
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
  const new({required this.item, required this.startM, required this.endM, this.offsetM = 0});

  final EnforcementItem item;
  final double startM;
  final double endM;

  /// How far a camera's point stands from the route's line, metres; 0 for
  /// a zone, which runs along it.
  final double offsetM;
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
      final near = [for (final p in points) ?index.nearest(p, maxM: zoneToleranceM)];
      final hits = [for (final n in near) n.alongM];
      if (hits.isEmpty || hits.length < math.min(4, (points.length + 1) ~/ 2)) continue;
      // A section controls one way: its road, drawn from its start to its
      // end, runs the route's way, and its bearing when given matches the
      // route's. The other carriageway of a motorway lies within the
      // tolerance. A zone counts either way.
      if (item.kind == EnforcementKind.camera) {
        if (hits.last <= hits.first) continue;
        final bearing = item.bearingDeg;
        if (bearing != null && _angle(bearing, near.first.headingDeg) > 60) continue;
      }
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
    found.add(ItemOnRoute(item: item, startM: n.alongM, endM: n.alongM, offsetM: n.offsetM));
  }
  // Ties keep the order of [items]: Dart's sort is not stable.
  final order = {for (final (i, f) in found.indexed) f: i};
  return found..sort((a, b) {
    final by = a.startM.compareTo(b.startM);
    return by != 0 ? by : order[a]!.compareTo(order[b]!);
  });
}

/// What a map of the route may draw of the items of [onRoute], [here]
/// being the rule where the device is (the strictest of the countries
/// around it), at rest as while driving: the stretches the danger zones
/// cover, merged, and only where the zone's own country allows zones.
/// Never a camera, whatever the rules: a zone is a stretch of road and
/// nothing that places a camera (docs/speed-cameras.md).
List<RouteSpan> zoneSpans(
  Iterable<ItemOnRoute> onRoute, {
  required EnforcementMode here,
  required EnforcementRules rules,
}) {
  if (!here.shows) return const [];
  return mergeSpans([
    for (final r in onRoute)
      if (r.item.kind == EnforcementKind.zone &&
          rules.modeOf(r.item.country).shows &&
          r.endM > r.startM)
        RouteSpan(r.startM, r.endM),
  ]);
}

/// Cameras of one kind closer than this along the route are one camera for
/// the driver: one per lane on a gantry (the A2 between Amsterdam and
/// Utrecht maps six), or the same one mapped twice. The radius the server
/// merges a camera of its sources within.
const sameCameraM = 50.0;

/// A camera this far from the route's line or more may stand on a road
/// beside it, metres: a slip road along a motorway runs 10 to 30 m from
/// it, a camera mapped on the route's own road a few metres.
const besideFromM = 8.0;

/// A camera's own limit this far under the route's, km/h or more, belongs
/// to another road ([besideFromM]).
const besideLimitGapKmh = 40;

/// [onRoute] without the cameras that control a road beside the route
/// rather than the route: off its line by [besideFromM] or more, and
/// limited [besideLimitGapKmh] or more under the route there
/// ([routeLimitAt]: the sign's or the vehicle's limit, null where only an
/// estimate is known). Two cameras of a slip road beside the AP-7, limited
/// to 30 and 12 to 22 m from a route at 120, were told to a driver on the
/// motorway (tour of 2026-10-09).
List<ItemOnRoute> withoutBeside(
  List<ItemOnRoute> onRoute,
  int? Function(double alongM) routeLimitAt,
) => [
  for (final r in onRoute)
    if (!_beside(r, routeLimitAt)) r,
];

bool _beside(ItemOnRoute r, int? Function(double alongM) routeLimitAt) {
  final own = r.item.controlledLimitKmh;
  if (own == null || r.offsetM < besideFromM) return false;
  final route = routeLimitAt(r.startM);
  return route != null && own <= route - besideLimitGapKmh;
}

/// The cameras a map of the route may draw of [onRoute], [here] being the
/// rule where the device is, at rest as while driving: only under a rule
/// that shows points, and each only where its own country's rule shows
/// them too. So never in a country of zones (France, unless the user
/// asked for its positions: [EnforcementRules.withChoices]).
List<ItemOnRoute> camerasOnRoute(
  Iterable<ItemOnRoute> onRoute, {
  required EnforcementMode here,
  required EnforcementRules rules,
}) {
  if (here != EnforcementMode.exact) return const [];
  final shown = <ItemOnRoute>[];
  // The gantry each kind of point camera stands in: a camera closer than
  // [sameCameraM] to the last one of its kind along the route belongs to
  // it, as the guidance's alerts count it (a chain at 0, 40 and 80 m is one
  // gantry), and a mark of its own would count it again. The lowest limit
  // known stands for the gantry. A section with its road is never one of
  // them: two sections end to end are two controls.
  final gantries = <CameraCategory?, ({int index, double lastM})>{};
  for (final r in onRoute) {
    if (r.item.kind != EnforcementKind.camera ||
        rules.modeOf(r.item.country) != EnforcementMode.exact) {
      continue;
    }
    if (r.endM > r.startM) {
      shown.add(r);
      continue;
    }
    final category = r.item.cameraCategory;
    final gantry = gantries[category];
    if (gantry != null && r.startM - gantry.lastM < sameCameraM) {
      final kept = shown[gantry.index].item.controlledLimitKmh;
      final own = r.item.controlledLimitKmh;
      if (own != null && (kept == null || own < kept)) shown[gantry.index] = r;
      gantries[category] = (index: gantry.index, lastM: r.startM);
      continue;
    }
    gantries[category] = (index: shown.length, lastM: r.startM);
    shown.add(r);
  }
  return shown;
}

/// A camera of the route as its maps draw it: where it stands along the
/// route, and the lists it comes from, cited on its card.
@immutable
final class CameraOnRoute {
  const new({required this.onRoute, this.sources = const []});

  final ItemOnRoute onRoute;
  final List<EnforcementSource> sources;

  EnforcementItem get item => onRoute.item;

  @override
  bool operator ==(Object other) =>
      other is CameraOnRoute &&
      other.item.id == item.id &&
      other.item.limitKmh == item.limitKmh &&
      other.item.category == item.category &&
      other.onRoute.startM == onRoute.startM &&
      other.onRoute.endM == onRoute.endM &&
      const ListEquality<String>().equals(
        [for (final s in other.sources) s.id],
        [for (final s in sources) s.id],
      );

  @override
  int get hashCode => Object.hash(item.id, onRoute.startM, onRoute.endM);
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
  /// along the route, the route's heading there, and how far [p] is.
  ({double alongM, double headingDeg, double offsetM})? nearest(LatLng p, {required double maxM}) {
    final cx = _cell(p.lon);
    final cy = _cell(p.lat);
    const metresPerDegree = 111195.0;
    final cosLat = math.cos(p.lat * math.pi / 180);
    double? best;
    ({double alongM, double headingDeg, double offsetM})? found;
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
            found = (alongM: _starts[i] + t * math.sqrt(len2), headingDeg: heading, offsetM: d);
          }
        }
      }
    }
    return found;
  }
}
