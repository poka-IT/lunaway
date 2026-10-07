import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';

void main() {
  // A phone's map under the guidance's banner and bar.
  const size = Size(400, 800);
  const padding = EdgeInsets.only(top: 220, bottom: 140);

  group('where following draws the vehicle', () {
    test('low in the free part of the map, centred across it', () {
      // 440 px free: the centre 45 % of the way down them, then the middle
      // of what is left (220 + 198 + (800 - 418 - 140) / 2).
      expect(followInsets(size, padding), const EdgeInsets.fromLTRB(0, 418, 0, 140));
      expect(followAnchor(size, padding), const Offset(200, 539));
    });

    test('a panel on the side moves it across', () {
      expect(followAnchor(size, const EdgeInsets.only(left: 100)).dx, 250);
    });
  });

  group('the magnet', () {
    final anchor = followAnchor(size, padding);
    FreeView view({Offset? vehicle, double zoom = 17, double bearing = 90, double tilt = 55}) =>
        FreeView(size: size, vehicle: vehicle ?? anchor, zoom: zoom, bearing: bearing, tilt: tilt);
    bool holds(FreeView v) =>
        magnetHolds(v, padding: padding, followZoom: 17, course: 90, followTilt: 55);

    test('snaps a view brought back within 15 % of the shorter side', () {
      // 15 % of 400 px.
      expect(holds(view(vehicle: anchor + const Offset(59, 0))), isTrue);
      expect(holds(view(vehicle: anchor + const Offset(0, -59))), isTrue);
    });

    test('leaves a view further away', () {
      expect(holds(view(vehicle: anchor + const Offset(61, 0))), isFalse);
      expect(holds(view(vehicle: anchor + const Offset(45, 45))), isFalse);
    });

    test('leaves a view zoomed more than one level away', () {
      expect(holds(view(zoom: 16)), isTrue);
      expect(holds(view(zoom: 18.2)), isFalse);
      expect(holds(view(zoom: 15.5)), isFalse);
    });

    test('leaves a map turned or tilted on purpose', () {
      expect(holds(view(bearing: 105)), isTrue);
      expect(holds(view(bearing: 130)), isFalse);
      expect(holds(view(tilt: 45)), isTrue);
      expect(holds(view(tilt: 0)), isFalse);
    });

    test('reads a turn the short way round', () {
      expect(
        magnetHolds(
          FreeView(size: size, vehicle: anchor, zoom: 17, bearing: 355, tilt: 55),
          padding: padding,
          followZoom: 17,
          course: 8,
          followTilt: 55,
        ),
        isTrue,
      );
    });

    test('never snaps without a vehicle on the map', () {
      expect(
        holds(const FreeView(size: size, vehicle: null, zoom: 17, bearing: 90, tilt: 55)),
        isFalse,
      );
    });
  });
}
