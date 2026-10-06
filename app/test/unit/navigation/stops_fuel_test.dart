import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';

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
    });

    test('the fuel and the consumption are kept with the route settings', () {
      const settings = NavigationSettings(fuel: VehicleFuel.lpg, consumptionL100: 13.5);
      final back = NavigationSettings.decode(settings.encode());
      expect(back.fuel, VehicleFuel.lpg);
      expect(back.consumptionL100, 13.5);
      final odd = NavigationSettings.decode('{"fuel":"KEROSENE","consumptionL100":400}');
      expect(odd.fuel, VehicleFuel.diesel);
      expect(odd.consumptionL100, NavigationSettings.defaultConsumptionL100);
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
          .along(route: road, fromM: 1000, fuel: VehicleFuel.diesel);
      expect(asked, isNotEmpty);
      // 1 km along the road, rounded to the hundredth of a degree before it
      // leaves the device.
      expect(asked.first['at'], {'lat': 45.0, 'lon': 1.01});
      expect(asked.first['radiusM'], 5700);
      expect([for (final o in offers) o.id], ['by-the-road'], reason: 'diesel, ahead');
      final o = offers.single;
      expect(o.priceEur, 1.789);
      expect(o.open, StationOpen.open);
      expect(o.detourEstimated, isTrue);
      // 55 m off the road: 2 x 55 m x 1.3 by road.
      expect(o.detourM, closeTo(143, 5));
    });
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
      await service.route(request);
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
