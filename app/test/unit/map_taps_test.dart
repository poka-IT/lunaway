import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    // tolerance (14), inside the reach of a free point (28).
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
    });

    test(
      'a finger 40 px from a pin still reaches it: a point drops beyond twice the tolerance',
      () {
        // A finger's tolerance is 22: 33 at one and a half times, 44 at twice.
        String? pinAt40(double tolerance) => tolerance >= 40 ? 'pin' : null;
        expect(hitAroundTap(pinAt40, tolerance: 22, zoom: 15), 'pin');
        String? pinAt45(double tolerance) => tolerance >= 45 ? 'pin' : null;
        expect(hitAroundTap(pinAt45, tolerance: 22, zoom: 15), isNull, reason: 'bare map');
      },
    );

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
      layer: RouteLayers.badgesOf(RouteLayers.endsSource),
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
    test('opens a point from street level only, with nothing open', () {
      expect(bareTapAt(zoom: 13.9, open: OpenOnMap.nothing), BareTap.nothing);
      expect(bareTapAt(zoom: 14, open: OpenOnMap.nothing), BareTap.freePoint);
      expect(bareTapAt(zoom: 18, open: OpenOnMap.nothing), BareTap.freePoint);
    });

    test('keeps what the user chose at any zoom, and drops no point over it', () {
      expect(bareTapAt(zoom: 16, open: OpenOnMap.chosen), BareTap.keep);
      expect(bareTapAt(zoom: 5, open: OpenOnMap.chosen), BareTap.keep);
    });

    test('takes a free point away at any zoom', () {
      expect(bareTapAt(zoom: 16, open: OpenOnMap.freePoint), BareTap.close);
      expect(bareTapAt(zoom: 5, open: OpenOnMap.freePoint), BareTap.close);
    });
  });

  group('a tap the user meant', () {
    const at = Offset(200, 300);
    var pointer = 0;

    /// A press and its release at [to] with [kind], one pointer.
    void tap(
      MapTapGuard guard, {
      Offset to = at,
      PointerDeviceKind kind = PointerDeviceKind.touch,
      bool sheetMoving = false,
    }) {
      final p = ++pointer;
      guard.down(
        PointerDownEvent(pointer: p, position: at, kind: kind),
        sheetMoving: sheetMoving,
      );
      if (to != at) guard.move(PointerMoveEvent(pointer: p, position: to, kind: kind));
      guard.up(PointerUpEvent(pointer: p, position: to, kind: kind));
    }

    /// A finger dragged 120 px across the map and lifted.
    void drag(MapTapGuard guard) => tap(guard, to: at + const Offset(120, 0));

    const lyon = LatLng(45.76, 4.83);
    const further = LatLng(45.77, 4.84);

    test('before the app hears any pointer, a tap stands: an engine whose pointers it does '
        'not see keeps its taps', () {
      expect(MapTapGuard().stands, isTrue);
    });

    test('a finger down and up in place is a tap', () {
      final guard = MapTapGuard();
      tap(guard);
      expect(guard.stands, isTrue);
      guard.dispose();
    });

    test('a finger that moved past the touch slop drags: no tap', () {
      final guard = MapTapGuard();
      tap(guard, to: at + const Offset(kTouchSlop - 1, 0));
      expect(guard.stands, isTrue, reason: 'a finger trembles');
      tap(guard, to: at + const Offset(kTouchSlop + 1, 0));
      expect(guard.stands, isFalse);
      guard.dispose();
    });

    test("a mouse moved more than MapLibre's click tolerance drags: no click", () {
      final guard = MapTapGuard();
      tap(guard, to: at + const Offset(2, 0), kind: PointerDeviceKind.mouse);
      expect(guard.stands, isTrue);
      tap(guard, to: at + const Offset(4, 0), kind: PointerDeviceKind.mouse);
      expect(guard.stands, isFalse);
      guard.dispose();
    });

    test('two fingers zoom: no tap', () {
      final guard = MapTapGuard()
        ..down(const PointerDownEvent(pointer: 91, position: at))
        ..down(const PointerDownEvent(pointer: 92, position: Offset(260, 300)))
        ..up(const PointerUpEvent(pointer: 92, position: Offset(260, 300)))
        ..up(const PointerUpEvent(pointer: 91, position: at));
      expect(guard.stands, isFalse);
      guard.dispose();
    });

    test('the touch that stops a fling is no tap, nor one within 500 ms of its end', () {
      fakeAsync((time) {
        final guard = MapTapGuard()..rested(lyon, 15);
        time.elapse(const Duration(seconds: 1));
        drag(guard);
        // The map still glides: the finger that stops it.
        time.elapse(const Duration(milliseconds: 700));
        tap(guard);
        expect(guard.stands, isFalse, reason: 'it stopped the fling');
        guard.rested(further, 15);
        time.elapse(const Duration(milliseconds: 400));
        tap(guard);
        expect(guard.stands, isFalse, reason: '400 ms after the rest');
        time.elapse(const Duration(milliseconds: 200));
        tap(guard);
        expect(guard.stands, isTrue, reason: '600 ms after the rest');
        guard.dispose();
      });
    });

    test('a rest the engine reports before the app hears the release ends the drag', () {
      fakeAsync((time) {
        final guard = MapTapGuard()
          ..down(const PointerDownEvent(pointer: 81, position: at))
          ..move(const PointerMoveEvent(pointer: 81, position: Offset(320, 300)))
          ..rested(further, 15)
          ..up(const PointerUpEvent(pointer: 81, position: Offset(320, 300)));
        time.elapse(const Duration(milliseconds: 600));
        tap(guard);
        expect(guard.stands, isTrue, reason: 'no rest is left to wait for');
        guard.dispose();
      });
    });

    test('an engine that never reports the rest holds the taps a bounded time', () {
      fakeAsync((time) {
        final guard = MapTapGuard();
        drag(guard);
        time.elapse(FreeTap.restWait - const Duration(milliseconds: 100));
        tap(guard);
        expect(guard.stands, isFalse);
        time.elapse(const Duration(milliseconds: 100) + FreeTap.motionQuiet);
        tap(guard);
        expect(guard.stands, isTrue);
        guard.dispose();
      });
    });

    test('a camera that moved by itself (a double tap, a flight) holds the taps 500 ms; '
        'the same camera reported again does not', () {
      fakeAsync((time) {
        final guard = MapTapGuard()..rested(lyon, 15);
        time.elapse(const Duration(seconds: 1));
        guard.rested(lyon, 15);
        tap(guard);
        expect(guard.stands, isTrue, reason: 'the camera did not move');
        guard.rested(lyon, 16);
        time.elapse(const Duration(milliseconds: 300));
        tap(guard);
        expect(guard.stands, isFalse, reason: 'the zoom just ended');
        guard.dispose();
      });
    });

    test('the wheel moves the map: a click within its rest is no tap', () {
      fakeAsync((time) {
        final guard = MapTapGuard()..scrolled();
        tap(guard, kind: PointerDeviceKind.mouse);
        expect(guard.stands, isFalse);
        guard.dispose();
      });
    });

    test('a press while a sheet moves over the map is no tap', () {
      final guard = MapTapGuard();
      tap(guard, sheetMoving: true);
      expect(guard.stands, isFalse);
      tap(guard);
      expect(guard.stands, isTrue);
      guard.dispose();
    });

    test('a tap reported after its release still answers for it once a new press is down', () {
      final guard = MapTapGuard();
      drag(guard);
      tap(guard);
      guard.down(const PointerDownEvent(pointer: 71, position: at));
      expect(guard.stands, isFalse, reason: 'the answer of the last gesture that ended');
      guard.dispose();
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
