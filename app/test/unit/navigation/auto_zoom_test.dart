import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';

void main() {
  group('the cruising zoom', () {
    test('widens the faster the vehicle goes, a town street closest, a motorway widest', () {
      final town = cruiseZoom(30 / 3.6);
      final road = cruiseZoom(80 / 3.6);
      final motorway = cruiseZoom(130 / 3.6);
      expect(town, closeTo(17.1, 1e-9));
      expect(road, closeTo(15.75, 1e-9));
      expect(motorway, closeTo(14.8, 1e-9));
      var last = double.infinity;
      for (var kmh = 0; kmh <= 150; kmh += 5) {
        final z = cruiseZoom(kmh / 3.6);
        expect(z, lessThanOrEqualTo(last), reason: '$kmh km/h');
        last = z;
      }
    });

    test('a vehicle without a speed is taken as parked', () {
      expect(cruiseZoom(null), AutoZoom.parkedZoom);
      expect(cruiseZoom(0), AutoZoom.parkedZoom);
    });
  });

  group('the speed the zoom reads', () {
    test('holds while the GPS speed wavers by a few km/h, moves past the hysteresis', () {
      final hold = SpeedHold();
      expect(hold.update(50 / 3.6), closeTo(50, 1e-9));
      for (final kmh in [47, 53, 49, 54.5, 46]) {
        expect(hold.update(kmh / 3.6), closeTo(50, 1e-9), reason: '$kmh km/h');
      }
      expect(hold.update(57 / 3.6), closeTo(57, 1e-9));
      expect(hold.update(null), closeTo(57, 1e-9), reason: 'an unknown speed keeps it');
      expect(hold.update(0), 0, reason: 'stopping is a change');
    });
  });

  group('closing in before a maneuver', () {
    double at(double kmh, double d, {String type = 'turn', String? modifier = 'right'}) =>
        autoZoom(cruiseKmh: kmh, distanceToManeuverM: d, maneuverType: type, modifier: modifier);

    test('far from the turn the camera cruises; near it, it comes closer', () {
      final cruise = cruiseZoom(40 / 3.6);
      expect(at(40, 1000), closeTo(cruise, 1e-9));
      expect(at(40, 150), greaterThan(cruise + 0.3));
      expect(at(40, 30), closeTo(at(40, 5), 1e-9), reason: 'held at its closest');
      expect(at(40, 30), lessThanOrEqualTo(cruise + AutoZoom.maxCloseIn));
    });

    test('the closer the turn, the closer the camera, never a jump', () {
      for (final kmh in [30.0, 50.0, 90.0, 130.0]) {
        var last = at(kmh, 3000);
        for (var d = 2999.0; d >= 0; d -= 1) {
          final z = at(kmh, d);
          expect(z, greaterThanOrEqualTo(last - 1e-9), reason: '$kmh km/h, $d m');
          expect(z - last, lessThan(0.02), reason: 'a metre moves the view a little, $kmh km/h');
          last = z;
        }
      }
    });

    test('a fast road starts closing in further from the maneuver', () {
      double start(double kmh) {
        final cruise = cruiseZoom(kmh / 3.6);
        for (var d = 3000.0; d >= 0; d -= 5) {
          if (at(kmh, d, type: 'off ramp') > cruise + 0.01) return d;
        }
        return 0;
      }

      expect(start(30), inInclusiveRange(150, 260));
      expect(start(130), inInclusiveRange(800, 1300));
    });

    test('a motorway exit stays wider at its closest than a town corner', () {
      expect(at(130, 0, type: 'off ramp'), lessThan(at(40, 0)));
    });

    test('a road that only changes its name, or goes straight on, keeps the cruise', () {
      final cruise = cruiseZoom(50 / 3.6);
      expect(at(50, 40, type: 'new name', modifier: 'straight'), closeTo(cruise, 1e-9));
      expect(at(50, 40, type: 'continue', modifier: 'straight'), closeTo(cruise, 1e-9));
      expect(at(50, 40, type: 'continue', modifier: 'slight left'), greaterThan(cruise));
      expect(at(50, 40, type: 'roundabout'), greaterThan(cruise));
      expect(at(50, 40, type: 'arrive', modifier: 'left'), greaterThan(cruise));
    });

    test('off the route, with no maneuver, the camera cruises', () {
      expect(
        autoZoom(cruiseKmh: 90, distanceToManeuverM: null),
        closeTo(cruiseZoom(90 / 3.6), 1e-9),
      );
    });
  });

  group('down a long straight', () {
    test('the view widens with the distance to the next maneuver, smoothly', () {
      final cruise = cruiseZoom(130 / 3.6);
      // 130 km/h: two minutes are 4.3 km.
      expect(
        autoZoom(cruiseKmh: 130, distanceToManeuverM: 4000, maneuverType: 'off ramp'),
        closeTo(cruise, 1e-9),
      );
      expect(
        autoZoom(cruiseKmh: 130, distanceToManeuverM: 30000, maneuverType: 'off ramp'),
        closeTo(cruise - AutoZoom.straightWiden, 1e-9),
      );
      var last = autoZoom(cruiseKmh: 130, distanceToManeuverM: 4000);
      for (var d = 4000.0; d <= 12000; d += 10) {
        final z = autoZoom(cruiseKmh: 130, distanceToManeuverM: d);
        expect(last - z, lessThan(0.01), reason: '$d m');
        last = z;
      }
    });

    test('a town street with a far turn widens only past three kilometres', () {
      expect(
        autoZoom(cruiseKmh: 40, distanceToManeuverM: 2500),
        closeTo(cruiseZoom(40 / 3.6), 1e-9),
      );
      expect(autoZoom(cruiseKmh: 40, distanceToManeuverM: 4500), lessThan(cruiseZoom(40 / 3.6)));
    });
  });

  test('the zoom stays within the bounds the camera follows in', () {
    for (final kmh in [0.0, 30.0, 200.0]) {
      for (final d in [0.0, 50.0, 100000.0]) {
        final z = autoZoom(cruiseKmh: kmh, distanceToManeuverM: d, maneuverType: 'turn');
        expect(z, inInclusiveRange(AutoZoom.minZoom, AutoZoom.maxZoom));
      }
    }
  });
}
