import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:meta/meta.dart';

/// The API takes this many stops on a route at most (`RouteInput.waypoints`).
const maxRouteStops = 5;

/// A stop on the way to the destination: a place, a point of interest or a
/// point of the map.
@immutable
final class RouteStop {
  const new({required this.position, this.label, this.placeId, this.poiId});

  final LatLng position;

  /// Its name, or nothing for a point of the map.
  final String? label;

  /// The place it is, when it is one: its card can be opened.
  final String? placeId;

  /// The point of interest it is (a fuel station), when it is one.
  final String? poiId;

  @override
  bool operator ==(Object other) =>
      other is RouteStop &&
      other.position == position &&
      other.label == label &&
      other.placeId == placeId &&
      other.poiId == poiId;

  @override
  int get hashCode => Object.hash(position, label, placeId, poiId);
}

/// Where [stop] goes among [stops] on the way from [origin] to
/// [destination]: the index that lengthens the trip the least, measured as
/// the crow flies. The route asked with it then gives the real cost.
int bestInsertion({
  required LatLng origin,
  required List<RouteStop> stops,
  required LatLng destination,
  required LatLng stop,
}) {
  final points = [origin, for (final s in stops) s.position, destination];
  var best = 0;
  var bestCost = double.infinity;
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i];
    final b = points[i + 1];
    final cost = a.distanceTo(stop) + stop.distanceTo(b) - a.distanceTo(b);
    if (cost < bestCost) {
      bestCost = cost;
      best = i;
    }
  }
  return best;
}

/// A route with one more stop, computed before the user confirms it: what
/// the stop costs is shown on its card.
@immutable
final class StopQuote {
  const new({
    required this.stop,
    required this.stops,
    required this.plan,
    required this.extraS,
    required this.extraM,
    this.base = const [],
    this.from,
    this.routeVersion,
  });

  /// The stop it adds.
  final RouteStop stop;

  /// The stops with the new one in its place.
  final List<RouteStop> stops;

  /// The stops it was computed from: another list since means another
  /// route to compute.
  final List<RouteStop> base;

  /// Where the vehicle was, for a quote made during guidance.
  final LatLng? from;

  /// The guidance's route it was computed against, counted by its
  /// recalculations: another route since (a closure, a wrong turn) means
  /// another quote.
  final int? routeVersion;
  final RoutePlan plan;

  /// Seconds and metres the stop adds to the route; null when the new
  /// route could not be compared (no route for the vehicle).
  final double? extraS;
  final double? extraM;
}

/// [stops] with [stop] at [index].
List<RouteStop> insertStop(List<RouteStop> stops, int index, RouteStop stop) => [
  ...stops.take(index),
  stop,
  ...stops.skip(index),
];

/// How far [p] lies from [line], in metres, and where the line passes
/// nearest, in metres from its start; null for a line of fewer than two
/// points.
({double offM, double alongM})? nearestOnLine(LatLng p, List<LatLng> line) {
  if (line.length < 2) return null;
  const metresPerDegree = 111195.0;
  final cosLat = math.cos(p.lat * math.pi / 180);
  // Metres east and north of p, on a plane tangent at p.
  (double, double) local(LatLng q) =>
      ((q.lon - p.lon) * metresPerDegree * cosLat, (q.lat - p.lat) * metresPerDegree);
  var best = double.infinity;
  var bestAlong = 0.0;
  var along = 0.0;
  var (ax, ay) = local(line.first);
  for (var i = 1; i < line.length; i++) {
    final (bx, by) = local(line[i]);
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final x = ax + t * dx;
    final y = ay + t * dy;
    final d = math.sqrt(x * x + y * y);
    // The plane tangent at p gives the offset and where the perpendicular
    // falls; the length along the line adds true distances, which the plane
    // shortens far from p.
    final segment = line[i - 1].distanceTo(line[i]);
    if (d < best) {
      best = d;
      bestAlong = along + t * segment;
    }
    along += segment;
    ax = bx;
    ay = by;
  }
  return (offM: best, alongM: bestAlong);
}
