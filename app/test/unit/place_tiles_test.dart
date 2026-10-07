import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// Evaluates the part of the MapLibre expression language the places'
/// filters use, with the engines' semantics: `get` of a missing property is
/// null, `==` of values of different types is false, `>=` on a null fails
/// the feature (an error in a filter keeps nothing), `match` compares its
/// input with each label or list of labels.
Object? _eval(Object? expr, Map<String, Object> properties) {
  if (expr is! List) return expr;
  final op = expr.first as String;
  Object? arg(int i) => _eval(expr[i], properties);
  num n(int i) => switch (arg(i)) {
    final num v => v,
    _ => throw const _Fails(),
  };
  switch (op) {
    case 'get':
      return properties[expr[1]];
    case 'has':
      return properties.containsKey(expr[1]);
    case '!':
      return arg(1) != true;
    // Both stop at the first argument that decides, as the engines do.
    case 'all':
      for (var i = 1; i < expr.length; i++) {
        if (arg(i) != true) return false;
      }
      return true;
    case 'any':
      for (var i = 1; i < expr.length; i++) {
        if (arg(i) == true) return true;
      }
      return false;
    case 'coalesce':
      for (var i = 1; i < expr.length; i++) {
        final v = arg(i);
        if (v != null) return v;
      }
      return null;
    case 'match':
      final input = arg(1);
      for (var i = 2; i + 1 < expr.length; i += 2) {
        final label = expr[i];
        if (label is List ? label.contains(input) : label == input) return arg(i + 1);
      }
      return arg(expr.length - 1);
    case '==':
      final a = arg(1);
      final b = arg(2);
      return (a.runtimeType == b.runtimeType || (a is num && b is num)) && a == b;
    case '>=':
      return n(1) >= n(2);
    case '/':
      return n(1) / n(2);
    case '*':
      return n(1) * n(2);
    case '-':
      return n(1) - n(2);
    case 'floor':
      return n(1).floor();
  }
  throw UnsupportedError(op);
}

class _Fails implements Exception {
  const new();
}

bool _keeps(List<Object> filter, Map<String, Object> properties) {
  try {
    return _eval(filter, properties) == true;
  } on _Fails {
    return false;
  }
}

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
  final mask = Service.maskOf(services);
  final place = PlaceSummary(
    id: 'p',
    kind: kind,
    lat: 45,
    lon: 6,
    overnight: night,
    services: services,
    priceParkingEur: price,
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
    },
  );
}

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
          _keeps(expression, s.tile),
          expected,
          reason: 'filter ${filter.activeCount} criteria, tile ${s.tile}',
        );
        if (expected) kept++;
      }
    }
    // Neither all nor nothing: the comparison means something.
    expect(kept, inInclusiveRange(4000, 76000));
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
        _keeps(placeTileFilter(filter), s.tile),
        filter.matches(s.place, maxHeightM: s.maxHeightM),
      );
    }
  });

  test('the empty filter keeps every feature', () {
    final r = Random(3);
    for (var i = 0; i < 50; i++) {
      expect(_keeps(placeTileFilter(PlaceFilter.none), _sample(r).tile), isTrue);
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
        ),
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
          _eval(placeTilePinImage(), {
            'kind': kind.wire.toLowerCase(),
            'night': night.wire.toLowerCase(),
          }),
          pinImageId(kind, night),
        );
      }
    }
    expect(
      _eval(placeTilePinImage(), {'kind': 'a_future_kind', 'night': 'allowed'}),
      pinImageId(PlaceKind.extraService, OvernightStatus.unknown),
      reason: 'a newer server must not leave a place without a pin',
    );
  });

  test('a night allowed is placed before a night tolerated, and drawn above it', () {
    num rank(OvernightStatus o, {bool placement = false}) =>
        _eval(placeTileRank(placement: placement), {'night': o.wire.toLowerCase()})! as num;
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
    expect((p.lat, p.lon), (45.9, 6.1));
    expect(placeFromTile({'kind': 'campsite'}, [6.1, 45.9]), isNull, reason: 'a dot has no id');
  });

  test('the tile codes are the domain codes of the server', () {
    expect(tileKindCode(PlaceKind.motorhomeArea), 'motorhome_area');
    expect(tileNightCode(OvernightStatus.dayOnly), 'day_only');
    expect(heightCentimetres(3.45), 345);
  });
}
