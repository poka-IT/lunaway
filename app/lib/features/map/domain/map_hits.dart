/// How a tap or a click picks a feature of the map, the same on every
/// engine: the feature whose drawn shape lies nearest the point wins, within
/// a tolerance that does not depend on how small the feature is drawn. A dot
/// of three pixels on the country view is then as easy to hit as a pin.
///
/// The browser and the desktop map page apply the same rule to the hover
/// and the clicks they handle themselves (`web/lunaway_maplibre.js`,
/// `assets/map/lunaway_map.js`), from the shapes `hitShapesJson` writes.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';

/// What points at the map.
enum PointerKind { touch, mouse }

/// The room around a feature's drawn shape that still picks it, in logical
/// pixels. A fingertip covers a disc of about 44 px across (the minimum
/// target of the Material and Apple guidelines); a mouse is precise, but a
/// target of under 28 px across makes a small dot a chase.
double hitTolerance(PointerKind kind) => switch (kind) {
  PointerKind.touch => 22,
  PointerKind.mouse => 14,
};

/// A number of a [HitShape]: fixed, read from a property of the feature, or
/// interpolated linearly (and clamped) over the zoom or over a property, as
/// the style's `interpolate` draws it.
@immutable
sealed class HitValue {
  const new();

  double at(double zoom, Map<Object?, Object?> properties);

  /// The JSON the map pages read (see `value` in the pages' hit code).
  Object toJson();
}

final class FixedHit extends HitValue {
  const new(this.value);

  final double value;

  @override
  double at(double zoom, Map<Object?, Object?> properties) => value;

  @override
  Object toJson() => value;
}

/// A property of the feature plus [plus] (a circle's radius and its rim);
/// [fallback] when the feature lacks it.
final class PropertyHit extends HitValue {
  const new(this.key, {this.plus = 0, this.fallback = 0});

  final String key;
  final double plus;
  final double fallback;

  @override
  double at(double zoom, Map<Object?, Object?> properties) {
    final v = properties[key];
    return (v is num ? v.toDouble() : fallback) + plus;
  }

  @override
  Object toJson() => {'prop': key, 'plus': plus, 'fallback': fallback};
}

/// Linear between [stops] (input, output) over the zoom (`by` 'zoom') or a
/// property of the feature, clamped at both ends.
final class StopsHit extends HitValue {
  const new(this.by, this.stops);

  final String by;
  final List<(double, double)> stops;

  @override
  double at(double zoom, Map<Object?, Object?> properties) {
    final raw = by == 'zoom' ? zoom : properties[by];
    final x = raw is num ? raw.toDouble() : stops.first.$1;
    return interpolateStops(stops, x);
  }

  @override
  Object toJson() => {
    'by': by,
    'stops': [
      for (final (x, y) in stops) [x, y],
    ],
  };
}

/// [stops] at [x], linear between them, clamped outside.
double interpolateStops(List<(double, double)> stops, double x) {
  if (x <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    final (x1, y1) = stops[i];
    if (x <= x1) {
      final (x0, y0) = stops[i - 1];
      return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
  }
  return stops.last.$2;
}

/// What a layer draws, as far as a pointer cares: a disc of [radius] whose
/// centre stands [lift] above the feature's point (a pin's head above its
/// tip; zero for a dot or a cluster), in logical pixels.
@immutable
final class HitShape {
  const new({
    required this.radius,
    required this.priority,
    this.lift = const FixedHit(0),
    this.anchor,
    this.ring,
    this.icon,
    this.hoverState,
    this.needs,
    this.inert = false,
    this.line = false,
  });

  final HitValue radius;
  final HitValue lift;

  /// The disc drawn at the feature's point itself, when its head stands
  /// above it: the dot under a place's pin, drawn by another layer from the
  /// same feature. It belongs to the same target, so a pointer on the
  /// place's exact point picks the pin as one on its head does, and the
  /// hover's ring goes around it. Only where such a dot is drawn: anywhere
  /// else it would take in bare ground under the pin, on every engine.
  final HitValue? anchor;

  /// The radius the hover's ring goes around at the feature's point, for a
  /// pin with no dot drawn there: read by the hover alone, it widens no
  /// target. Null where the ring goes around [anchor] or, for a shape
  /// centred on its point, around [radius].
  final HitValue? ring;

  /// The icon size the layer draws the feature at: under the mouse, the
  /// hover grows a copy of its image from it (a pin). Null for what does
  /// not grow (a dot, a cluster, a badge whose text the copy would hide).
  final HitValue? icon;

  /// The property a feature must carry for the hover to tell it, through
  /// the feature state `hover`, that the mouse is on it: its layers then
  /// give way to the hover's ring (a route mark's lit ring).
  final String? hoverState;

  /// Breaks a tie (two shapes under the pointer): the lower wins. What is
  /// drawn on top and what matters more come first.
  final int priority;

  /// A property a feature must carry to be picked: a route mark without an
  /// id is a sign on the route, not a target.
  final String? needs;

  /// Picked but leads nowhere: the marker of a long-pressed point, whose
  /// details are already open. A tap on it is not a tap on empty map.
  final bool inert;

  /// A line: any part of it inside the tolerance box counts, ranked after
  /// every point-like shape in reach.
  final bool line;

  Map<String, Object?> toJson() => {
    'r': radius.toJson(),
    'y': lift.toJson(),
    'p': priority,
    if (anchor != null) 'a': anchor!.toJson(),
    if (ring != null) 'ring': ring!.toJson(),
    if (icon != null) 'icon': icon!.toJson(),
    if (hoverState != null) 'state': hoverState,
    if (needs != null) 'needs': needs,
    if (inert) 'inert': true,
    if (line) 'line': true,
  };
}

/// The shape of a feature of [layer] with [properties] in [shapes]: a
/// layer may draw two kinds of features, told apart by their `kind`
/// (`lw-selection-pin` holds a selected place or the long-press marker),
/// keyed `layer/kind`.
HitShape? hitShapeOf(Map<String, HitShape> shapes, String layer, Map<Object?, Object?> properties) {
  final kind = properties['kind'];
  if (kind is String) {
    final specific = shapes['$layer/$kind'];
    if (specific != null) return specific;
  }
  return shapes[layer];
}

/// A feature in reach of the pointer, as the engine's query answered it.
@immutable
final class HitCandidate {
  const new({required this.layer, required this.properties, required this.points});

  /// The id of the layer (or, where the engine does not say, the layer the
  /// feature's properties and the query tell).
  final String layer;
  final Map<Object?, Object?> properties;

  /// Where the feature stands on screen, in logical pixels: its point, or
  /// each point of a MultiPoint (the tiles' dots of the low zooms). Empty
  /// for a line.
  final List<Offset> points;
}

/// The feature picked: its index among the candidates, the point of it
/// nearest the pointer (one of a MultiPoint) and that point's index, and
/// how far outside its drawn shape the pointer was.
@immutable
final class MapHit {
  const new({
    required this.index,
    required this.pointIndex,
    required this.distance,
    this.inert = false,
  });

  final int index;
  final int pointIndex;
  final double distance;

  /// The shape leads nowhere ([HitShape.inert]).
  final bool inert;
}

/// The candidate nearest [at] within [tolerance] of its drawn shape, or
/// null. Candidates come topmost first, as the engines answer; a tie goes to
/// the shape of lower priority, then to the one drawn on top.
MapHit? nearestHit(
  Offset at,
  List<HitCandidate> candidates, {
  required Map<String, HitShape> shapes,
  required double zoom,
  required double tolerance,
}) {
  MapHit? best;
  var bestPriority = 0;
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    final shape = hitShapeOf(shapes, c.layer, c.properties);
    if (shape == null) continue;
    if (shape.needs case final key? when c.properties[key] == null) continue;
    var distance = tolerance;
    var point = 0;
    if (!shape.line) {
      if (c.points.isEmpty) continue;
      final radius = shape.radius.at(zoom, c.properties);
      final lift = shape.lift.at(zoom, c.properties);
      final anchor = shape.anchor?.at(zoom, c.properties);
      distance = double.infinity;
      for (var j = 0; j < c.points.length; j++) {
        final p = c.points[j];
        var d = _outside(at, Offset(p.dx, p.dy - lift), radius);
        if (anchor != null) d = math.min(d, _outside(at, p, anchor));
        if (d < distance) {
          distance = d;
          point = j;
        }
      }
    }
    if (distance > tolerance) continue;
    final better =
        best == null ||
        distance < best.distance - _epsilon ||
        (distance <= best.distance + _epsilon && shape.priority < bestPriority);
    if (better) {
      best = MapHit(index: i, pointIndex: point, distance: distance, inert: shape.inert);
      bestPriority = shape.priority;
    }
  }
  return best;
}

const _epsilon = 1e-6;

/// How far [at] lies outside the disc of [radius] around [centre]; zero
/// inside.
double _outside(Offset at, Offset centre, double radius) =>
    math.max<double>(0, (at - centre).distance - radius);

/// The points of a GeoJSON geometry as `[lon, lat]`: one for a Point, each
/// of a MultiPoint, none for anything else.
List<LatLng> pointsOfGeometry(Map<Object?, Object?>? geometry) {
  final coordinates = geometry?['coordinates'];
  LatLng? point(Object? c) {
    if (c is! List || c.length < 2) return null;
    final lon = c[0];
    final lat = c[1];
    return lon is num && lat is num ? LatLng(lat.toDouble(), lon.toDouble()) : null;
  }

  switch (geometry?['type']) {
    case 'Point':
      final p = point(coordinates);
      return p == null ? const [] : [p];
    case 'MultiPoint' when coordinates is List:
      return [for (final c in coordinates) ?point(c)];
    default:
      return const [];
  }
}

/// Where [point] is drawn on a north-up, flat map at [zoom] (MapLibre's
/// 512 px tiles) on which [reference] is drawn at [referenceAt], in the
/// same units. The maps whose taps pick features never turn nor tilt.
Offset screenOf(
  LatLng point, {
  required LatLng reference,
  required Offset referenceAt,
  required double zoom,
}) {
  final world = 512 * math.pow(2, zoom).toDouble();
  // The shorter way round: a point across the antimeridian from the
  // reference is drawn beside it, on the world's next copy.
  var dLon = point.lon - reference.lon;
  if (dLon > 180) dLon -= 360;
  if (dLon < -180) dLon += 360;
  return referenceAt +
      Offset(dLon / 360 * world, (_mercatorY(point.lat) - _mercatorY(reference.lat)) * world);
}

double _mercatorY(double lat) {
  final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
  return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
}

/// What the mouse is over on a map of the page, as the page's hover picked
/// it: the layer, the feature's properties, and where the feature stands
/// on the map, in logical pixels.
@immutable
final class WebMapHover {
  const new({required this.layer, required this.properties, required this.at});

  final String layer;
  final Map<Object?, Object?> properties;
  final Offset at;
}
