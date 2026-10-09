import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_marks_overlay.dart';

void main() {
  test("the bands of the zones' legend take whole device pixels at every density", () {
    // The legend draws the zone's band, the route's casing and its line at
    // 0.62 or 0.8 of the map's widths: 12.4, 5.89 and 3.72 logical pixels
    // on a phone, fractions that smear on every screen.
    for (final ratio in [1.0, 1.5, 2.0, 2.625, 3.0, 3.5]) {
      for (final scale in [0.62, 0.8]) {
        for (final logical in [RouteLook.zoneWidth, RouteLook.casingWidth, RouteLook.lineWidth]) {
          final width = wholeDevicePixels(logical * scale, ratio);
          final pixels = width * ratio;
          expect(pixels, closeTo(pixels.roundToDouble(), 1e-9), reason: '$logical at $ratio');
          expect((width - logical * scale).abs(), lessThanOrEqualTo(0.5 / ratio + 1e-9));
        }
      }
    }
    expect(wholeDevicePixels(0.1, 2), 0.5, reason: 'one device pixel at the least');
  });
}
