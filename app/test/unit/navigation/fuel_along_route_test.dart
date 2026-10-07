import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/fuel_along_route.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

import '../../contract/graphql_validator.dart';
import '../../helpers/navigation.dart';

/// Limoges to Brive, a few points of a route as the server draws it.
const _route = [
  LatLng(45.8336, 1.2611),
  LatLng(45.8200, 1.2700),
  LatLng(45.7800, 1.3000),
  LatLng(45.6000, 1.4000),
  LatLng(45.4000, 1.5000),
  LatLng(45.1600, 1.5300),
];

void main() {
  final schema = SchemaValidator(File('../schema/lunaway.graphql').readAsStringSync());
  late List<Map<String, dynamic>> sent;

  GraphQLClient client(http.Response Function(Map<String, dynamic> body) answer) {
    sent = [];
    return GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        sent.add(body);
        return answer(body);
      }),
      userAgent: 'test',
    );
  }

  http.Response recorded(Map<String, dynamic> _) => http.Response.bytes(
    File('test/fixtures/navigation/fuel_along_route.json').readAsBytesSync(),
    200,
    headers: {'content-type': 'application/json'},
  );

  test(
    'the route ahead leaves as the server drew it, from its first point past the vehicle',
    () async {
      final source = ServerFuelStations(client(recorded), fallback: FakeFuelStations(const []));
      // 1.9 km along the first leg: the vehicle is between the second and
      // third points.
      await source.along(
        route: _route,
        fromM: 1900,
        fuel: FuelType.diesel,
        consumptionL100: 13.5,
        vehicle: const {
          'kind': 'OVERCAB',
          'heightM': 3.1,
          'widthM': 2.3,
          'lengthM': 7,
          'weightT': 3.5,
        },
      );
      final input = (sent.single['variables'] as Map)['input'] as Map<String, dynamic>;
      expect(decodePolyline(input['polyline'] as String), _route.sublist(2));
      expect(input['fuel'], 'DIESEL');
      expect(input['litresPer100Km'], 13.5);
      expect(input['fillLitres'], refillLitres);
      expect((input['vehicle'] as Map)['kind'], 'OVERCAB');
      expect(schema.validate(fuelAlongRouteOperation.document), isEmpty);
      expect(
        schema.checkVariables(
          fuelAlongRouteOperation.document,
          sent.single['variables'] as Map<String, dynamic>,
        ),
        isEmpty,
      );
    },
  );

  test(
    'from the start of a route, the line leaves 2 km away from where the device stands',
    () async {
      final source = ServerFuelStations(client(recorded), fallback: FakeFuelStations(const []));
      await source.along(route: _route, fromM: 0, fuel: FuelType.diesel);
      final input = (sent.single['variables'] as Map)['input'] as Map<String, dynamic>;
      final line = decodePolyline(input['polyline'] as String);
      expect(line, _route.sublist(2), reason: 'the second point is 1.75 km from the start');
      expect(line.every((p) => p.distanceTo(_route.first) >= 2000), isTrue);
    },
  );

  test(
    'a station is placed along the route, its detour measured or estimated, its sheet named',
    () async {
      final source = ServerFuelStations(client(recorded), fallback: FakeFuelStations(const []));
      final offers = await source.along(route: _route, fromM: 1900, fuel: FuelType.diesel);
      final startM = _route[0].distanceTo(_route[1]) + _route[1].distanceTo(_route[2]);
      expect(offers, hasLength(2), reason: 'the station out of diesel is no offer');
      final total = offers.first;
      expect(total.poiId, '01a110e9-f037-7172-b861-f4e0e3e52c09');
      expect(total.alongM, closeTo(startM + 77795.1, 0.5));
      expect(total.detourM, closeTo(2901, 0.1));
      expect(total.detourS, closeTo(222, 0.1));
      expect(total.detourEstimated, isFalse);
      expect(total.open, StationOpen.open);
      final bare = offers.last;
      expect(bare.poiId, isNull, reason: 'no point of interest describes it');
      expect(bare.id, 'fuel-station:87220002');
      expect(bare.detourEstimated, isTrue);
      expect(bare.open, StationOpen.unknown);
    },
  );

  test(
    'an API without the search falls back to the stations around the route, then stays there',
    () async {
      final fallback = FakeFuelStations(const []);
      final source = ServerFuelStations(
        client(
          (_) => http.Response(
            jsonEncode({
              'data': null,
              'errors': [
                {
                  'message': 'Unknown field "fuelAlongRoute" on type "Query".',
                  'extensions': {'code': 'INVALID_INPUT'},
                },
              ],
            }),
            200,
          ),
        ),
        fallback: fallback,
      );
      await source.along(route: _route, fromM: 0, fuel: FuelType.lpg);
      await source.along(route: _route, fromM: 500, fuel: FuelType.lpg);
      expect(sent, hasLength(1), reason: 'asked once');
      // 2 km ahead of the vehicle there too: no point where it stands.
      expect(fallback.queries.map((q) => q.fromM), [2000, 2500]);
    },
  );

  test('the detours are timed at the cruising speed, or without it on an older API', () async {
    // The API before the cruising speed refuses it as async-graphql does.
    final source = ServerFuelStations(
      client((body) {
        final vehicle = ((body['variables'] as Map)['input'] as Map)['vehicle'] as Map;
        if (!vehicle.containsKey('cruiseSpeedKph')) return recorded(body);
        return http.Response(
          jsonEncode({
            'data': null,
            'errors': [
              {
                'message':
                    'Invalid value for argument "input.vehicle", unknown field "cruiseSpeedKph" '
                    'of type "VehicleProfileInput"',
                'extensions': {'code': 'INVALID_INPUT'},
              },
            ],
          }),
          200,
        );
      }),
      fallback: FakeFuelStations(const []),
    );
    final offers = await source.along(
      route: _route,
      fromM: 0,
      fuel: FuelType.diesel,
      vehicle: const {
        'kind': 'OVERCAB',
        'heightM': 3.1,
        'widthM': 2.3,
        'lengthM': 7,
        'weightT': 3.5,
        'cruiseSpeedKph': 90,
      },
    );
    expect(sent, hasLength(2));
    Map<String, dynamic> vehicleOf(int i) =>
        ((sent[i]['variables'] as Map)['input'] as Map)['vehicle'] as Map<String, dynamic>;
    expect(vehicleOf(0)['cruiseSpeedKph'], 90, reason: 'the speed goes first');
    expect(vehicleOf(1), isNot(contains('cruiseSpeedKph')));
    expect(vehicleOf(1)['heightM'], 3.1, reason: 'the rest of the vehicle still goes');
    expect(offers, isNotEmpty, reason: 'the server search, not the fallback');
  });

  test('a route too long for the server is simplified before it leaves', () async {
    // 2 000 km of a zigzag every 100 m: hundreds of thousands of
    // characters as it is.
    final zigzag = [
      for (var i = 0; i < 20000; i++) LatLng(43 + i * 0.0009, 1 + (i.isEven ? 0 : 0.00005)),
    ];
    final source = ServerFuelStations(client(recorded), fallback: FakeFuelStations(const []));
    await source.along(route: zigzag, fromM: 0, fuel: FuelType.diesel);
    final polyline = ((sent.single['variables'] as Map)['input'] as Map)['polyline'] as String;
    expect(polyline.length, lessThanOrEqualTo(ServerFuelStations.maxPolyline));
    final back = decodePolyline(polyline);
    // 2 km in, past the stretch that would place the device.
    expect(back.first.distanceTo(zigzag.first), closeTo(2000, 100));
    expect(back.last.lat, closeTo(zigzag.last.lat, 1e-6));
  });

  test('a polyline written is read back to the same points', () {
    final points = [
      for (var i = 0; i < 50; i++)
        LatLng(-33.9 + math.sin(i) * 0.123456, 151.2 - math.cos(i) * 0.654321),
    ];
    final back = decodePolyline(encodePolyline(points));
    for (var i = 0; i < points.length; i++) {
      expect(back[i].lat, closeTo(points[i].lat, 1e-6));
      expect(back[i].lon, closeTo(points[i].lon, 1e-6));
    }
  });
}
