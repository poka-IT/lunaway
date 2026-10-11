import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:meta/meta.dart';

/// A route's line measured twice, for the part behind the vehicle: in
/// metres along it, as the guidance counts ([LatLng.distanceTo]), and in
/// the plane of the map, as MapLibre's `line-progress` counts (Web
/// Mercator, 0 at the start, 1 at the end). The two disagree: a metre
/// near Lille is a longer step on the map than a metre near Marseille, so
/// a share of the metres would draw the grey ahead of or behind the arrow
/// on a long trip.
final class RouteProgress {
  new(this.line) : _metres = List.filled(line.length, 0), _plane = List.filled(line.length, 0) {
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1];
      final b = line[i];
      _metres[i] = _metres[i - 1] + a.distanceTo(b);
      final (ax, ay) = _mercator(a);
      final (bx, by) = _mercator(b);
      _plane[i] = _plane[i - 1] + math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    }
  }

  /// The line measured.
  final List<LatLng> line;
  final List<double> _metres;
  final List<double> _plane;

  /// The line's length, metres.
  double get lengthM => _metres.isEmpty ? 0 : _metres.last;

  /// The share of the line, as the map measures it, before the point
  /// [alongM] metres from its start; 0 before the start, 1 past the end.
  double shareAt(double alongM) {
    if (line.length < 2 || _plane.last <= 0 || alongM <= 0) return 0;
    if (alongM >= _metres.last) return 1;
    var low = 0;
    var high = _metres.length - 1;
    // The last point at or before alongM.
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (_metres[mid] <= alongM) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = _metres[high] - _metres[low];
    final t = span <= 0 ? 0.0 : (alongM - _metres[low]) / span;
    return (_plane[low] + (_plane[high] - _plane[low]) * t) / _plane.last;
  }

  /// The metres from the start of the line at [share] of it as the map
  /// measures it, the inverse of [shareAt].
  double alongAt(double share) {
    if (line.length < 2 || _plane.last <= 0 || share <= 0) return 0;
    if (share >= 1) return _metres.last;
    final target = share * _plane.last;
    var low = 0;
    var high = _plane.length - 1;
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (_plane[mid] <= target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = _plane[high] - _plane[low];
    final t = span <= 0 ? 0.0 : (target - _plane[low]) / span;
    return _metres[low] + (_metres[high] - _metres[low]) * t;
  }

  /// The longitude and latitude in the unit square of Web Mercator, as
  /// MapLibre projects a GeoJSON line before it measures it.
  static (double, double) _mercator(LatLng p) {
    final lat = p.lat.clamp(-85.051129, 85.051129) * math.pi / 180;
    return ((p.lon + 180) / 360, 0.5 - math.log(math.tan(math.pi / 4 + lat / 2)) / (2 * math.pi));
  }
}

/// The arrow the map draws on the route at a maneuver: the stretch of road
/// leading in and out of it, and the direction its head points.
@immutable
final class ManeuverArrow {
  const new({required this.shaft, required this.headCourse});

  /// The route from a little before the maneuver to a little after it, in
  /// driving order; its last point is the arrow's tip.
  final List<LatLng> shaft;

  /// The course at the tip, degrees from north.
  final double headCourse;

  LatLng get tip => shaft.last;

  @override
  bool operator ==(Object other) =>
      other is ManeuverArrow &&
      other.headCourse == headCourse &&
      other.shaft.length == shaft.length &&
      (shaft.isEmpty || (other.shaft.first == shaft.first && other.shaft.last == shaft.last));

  @override
  int get hashCode => Object.hash(headCourse, shaft.length, shaft.firstOrNull, shaft.lastOrNull);
}

/// The arrow of a maneuver [atM] metres along [line], from [beforeM]
/// before it to [afterM] past it ([throughM] more for a roundabout, whose
/// ring the arrow follows to its exit); null where the line has no such
/// stretch.
ManeuverArrow? maneuverArrow(
  List<LatLng> line, {
  required double atM,
  double beforeM = 30,
  double afterM = 30,
  double throughM = 0,
}) {
  final shaft = lineAlong(line, RouteSpan(math.max(0, atM - beforeM), atM + throughM + afterM));
  if (shaft.length < 2) return null;
  // The head points along the last stretch long enough to have a course: a
  // last piece cut a few centimetres long would point anywhere.
  final tip = shaft.last;
  var from = shaft[shaft.length - 2];
  for (var i = shaft.length - 2; i >= 0; i--) {
    from = shaft[i];
    if (from.distanceTo(tip) >= 3) break;
  }
  if (from.distanceTo(tip) < 0.5) return null;
  return ManeuverArrow(shaft: shaft, headCourse: courseFrom(from, tip));
}

/// The arrow drawn for the maneuver of OSRM [type] and [modifier]
/// [atM] metres along [line]: none where the road goes on (a new name, a
/// straight continue, the start, the arrival); longer at a fork or a ramp,
/// taken at speed; through the ring of a roundabout entered there, which
/// is [ringM] long, to its exit.
ManeuverArrow? arrowForManeuver(
  List<LatLng> line, {
  required double atM,
  required String? type,
  required String? modifier,
  double ringM = 0,
}) {
  final (before, after, through) = switch (type) {
    'roundabout' || 'rotary' => (30.0, 25.0, ringM),
    'exit roundabout' || 'exit rotary' || 'roundabout turn' => (25.0, 25.0, 0.0),
    'fork' || 'off ramp' || 'on ramp' || 'merge' => (60.0, 60.0, 0.0),
    'turn' || 'end of road' => modifier == 'straight' ? (0.0, 0.0, -1.0) : (30.0, 30.0, 0.0),
    'continue' when modifier != null && modifier != 'straight' => (30.0, 30.0, 0.0),
    _ => (0.0, 0.0, -1.0),
  };
  if (through < 0) return null;
  return maneuverArrow(line, atM: atM, beforeM: before, afterM: after, throughM: through);
}

/// The course from [a] to [b], degrees from north.
double courseFrom(LatLng a, LatLng b) {
  final la = a.lat * math.pi / 180;
  final lb = b.lat * math.pi / 180;
  final dl = (b.lon - a.lon) * math.pi / 180;
  final y = math.sin(dl) * math.cos(lb);
  final x = math.cos(la) * math.sin(lb) - math.sin(la) * math.cos(lb) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
