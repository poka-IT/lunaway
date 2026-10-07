import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/presentation/place_placement.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

void main() {
  group('what a tap reaches', () {
    // A pin whose drawn edge is 18 px from the tap: outside a mouse's
    // tolerance (14), inside the reach of a free point (21).
    String? pinAt18(double tolerance) => tolerance >= 18 ? 'pin' : null;

    test('from the street, a near miss reaches the pin rather than the bare map', () {
      final asked = <double>[];
      final hit = hitAroundTap(
        (t) {
          asked.add(t);
          return pinAt18(t);
        },
        tolerance: 14,
        zoom: 15,
      );
      expect(hit, 'pin');
      expect(asked, [14, 14 * FreeTap.wider]);
      expect(FreeTap.wider, 1.5);
    });

    test('a pin within the tolerance is taken without looking further', () {
      final asked = <double>[];
      final hit = hitAroundTap(
        (t) {
          asked.add(t);
          return 'pin at $t';
        },
        tolerance: 14,
        zoom: 15,
      );
      expect(hit, 'pin at 14.0');
      expect(asked, [14]);
    });

    test('further out than the street, the tolerance of a selection alone', () {
      final asked = <double>[];
      final hit = hitAroundTap(
        (t) {
          asked.add(t);
          return pinAt18(t);
        },
        tolerance: 14,
        zoom: 13,
      );
      expect(hit, isNull, reason: 'a click there does no more than before');
      expect(asked, [14]);
    });
  });

  group('a tap on the marks of a route', () {
    // The destination's badge, its centre 11 px from the tap.
    final destination = HitCandidate(
      layer: RouteLayers.badgesOf(RouteLayers.anchorsSource),
      properties: const {'kind': 'destination', 'mark': 'destination', 'size': 1},
      points: const [Offset(110, 104)],
    );

    test('every mark is a target: a tap beside the destination is no tap on bare map', () {
      final hit = nearestHit(
        const Offset(100, 100),
        [destination],
        shapes: routeHitShapes,
        zoom: 0,
        tolerance: 22,
      );
      expect(hit, isNotNull);
    });
  });

  group('a tap on bare map', () {
    test('opens a point from street level only', () {
      expect(bareTapAt(zoom: 13.9, open: false), BareTap.nothing);
      expect(bareTapAt(zoom: 14, open: false), BareTap.freePoint);
      expect(bareTapAt(zoom: 18, open: false), BareTap.freePoint);
    });

    test('closes what is open first, at any zoom', () {
      expect(bareTapAt(zoom: 16, open: true), BareTap.close);
      expect(bareTapAt(zoom: 5, open: true), BareTap.close);
    });
  });

  group('the double tap window', () {
    test('the screen waits for mouse clicks only: the engines wait for fingers', () {
      Duration on(TargetPlatform p, {bool web = false, PointerKind pointer = PointerKind.touch}) =>
          FreeTap.doubleTapWindowFor(web: web, platform: p, pointer: pointer);
      expect(on(TargetPlatform.android), Duration.zero);
      expect(on(TargetPlatform.iOS), Duration.zero);
      expect(on(TargetPlatform.android, web: true), Duration.zero, reason: 'zoomedAfterTap');
      expect(
        on(TargetPlatform.android, web: true, pointer: PointerKind.mouse),
        FreeTap.doubleTapWindow,
      );
      expect(on(TargetPlatform.macOS, pointer: PointerKind.mouse), FreeTap.doubleTapWindow);
      expect(on(TargetPlatform.windows, pointer: PointerKind.mouse), FreeTap.doubleTapWindow);
    });

    // A bare tap with a finger in the browser, at zoom 15 on the lake.
    const lake = LatLng(45.8992, 6.1294);

    bool? standsAfter(
      FakeAsync time, {
      required ({LatLng center, double zoom})? Function() camera,
      bool Function()? superseded,
      void Function()? meanwhile,
    }) {
      bool? stands;
      unawaited(
        touchTapStands(
          camera: () async => camera(),
          center: lake,
          zoom: 15,
          superseded: superseded ?? () => false,
        ).then((v) => stands = v),
      );
      time.elapse(const Duration(milliseconds: 450));
      meanwhile?.call();
      time.elapse(FreeTap.touchDoubleTapWait);
      return stands;
    }

    test('a second tap held 150 ms after 450 ms: its zoom still drops the first', () {
      fakeAsync((time) {
        var zoom = 15.0;
        final stands = standsAfter(
          time,
          camera: () => (center: lake, zoom: zoom),
          // The second tap ends at 600 ms: GL JS starts its zoom.
          meanwhile: () => zoom = 15.1,
        );
        expect(stands, isFalse);
        expect(FreeTap.touchDoubleTapWait, greaterThan(const Duration(milliseconds: 600)));
      });
    });

    test('a single tap with a finger: the camera stays, the tap stands', () {
      fakeAsync((time) {
        expect(standsAfter(time, camera: () => (center: lake, zoom: 15)), isTrue);
      });
    });

    test('a pin tapped meanwhile: the bare tap gives way', () {
      fakeAsync((time) {
        var taps = 1;
        final stands = standsAfter(
          time,
          camera: () => (center: lake, zoom: 15),
          superseded: () => taps != 1,
          meanwhile: () => taps++,
        );
        expect(stands, isFalse, reason: 'the card of the pin must not close');
      });
    });

    test('a pan begun at once: the tap was the start of a drag', () {
      fakeAsync((time) {
        // About 50 px at zoom 15.
        var center = lake;
        final stands = standsAfter(
          time,
          camera: () => (center: center, zoom: 15),
          meanwhile: () => center = const LatLng(45.8992, 6.1305),
        );
        expect(stands, isFalse);
      });
    });

    test('a camera that cannot be read lets the tap stand', () {
      fakeAsync((time) {
        expect(standsAfter(time, camera: () => throw StateError('gone')), isTrue);
      });
    });

    test('a single tap acts once the window has passed, not before', () {
      fakeAsync((time) {
        final gate = DoubleTapGate();
        var acted = 0;
        gate.tap(() => acted++);
        time.elapse(const Duration(milliseconds: 200));
        expect(acted, 0, reason: 'a second tap may still come');
        time.elapse(const Duration(milliseconds: 60));
        expect(acted, 1);
      });
    });

    test('a second tap within the window is a double tap: nothing acts', () {
      fakeAsync((time) {
        final gate = DoubleTapGate();
        var acted = 0;
        gate.tap(() => acted++);
        time.elapse(const Duration(milliseconds: 120));
        gate.tap(() => acted++);
        time.elapse(const Duration(seconds: 1));
        expect(acted, 0);
      });
    });

    test('two taps further apart act both', () {
      fakeAsync((time) {
        final gate = DoubleTapGate();
        var acted = 0;
        gate.tap(() => acted++);
        time.elapse(const Duration(milliseconds: 400));
        gate.tap(() => acted++);
        time.elapse(const Duration(milliseconds: 400));
        expect(acted, 2);
      });
    });

    test('a pin tapped meanwhile drops the waiting tap', () {
      fakeAsync((time) {
        var acted = 0;
        DoubleTapGate()
          ..tap(() => acted++)
          ..cancel();
        time.elapse(const Duration(seconds: 1));
        expect(acted, 0);
      });
    });
  });

  group('the place a new one may duplicate', () {
    PlaceSummary at(String id, double lat, double lon) => PlaceSummary(
      id: id,
      kind: PlaceKind.parking,
      lat: lat,
      lon: lon,
      overnight: OvernightStatus.unknown,
    );

    const spot = LatLng(45.8992, 6.1294);

    test('the nearest within 50 m, with its distance', () {
      final found = nearestPlace([
        at('far', 45.8997, 6.1294),
        at('near', 45.89947, 6.1294),
        at('nearer', 45.89935, 6.1294),
      ], spot);
      expect(found?.place.id, 'nearer');
      expect(found!.metres, closeTo(16.7, 0.5));
    });

    test('none past 50 m', () {
      expect(nearestPlace([at('far', 45.89966, 6.1294)], spot), isNull);
    });
  });
}
