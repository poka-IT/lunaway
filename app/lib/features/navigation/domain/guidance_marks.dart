import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:meta/meta.dart';

/// The rich marks of the route maps: a few places drawn large (their photo,
/// or their kind's pictogram with a short label) among the small pins, so a
/// driver tells at a glance what a place is. Never where they would hide
/// what driving needs: the vehicle, the road just ahead, the maneuver's
/// banner, the buttons. This file holds the rules; the engines measure the
/// screen and draw.
abstract final class RichMarks {
  /// The rich mark's disc, logical pixels, by its distance from the
  /// vehicle on a phone: `near` up to [nearM], `far` from [farM], linear
  /// between. 40 px is the smallest at which a photo still reads as a
  /// scene (a field, a car park, a lake) at arm's length; 52 px the most a
  /// 390 px wide map gives one place without covering a lane of the road
  /// beside it at the zoom of a town (17: 52 px are 22 m). The distances
  /// span what the following camera shows ahead: about 250 m below the
  /// banner in town, 1.2 km on a fast road.
  static const RichSizes phone = RichSizes(near: 52, far: 40);

  /// A tablet's or a computer's map is wider: each mark a little larger.
  static const RichSizes wide = RichSizes(near: 56, far: 44);
  static const double nearM = 250;
  static const double farM = 1200;

  /// How many rich marks at once, by the map's width class: a phone shows
  /// the road and four places at most, a wider map more.
  static const int compactLimit = 4;
  static const int mediumLimit = 6;
  static const int expandedLimit = 8;

  /// The room kept free around the vehicle's arrow, logical pixels: the
  /// arrow is 30 px wide; a driver must see it and the road around it.
  static const double vehicleClear = 56;

  /// The room kept free on each side of the road just ahead: half the
  /// route's casing (9.5 px) and a margin, so no mark lies on the lane.
  static const double pathClear = 12;

  /// Farther ahead, over [lineAheadM] of road, a mark may stand beside the
  /// road and brush its casing, its tail down to a place at the roadside,
  /// but its head never hides the line's middle. Kept a casing's half
  /// (5 px) off, with its tail, the places at the roadside were never drawn
  /// large on a phone in town (Penthièvre, 2026-10-09).
  static const double lineClear = 0;
  static const double lineAheadM = 2000;

  /// The room kept between two rich marks, and from the edges of what
  /// covers the map.
  static const double gap = 6;

  /// The road ahead kept clear ([immediateM]): what the next eight seconds
  /// cover, 120 m at least, 300 m at most. It is the stretch a driver
  /// reads to place the vehicle (111 m at 50 km/h, 200 m at 90 km/h);
  /// farther, a mark beside the road says what is coming and hides no
  /// lane the vehicle is about to take. Kept longer (12 s, 250 m at
  /// least), the places beside the road were never drawn large on a
  /// phone in town: their mark reached the road until they came under
  /// the banner (Quiberon, Penthièvre, 2026-10-09).
  static const double immediateMinM = 120;
  static const Duration immediateTime = Duration(seconds: 8);
  static const double immediateMaxM = 300;

  /// A place passed this far behind the vehicle no longer stands out: it
  /// is behind the driver.
  static const double behindM = 30;

  /// Only the places within this distance of the route are weighed by
  /// their way along it; farther off, by their distance from the vehicle.
  static const double nearRouteM = 1500;

  /// The bonus of a place already drawn rich: it stays rather than swap
  /// with one of nearly the same weight at the next fix.
  static const double keepBonus = 0.6;
}

/// The disc's size of a rich mark by the distance from the vehicle.
@immutable
final class RichSizes {
  const new({required this.near, required this.far});

  final double near;
  final double far;

  /// [fromVehicleM] null (no vehicle: the preview) gives the middle size.
  double at(double? fromVehicleM) {
    final t = fromVehicleM == null
        ? 0.5
        : ((fromVehicleM - RichMarks.nearM) / (RichMarks.farM - RichMarks.nearM)).clamp(0.0, 1.0);
    final size = near + (far - near) * t;
    // In steps of [step]: a mark approaching the vehicle is drawn again
    // three times, not at every pixel.
    return far + step * ((size - far) / step).round();
  }

  /// The sizes a mark is drawn at, from [far] to [near].
  static const double step = 4;

  @override
  bool operator ==(Object other) => other is RichSizes && other.near == near && other.far == far;

  @override
  int get hashCode => Object.hash(near, far);
}

/// How far ahead the road is kept clear at [speedMps].
double immediateM(double? speedMps) =>
    ((speedMps ?? 0) * RichMarks.immediateTime.inMilliseconds / 1000).clamp(
      RichMarks.immediateMinM,
      RichMarks.immediateMaxM,
    );

/// The drawn shape of a rich mark of [size], logical pixels, its tip on the
/// place. A photo is a round head of diameter [size] on a short tail, the
/// kind's badge at its lower right. An illustrated mark is a [capsule]: the
/// kind's pictogram in a disc at its left, the label after it, a short tail
/// under its middle; three quarters of [size] tall, as wide as its label
/// makes it. Of the three placements of the label measured (across the
/// bottom of a round head, beside it, in a capsule), the label across the
/// head hid the lower half of the pictogram, and the label beside it took
/// 42 to 47 % more room than the capsule.
@immutable
final class RichGeometry {
  const new(this.size, {this.labelWidth = 0, this.capsule = false});

  final double size;

  /// The label's width, its padding included; zero for none.
  final double labelWidth;
  final bool capsule;

  /// The head's height: the photo's disc, or the capsule.
  double get height => capsule ? (size * 0.75).roundToDouble() : size;

  /// The head's width.
  double get width => capsule ? height + labelWidth : size;

  /// Half the head's height.
  double get radius => height / 2;

  /// From the head's centre down to the tip.
  double get tipDrop => capsule ? radius + 8 : radius * 1.25;

  /// The badge of the kind on a photo.
  double get badge => math.max(16, size * 0.36);

  /// The reach of a pointer around the head's centre: the photo's disc, or
  /// the capsule's height with a share of its length.
  double get hitRadius => capsule ? radius + labelWidth / 4 : radius;

  /// Where the head's centre stands above the tip.
  Offset head(Offset tip) => tip - Offset(0, tipDrop);

  /// The box the mark covers when its tip is at [tip].
  Rect bounds(Offset tip) {
    final c = head(tip);
    final half = capsule ? width / 2 : radius + badge * 0.35;
    return Rect.fromLTRB(c.dx - half, c.dy - radius, c.dx + half, tip.dy);
  }

  /// The head alone, without the narrow tail down to the place: what
  /// hides the map behind it. A photo's disc, its badge at the lower right
  /// (centred 0.72 and 0.62 of the radius off the disc's centre, its rim
  /// 1.5 px); a capsule's body.
  Rect face(Offset tip) {
    final c = head(tip);
    if (capsule) {
      return Rect.fromLTRB(c.dx - width / 2, c.dy - radius, c.dx + width / 2, c.dy + radius);
    }
    final reach = badge / 2 + 1.5;
    return Rect.fromLTRB(
      c.dx - radius,
      c.dy - radius,
      c.dx + math.max(radius, radius * 0.72 + reach),
      c.dy + math.max(radius, radius * 0.62 + reach),
    );
  }
}

/// A place a route map could draw as a rich mark, where the engine draws
/// it.
@immutable
final class RichCandidate {
  const new({
    required this.id,
    required this.at,
    required this.place,
    this.aheadM,
    this.offRouteM,
    this.fromVehicleM,
    this.capsule = false,
    this.labelWidth = 0,
  });

  /// The place's id.
  final String id;

  /// The place's point on the map, logical pixels from its top left.
  final Offset at;
  final PlaceSummary place;

  /// Along the route from the vehicle, metres; negative behind it; null
  /// without a vehicle or far from the route.
  final double? aheadM;

  /// From the route, metres; null without one.
  final double? offRouteM;

  /// From the vehicle as the crow flies, metres; null without one.
  final double? fromVehicleM;

  /// Its mark would be illustrated ([RichGeometry.capsule]), not a photo.
  final bool capsule;

  /// The width its label would take; zero for none.
  final double labelWidth;

  /// The shape of its mark at [size].
  RichGeometry geometry(double size) =>
      RichGeometry(size, labelWidth: labelWidth, capsule: capsule);
}

/// What the map leaves to rich marks.
@immutable
final class RichFrame {
  const new({
    required this.size,
    required this.limit,
    this.sizes = RichMarks.phone,
    this.clear = EdgeInsets.zero,
    this.obstacles = const [],
    this.vehicle,
    this.path = const [],
    this.line = const [],
  });

  /// The map's size, logical pixels.
  final Size size;

  /// How many at most.
  final int limit;
  final RichSizes sizes;

  /// The edges of the map that something covers across: the maneuver's
  /// banner and the notices at the top, the bar at the bottom, a side
  /// panel.
  final EdgeInsets clear;

  /// What covers a part of the map only, in its logical pixels: the
  /// buttons' column, "Recentrer". Above the column the map's edge stays
  /// open.
  final List<Rect> obstacles;

  /// Where the vehicle's arrow is drawn; null without one, or off the map.
  final Offset? vehicle;

  /// The road just ahead of the vehicle ([immediateM]), on the map.
  final List<Offset> path;

  /// The road after it ([RichMarks.lineAheadM]), on the map.
  final List<Offset> line;

  /// The part of the map a mark may cover.
  Rect get open => Rect.fromLTRB(
    clear.left + RichMarks.gap,
    clear.top + RichMarks.gap,
    size.width - clear.right - RichMarks.gap,
    size.height - clear.bottom - RichMarks.gap,
  );
}

/// A place chosen to stand out, and its disc's size.
@immutable
final class RichPick {
  const new({required this.candidate, required this.size});

  final RichCandidate candidate;
  final double size;

  String get id => candidate.id;

  @override
  bool operator ==(Object other) =>
      other is RichPick && other.candidate.id == candidate.id && other.size == size;

  @override
  int get hashCode => Object.hash(candidate.id, size);
}

/// Why a candidate is left a small pin, for the tests and the log.
enum RichRefusal {
  /// Its mark would leave the open part of the map: under the banner, the
  /// bar, the buttons, or off the edge.
  covered,

  /// Its mark would lie on the vehicle or around it.
  vehicle,

  /// Its mark would lie on the road just ahead.
  path,

  /// Passed: behind the vehicle.
  behind,

  /// Another rich mark, weighed higher, takes its room.
  crowded,

  /// The limit is reached.
  limit,
}

/// The places to draw rich among [candidates], best first, at most
/// [RichFrame.limit]: the mark of each lies wholly in the open part of the
/// map, clear of the vehicle, of the road just ahead and of the others.
/// Among those, ahead of the vehicle first, then near the route, then the
/// better rated ([richWeight]); those of [previous] keep their place over
/// an equal newcomer. [refused], when given, records why each other one
/// stays a small pin.
List<RichPick> chooseRichMarks(
  List<RichCandidate> candidates,
  RichFrame frame, {
  Set<String> previous = const {},
  Map<String, RichRefusal>? refused,
}) {
  final open = frame.open;
  final vehicle = frame.vehicle;
  final ranked = <(RichCandidate, double, Rect)>[];
  for (final c in candidates) {
    if (vehicle != null && (c.aheadM ?? 0) < -RichMarks.behindM) {
      refused?[c.id] = RichRefusal.behind;
      continue;
    }
    final size = frame.sizes.at(c.fromVehicleM);
    final geometry = c.geometry(size);
    final box = geometry.bounds(c.at);
    final spaced = box.inflate(RichMarks.gap);
    if (!_inside(open, box) || frame.obstacles.any(spaced.overlaps)) {
      refused?[c.id] = RichRefusal.covered;
      continue;
    }
    if (vehicle != null && _distanceToRect(vehicle, box) < RichMarks.vehicleClear) {
      refused?[c.id] = RichRefusal.vehicle;
      continue;
    }
    if (_nearPath(box, frame.path) ||
        _nearPath(geometry.face(c.at), frame.line, clear: RichMarks.lineClear)) {
      refused?[c.id] = RichRefusal.path;
      continue;
    }
    final weight = richWeight(c, frame) - (previous.contains(c.id) ? RichMarks.keepBonus : 0);
    ranked.add((c, weight, box));
  }
  ranked.sort((a, b) {
    final byWeight = a.$2.compareTo(b.$2);
    return byWeight != 0 ? byWeight : a.$1.id.compareTo(b.$1.id);
  });
  final chosen = <RichPick>[];
  final boxes = <Rect>[];
  for (final (c, _, box) in ranked) {
    if (chosen.length >= frame.limit) {
      refused?[c.id] = RichRefusal.limit;
      continue;
    }
    final spaced = box.inflate(RichMarks.gap / 2);
    if (boxes.any((b) => b.overlaps(spaced))) {
      refused?[c.id] = RichRefusal.crowded;
      continue;
    }
    boxes.add(spaced);
    chosen.add(RichPick(candidate: c, size: frame.sizes.at(c.fromVehicleM)));
  }
  return chosen;
}

/// How much a candidate is worth standing out, lower first: a kilometre
/// further along the route costs as much as 300 m further from it or a
/// star and a half less. Without a vehicle (the preview), the distance
/// from the middle of the open map stands for the way ahead.
double richWeight(RichCandidate c, RichFrame frame) {
  final ahead = c.aheadM;
  final off = c.offRouteM;
  final double along;
  if (frame.vehicle != null && ahead != null && (off ?? 0) <= RichMarks.nearRouteM) {
    along = math.max(0, ahead) / 1000;
  } else if (frame.vehicle != null && c.fromVehicleM != null) {
    along = c.fromVehicleM! / 1000;
  } else {
    final open = frame.open;
    along = (c.at - open.center).distance / math.max(1, open.shortestSide) * 2;
  }
  final away = (off ?? 0) / 300;
  final rating = c.place.ratingForFilters ?? c.place.ratingAverage;
  final stars = rating == null ? 0.3 : -(rating - 3) * 0.66;
  return along + away + stars;
}

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;

double _distanceToRect(Offset p, Rect r) {
  final dx = math.max(0, math.max(r.left - p.dx, p.dx - r.right));
  final dy = math.max(0, math.max(r.top - p.dy, p.dy - r.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

/// Whether [box] comes within [clear] of the polyline [path].
bool _nearPath(Rect box, List<Offset> path, {double clear = RichMarks.pathClear}) {
  if (path.isEmpty) return false;
  final grown = box.inflate(clear);
  if (path.length == 1) return grown.contains(path.single);
  for (var i = 1; i < path.length; i++) {
    if (_segmentHitsRect(path[i - 1], path[i], grown)) return true;
  }
  return false;
}

/// Whether the segment from [a] to [b] crosses or lies in [r]
/// (Liang-Barsky clipping).
bool _segmentHitsRect(Offset a, Offset b, Rect r) {
  if (r.contains(a) || r.contains(b)) return true;
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  var t0 = 0.0;
  var t1 = 1.0;
  for (final (p, q) in [
    (-dx, a.dx - r.left),
    (dx, r.right - a.dx),
    (-dy, a.dy - r.top),
    (dy, r.bottom - a.dy),
  ]) {
    if (p == 0) {
      if (q < 0) return false;
      continue;
    }
    final t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
  }
  return t0 <= t1;
}

/// A route's points with their distance from its start, measured once: a
/// stretch of it is then found by a binary search, not by a walk from the
/// start at each place and each pass (a long route holds tens of thousands
/// of points).
final class RouteIndex {
  new(this.line) : _along = _cumulative(line);

  final List<LatLng> line;
  final List<double> _along;

  static List<double> _cumulative(List<LatLng> line) {
    final out = <double>[];
    var along = 0.0;
    for (var i = 0; i < line.length; i++) {
      if (i > 0) along += line[i - 1].distanceTo(line[i]);
      out.add(along);
    }
    return out;
  }

  double get length => _along.isEmpty ? 0 : _along.last;

  /// The index of the last point at most [metres] along.
  int _before(double metres) {
    var lo = 0;
    var hi = _along.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_along[mid] <= metres) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  LatLng _at(double metres) {
    final i = _before(metres);
    if (i >= line.length - 1) return line.last;
    final span = _along[i + 1] - _along[i];
    final t = span <= 0 ? 0.0 : ((metres - _along[i]) / span).clamp(0.0, 1.0);
    final a = line[i];
    final b = line[i + 1];
    return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  /// The points from [fromM] to [toM] along the route, cut inside the
  /// segments where the stretch starts and ends; fewer than two points when
  /// it misses the route.
  List<LatLng> stretch(double fromM, double toM) {
    if (line.length < 2) return const [];
    final from = math.max<double>(0, fromM);
    final to = math.min(length, toM);
    if (to <= from) return const [];
    final first = _before(from);
    final last = _before(to);
    return [
      _at(from),
      for (var i = first + 1; i <= last; i++) line[i],
      if (_along[last] < to) _at(to),
    ];
  }
}

/// The route's points from [alongM] to [aheadM] further, the road the
/// marks keep clear of; empty without two points there.
List<LatLng> roadAhead(RouteIndex route, {required double alongM, required double aheadM}) =>
    route.stretch(alongM, alongM + aheadM);

/// Where [place] lies beside [route] from a vehicle [alongM] along it:
/// how far ahead along the route and how far off it, looked for in the
/// stretch from a little behind the vehicle to [windowM] ahead, so a route
/// that comes back near itself later does not pull a place to its far
/// side. Null when the stretch is too short to measure.
({double aheadM, double offM})? placeAlong(
  LatLng place,
  RouteIndex route, {
  required double alongM,
  double windowM = 8000,
}) {
  final from = math.max(0, alongM - 500).toDouble();
  final near = nearestOnLine(place, route.stretch(from, alongM + windowM));
  if (near == null) return null;
  return (aheadM: from + near.alongM - alongM, offM: near.offM);
}

/// The size MapLibre draws a symbol at, beside the size it is given, at a
/// point [dy] logical pixels below the centre of the camera, on a map
/// [height] tall tilted [pitchDeg] from straight down: a pitched camera
/// draws what is near larger and what is far smaller
/// (`perspective_ratio` of its symbol shaders, from the camera's vertical
/// field of view of 36.87°). The engines divide a mark's size by it, so
/// a mark is drawn at the size [RichSizes] gives, near or far.
double symbolPerspective({required double dy, required double height, required double pitchDeg}) {
  if (height <= 0 || pitchDeg <= 0) return 1;
  final pitch = pitchDeg * math.pi / 180;
  // The camera's distance to the centre, in pixels: half the height over
  // the tangent of half the field of view (MapLibre's 0.6435 rad).
  final toCentre = 0.5 / math.tan(0.6435011087932844 / 2) * height;
  final alpha = math.atan(dy / toCentre);
  final ratio = math.cos(pitch - alpha) / (math.cos(pitch) * math.cos(alpha));
  return (0.5 + 0.5 * ratio).clamp(0.0, 4.0);
}

/// What a place's illustrated mark says under its pictogram: the one fact
/// a driver weighs first. The price when known (the tiles only say free or
/// paid), then a good rating, then whether a night is possible, then any
/// rating.
@immutable
sealed class RichLabel {
  const new();

  static RichLabel? of(PlaceSummary place, {double? priceEur}) {
    final price = priceEur ?? place.priceParkingEur;
    if (price != null) return price == 0 ? const FreeLabel() : PriceLabel(price);
    final rating = place.ratingForFilters ?? place.ratingAverage;
    if (rating != null && rating >= goodRating) return RatingLabel(rating);
    if (place.overnight.nightOk) return const NightLabel();
    if (rating != null) return RatingLabel(rating);
    return null;
  }

  /// From this rating the stars come before the night: a good place is
  /// worth the detour whatever else it says.
  static const goodRating = 3.5;
}

final class FreeLabel extends RichLabel {
  const new();

  @override
  bool operator ==(Object other) => other is FreeLabel;

  @override
  int get hashCode => (FreeLabel).hashCode;
}

final class PriceLabel extends RichLabel {
  const new(this.eur);

  final double eur;

  @override
  bool operator ==(Object other) => other is PriceLabel && other.eur == eur;

  @override
  int get hashCode => eur.hashCode;
}

final class RatingLabel extends RichLabel {
  const new(this.rating);

  final double rating;

  @override
  bool operator ==(Object other) => other is RatingLabel && other.rating == rating;

  @override
  int get hashCode => rating.hashCode;
}

final class NightLabel extends RichLabel {
  const new();

  @override
  bool operator ==(Object other) => other is NightLabel;

  @override
  int get hashCode => (NightLabel).hashCode;
}

/// The maneuvers that ask the driver's full attention: a roundabout, a
/// fork, a slip road, a merge, a U-turn or a sharp turn (OSRM's types and
/// modifiers, as the banner has them).
bool complexManeuver(String? type, String? modifier) {
  const types = {
    'roundabout',
    'rotary',
    'roundabout turn',
    'exit roundabout',
    'exit rotary',
    'fork',
    'off ramp',
    'on ramp',
    'merge',
  };
  const modifiers = {'uturn', 'sharp left', 'sharp right'};
  return types.contains(type) || modifiers.contains(modifier);
}

/// Whether the rich marks step aside for the maneuver ahead: a complex one
/// ([complexManeuver]) closer than 10 s of driving, 200 m at least. They
/// come back once it is behind.
bool richMarksYield({
  required String? maneuverType,
  required String? modifier,
  required double distanceM,
  double? speedMps,
}) {
  if (!complexManeuver(maneuverType, modifier)) return false;
  return distanceM <= math.max(200, (speedMps ?? 0) * 10);
}
