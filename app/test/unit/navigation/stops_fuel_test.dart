import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

import '../../helpers/fakes.dart';
import '../../helpers/navigation.dart';

/// A straight road east along the 45th parallel, 10 km long.
final List<LatLng> road = [for (var i = 0; i <= 100; i++) LatLng(45, 1 + i * 0.00127)];

FuelOffer offer(String id, {required double price, double detourM = 0}) => FuelOffer(
  id: id,
  position: const LatLng(45, 1.005),
  priceEur: price,
  priceUpdatedAt: DateTime.utc(2026, 10, 6, 7),
  detourM: detourM,
  detourS: detourM / 14,
  alongM: 400,
  fuel: FuelType.diesel,
);

void main() {
  group('a stop', () {
    test('goes where it lengthens the trip the least', () {
      const origin = LatLng(45, 1);
      const destination = LatLng(45, 2);
      final stops = [
        const RouteStop(position: LatLng(45, 1.3), label: 'A'),
        const RouteStop(position: LatLng(45, 1.7), label: 'B'),
      ];
      int at(double lon) => bestInsertion(
        origin: origin,
        stops: stops,
        destination: destination,
        stop: LatLng(45.01, lon),
      );
      expect(at(1.1), 0, reason: 'before A');
      expect(at(1.5), 1, reason: 'between A and B');
      expect(at(1.9), 2, reason: 'after B');
      final inserted = insertStop(stops, 1, const RouteStop(position: LatLng(45, 1.5)));
      expect([for (final s in inserted) s.label], ['A', null, 'B']);
    });

    test('along a long diagonal route, the distance along it stays true', () {
      // From the Pyrenees to the Alps, 366 km as the crow flies.
      final line = [for (var i = 0; i <= 300; i++) LatLng(42.3 + i * 0.009, i * 0.01)];
      final last = line.last;
      var length = 0.0;
      for (var i = 1; i < line.length; i++) {
        length += line[i - 1].distanceTo(line[i]);
      }
      final near = nearestOnLine(LatLng(last.lat + 0.001, last.lon), line)!;
      expect(near.alongM, closeTo(length, 200));
    });

    test('a point is measured to the nearest point of the route, and along it', () {
      // 0.009 degrees of latitude: about a kilometre north of the road.
      final near = nearestOnLine(const LatLng(45.009, 1.0635), road)!;
      expect(near.offM, closeTo(1000, 15));
      expect(near.alongM, closeTo(5000, 60));
      expect(nearestOnLine(const LatLng(45, 1), const [LatLng(45, 1)]), isNull);
    });
  });

  group('fuel', () {
    test('the detour costs its fuel, spread over a refill', () {
      // 2 km there and back at 11 L/100 km: 0.22 L, over 50 L.
      final far = offer('far', price: 1.75, detourM: 2000);
      expect(effectivePrice(far, consumptionL100: 11), closeTo(1.75 * (1 + 0.22 / 50), 1e-9));
      final ranked = rankOffers([
        offer('cheap but far', price: 1.70, detourM: 40000),
        offer('on the road', price: 1.78),
        offer('a bit off', price: 1.72, detourM: 3000),
      ], consumptionL100: 11);
      expect([for (final o in ranked) o.id], ['a bit off', 'on the road', 'cheap but far']);
      final closed = FuelOffer(
        id: 'closed',
        position: const LatLng(45, 1.005),
        priceEur: 1.50,
        priceUpdatedAt: DateTime.utc(2026, 10, 6, 7),
        detourM: 0,
        detourS: 0,
        alongM: 400,
        fuel: FuelType.diesel,
        open: StationOpen.closed,
      );
      final withClosed = rankOffers([closed, ...ranked], consumptionL100: 11);
      expect(withClosed.last.id, 'closed', reason: 'cheapest, but closed now');
    });

    test('stations around the route ahead, with their price, open state and detour', () async {
      final asked = <Map<String, dynamic>>[];
      Map<String, Object?> station(String id, double lat, double lon, {String fuel = 'DIESEL'}) => {
        'id': id,
        'name': 'Station $id',
        'brand': null,
        'lat': lat,
        'lon': lon,
        'openNow': {'state': 'OPEN'},
        'fuel': {
          'prices': [
            {'fuel': fuel, 'priceEur': 1.789, 'updatedAt': '2026-10-06T07:00:00Z'},
          ],
          'shortages': <Object>[],
        },
      };
      final client = GraphQLClient(
        endpoint: Uri.parse('http://127.0.0.1:8484/graphql'),
        httpClient: MockClient((r) async {
          asked.add(
            (jsonDecode(r.body) as Map<String, dynamic>)['variables'] as Map<String, dynamic>,
          );
          final body = {
            'data': {
              'nearbyPois': [
                {
                  'pois': [
                    station('by-the-road', 45.0005, 1.05),
                    station('lpg-only', 45.001, 1.06, fuel: 'LPG'),
                    station('behind', 45.0005, 0.99),
                  ],
                },
              ],
            },
          };
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        userAgent: AppConfig.userAgent('1.0.0'),
      );
      final offers = await NearbyFuelStations(client)
          .along(route: road, fromM: 1000, fuel: FuelType.diesel);
      expect(asked, isNotEmpty);
      // 1 km along the road, rounded to the hundredth of a degree before it
      // leaves the device.
      expect(asked.first['at'], {'lat': 45.0, 'lon': 1.01});
      expect(asked.first['radiusM'], 5800);
      expect([for (final o in offers) o.id], ['by-the-road'], reason: 'diesel, ahead');
      final o = offers.single;
      expect(o.priceEur, 1.789);
      expect(o.open, StationOpen.open);
      expect(o.detourEstimated, isTrue);
      // 55 m off the road: 2 x 55 m x 1.3 by road.
      expect(o.detourM, closeTo(143, 5));
    });
  });

  group('the places by the route', () {
    /// [metres] east of the meridian 1°E at [lat].
    Place at(String id, double lat, double metres) => Place(
      id: id,
      kind: PlaceKind.motorhomeArea,
      lat: lat,
      lon: 1 + metres / (111195 * 0.7071),
      overnight: OvernightStatus.allowed,
      updatedAt: DateTime.utc(2026),
    );

    // North along 1°E for 55 km, then 3 km east: four stretches of 15 km.
    final line = [
      for (var i = 0; i <= 100; i++) LatLng(45 + i * 0.005, 1),
      for (var i = 1; i <= 10; i++) LatLng(45.5, 1 + i * 0.004),
    ];

    Future<List<PlaceSummary>> near(List<Place> places) async {
      final container = ProviderContainer.test(
        overrides: [
          placesRepositoryProvider.overrideWithValue(FakePlacesRepository(places)),
          effectiveFilterProvider.overrideWithValue(PlaceFilter.none),
        ],
      );
      return await container.read(placesNearRouteProvider(line).future);
    }

    test('come from the whole route, not only around its middle, each once', () async {
      final found = await near([
        at('start', 45.01, 100),
        // Where the first stretch ends and the second begins: in both.
        at('boundary', 45.135, 200),
        at('end', 45.49, 300),
        // A crowd in the middle (the third stretch), more than one query
        // returns around it.
        for (var i = 0; i < 250; i++) at('crowd-$i', 45.33 + i * 0.00001, 400),
      ]);
      final ids = [for (final p in found) p.id];
      expect(ids.take(3), ['start', 'boundary', 'end']);
      expect(ids.toSet(), hasLength(ids.length), reason: 'a place shows once');
      expect(ids, hasLength(120), reason: 'the nearest 120');
    });

    test('farther than 800 m from the road, a place in its box is left out', () async {
      final found = await near([
        at('by the road', 45.45, 700),
        // Inside the box of the last stretch, which turns east: 2 km from
        // both of its legs.
        at('in the corner', 45.48, 2700),
      ]);
      expect([for (final p in found) p.id], ['by the road']);
    });
  });

  test('a route through a stop is read leg after leg, to the destination', () {
    // Recorded from the API on 2026-10-06: 1.5 km to the stop, 2.7 km on.
    final route = routeFixture('limoges_stop').routes.single;
    final arrivals = route.steps.where((s) => s.maneuverType == 'arrive').toList();
    expect(route.steps, hasLength(25));
    expect(arrivals, hasLength(2), reason: 'at the stop, then at the destination');
    expect(route.steps.last.maneuverType, 'arrive');
    expect(route.line.last.distanceTo(const LatLng(45.84510, 1.28637)), lessThan(60));
  });

  group('the route service', () {
    test('a request asked again within two minutes is answered from memory', () async {
      var now = DateTime.utc(2026, 10, 6, 9);
      final inner = FakeRouteService([routeFixture('limoges_drive')]);
      final service = CachingRouteService(inner, clock: () => now);
      final request = RouteRequest(
        origin: const LatLng(45.8, 1.2),
        destination: const LatLng(45.9, 1.3),
        vehicle: checkVehicle(motorhome).profile!,
        avoid: const AvoidOptions(),
        language: RouteLanguage.fr,
        stops: const [LatLng(45.85, 1.25)],
      );
      await service.route(request);
      // Built again, field by field, as the preview does after the card.
      await service.route(
        RouteRequest(
          origin: const LatLng(45.8, 1.2),
          destination: const LatLng(45.9, 1.3),
          vehicle: checkVehicle(motorhome).profile!,
          avoid: const AvoidOptions(),
          language: RouteLanguage.fr,
          stops: const [LatLng(45.85, 1.25)],
        ),
      );
      expect(inner.requests, hasLength(1));
      now = now.add(const Duration(minutes: 3));
      await service.route(request);
      expect(inner.requests, hasLength(2));
    });

    test('stops travel as waypoints', () {
      final vars = routeVariables(
        origin: const LatLng(45.8, 1.2),
        destination: const LatLng(45.9, 1.3),
        vehicle: checkVehicle(motorhome).profile!,
        avoid: const AvoidOptions(),
        language: RouteLanguage.fr,
        stops: const [LatLng(45.85, 1.25)],
      );
      final input = vars['input']! as Map<String, Object?>;
      expect(input['waypoints'], [
        {'lat': 45.85, 'lon': 1.25},
      ]);
    });
  });
}
