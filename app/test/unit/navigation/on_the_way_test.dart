import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/on_the_way_api.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

import '../../contract/graphql_validator.dart';

/// Limoges to Brive, a few points of a route as the server draws it.
const _route = [
  LatLng(45.8336, 1.2611),
  LatLng(45.8200, 1.2700),
  LatLng(45.7800, 1.3000),
  LatLng(45.6000, 1.4000),
  LatLng(45.4000, 1.5000),
  LatLng(45.1600, 1.5300),
];

/// A page as the API answers it: a place with another source's photo, a
/// place with the community's own, a shop with its hours, and an item no
/// road reaches.
Map<String, dynamic> _answer() => {
  'data': {
    'alongRoute': {
      'next': 'YTE6MjA6YWJj',
      'items': [
        {
          'alongKm': 12.5,
          'distanceM': 320.0,
          'detour': {'km': 1.4, 'minutes': 3.2, 'measured': true},
          'place': {
            'id': '01a12000-0000-7000-8000-000000000001',
            'name': 'Aire du lac',
            'kind': 'MOTORHOME_AREA',
            'lat': 45.70,
            'lon': 1.35,
            'overnight': 'ALLOWED',
            'services': ['DRINKING_WATER', 'GREY_WATER'],
            'address': {'city': 'Pierre-Buffière'},
            'municipality': null,
            'priceParkingEur': 12.0,
            'ratings': [
              {'sourceId': 'community-cc-by', 'average': 4.5, 'count': 3},
            ],
            'ratingForFilters': 4.5,
            'reviewCount': 2,
            'coverPhotos': <Object>[],
          },
          'poi': null,
          'photo': {
            'id': '01a12000-0000-7000-8000-000000000011',
            'sourceId': 'wikimedia-commons',
            'thumbUrl': 'https://api.example.org/media/a/thumb.webp',
            'largeUrl': 'https://api.example.org/media/a/full.webp',
            'thumbhash': null,
            'authorName': 'Jeanne',
            'licence': 'CC BY-SA 4.0',
          },
        },
        {
          'alongKm': 20.0,
          'distanceM': 40.0,
          'detour': {'km': 0.1, 'minutes': 0.2, 'measured': false},
          'place': {
            'id': '01a12000-0000-7000-8000-000000000002',
            'name': null,
            'kind': 'PARKING',
            'lat': 45.65,
            'lon': 1.38,
            'overnight': 'TOLERATED',
            'services': <Object>[],
            'address': null,
            'municipality': null,
            'priceParkingEur': null,
            'ratings': <Object>[],
            'ratingForFilters': null,
            'reviewCount': 0,
            'coverPhotos': [
              {
                'id': '01a12000-0000-7000-8000-000000000021',
                'sourceId': 'community-cc-by',
                'thumbUrl': 'https://api.example.org/media/b/thumb.webp',
                'largeUrl': 'https://api.example.org/media/b/full.webp',
                'thumbhash': 'HBkSHYSIeHiPiHh8eJd4eTN0EEQG',
                'authorId': '01a12000-0000-7000-8000-000000000031',
              },
            ],
          },
          'poi': null,
          'photo': {
            'id': '01a12000-0000-7000-8000-000000000012',
            'sourceId': 'extcom',
            'thumbUrl': 'https://api.example.org/media/c/thumb.webp',
            'largeUrl': 'https://api.example.org/media/c/full.webp',
            'thumbhash': null,
            'authorName': 'Marie',
            'licence': 'REF-1',
          },
        },
        {
          'alongKm': 30.0,
          'distanceM': 150.0,
          'detour': {'km': 0.9, 'minutes': 2.0, 'measured': true},
          'place': null,
          'poi': {
            'id': '01a12000-0000-7000-8000-000000000041',
            'kind': 'BAKERY',
            'name': 'Au bon pain',
            'brand': null,
            'lat': 45.6,
            'lon': 1.4,
            'alwaysOpen': false,
            'openingIntervals': [
              {'start': '2026-10-06T05:00:00Z', 'end': '2026-10-06T11:00:00Z'},
            ],
            'openingIntervalsUntil': '2026-10-20T00:00:00Z',
          },
          'photo': null,
        },
      ],
    },
  },
};

RouteOption _option(List<RouteStep> steps) => RouteOption(
  index: 0,
  distanceM: 3000,
  durationS: 300,
  hasToll: false,
  hasFerry: false,
  hasMotorway: false,
  warnings: const [],
  steps: steps,
);

RouteStep _step(double metres, double seconds) => RouteStep(
  instruction: '',
  distanceM: metres,
  durationS: seconds,
  position: _route.first,
  maneuverType: 'turn',
);

PlaceOnTheWay _placeAt(double alongM) => PlaceOnTheWay(
  id: 'p$alongM',
  position: _route.first,
  alongM: alongM,
  offM: 0,
  detourM: 0,
  detourS: 0,
  place: PlaceSummary(
    id: 'p$alongM',
    kind: PlaceKind.parking,
    lat: 0,
    lon: 0,
    overnight: OvernightStatus.allowed,
  ),
);

void main() {
  final schema = SchemaValidator(File('../schema/lunaway.graphql').readAsStringSync());
  late List<Map<String, dynamic>> sent;

  GraphQLClient client(Map<String, dynamic> answer) {
    sent = [];
    return GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient((r) async {
        sent.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode(answer),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      userAgent: 'test',
    );
  }

  group('the chips', () {
    test('fuel searches on its own; every other chip asks the server for something', () {
      expect(OnTheWayCategory.fuel.search(), isNull);
      for (final c in OnTheWayCategory.values.skip(1)) {
        final s = c.search()!;
        expect(s.poiKinds.isNotEmpty || s.places != null, isTrue, reason: '$c');
        expect(s.poiKinds.toSet(), hasLength(s.poiKinds.length), reason: '$c asks each kind once');
      }
      expect(OnTheWayCategory.values.first, OnTheWayCategory.fuel, reason: 'fuel first');
    });

    test('sleeping keeps the night statuses of the map filters a night can be spent at', () {
      Set<OvernightStatus>? nights(Set<OvernightStatus> filter) =>
          OnTheWayCategory.sleep.search(nightFilter: filter)!.places!.overnight;
      expect(nights({}), {OvernightStatus.allowed, OvernightStatus.tolerated});
      expect(nights({OvernightStatus.allowed}), {OvernightStatus.allowed});
      expect(nights({OvernightStatus.allowed, OvernightStatus.dayOnly}), {
        OvernightStatus.allowed,
      }, reason: 'day only is no night');
      expect(nights({OvernightStatus.dayOnly}), {
        OvernightStatus.allowed,
        OvernightStatus.tolerated,
      }, reason: 'a filter without a night status of its own leaves both');
    });

    test('restaurants and sights ask for the kinds of their category, as the map chips do', () {
      expect(OnTheWayCategory.food.search()!.poiKinds, PoiCategory.food.kinds);
      final sights = OnTheWayCategory.sights.search()!;
      expect(sights.poiKinds, PoiCategory.sights.kinds);
      expect(sights.maxDetourM, 10000, reason: 'something to see is worth a longer detour');
      expect(
        OnTheWayCategory.services.search()!.poiKinds,
        isNot(contains(PoiKind.touristOffice)),
        reason: 'one chip per kind: the tourist offices are among the sights',
      );
      expect(OnTheWayCategory.garages.search()!.poiKinds, contains(PoiKind.outdoorShop));
      final asked = [for (final c in OnTheWayCategory.values.skip(1)) ...c.search()!.poiKinds];
      // The fuel stations are the fuel chip's, ranked by their price.
      for (final k in PoiKind.values.where((k) => k != PoiKind.fuelStation)) {
        expect(asked.where((a) => a == k), hasLength(1), reason: '$k under exactly one chip');
      }
    });

    test('water takes the water points and the places with water or a dump', () {
      final s = OnTheWayCategory.water.search()!;
      expect(s.poiKinds, containsAll([PoiKind.drinkingWater, PoiKind.dumpStation]));
      expect(s.places!.anyService, contains(Service.drinkingWater));
      expect(s.places!.overnight, isNull, reason: 'any night status: water is not a night');
    });
  });

  test('the list folds what lies past its near distance, in the order the server gave', () {
    final items = [_placeAt(12000), _placeAt(80000), _placeAt(9000), _placeAt(70000)];
    final (:near, :further) = splitNear(items, lineStartM: 5000, nearM: 50000);
    expect([for (final i in near) i.alongM], [12000, 9000]);
    expect([for (final i in further) i.alongM], [80000, 70000]);
  });

  test('the time of passage reads the steps from where the vehicle is, half the detour on', () {
    // 1 km in 60 s, then 2 km in 240 s.
    final route = _option([_step(1000, 60), _step(2000, 240)]);
    expect(secondsTo(route, 500), 30);
    expect(secondsTo(route, 2000), 60 + 120);
    expect(secondsTo(route, 9000), 300, reason: 'past the end, the whole route');
    final now = DateTime.utc(2026, 10, 6, 12);
    final item = PoiOnTheWay(
      id: 'x',
      position: _route.first,
      alongM: 2000,
      offM: 0,
      detourM: 600,
      detourS: 120,
      kind: PoiKind.bakery,
    );
    // From 500 m (30 s) to 2 km (180 s), plus one minute to the shop.
    expect(passageAt(route, 500, item, now), now.add(const Duration(seconds: 210)));
    expect(passageAt(_option(const []), 0, item, now), isNull, reason: 'no times, no passage');
  });

  test(
    'a page sends the line from 2 km past the vehicle and the search as the contract reads it',
    () async {
      final source = ServerOnTheWay(client(_answer()));
      final search = OnTheWayCategory.water.search()!;
      final page = await source.along(
        route: _route,
        fromM: 0,
        search: search,
        after: 'cursor',
        vehicle: const {
          'kind': 'OVERCAB',
          'heightM': 3.1,
          'widthM': 2.3,
          'lengthM': 7,
          'weightT': 3.5,
        },
      );
      final variables = sent.single['variables'] as Map<String, dynamic>;
      final input = variables['input'] as Map<String, dynamic>;
      final line = decodePolyline(input['polyline'] as String);
      expect(line, _route.sublist(2), reason: 'the second point is 1.75 km from the start');
      expect(input['poiKinds'], ['DRINKING_WATER', 'WATER_POINT', 'DUMP_STATION']);
      expect((input['places'] as Map)['anyService'], containsAll(['DRINKING_WATER', 'GREY_WATER']));
      expect(input['maxDetourKm'], 6);
      expect(input['nearKm'], 50);
      expect(input['after'], 'cursor');
      expect(schema.validate(alongRouteOperation.document), isEmpty);
      expect(schema.checkVariables(alongRouteOperation.document, variables), isEmpty);
      expect(
        schema.checkResponse(
          alongRouteOperation.document,
          _answer()['data'] as Map<String, dynamic>,
        ),
        isEmpty,
        reason: 'the answer of these tests is one the server can give',
      );
      expect(page.next, 'YTE6MjA6YWJj');
      final startM = _route[0].distanceTo(_route[1]) + _route[1].distanceTo(_route[2]);
      expect(page.lineStartM, closeTo(startM, 0.01));
      final [aire, parking, bakery] = page.items;
      aire as PlaceOnTheWay;
      expect(aire.alongM, closeTo(startM + 12500, 0.01));
      expect(aire.detourS, closeTo(192, 0.01));
      expect(aire.detourEstimated, isFalse);
      expect(aire.place.priceParkingEur, 12);
      expect(aire.place.ratingAverage, 4.5);
      expect(aire.photo!.sourceId, 'wikimedia-commons');
      expect(aire.photo!.authorName, 'Jeanne');
      expect(aire.photoLicence, 'CC BY-SA 4.0');
      parking as PlaceOnTheWay;
      expect(
        parking.photo!.id,
        '01a12000-0000-7000-8000-000000000021',
        reason: "the community's own photo first",
      );
      expect(parking.photoLicence, isNull);
      expect(parking.detourEstimated, isTrue);
      bakery as PoiOnTheWay;
      expect(bakery.kind, PoiKind.bakery);
      expect(bakery.name, 'Au bon pain');
      expect(
        bakery.hours.opennessAt(DateTime.utc(2026, 10, 6, 10)),
        PoiOpenness.open,
        reason: "the server's hours",
      );
      expect(bakery.hours.opennessAt(DateTime.utc(2026, 10, 6, 12)), PoiOpenness.closed);
    },
  );

  test('nothing is asked for a route that ends within 2 km of the vehicle', () async {
    final source = ServerOnTheWay(client(_answer()));
    final page = await source.along(
      route: _route.sublist(0, 2),
      fromM: 0,
      search: OnTheWayCategory.toilets.search()!,
    );
    expect(page.items, isEmpty);
    expect(sent, isEmpty);
  });
}
