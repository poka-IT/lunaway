import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/presentation/place_placement.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

void main() {
  group('the features a tap reaches', () {
    test('a near miss reaches the pin rather than the bare map', () async {
      // The pin's edge is 18 px from the tap: outside the square of a
      // selection, inside the wider one of a free point.
      final asked = <double>[];
      final found = await featuresAroundTap((slop) async {
        asked.add(slop);
        return slop >= 18 ? ['pin'] : const <String>[];
      }, zoom: 15);
      expect(found, ['pin']);
      expect(asked, [MapHit.select, MapHit.freePoint]);
      expect(MapHit.freePoint, MapHit.select * 1.5);
    });

    test('a pin under the finger is taken without looking further', () async {
      final asked = <double>[];
      final found = await featuresAroundTap((slop) async {
        asked.add(slop);
        return ['pin at $slop'];
      }, zoom: 15);
      expect(found, ['pin at ${MapHit.select}']);
      expect(asked, [MapHit.select]);
    });

    test('nothing in the wider square: the map is bare there', () async {
      expect(await featuresAroundTap((_) async => const <String>[], zoom: 15), isEmpty);
    });

    test('further out than the street, the square of a selection alone', () async {
      final asked = <double>[];
      final found = await featuresAroundTap((slop) async {
        asked.add(slop);
        return slop >= 18 ? ['dot'] : const <String>[];
      }, zoom: 13);
      expect(found, isEmpty, reason: 'a click there does no more than before');
      expect(asked, [MapHit.select]);
    });
  });

  group('a tap on the marks of a route', () {
    test('opens the first mark that has a card', () {
      expect(markTapFor([null, 'place:lake', 'stop:1']), (open: 'place:lake'));
    });

    test('on the destination or a warning, does nothing: no bare map there', () {
      expect(markTapFor([null]), (open: null));
    });

    test('with no mark under it, looks further', () {
      expect(markTapFor(const []), isNull);
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
    test('the app waits on GL JS only: the native engines wait themselves', () {
      Duration on(TargetPlatform p, {bool web = false}) =>
          MapHit.doubleTapWindowFor(web: web, platform: p);
      expect(on(TargetPlatform.android), Duration.zero);
      expect(on(TargetPlatform.iOS), Duration.zero);
      expect(on(TargetPlatform.android, web: true), MapHit.doubleTapWindow);
      expect(on(TargetPlatform.macOS), MapHit.doubleTapWindow);
      expect(on(TargetPlatform.windows), MapHit.doubleTapWindow);
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
