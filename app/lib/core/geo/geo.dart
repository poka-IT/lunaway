import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A WGS 84 position in decimal degrees.
@immutable
final class LatLng {
  const new(this.lat, this.lon);

  final double lat;
  final double lon;

  /// The mean Earth radius (IUGG), the one the backend's matching uses too.
  static const double earthRadiusM = 6371008.8;

  /// Great-circle distance in metres (haversine). Precise to well under a
  /// metre at the scales the app sorts by, and cheap enough for a list.
  double distanceTo(LatLng other) {
    const earthRadius = earthRadiusM;
    final dLat = _rad(other.lat - lat);
    final dLon = _rad(other.lon - lon);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat)) * math.cos(_rad(other.lat)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLng($lat, $lon)';
}

/// An axis-aligned box in degrees. Boxes crossing the antimeridian are not
/// needed for Europe and are not supported.
@immutable
final class GeoBounds {
  const new({required this.south, required this.west, required this.north, required this.east});

  /// The smallest box holding every point; null for no point.
  static GeoBounds? around(Iterable<LatLng> points) {
    if (points.isEmpty) return null;
    var south = 90.0;
    var north = -90.0;
    var west = 180.0;
    var east = -180.0;
    for (final p in points) {
      south = math.min(south, p.lat);
      north = math.max(north, p.lat);
      west = math.min(west, p.lon);
      east = math.max(east, p.lon);
    }
    return GeoBounds(south: south, west: west, north: north, east: east);
  }

  /// Metropolitan France with Corsica: the region the MVP syncs.
  static const metropolitanFrance = GeoBounds(south: 41.2, west: -5.5, north: 51.3, east: 9.9);

  final double south;
  final double west;
  final double north;
  final double east;

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  bool contains(LatLng p) => p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.south == south &&
      other.west == west &&
      other.north == north &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);

  @override
  String toString() => 'GeoBounds($south, $west, $north, $east)';
}
