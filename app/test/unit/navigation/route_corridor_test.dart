import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_corridor.dart';

/// [p] moved [northM] metres north and [eastM] east.
LatLng moved(LatLng p, {double northM = 0, double eastM = 0}) =>
    LatLng(p.lat + northM / 111195, p.lon + eastM / (111195 * math.cos(p.lat * math.pi / 180)));

/// The distance from [p] to the segment [a] to [b], metres, on a plane
/// tangent at [p].
double toSegment(LatLng p, LatLng a, LatLng b) {
  final k = math.cos(p.lat * math.pi / 180) * 111195;
  final ax = (a.lon - p.lon) * k;
  final ay = (a.lat - p.lat) * 111195;
  final dx = (b.lon - a.lon) * k;
  final dy = (b.lat - a.lat) * 111195;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
  return math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
}

void main() {
  test('a point beside the middle of a long straight stretch is reached', () {
    // A motorway stretch of 30 km between two shape points.
    const a = LatLng(45, 4.8);
    final b = moved(a, northM: 30000, eastM: 5000);
    final corridor = RouteCorridor.of([a, b]);
    final middle = LatLng((a.lat + b.lat) / 2, (a.lon + b.lon) / 2);
    expect(corridor.reaches([moved(middle, eastM: eventPointToleranceM)]), isTrue);
    expect(corridor.reaches([moved(middle, eastM: -eventPointToleranceM)]), isTrue);
  });

  test('a closure crossing the route between two shape points is reached', () {
    const a = LatLng(45, 4.8);
    final b = moved(a, eastM: 20000);
    final middle = LatLng(a.lat, (a.lon + b.lon) / 2);
    // A road of 4 km crossing the route, without a point near it.
    final crossing = [moved(middle, northM: -2000), moved(middle, northM: 2000)];
    expect(RouteCorridor.of([a, b]).reaches(crossing), isTrue);
  });

  test('an event a few kilometres off the route is not', () {
    const a = LatLng(45, 4.8);
    final b = moved(a, northM: 10000);
    final corridor = RouteCorridor.of([a, b]);
    expect(corridor.reaches([moved(a, eastM: 4000, northM: 5000)]), isFalse);
    expect(
      corridor.reaches([moved(a, eastM: 4000), moved(a, eastM: 4000, northM: 10000)]),
      isFalse,
      reason: 'a road running beside the route, 4 km away',
    );
    expect(corridor.reaches(const []), isFalse);
  });

  test('every point the engine could find on a route is reached, north to the Cape', () {
    // Random routes from Spain to the North Cape, and points thrown near
    // them: any point within the engine's widest tolerance of the route
    // must be reached.
    final random = math.Random(112);
    var near = 0;
    for (var r = 0; r < 60; r++) {
      final lat0 = 36 + random.nextDouble() * 35;
      final lon0 = -8 + random.nextDouble() * 30;
      final line = <LatLng>[LatLng(lat0, lon0)];
      for (var i = 0; i < 30; i++) {
        line.add(
          moved(
            line.last,
            northM: (random.nextDouble() - 0.3) * 3000,
            eastM: (random.nextDouble() - 0.5) * 3000,
          ),
        );
      }
      final corridor = RouteCorridor.of(line);
      for (var k = 0; k < 400; k++) {
        final i = random.nextInt(line.length - 1);
        final t = random.nextDouble();
        final on = LatLng(
          line[i].lat + (line[i + 1].lat - line[i].lat) * t,
          line[i].lon + (line[i + 1].lon - line[i].lon) * t,
        );
        final angle = random.nextDouble() * 2 * math.pi;
        final reach = random.nextDouble() * 30;
        final p = moved(on, northM: reach * math.cos(angle), eastM: reach * math.sin(angle));
        var distance = double.infinity;
        for (var j = 1; j < line.length; j++) {
          distance = math.min(distance, toSegment(p, line[j - 1], line[j]));
        }
        if (distance <= eventPointToleranceM) {
          near++;
          expect(corridor.reaches([p]), isTrue, reason: 'route $r, point $k at ${distance}m');
        }
      }
    }
    expect(near, greaterThan(5000), reason: 'enough points to mean something');
  });
}
