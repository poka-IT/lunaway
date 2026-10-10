import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// A phone's guidance map under its banner, beside its buttons, over its
/// bar.
const _phone = Size(390, 760);
const _clear = EdgeInsets.fromLTRB(0, 200, 72, 140);

const RichCamera _following = (target: LatLng(45.8992, 6.1294), zoom: 16.7, bearing: 270, tilt: 55);

/// [camera] with its target [northM] metres further north.
RichCamera _moved(RichCamera camera, {double northM = 0, double? zoom, double? bearing}) => (
  target: LatLng(camera.target.lat + northM / 111195, camera.target.lon),
  zoom: zoom ?? camera.zoom,
  bearing: bearing ?? camera.bearing,
  tilt: camera.tilt,
);

void main() {
  test('no place outside the part of the map asked about can carry a mark', () {
    final rect = richQueryRect(_phone, _clear);
    expect(rect, const Rect.fromLTRB(0, 200, 318, 620));
    final candidates = [
      for (var x = 0.0; x <= _phone.width; x += 6)
        for (var y = 0.0; y <= _phone.height; y += 6)
          RichCandidate(
            id: '$x,$y',
            at: Offset(x, y),
            place: PlaceSummary(
              id: '$x,$y',
              kind: PlaceKind.motorhomeArea,
              lat: 45,
              lon: 4,
              overnight: OvernightStatus.allowed,
            ),
          ),
    ];
    final refused = <String, RichRefusal>{};
    chooseRichMarks(
      candidates,
      const RichFrame(size: _phone, limit: 10000, clear: _clear),
      refused: refused,
    );
    final allowed = candidates.where((c) => !refused.containsKey(c.id)).toList();
    expect(allowed, isNotEmpty);
    for (final c in allowed) {
      expect(rect.contains(c.at), isTrue, reason: '${c.id} stands outside');
    }
  });

  group('the places found stand while the camera stays near', () {
    test('a vehicle that drove 20 m in two seconds keeps them', () {
      expect(
        tilePlacesStillHold(
          then: _following,
          now: _moved(_following, northM: 20),
          age: const Duration(seconds: 2),
          size: _phone,
        ),
        isTrue,
      );
    });

    test('they are asked again after a while, or once the camera moved a fifth of the view', () {
      expect(
        tilePlacesStillHold(
          then: _following,
          now: _following,
          age: tilePlacesKept + const Duration(milliseconds: 1),
          size: _phone,
        ),
        isFalse,
      );
      // 390 px at zoom 16.7 and 45.9 degrees cover about 200 m.
      expect(
        tilePlacesStillHold(
          then: _following,
          now: _moved(_following, northM: 60),
          age: Duration.zero,
          size: _phone,
        ),
        isFalse,
      );
    });

    test('a zoom, a turn or a tilt asks them again; a turn across north is a small one', () {
      bool holds(RichCamera now) =>
          tilePlacesStillHold(then: _following, now: now, age: Duration.zero, size: _phone);
      expect(holds(_moved(_following, zoom: 15.5)), isFalse);
      expect(holds(_moved(_following, bearing: 310)), isFalse);
      expect(holds((target: _following.target, zoom: 16.7, bearing: 270, tilt: 0)), isFalse);
      const north = (target: LatLng(45.8992, 6.1294), zoom: 16.7, bearing: 355.0, tilt: 55.0);
      expect(
        tilePlacesStillHold(
          then: north,
          now: (target: north.target, zoom: 16.7, bearing: 5, tilt: 55),
          age: Duration.zero,
          size: _phone,
        ),
        isTrue,
      );
    });
  });
}
