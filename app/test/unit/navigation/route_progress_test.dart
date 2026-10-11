import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_progress.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';

void main() {
  group('the share of the route behind the vehicle', () {
    // Due north from the Pyrenees to the Channel: a metre near the Channel
    // is a longer step on the map than one near the Pyrenees.
    final line = [for (var i = 0; i <= 100; i++) LatLng(42.5 + i * 0.08, 2.3)];
    final progress = RouteProgress(line);

    test('is counted as the map counts the line, not in metres', () {
      final half = progress.lengthM / 2;
      final share = progress.shareAt(half);
      double y(double lat) {
        final r = lat * math.pi / 180;
        return math.log(math.tan(math.pi / 4 + r / 2));
      }

      // The point half the metres along, then its share of the plane.
      const mid = 42.5 + 8 * 0.5;
      final expected = (y(mid) - y(42.5)) / (y(50.5) - y(42.5));
      expect(share, closeTo(expected, 2e-3));
      expect(share, isNot(closeTo(0.5, 5e-3)), reason: 'a share of the metres would be off');
    });

    test('runs from 0 at the start to 1 at the end, never back', () {
      expect(progress.shareAt(-5), 0);
      expect(progress.shareAt(0), 0);
      expect(progress.shareAt(progress.lengthM + 10), 1);
      var last = 0.0;
      for (var m = 0.0; m <= progress.lengthM; m += 997) {
        final s = progress.shareAt(m);
        expect(s, greaterThanOrEqualTo(last));
        last = s;
      }
    });

    test('cuts a stretch of the line as the slow walk along it does', () {
      for (final (from, to) in [(0.0, 50.0), (1234.5, 4321.0), (88000.0, 99999.0)]) {
        final fast = progress.between(from, to);
        final slow = lineAlong(line, RouteSpan(from, to));
        expect(fast.length, slow.length, reason: '$from to $to');
        for (var i = 0; i < fast.length; i++) {
          expect(fast[i].distanceTo(slow[i]), lessThan(0.01), reason: '$from to $to, point $i');
        }
      }
      expect(progress.between(500, 400), isEmpty);
    });

    test('measures back from a share to the metres', () {
      for (final m in <double>[0, 1234.5, 40000, progress.lengthM]) {
        expect(progress.alongAt(progress.shareAt(m)), closeTo(m, 1e-6), reason: '$m m');
      }
    });

    test('the gradient greys up to a colour of its ramp behind the vehicle, the tail up to it', () {
      final traveled = TraveledLine();
      final lines = [RouteMapLine(index: 0, points: line, selected: true)];
      // 890 km of route: a colour of the ramp is about 3.5 km.
      const at = 300000.0;
      expect(traveled.next(lines, at), isTrue);
      final ramp = traveled.share * gradientRamp;
      expect(ramp, ramp.roundToDouble(), reason: 'on a colour of the ramp');
      final drawn = progress.alongAt(traveled.share);
      expect(drawn, lessThan(at), reason: 'never ahead of the vehicle');
      expect(at - drawn, lessThan(2 * progress.lengthM / gradientRamp), reason: 'nor far behind');
      // The tail covers the rest, from half a colour back, up to the vehicle.
      expect(traveled.tail.first.distanceTo(line.first), lessThan(drawn));
      expect(traveled.tail.last.distanceTo(line.first), closeTo(at, 200));
    });

    test('an engine sends it once the vehicle moved a few metres, keeps it off the route', () {
      final traveled = TraveledLine();
      final lines = [RouteMapLine(index: 0, points: line, selected: true)];
      expect(traveled.next(lines, null), isTrue, reason: 'a new route starts with none');
      expect(traveled.share, 0);
      expect(traveled.tail, isEmpty);
      expect(traveled.next(lines, null), isFalse);
      expect(traveled.next(lines, 100000), isTrue);
      final first = (traveled.share, traveled.tail);
      expect(traveled.next(lines, 100002), isFalse, reason: 'two metres are no call');
      expect(traveled.next(lines, null), isFalse, reason: 'off the route the grey stays');
      expect((traveled.share, traveled.tail), first);
      traveled.forget();
      expect(traveled.next(lines, null), isTrue, reason: 'a new style draws it again');
      expect(traveled.share, first.$1, reason: 'where it was, off the route');
      expect(traveled.next(lines, 100010), isTrue);
      final other = [
        RouteMapLine(index: 0, points: [...line], selected: true),
      ];
      expect(traveled.next(other, null), isTrue);
      expect(traveled.share, 0, reason: 'a new route drops the grey');
    });

    test('the grey is a step at the share, the line coloured past it', () {
      expect(RouteLook.progressGradient('#fill', '#grey', 0.25), [
        'step',
        ['line-progress'],
        '#grey',
        0.25,
        '#fill',
      ]);
      final paint = routeLinePaint(RouteLayers.route, dark: false, traveledShare: 0.4);
      expect((paint['line-gradient']! as List)[3], 0.4);
      expect(
        routeLinePaint(RouteLayers.routeCasing, dark: true, traveledShare: 0.4)['line-gradient'],
        isA<List<Object>>(),
      );
    });
  });

  group("the maneuver's arrow", () {
    // East along a street for 200 m, then north for 200 m.
    const corner = LatLng(45.9, 6.12);
    final east = LatLng(45.9, 6.12 - 200 / (111195 * math.cos(45.9 * math.pi / 180)));
    const north = LatLng(45.9 + 200 / 111195, 6.12);
    final line = [east, corner, north];

    test('runs from a little before the turn to a little after, its head on the new road', () {
      final arrow = arrowForManeuver(line, atM: 200, type: 'turn', modifier: 'left')!;
      expect(arrow.shaft.first.distanceTo(corner), closeTo(30, 0.5));
      expect(arrow.tip.distanceTo(corner), closeTo(30, 0.5));
      expect(arrow.shaft, contains(corner));
      expect(arrow.headCourse, closeTo(0, 0.5), reason: 'pointing north, the way out');
    });

    test('a fork or a ramp, taken at speed, draws a longer arrow', () {
      final arrow = arrowForManeuver(line, atM: 200, type: 'off ramp', modifier: 'slight right')!;
      expect(arrow.shaft.first.distanceTo(corner), closeTo(60, 0.5));
    });

    test('through a roundabout to its exit', () {
      final arrow = arrowForManeuver(
        line,
        atM: 100,
        type: 'roundabout',
        modifier: 'right',
        ringM: 100,
      )!;
      expect(arrow.shaft.first.distanceTo(east), closeTo(70, 0.5));
      expect(arrow.tip.distanceTo(corner), closeTo(25, 0.5), reason: 'the ring, then 25 m out');
    });

    test('none where the road goes on, at the start or at the arrival', () {
      for (final (type, modifier) in [
        ('new name', 'straight'),
        ('continue', 'straight'),
        ('turn', 'straight'),
        ('depart', null),
        ('arrive', 'left'),
        ('notification', null),
      ]) {
        expect(
          arrowForManeuver(line, atM: 200, type: type, modifier: modifier),
          isNull,
          reason: '$type $modifier',
        );
      }
    });

    test('its shaft and head become the map sources, the head turned to its course', () {
      final arrow = arrowForManeuver(line, atM: 200, type: 'turn', modifier: 'left')!;
      final shaft = routeArrowCollection(arrow)['features']! as List;
      expect(shaft, hasLength(1));
      final head = (routeArrowHeadCollection(arrow)['features']! as List).single as Map;
      expect((head['properties'] as Map)['course'], arrow.headCourse);
      expect(routeArrowCollection(null)['features'], isEmpty);
    });
  });
}
