import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_legs.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';

import '../../helpers/navigation.dart';

/// A straight road north from the equator, [steps] metres and seconds each.
RouteOption _road(List<LatLng> line, {List<(double, double)> steps = const []}) => RouteOption(
  index: 0,
  distanceM: steps.fold(0, (s, x) => s + x.$1),
  durationS: steps.fold(0, (s, x) => s + x.$2),
  hasToll: false,
  hasFerry: false,
  hasMotorway: false,
  warnings: const [],
  line: line,
  steps: [
    for (final (m, s) in steps)
      RouteStep(
        instruction: '',
        distanceM: m,
        durationS: s,
        position: line.first,
        maneuverType: 'turn',
      ),
  ],
);

LegEnd _at(LatLng p) => (asked: p, reached: p);

void main() {
  test('one leg per stop ahead and one to the destination, the last ending with the trip', () {
    final route = routeFixture('limoges_drive').routes.first;
    final track = LineTrack(route);
    final pause = track.at(800);
    final fontaine = track.at(2000);
    final legs = routeLegs(
      route: route,
      stops: [_at(pause), _at(fontaine)],
      destination: _at(route.line.last),
      alongM: 0,
      leftM: route.distanceM,
      leftS: route.durationS,
    );
    expect([for (final l in legs) l.stop], [0, 1, null]);
    expect([for (final l in legs) l.to], [pause, fontaine, route.line.last]);
    expect(legs.last.toM, route.distanceM);
    expect(legs.last.toS, closeTo(route.durationS, 0.001));
    expect(legs[0].toM, closeTo(800 * route.distanceM / track.length, 30));
    expect(legs[0].toM, lessThan(legs[1].toM));
    expect(legs[0].toS, lessThan(legs[1].toS));
    // Each leg frames its own stretch, from the stop before.
    expect(legs[0].bounds.contains(track.at(400)), isTrue);
    expect(legs[0].bounds.contains(track.at(1500)), isFalse);
    expect(legs[1].bounds.contains(track.at(1500)), isTrue);
    expect(legs[1].bounds.contains(track.at(200)), isFalse);
  });

  test('the first leg starts at the vehicle, and its distance is what is left of it', () {
    final route = routeFixture('limoges_drive').routes.first;
    final track = LineTrack(route);
    final left = route.distanceM - 500;
    final legs = routeLegs(
      route: route,
      stops: [_at(track.at(800))],
      destination: _at(route.line.last),
      alongM: 500,
      leftM: left,
      leftS: 200,
      vehicle: track.at(500),
    );
    expect(legs[0].toM, closeTo(300 * left / (track.length - 500), 30));
    expect(legs[0].bounds.contains(track.at(200)), isFalse, reason: 'the road driven is behind');
    expect(legs[0].bounds.contains(track.at(650)), isTrue);
    expect(legs.last.toM, left);
    expect(legs.last.toS, closeTo(200, 0.001));
  });

  test('a road driven fast takes less of the time than a slow one of the same length', () {
    const a = LatLng(0, 0);
    const b = LatLng(0.009, 0);
    const c = LatLng(0.018, 0);
    // 1 km in 100 s, then 1 km in 300 s: the middle is a quarter of the time.
    final route = _road([a, b, c], steps: [(1000, 100), (1000, 300)]);
    final legs = routeLegs(
      route: route,
      stops: [_at(b)],
      destination: _at(c),
      alongM: 0,
      leftM: 2000,
      leftS: 400,
    );
    expect(legs[0].toS, closeTo(100, 2));
    expect(legs[0].toM, closeTo(1000, 2));
  });

  test('a stop the route passes twice is reached after the stop before it', () {
    const start = LatLng(0, 0);
    const middle = LatLng(0.009, 0);
    const far = LatLng(0.018, 0);
    // Out to the far end and back past the middle.
    final route = _road([start, middle, far, middle, start], steps: [(4000, 400)]);
    final legs = routeLegs(
      route: route,
      stops: [_at(far), _at(middle)],
      destination: _at(start),
      alongM: 0,
      leftM: 4000,
      leftS: 400,
    );
    expect(legs[0].toM, closeTo(2000, 5));
    expect(legs[1].toM, closeTo(3000, 5), reason: 'on the way back, not the way out');
  });

  test('a stop the server moved is framed where the route reaches it, named as asked', () {
    const a = LatLng(0, 0);
    const b = LatLng(0.009, 0);
    const c = LatLng(0.018, 0);
    const asked = LatLng(0.009, 0.004);
    final route = _road([a, b, c], steps: [(2000, 200)]);
    final legs = routeLegs(
      route: route,
      stops: [(asked: asked, reached: b)],
      destination: _at(c),
      alongM: 0,
      leftM: 2000,
      leftS: 200,
    );
    expect(legs[0].to, asked);
    expect(legs[0].bounds.contains(b), isTrue);
    expect(legs[0].toM, closeTo(1000, 2));
  });

  test('a route without a shape has no legs', () {
    expect(
      routeLegs(
        route: _road(const []),
        stops: const [],
        destination: _at(const LatLng(0, 0)),
        alongM: 0,
        leftM: 0,
        leftS: 0,
      ),
      isEmpty,
    );
  });
}
