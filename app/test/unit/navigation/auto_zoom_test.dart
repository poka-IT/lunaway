import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';

void main() {
  CameraAim at(
    double kmh,
    double? d, {
    String type = 'turn',
    String? modifier = 'right',
    double? afterM,
  }) => autoAim(
    speedKmh: kmh,
    distanceToManeuverM: d,
    maneuverType: type,
    modifier: modifier,
    afterM: afterM,
  );

  group('the bounds the speed sets', () {
    test('the widest view widens with the speed, a motorway widest', () {
      expect(wideZoom(30), closeTo(16.0, 1e-9));
      expect(wideZoom(80), closeTo(15.05, 1e-9));
      expect(wideZoom(130), closeTo(14.4, 1e-9));
      var last = double.infinity;
      for (var kmh = 0.0; kmh <= 150; kmh += 5) {
        expect(wideZoom(kmh), lessThanOrEqualTo(last), reason: '$kmh km/h');
        expect(closeZoom(kmh), greaterThan(wideZoom(kmh)), reason: '$kmh km/h');
        last = wideZoom(kmh);
      }
    });

    test('a motorway exit is never seen at the scale of a street corner', () {
      expect(closeZoom(130), lessThan(closeZoom(40) - 1));
    });
  });

  group('the speed the framing reads', () {
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

  group('the next maneuver framed', () {
    test('far off, the widest the speed allows; near, the closest', () {
      expect(at(40, 3000).zoom, closeTo(wideZoom(40), 1e-9));
      expect(at(40, 20).zoom, closeTo(closeZoom(40), 1e-9));
      expect(at(130, 5000, type: 'roundabout').zoom, closeTo(wideZoom(130), 1e-9));
      expect(at(130, 50, type: 'roundabout').zoom, closeTo(closeZoom(130), 1e-9));
    });

    test('a motorway fork or ramp taken fast keeps the wide view, as Google Maps does', () {
      for (final type in ['fork', 'off ramp', 'on ramp', 'merge']) {
        final fast = at(110, 100, type: type, modifier: 'slight right', afterM: 3000);
        expect(fast.zoom, closeTo(wideZoom(110), 1e-9), reason: type);
        expect(fast.tilt, greaterThanOrEqualTo(AutoTilt.cruise), reason: type);
        final slow = at(40, 100, type: type, modifier: 'slight right', afterM: 3000);
        expect(slow.zoom, greaterThan(wideZoom(40) + 1), reason: '$type in town');
      }
    });

    test('the closer the turn, the closer the camera, never a jump', () {
      for (final kmh in [30.0, 50.0, 90.0, 130.0]) {
        var last = at(kmh, 6000);
        for (var d = 5999.0; d >= 0; d -= 1) {
          final aim = at(kmh, d);
          expect(aim.zoom, greaterThanOrEqualTo(last.zoom - 1e-9), reason: '$kmh km/h, $d m');
          expect(aim.zoom - last.zoom, lessThan(0.02), reason: 'a metre moves the view a little');
          expect((aim.tilt - last.tilt).abs(), lessThan(0.2), reason: 'and tilts it a little');
          last = aim;
        }
      }
    });

    test('a fast road starts closing in further from the maneuver', () {
      double start(double kmh) {
        for (var d = 6000.0; d >= 0; d -= 5) {
          if (at(kmh, d, type: 'roundabout').zoom > wideZoom(kmh) + 0.01) return d;
        }
        return 0;
      }

      expect(start(30), inInclusiveRange(350, 550));
      expect(start(130), inInclusiveRange(1200, 2000));
    });

    test('a road that only changes its name counts as far as the maneuver after it', () {
      final named = at(50, 40, type: 'new name', modifier: 'straight', afterM: 900);
      expect(named.zoom, closeTo(at(50, 940).zoom, 1e-9));
      expect(
        at(50, 40, type: 'continue', modifier: 'straight', afterM: 50).zoom,
        greaterThan(16.5),
      );
      expect(at(50, 40, type: 'continue', modifier: 'straight').zoom, closeTo(wideZoom(50), 1e-9));
      expect(at(50, 40, type: 'continue', modifier: 'slight left').zoom, greaterThan(wideZoom(50)));
      expect(at(50, 40, type: 'roundabout').zoom, greaterThan(wideZoom(50)));
      expect(at(50, 40, type: 'arrive', modifier: 'left').zoom, greaterThan(wideZoom(50)));
    });

    test('off the route, with no maneuver, between the bounds of the speed', () {
      final aim = at(90, null);
      expect(aim.zoom, inExclusiveRange(wideZoom(90), closeZoom(90)));
      expect(aim.tilt, AutoTilt.cruise);
    });
  });

  group('the tilt', () {
    test('toward the horizon down a long straight, cruising otherwise', () {
      expect(at(130, 8000, type: 'roundabout').tilt, AutoTilt.straight);
      final cruising = at(50, 330);
      expect(cruising.zoom, greaterThan(wideZoom(50) + 0.5));
      expect(cruising.tilt, AutoTilt.cruise);
    });

    test('flatter over a junction close by, flattest over a roundabout', () {
      expect(at(40, 100, type: 'roundabout').tilt, AutoTilt.roundabout);
      expect(at(40, 100).tilt, AutoTilt.junction);
      expect(
        at(40, 200, type: 'roundabout').tilt,
        inExclusiveRange(AutoTilt.roundabout, AutoTilt.cruise),
      );
      expect(at(40, 20, type: 'arrive').tilt, AutoTilt.cruise, reason: 'the arrival keeps it');
    });
  });

  test('the zoom and the tilt stay within the bounds the camera follows in', () {
    for (final kmh in [0.0, 30.0, 200.0]) {
      for (final d in [0.0, 50.0, 100000.0]) {
        final aim = at(kmh, d);
        expect(aim.zoom, inInclusiveRange(AutoZoom.minZoom, AutoZoom.maxZoom));
        expect(aim.tilt, inInclusiveRange(AutoTilt.roundabout, AutoTilt.straight));
      }
    }
  });
}
