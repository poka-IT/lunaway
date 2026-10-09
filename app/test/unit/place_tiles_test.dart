import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

import '../helpers/style_expressions.dart';

/// A place and the properties the API's tiles give it (`docs/deploy.md`,
/// "Places layer"): domain codes, the services mask, the price class, the
/// height in centimetres. [dots] masks the services to the bits the dots
/// carry.
({PlaceSummary place, double? maxHeightM, Map<String, Object> tile}) _sample(
  Random r, {
  bool dots = false,
}) {
  final kind = PlaceKind.values[r.nextInt(PlaceKind.values.length)];
  final night = OvernightStatus.values[r.nextInt(OvernightStatus.values.length)];
  final services = {
    for (final s in Service.values)
      if (r.nextInt(4) == 0) s,
  };
  final price = switch (r.nextInt(3)) {
    0 => null,
    1 => 0.0,
    _ => (r.nextInt(30) + 1).toDouble(),
  };
  final height = r.nextBool() ? null : 1.8 + r.nextInt(300) / 100;
  // Tenths of a rating, on and around the filter's steps.
  final tenths = r.nextInt(3) == 0 ? null : 10 + r.nextInt(41);
  final season = _randomSeason(r);
  final mask = Service.maskOf(services);
  final place = PlaceSummary(
    id: 'p',
    kind: kind,
    lat: 45,
    lon: 6,
    overnight: night,
    services: services,
    priceParkingEur: price,
    ratingForFilters: tenths == null ? null : tenths / 10,
    openingSeason: season,
  );
  return (
    place: place,
    maxHeightM: height,
    tile: {
      'kind': kind.wire.toLowerCase(),
      'night': night.wire.toLowerCase(),
      's': dots ? mask & 0x1FF : mask,
      'price': ?switch (price) {
        null => null,
        0 => 0,
        _ => 1,
      },
      'h': ?height == null ? null : (height * 100).round(),
      // A pin carries the tenths; a dot the step reached (30, 40 or 45),
      // nothing below 3.
      'r': ?switch (tenths) {
        null => null,
        final t when !dots => t,
        final t when t >= 45 => 45,
        final t when t >= 40 => 40,
        final t when t >= 30 => 30,
        _ => null,
      },
      'o1': ?season?.first.code,
      'o2': ?season?.skip(1).firstOrNull?.code,
    },
  );
}

/// No season, the whole year, one range, or two across the new year, as
/// the server writes them.
List<DayRange>? _randomSeason(Random r) {
  int day() => 1 + r.nextInt(lastDayOfYear);
  switch (r.nextInt(4)) {
    case 0:
      return null;
    case 1:
      return const [DayRange.wholeYear];
    case 2:
      final (a, b) = (day(), day());
      return [DayRange(min(a, b), max(a, b))];
    default:
      final end = 1 + r.nextInt(150);
      return [DayRange(1, end), DayRange(end + 2 + r.nextInt(200), lastDayOfYear)];
  }
}

/// No opening filter, the whole year, or a stay of up to a few weeks from
/// a day of 2026, sometimes across the new year.
OpeningFilter? _randomOpening(Random r) => switch (r.nextInt(3)) {
  0 => null,
  1 => const AllYearOpening(),
  _ => () {
    final arrival = DateTime(2026, 1, 1 + r.nextInt(365));
    return StayOpening(arrival, arrival.add(Duration(days: r.nextInt(30))));
  }(),
};

PlaceFilter _randomFilter(Random r) => PlaceFilter(
  families: {
    for (final f in KindFamily.values)
      if (r.nextInt(3) == 0) f,
  },
  overnight: {
    for (final o in OvernightStatus.values)
      if (r.nextInt(3) == 0) o,
  },
  amenities: {
    for (final a in Amenity.offered)
      if (r.nextInt(5) == 0) a,
  },
  freeOnly: r.nextInt(4) == 0,
  vehicleHeightM: r.nextBool() ? null : 2 + r.nextInt(250) / 100,
  minRating: r.nextBool() ? null : minRatingSteps[r.nextInt(minRatingSteps.length)],
  opening: _randomOpening(r),
);

void main() {
  test('a filter on the tiles keeps exactly what the same filter keeps on the device', () {
    final r = Random(7);
    var kept = 0;
    for (var i = 0; i < 4000; i++) {
      final filter = _randomFilter(r);
      final expression = placeTileFilter(filter);
      for (var j = 0; j < 20; j++) {
        final s = _sample(r);
        final expected = filter.matches(s.place, maxHeightM: s.maxHeightM);
        expect(
          styleFilterKeeps(expression, s.tile),
          expected,
          reason: 'filter ${filter.activeCount} criteria, tile ${s.tile}',
        );
        if (expected) kept++;
      }
    }
    // Neither all nor nothing: the comparison means something.
    expect(kept, inInclusiveRange(1000, 76000));
  });

  test('the dots carry every service a filter can ask for', () {
    // place_dots masks the services to bits 0 to 8: an offered amenity
    // beyond them would hide every dot.
    for (final a in Amenity.offered) {
      for (final s in a.services) {
        expect(s.position, lessThan(9), reason: '${a.name} reads ${s.name}');
      }
    }
    final r = Random(11);
    for (var i = 0; i < 2000; i++) {
      final filter = _randomFilter(r);
      final s = _sample(r, dots: true);
      expect(
        styleFilterKeeps(placeTileFilter(filter), s.tile),
        filter.matches(s.place, maxHeightM: s.maxHeightM),
      );
    }
  });

  test('a minimum rating keeps the features rated at least as high, in tenths', () {
    expect(placeTileFilter(const PlaceFilter(minRating: 4.5)), [
      'all',
      [
        '>=',
        [
          'coalesce',
          ['get', 'r'],
          0,
        ],
        45,
      ],
    ]);
    bool keeps(Map<String, Object> tile) =>
        styleFilterKeeps(placeTileFilter(const PlaceFilter(minRating: 4)), tile);
    expect(keeps({'kind': 'parking', 'r': 40}), isTrue, reason: 'exactly at the step');
    expect(keeps({'kind': 'parking', 'r': 39}), isFalse);
    expect(keeps({'kind': 'parking'}), isFalse, reason: 'a place nobody rated is left out');
  });

  test('an opening filter keeps the places open on its days and those without a season', () {
    bool keeps(PlaceFilter filter, Map<String, Object> tile) =>
        styleFilterKeeps(placeTileFilter(filter), {'kind': 'campsite', ...tile});
    const allYear = PlaceFilter(opening: AllYearOpening());
    expect(keeps(allYear, {}), isTrue, reason: 'no season: its opening is not known by the day');
    expect(keeps(allYear, {'o1': 1366}), isTrue);
    expect(keeps(allYear, {'o1': 92305}), isFalse, reason: 'April to October');
    expect(keeps(allYear, {'o1': 1091, 'o2': 305366}), isFalse, reason: 'closed in summer');

    // Nights of 28 December to 2 January: days 363 to 366 and 1 to 2.
    final newYear = PlaceFilter(opening: StayOpening(DateTime(2026, 12, 28), DateTime(2027, 1, 3)));
    expect(keeps(newYear, {'o1': 1091, 'o2': 305366}), isTrue, reason: 'a winter season');
    expect(keeps(newYear, {'o1': 1091, 'o2': 305365}), isFalse, reason: 'closed on 31 December');
    expect(keeps(newYear, {'o1': 2091, 'o2': 305366}), isFalse, reason: 'closed on 1 January');
    expect(keeps(newYear, {'o1': 92305}), isFalse);
    expect(keeps(newYear, {}), isTrue);

    final october = PlaceFilter(
      opening: StayOpening(DateTime(2026, 10, 12), DateTime(2026, 10, 15)),
    );
    expect(keeps(october, {'o1': 92305}), isTrue);
    expect(keeps(october, {'o1': 92287}), isFalse, reason: 'closes on 13 October');
    expect(keeps(october, {'o1': 1091, 'o2': 288366}), isFalse, reason: 'opens on 14 October');
    expect(keeps(october, {'o1': 1091, 'o2': 286366}), isTrue, reason: 'the second range');
  });

  test('the dots keep the same places as the pins under an opening filter', () {
    final r = Random(19);
    for (var i = 0; i < 2000; i++) {
      final filter = PlaceFilter(opening: _randomOpening(r));
      final s = _sample(r, dots: true);
      expect(styleFilterKeeps(placeTileFilter(filter), s.tile), filter.matches(s.place));
    }
  });

  test('the empty filter keeps every feature', () {
    final r = Random(3);
    for (var i = 0; i < 50; i++) {
      expect(styleFilterKeeps(placeTileFilter(PlaceFilter.none), _sample(r).tile), isTrue);
    }
  });

  test('the expressions use no operator the iOS plugin cannot convert', () {
    final text = [
      placeTileFilter(
        const PlaceFilter(
          families: {KindFamily.nature},
          overnight: {OvernightStatus.allowed},
          amenities: {Amenity.dumpStation, Amenity.water},
          freeOnly: true,
          vehicleHeightM: 3.2,
          opening: AllYearOpening(),
        ),
      ),
      placeTileFilter(
        PlaceFilter(opening: StayOpening(DateTime(2026, 12, 28), DateTime(2027, 1, 3))),
      ),
      placeTilePinImage(),
      placeTileRank(),
    ].toString();
    for (final op in ['to-string', 'concat', 'number-format', '%', 'let', 'var']) {
      expect(text, isNot(contains('[$op,')), reason: op);
    }
  });

  test('each kind and night of a tile draws its own pin', () {
    for (final kind in PlaceKind.values) {
      for (final night in OvernightStatus.values) {
        expect(
          evalStyleExpression(placeTilePinImage(), {
            'kind': kind.wire.toLowerCase(),
            'night': night.wire.toLowerCase(),
          }),
          pinImageId(kind, night),
        );
      }
    }
    expect(
      evalStyleExpression(placeTilePinImage(), {'kind': 'a_future_kind', 'night': 'allowed'}),
      pinImageId(PlaceKind.extraService, OvernightStatus.unknown),
      reason: 'a newer server must not leave a place without a pin',
    );
  });

  test('a night allowed is placed before a night tolerated, and drawn above it', () {
    num rank(OvernightStatus o, {bool placement = false}) =>
        evalStyleExpression(placeTileRank(placement: placement), {'night': o.wire.toLowerCase()})!
            as num;
    expect(rank(OvernightStatus.allowed), greaterThan(rank(OvernightStatus.tolerated)));
    expect(
      rank(OvernightStatus.allowed, placement: true),
      lessThan(rank(OvernightStatus.tolerated, placement: true)),
    );
  });

  test('a tap on a pin opens its place with what the tile says', () {
    final p = placeFromTile(
      {
        'id': 'abc',
        'kind': 'campsite',
        'night': 'day_only',
        's': 1 | 16,
        'price': 0,
        'name': 'Le Pré',
        'city': 'Doussard',
        'r': 33,
        'o1': 1091,
        'o2': 305366,
      },
      [6.1, 45.9],
    );
    expect(p, isNotNull);
    expect(p!.id, 'abc');
    expect(p.kind, PlaceKind.campsite);
    expect(p.overnight, OvernightStatus.dayOnly);
    expect(p.services, {Service.drinkingWater, Service.toilets});
    expect(p.priceParkingEur, 0);
    expect(p.name, 'Le Pré');
    expect(p.city, 'Doussard', reason: 'a row titles a place without a name by its town');
    expect(p.ratingForFilters, 3.3, reason: 'the list filters again on what the tile says');
    expect(p.openingSeason, const [DayRange(1, 91), DayRange(305, 366)]);
    expect((p.lat, p.lon), (45.9, 6.1));
    expect(p.maxHeightM, isNull, reason: 'no height in the tile: no limit');
    expect(placeFromTile({'kind': 'campsite'}, [6.1, 45.9]), isNull, reason: 'a dot has no id');
  });

  test("a vehicle's height keeps, on the device, the places of the tiles it fits under", () {
    PlaceSummary? place(int? cm) =>
        placeFromTile({'id': 'p$cm', 'kind': 'parking', 'night': 'allowed', 'h': ?cm}, [6.1, 45.9]);
    const van = PlaceFilter(fitsMyVehicle: true, vehicleHeightM: 2.9);
    expect(place(210)!.maxHeightM, 2.1);
    expect(van.matches(place(210)!), isFalse, reason: 'a 2.10 m gantry stops a 2.90 m van');
    expect(van.matches(place(290)!), isTrue, reason: 'as the tiles keep h >= 290');
    expect(van.matches(place(null)!), isTrue, reason: 'an unknown height is no limit');
    expect(
      const PlaceFilter(fitsMyVehicle: true, vehicleHeightM: 2.954).matches(place(295)!),
      isTrue,
      reason: 'in whole centimetres, as the tiles keep h >= round(295.4)',
    );
    expect(
      van.matches(place(400)!, maxHeightM: 2.5),
      isFalse,
      reason: 'a height the caller knows wins',
    );
  });

  test("a tap opens a place of the tiles, comes closer to a dot, leaves the map's own alone", () {
    expect(
      placeTileTapFor({'id': 'a', 'kind': 'parking', 'night': 'allowed'}, [6.1, 45.9]),
      isA<OpenTilePlace>().having((t) => t.place.id, 'id', 'a'),
    );
    expect(
      placeTileTapFor(
        {'kind': 'parking', 'night': 'allowed'},
        [
          [6.1, 45.9],
          [6.2, 45.8],
        ],
      ),
      isA<ZoomToTileDot>(),
      reason: 'the dots of the low zooms come as MultiPoints without id',
    );
    expect(
      placeTileTapFor({'id': 'a', 'kind': 'place'}, [6.1, 45.9]),
      isNull,
      reason: "the device's own pins (GeoJSON) are the map's",
    );
    expect(placeTileTapFor({'kind': 'point'}, [6.1, 45.9]), isNull);
    expect(
      placeTileTapFor({'id': 'p1', 'kind': 'fuel_station', 'category': 'fuel'}, [6.1, 45.9]),
      isNull,
      reason: 'a point of interest is left to its own layer, never opened as a place',
    );
  });

  test('the tile codes are the domain codes of the server', () {
    expect(tileKindCode(PlaceKind.motorhomeArea), 'motorhome_area');
    expect(tileNightCode(OvernightStatus.dayOnly), 'day_only');
    expect(heightCentimetres(3.45), 345);
  });
}
