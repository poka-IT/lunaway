import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';

/// What MapLibre draws of an `interpolate` `exponential` expression of the
/// zoom at [zoom] (the style specification's formula).
double _atZoom(List<Object> expression, double zoom) {
  final base = ((expression[1] as List<Object>)[1] as num).toDouble();
  final stops = expression.sublist(3).cast<num>();
  if (zoom <= stops.first) return stops[1].toDouble();
  for (var i = 2; i < stops.length; i += 2) {
    final (z1, w1) = (stops[i].toDouble(), stops[i + 1].toDouble());
    if (zoom <= z1) {
      final (z0, w0) = (stops[i - 2].toDouble(), stops[i - 1].toDouble());
      final t = (math.pow(base, zoom - z0) - 1) / (math.pow(base, z1 - z0) - 1);
      return w0 + (w1 - w0) * t;
    }
  }
  return stops.last.toDouble();
}

void main() {
  test("over the zooms the guidance follows at, the route is about as wide as Google Maps'", () {
    // Google Maps: a fill of 10.2 to 10.5 dp in a rim of 2 dp each side,
    // 15 dp in all, from a motorway at 130 km/h to a street corner.
    for (final zoom in [wideZoom(130), AutoZoom.motorwayWide, wideZoom(50), 16.5, closeZoom(0)]) {
      final fill = _atZoom(RouteLook.lineWidthByZoom, zoom);
      final whole = _atZoom(RouteLook.casingWidthByZoom, zoom);
      expect(fill, inInclusiveRange(9.0, 12.0), reason: 'fill at $zoom');
      expect(whole, inInclusiveRange(13.0, 16.0), reason: 'with its rim at $zoom');
    }
  });

  test('the whole route seen at once is thinner', () {
    expect(_atZoom(RouteLook.lineWidthByZoom, 11), lessThan(5));
  });
}
