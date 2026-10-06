import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/shared/theme/luna_scheme.dart';

import '../helpers/poi_fakes.dart';
import 'contrast_test.dart' show contrast, text;

Poi _station(
  String id,
  Map<String, double> prices, {
  double lat = 45.905,
  double lon = 6.12,
  List<Map<String, Object?>> shortages = const [],
}) => poiFromJson(stationWith(id, id, prices, lat: lat, lon: lon, shortages: shortages))!;

Map<String, Object?> _out(String fuel, {bool definitive = false}) => {
  'fuel': fuel,
  'kind': definitive ? 'DEFINITIVE' : 'TEMPORARY',
  'since': '2026-10-03T00:00:00Z',
};

const _from = LatLng(45.9, 6.12);

/// The view of the tests: around the lake, at a zoom the stations are read.
const _view = MapViewport(
  bounds: GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.2),
  center: _from,
  zoom: 12,
);

void main() {
  group('the cheapest offers', () {
    test('cheapest first, then nearest; out of it for now last; no longer sold left out', () {
      final offers = cheapestOffers(
        [
          _station('dear', {'DIESEL': 1.80}),
          _station('far', {'DIESEL': 1.75}, lat: 45.94),
          _station('near', {'DIESEL': 1.75}, lat: 45.901),
          _station('dry', {'DIESEL': 1.70}, shortages: [_out('DIESEL')]),
          _station('stopped', {'DIESEL': 1.60}, shortages: [_out('DIESEL', definitive: true)]),
          _station('petrol', {'E10': 1.65}),
        ],
        'DIESEL',
        from: _from,
      );
      expect(offers.map((o) => o.station.id), ['near', 'far', 'dear', 'dry']);
      expect(offers.last.shortage, isNotNull);
      expect(offers.first.distanceM, lessThan(offers[1].distanceM));
    });

    test('a price ranks 0 for the cheapest, 1 for the dearest, 0 when all are the same', () {
      const prices = [1.70, 1.80, 1.90];
      expect(priceRank(1.70, prices), 0);
      expect(priceRank(1.80, prices), closeTo(0.5, 1e-9));
      expect(priceRank(1.90, prices), 1);
      expect(priceRank(1.75, const [1.75, 1.75]), 0);
      expect(priceRank(1.75, const <double>[]), 0);
    });

    test("a station's prices put the vehicle's fuels first, LPG first otherwise", () {
      final fuel = poiFromJson(stationJson)!.fuel!;
      expect(fuel.sortedPrices.map((p) => p.fuel), ['LPG', 'DIESEL', 'E10']);
      expect(fuel.pricesFirst(['E10', 'LPG']).map((p) => p.fuel), ['E10', 'LPG', 'DIESEL']);
    });
  });

  group('the box the stations are read for', () {
    test('snaps to a 0.05 degree grid, so a small move asks for the same box', () {
      final a = fuelQueryBox(const GeoBounds(south: 45.12, west: 6.03, north: 45.18, east: 6.17));
      final b = fuelQueryBox(const GeoBounds(south: 45.13, west: 6.04, north: 45.17, east: 6.16));
      expect(a, b);
      expect(a.south, closeTo(45.10, 1e-9));
      expect(a.west, closeTo(6.00, 1e-9));
      expect(a.north, closeTo(45.20, 1e-9));
      expect(a.east, closeTo(6.20, 1e-9));
    });

    test('stays under the four square degrees of the API around the centre of a wide view', () {
      final box = fuelQueryBox(const GeoBounds(south: 40, west: 0, north: 50, east: 10));
      expect(box.north - box.south, closeTo(1.95, 1e-9));
      expect(box.east - box.west, closeTo(1.95, 1e-9));
      expect((box.north - box.south) * (box.east - box.west), lessThan(4));
      expect(box.contains(const LatLng(45, 5)), isTrue);
    });
  });

  group('the stations read for an area', () {
    late CacheDatabase db;
    setUp(() => db = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    PoiRepository repo(int stations) => PoiRepository(
      db: db,
      clock: () => DateTime.utc(2026, 10, 6, 8),
      source: FakePoiSource(
        pois: [
          for (var i = 0; i < stations; i++)
            stationWith('s$i', 'Station $i', {'DIESEL': 1.7 + i / 1000}, lat: 45.9 + i / 1000),
        ],
      )..fuelPageSize = 2,
    );
    const box = GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.2);

    test('come page after page, all of them', () async {
      final read = await repo(5).fuelStations(box);
      expect(read?.map((s) => s.id), ['s0', 's1', 's2', 's3', 's4']);
    });

    test('are none at all past the pages read: a part would rank wrong', () async {
      expect(await repo(PoiRepository.fuelPages * 2 + 1).fuelStations(box), isNull);
    });
  });

  group('the fuel shown', () {
    ProviderContainer container(VehicleFuel vehicle, List<Poi> stations) {
      final c = ProviderContainer.test(
        overrides: [
          vehicleFuelProvider.overrideWithValue(vehicle),
          fuelStationsInViewProvider.overrideWith((ref) async => stations),
        ],
      );
      c.read(viewportProvider.notifier).update(_view);
      return c;
    }

    test("is the vehicle's, gazole when unsaid, and switches in the list", () {
      expect(
        container(const VehicleFuel(fuel: FuelType.e85), const []).read(chosenFuelProvider),
        FuelType.e85,
      );
      final c = container(const VehicleFuel(), const []);
      expect(c.read(chosenFuelProvider), FuelType.diesel);
      c.read(chosenFuelProvider.notifier).choose(FuelType.lpg);
      expect(c.read(chosenFuelProvider), FuelType.lpg);
    });

    test(
      'the labels price the stations of the view, coloured among them, written the French way',
      () async {
        final c = container(const VehicleFuel(fuel: FuelType.e10), [
          _station('a', {'E10': 1.759, 'DIESEL': 1.70}),
          _station('b', {'E10': 1.819}, lat: 45.91),
          _station('c', {'E10': 1.789}, lat: 45.92),
          _station('dry', {'E10': 1.50}, shortages: [_out('E10')]),
          _station('outside', {'E10': 1.40}, lat: 46.5),
          _station('diesel', {'DIESEL': 1.69}),
        ]);
        await c.read(fuelStationsInViewProvider.future);
        final labels = c.read(fuelLabelsProvider('fr'));
        expect({for (final l in labels) l.id: l.text}, {'a': '1,759', 'b': '1,819', 'c': '1,789'});
        expect({for (final l in labels) l.id: l.rank}, {'a': 0, 'b': 1, 'c': closeTo(0.5, 1e-9)});
        expect(c.read(fuelLabelsProvider('en')).first.text, '1.759');

        final offers = await c.read(cheapestFuelProvider.future);
        expect(offers!.map((o) => o.station.id), ['a', 'c', 'b', 'dry'], reason: 'the view only');

        c.read(chosenFuelProvider.notifier).choose(FuelType.diesel);
        expect(c.read(fuelLabelsProvider('fr')).map((l) => l.text), ['1,700', '1,690']);
        expect((await c.read(cheapestFuelProvider.future))!.map((o) => o.station.id), [
          'diesel',
          'a',
        ]);
      },
    );
  });

  test('every price colour reads on the halo of its map and on its list', () {
    for (final (dark, backgrounds) in [
      (false, [const Color(0xFFFFFBF4), LunaScheme.aube.surface]),
      (true, [const Color(0xFF06142A), LunaScheme.minuit.surface]),
    ]) {
      for (final rank in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        for (final bg in backgrounds) {
          expect(
            contrast(PoiLook.price(rank, dark: dark), bg),
            greaterThanOrEqualTo(text),
            reason: 'rank $rank, ${dark ? 'night' : 'day'}',
          );
        }
      }
    }
  });
}
