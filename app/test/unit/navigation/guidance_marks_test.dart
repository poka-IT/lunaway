import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// A phone's guidance map: 390 x 760, the banner over its top 200 px, the
/// buttons' column over its right 72 px, the bar over its bottom 140 px,
/// the vehicle low in the middle, the road going up the screen from it.
const _phone = Size(390, 760);
const _clear = EdgeInsets.fromLTRB(0, 200, 72, 140);
const _vehicle = Offset(195, 560);
const _road = [Offset(195, 560), Offset(195, 380)];

RichFrame _frame({int limit = 4, List<Offset> path = _road, Offset? vehicle = _vehicle}) =>
    RichFrame(size: _phone, limit: limit, clear: _clear, vehicle: vehicle, path: path);

PlaceSummary _place(String id, {double? rating, double? price}) => PlaceSummary(
  id: id,
  kind: PlaceKind.motorhomeArea,
  lat: 45,
  lon: 4,
  overnight: OvernightStatus.allowed,
  ratingForFilters: rating,
  priceParkingEur: price,
);

RichCandidate _at(
  String id,
  Offset at, {
  double aheadM = 300,
  double offRouteM = 40,
  double fromVehicleM = 300,
  double? rating,
}) => RichCandidate(
  id: id,
  at: at,
  place: _place(id, rating: rating),
  aheadM: aheadM,
  offRouteM: offRouteM,
  fromVehicleM: fromVehicleM,
);

List<String> _ids(List<RichPick> picks) => [for (final p in picks) p.id];

void main() {
  group('the marks keep what driving needs clear', () {
    test('a place in the open part of the map, beside the road, stands out', () {
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks([_at('a', const Offset(80, 420))], _frame(), refused: refused);
      expect(_ids(picks), ['a'], reason: '$refused');
    });

    test('none under the banner, the buttons or the bar, nor past the edge', () {
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks(
        [
          // Its head would reach up under the banner.
          _at('banner', const Offset(80, 240)),
          // Under the buttons' column.
          _at('buttons', const Offset(340, 420)),
          // Its tip on the bar.
          _at('bar', const Offset(80, 640)),
          _at('edge', const Offset(10, 420)),
        ],
        _frame(),
        refused: refused,
      );
      expect(picks, isEmpty);
      expect(refused.values.toSet(), {RichRefusal.covered});
    });

    test('none under the buttons, but at the edge of the map above them', () {
      const column = Rect.fromLTRB(318, 330, 390, 620);
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks(
        [_at('beside-buttons', const Offset(330, 420)), _at('above', const Offset(330, 300))],
        const RichFrame(
          size: _phone,
          limit: 4,
          clear: EdgeInsets.fromLTRB(0, 200, 0, 140),
          obstacles: [column],
          vehicle: _vehicle,
          path: _road,
        ),
        refused: refused,
      );
      expect(_ids(picks), ['above']);
      expect(refused, {'beside-buttons': RichRefusal.covered});
    });

    test('none on the vehicle nor around it', () {
      final refused = <String, RichRefusal>{};
      chooseRichMarks(
        [_at('beside', const Offset(150, 600), aheadM: 0, fromVehicleM: 30)],
        _frame(path: const []),
        refused: refused,
      );
      expect(refused, {'beside': RichRefusal.vehicle});
    });

    test('none on the road just ahead, but one beside it', () {
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks(
        [_at('on', const Offset(205, 470)), _at('beside', const Offset(90, 470))],
        _frame(),
        refused: refused,
      );
      expect(_ids(picks), ['beside']);
      expect(refused, {'on': RichRefusal.path});
    });

    test('farther ahead, beside the road but never on its line', () {
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks(
        [
          // Its head over the line at 300, past the stretch kept clear.
          _at('on-line', const Offset(205, 300), aheadM: 600),
          // Its head and badge 12 px clear of the line.
          _at('beside-line', const Offset(150, 300), aheadM: 600),
        ],
        const RichFrame(
          size: _phone,
          limit: 4,
          clear: _clear,
          vehicle: _vehicle,
          path: _road,
          line: [Offset(195, 380), Offset(195, 220)],
        ),
        refused: refused,
      );
      expect(_ids(picks), ['beside-line']);
      expect(refused, {'on-line': RichRefusal.path});
    });

    test("a place at the roadside may brush the casing, the line's middle in sight", () {
      const line = [Offset(195, 380), Offset(195, 220)];
      RichFrame frame() => const RichFrame(
        size: _phone,
        limit: 4,
        clear: _clear,
        vehicle: _vehicle,
        path: _road,
        line: line,
      );
      // Left of the road, its disc and badge end 3 px short of the line's
      // middle.
      final left = _at('left', const Offset(162.4, 300), aheadM: 600);
      expect(left.geometry(52).face(left.at).right, closeTo(192, 0.5));
      expect(_ids(chooseRichMarks([left], frame())), ['left']);
      // Right of the road, the disc 3 px off: the badge stands on the far
      // side, the wider box kept between marks reaches over the line.
      final right = _at('right', const Offset(224, 300), aheadM: 600);
      expect(right.geometry(52).face(right.at).left, closeTo(198, 0.5));
      expect(right.geometry(52).bounds(right.at).left, lessThan(195));
      expect(_ids(chooseRichMarks([right], frame())), ['right']);
      expect(chooseRichMarks([_at('over', const Offset(190, 300), aheadM: 600)], frame()), isEmpty);
    });

    test('a road that turns is followed, not a straight line', () {
      // The road turns right at 450: a place left of the turn, clear of the
      // straight line ahead, lies on the road after the turn.
      final refused = <String, RichRefusal>{};
      chooseRichMarks(
        [_at('after-turn', const Offset(260, 470))],
        _frame(path: const [Offset(195, 560), Offset(195, 480), Offset(300, 470)]),
        refused: refused,
      );
      expect(refused, {'after-turn': RichRefusal.path});
    });

    test('a place passed is behind the driver', () {
      final refused = <String, RichRefusal>{};
      chooseRichMarks(
        [_at('passed', const Offset(80, 420), aheadM: -120)],
        _frame(),
        refused: refused,
      );
      expect(refused, {'passed': RichRefusal.behind});
    });
  });

  group('the few that stand out', () {
    test('at most the limit, the others left small pins', () {
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks(
        [for (var i = 0; i < 4; i++) _at('l$i', Offset(60, 280 + i * 70.0), aheadM: 100.0 * i)],
        _frame(limit: 2),
        refused: refused,
      );
      expect(_ids(picks), ['l0', 'l1']);
      expect(refused, {'l2': RichRefusal.limit, 'l3': RichRefusal.limit});
    });

    test('ahead first, then near the route, then the better rated', () {
      final picks = chooseRichMarks([
        _at('far-ahead', const Offset(60, 300), aheadM: 2500),
        _at('off-route', const Offset(60, 380), offRouteM: 900),
        _at('well-rated', const Offset(60, 460), rating: 4.6),
        _at('plain', const Offset(250, 300)),
      ], _frame(limit: 2, path: const []));
      expect(_ids(picks), ['well-rated', 'plain']);
    });

    test('two that would overlap: the better one alone', () {
      final refused = <String, RichRefusal>{};
      final picks = chooseRichMarks(
        [_at('a', const Offset(80, 420), rating: 4.5), _at('b', const Offset(95, 430), rating: 3)],
        _frame(),
        refused: refused,
      );
      expect(_ids(picks), ['a']);
      expect(refused, {'b': RichRefusal.crowded});
    });

    test('a mark already shown keeps its place over an equal newcomer', () {
      final candidates = [
        _at('shown', const Offset(80, 420), aheadM: 340),
        _at('newcomer', const Offset(95, 430)),
      ];
      expect(_ids(chooseRichMarks(candidates, _frame())), ['newcomer']);
      expect(_ids(chooseRichMarks(candidates, _frame(), previous: {'shown'})), ['shown']);
    });

    test('without a vehicle (the preview), the middle of the map comes first', () {
      final picks = chooseRichMarks([
        _at('corner', const Offset(40, 260)),
        _at('middle', const Offset(160, 440)),
      ], const RichFrame(size: _phone, limit: 1, clear: _clear));
      expect(_ids(picks), ['middle']);
    });
  });

  group('their size', () {
    test('52 px near the vehicle, 40 px far, linear between; the middle without one', () {
      expect(RichMarks.phone.at(100), 52);
      expect(RichMarks.phone.at(RichMarks.nearM), 52);
      expect(RichMarks.phone.at(725), 48);
      expect(RichMarks.phone.at(900), 44, reason: 'in steps of 4 px');
      expect(RichMarks.phone.at(5000), 40);
      expect(RichMarks.phone.at(null), 48);
      expect(RichMarks.wide.at(100), greaterThan(RichMarks.phone.at(100)));
    });

    test('a pick carries the size its distance gives', () {
      final picks = chooseRichMarks([
        _at('near', const Offset(60, 420), fromVehicleM: 150),
        _at('far', const Offset(250, 300), fromVehicleM: 1500),
      ], _frame(path: const []));
      expect({for (final p in picks) p.id: p.size}, {'near': 52, 'far': 40});
    });

    test("the engine's perspective is undone: larger below the camera's centre, smaller above", () {
      expect(symbolPerspective(dy: 0, height: 760, pitchDeg: 55), closeTo(1, 1e-9));
      expect(symbolPerspective(dy: 200, height: 760, pitchDeg: 55), greaterThan(1.05));
      expect(symbolPerspective(dy: -200, height: 760, pitchDeg: 55), lessThan(0.95));
      expect(symbolPerspective(dy: 300, height: 760, pitchDeg: 0), 1);
    });

    test('a capsule is wider than a photo by its label, and as tall as three quarters of it', () {
      const photo = RichGeometry(48);
      const capsule = RichGeometry(48, labelWidth: 50, capsule: true);
      expect(capsule.height, 36);
      expect(capsule.width, 86);
      expect(photo.bounds(const Offset(100, 100)).bottom, 100, reason: 'the tip on the place');
      expect(capsule.bounds(const Offset(100, 100)).width, 86);
      // What hides the map: the body and its cream rim; a photo's disc and
      // its badge, without the tail.
      expect(capsule.face(const Offset(100, 100)).width, closeTo(86 + 3.2, 0.01));
      expect(photo.face(const Offset(100, 100)).bottom, lessThan(100));
    });
  });

  group('the road kept clear', () {
    test('120 m at least, the next 8 s at speed, 300 m at most', () {
      expect(immediateM(null), 120);
      expect(immediateM(13.9), 120);
      expect(immediateM(25), 200);
      expect(immediateM(50), 300);
    });

    test('a place beside a straight road: how far ahead and how far off', () {
      final line = [for (var i = 0; i <= 20; i++) LatLng(45 + i * 0.001, 4)];
      // 1 km north of the vehicle at the start, 79 m east of the road.
      final beside = placeAlong(const LatLng(45.009, 4.001), RouteIndex(line), alongM: 0)!;
      expect(beside.aheadM, closeTo(1000, 15));
      expect(beside.offM, closeTo(79, 3));
      final behind = placeAlong(const LatLng(45.00675, 4.0005), RouteIndex(line), alongM: 1000)!;
      expect(behind.aheadM, closeTo(-250, 15));
    });

    test('the way back near the road later does not pull a place to the far side', () {
      // Out north 2 km, then back south 300 m east of the way out.
      final line = [
        for (var i = 0; i <= 20; i++) LatLng(45 + i * 0.001, 4),
        for (var i = 20; i >= 0; i--) LatLng(45 + i * 0.001, 4.004),
      ];
      final place = placeAlong(
        const LatLng(45.01, 4.0035),
        RouteIndex(line),
        alongM: 500,
        windowM: 1500,
      )!;
      expect(place.aheadM, closeTo(612, 30), reason: 'the way out, not the way back');
    });
  });

  group('the route measured once', () {
    final line = [for (var i = 0; i <= 10; i++) LatLng(45 + i * 0.001, 4)];
    final route = RouteIndex(line);

    test('a stretch starts and ends inside its segments, the points between kept', () {
      final stretch = route.stretch(150, 450);
      expect(stretch.first.lat, closeTo(45 + 150 / 111195, 1e-6));
      expect(stretch.last.lat, closeTo(45 + 450 / 111195, 1e-6));
      expect(stretch.sublist(1, stretch.length - 1), [line[2], line[3], line[4]]);
    });

    test('past the end it stops at the end; before the start it starts there', () {
      expect(route.stretch(-100, 50).first, line.first);
      expect(route.stretch(1000, 5000).last, line.last);
      expect(route.stretch(2000, 3000), isEmpty);
      expect(RouteIndex(const []).stretch(0, 10), isEmpty);
    });
  });

  group('the label of an illustrated mark', () {
    test('the price first, then a good rating, then the night, then any rating', () {
      expect(RichLabel.of(_place('a', price: 0)), const FreeLabel());
      expect(RichLabel.of(_place('a', price: 12)), const PriceLabel(12));
      expect(RichLabel.of(_place('a', rating: 4.3)), const RatingLabel(4.3));
      expect(RichLabel.of(_place('a', rating: 2.5)), const NightLabel());
      expect(
        RichLabel.of(
          const PlaceSummary(
            id: 'b',
            kind: PlaceKind.serviceArea,
            lat: 45,
            lon: 4,
            overnight: OvernightStatus.forbidden,
            ratingForFilters: 2.5,
          ),
        ),
        const RatingLabel(2.5),
      );
      expect(
        RichLabel.of(
          const PlaceSummary(
            id: 'c',
            kind: PlaceKind.serviceArea,
            lat: 45,
            lon: 4,
            overnight: OvernightStatus.unknown,
          ),
        ),
        isNull,
      );
      expect(RichLabel.of(_place('a'), priceEur: 8), const PriceLabel(8), reason: "the API's");
    });
  });

  group('the marks step aside for a complex maneuver', () {
    test('a roundabout within 200 m, a fork within 10 s at speed', () {
      expect(richMarksYield(maneuverType: 'roundabout', modifier: 'right', distanceM: 180), isTrue);
      expect(
        richMarksYield(maneuverType: 'roundabout', modifier: 'right', distanceM: 400),
        isFalse,
      );
      expect(
        richMarksYield(maneuverType: 'fork', modifier: 'slight left', distanceM: 280, speedMps: 30),
        isTrue,
      );
      expect(richMarksYield(maneuverType: 'turn', modifier: 'sharp left', distanceM: 120), isTrue);
    });

    test('a plain turn or the road going on leaves them', () {
      expect(richMarksYield(maneuverType: 'turn', modifier: 'right', distanceM: 50), isFalse);
      expect(
        richMarksYield(maneuverType: 'new name', modifier: 'straight', distanceM: 20),
        isFalse,
      );
      expect(richMarksYield(maneuverType: null, modifier: null, distanceM: 10), isFalse);
    });
  });
}
