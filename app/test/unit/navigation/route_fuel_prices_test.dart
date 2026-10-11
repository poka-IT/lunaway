import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/route_fuel_prices.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_fuel_prices.dart';
import 'package:lunaway/features/navigation/presentation/route_layer_order.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart' show Poi, maxPriceAge, priceIsCurrent;
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

import '../../helpers/poi_fakes.dart';

/// The day the prices of [stationWith] were given, and one a little later.
final _given = DateTime.utc(2026, 10, 6, 6);
final _now = DateTime.utc(2026, 10, 9, 12);

FuelOffer _offer(
  String id, {
  double price = 1.789,
  FuelType fuel = FuelType.diesel,
  DateTime? at,
  String? poiId,
}) => FuelOffer(
  id: id,
  poiId: poiId,
  position: const LatLng(45.9, 6.12),
  priceEur: price,
  priceUpdatedAt: at ?? _given,
  detourM: 0,
  detourS: 0,
  alongM: 1000,
  fuel: fuel,
);

Poi _station(
  String id,
  Map<String, double> prices, {
  List<Map<String, Object?>> shortages = const [],
}) => poiFromJson(stationWith(id, id, prices, shortages: shortages))!;

void main() {
  test("the price of the profile's fuel beside each station of the fuel list, as the main map "
      'writes it, coloured from the cheapest to the dearest', () {
    final prices = routePrices(
      fuel: FuelType.diesel,
      now: _now,
      language: 'fr',
      offers: [_offer('a'), _offer('b', price: 1.849), _offer('c', price: 1.819)],
    );
    expect(
      {for (final e in prices.marks.entries) e.key: e.value.text},
      {'a': '1,789', 'b': '1,849', 'c': '1,819'},
    );
    expect(prices.marks['a']!.rank, 0);
    expect(prices.marks['b']!.rank, 1);
    expect(prices.marks['c']!.rank, closeTo(0.5, 1e-9));
    expect(
      routePrices(
        fuel: FuelType.diesel,
        now: _now,
        language: 'en',
        offers: [_offer('a')],
      ).marks['a']!.text,
      '1.789',
    );
  });

  test('without a fuel in the profile, no price: the logo alone', () {
    final prices = routePrices(
      fuel: null,
      now: _now,
      language: 'fr',
      offers: [_offer('a')],
      stations: [
        _station('s', {'DIESEL': 1.70}),
      ],
    );
    expect(prices.marks, isEmpty);
    expect(prices.pins, isEmpty);
  });

  test("an offer of another fuel is no price of the vehicle's", () {
    final prices = routePrices(
      fuel: FuelType.diesel,
      now: _now,
      language: 'fr',
      offers: [_offer('gas', fuel: FuelType.lpg, price: 0.999)],
    );
    expect(prices.marks, isEmpty);
  });

  test('a price older than the age the server offers none past shows nothing', () {
    final old = _now.subtract(maxPriceAge + const Duration(hours: 1));
    final fresh = _now.subtract(maxPriceAge - const Duration(hours: 1));
    expect(priceIsCurrent(old, _now), isFalse);
    expect(priceIsCurrent(fresh, _now), isTrue);
    final prices = routePrices(
      fuel: FuelType.diesel,
      now: _now,
      language: 'fr',
      offers: [
        _offer('old', at: old),
        _offer('fresh', at: fresh),
      ],
    );
    expect(prices.marks.keys, ['fresh']);
    final stale = routePrices(
      fuel: FuelType.diesel,
      now: _given.add(maxPriceAge + const Duration(days: 1)),
      language: 'fr',
      stations: [
        _station('s', {'DIESEL': 1.70}),
      ],
    );
    expect(stale.pins, isEmpty);
  });

  test("under the pins: the vehicle's fuel of the stations around, none of a station out of "
      'it, nor of one without the fuel, nor twice for a station of the list', () {
    final prices = routePrices(
      fuel: FuelType.diesel,
      now: _now,
      language: 'fr',
      offers: [_offer('listed:1', price: 1.749, poiId: 'listed')],
      stations: [
        _station('near', {'DIESEL': 1.789, 'E10': 1.85}),
        _station('dear', {'DIESEL': 1.849}),
        _station('petrol', {'E10': 1.70}),
        _station(
          'dry',
          {'DIESEL': 1.50},
          shortages: [
            {'fuel': 'DIESEL', 'kind': 'TEMPORARY', 'since': '2026-10-03T00:00:00Z'},
          ],
        ),
        _station('listed', {'DIESEL': 1.749}),
        _station('near', {'DIESEL': 1.789}),
      ],
    );
    expect({for (final l in prices.pins) l.id: l.text}, {'near': '1,789', 'dear': '1,849'});
    // Ranked together with the list's: one colour, one price.
    expect(prices.marks['listed:1']!.rank, 0);
    expect(prices.pins.firstWhere((l) => l.id == 'dear').rank, 1);
    expect(prices.pins.firstWhere((l) => l.id == 'near').position, const LatLng(45.905, 6.12));
  });

  test(
    "a station of the list switched to another fuel keeps the vehicle's price under its pin",
    () {
      final prices = routePrices(
        fuel: FuelType.diesel,
        now: _now,
        language: 'fr',
        offers: [_offer('gas:1', fuel: FuelType.lpg, price: 0.999, poiId: 'gas')],
        stations: [
          _station('gas', {'DIESEL': 1.779, 'LPG': 0.999}),
        ],
      );
      expect(prices.marks, isEmpty, reason: "the list's price is of another fuel");
      expect({for (final l in prices.pins) l.id: l.text}, {'gas': '1,779'});
    },
  );

  test('outside France a station has no price: nothing written', () {
    final abroad = poiFromJson(poiJson('es', 'FUEL_STATION', name: 'Repsol'))!;
    expect(abroad.fuel, isNull);
    expect(
      routePrices(fuel: FuelType.diesel, now: _now, language: 'fr', stations: [abroad]).pins,
      isEmpty,
    );
  });

  test("a price is its station pin's own text: written with the pin, never without it", () {
    final prices = routePrices(
      fuel: FuelType.diesel,
      now: _now,
      language: 'fr',
      stations: [
        _station('near', {'DIESEL': 1.789}),
        _station('dear', {'DIESEL': 1.849}),
      ],
    ).pins;
    final layout = RoutePlaceLayers.poiLayout(1, prices: prices);
    expect(layout['text-field'], [
      'match',
      ['get', 'id'],
      'near',
      '1,789',
      'dear',
      '1,849',
      '',
    ]);
    expect(layout['text-optional'], isTrue, reason: 'the pin stays where its price finds no room');
    expect(layout['text-anchor'], 'top', reason: 'under the tip of the pin');
    expect(RoutePlaceLayers.priceText(const []), '', reason: 'no price, the logo alone');
    final colour = RoutePlaceLayers.priceColor(prices, dark: false) as List<Object?>;
    expect(colour[3], RouteLook.hex(PoiLook.price(0, dark: false)), reason: 'the cheapest');
    expect(colour[5], RouteLook.hex(PoiLook.price(1, dark: false)), reason: 'the dearest');
    // No layer of prices of its own, which drew a figure where its pin had
    // found no room.
    expect(RouteLayerOrder.layers.where((l) => l.contains('price')), isEmpty);
  });

  test('the stations around the vehicle are read for its cell, the same box while it stays '
      'there, the vehicle well inside it', () {
    final a = stationsAround(const LatLng(45.9012, 6.1203));
    final b = stationsAround(const LatLng(45.9489, 6.1497));
    expect(a, b, reason: 'one request per cell');
    for (final at in [const LatLng(45.9001, 6.1001), const LatLng(45.9499, 6.1499)]) {
      final box = stationsAround(at);
      expect(at.lat - box.south, greaterThanOrEqualTo(0.02 - 1e-9));
      expect(box.north - at.lat, greaterThanOrEqualTo(0.02 - 1e-9));
      expect(at.lon - box.west, greaterThanOrEqualTo(0.02 - 1e-9));
      expect(box.east - at.lon, greaterThanOrEqualTo(0.02 - 1e-9));
    }
    expect(stationsAround(const LatLng(45.9501, 6.12)), isNot(a), reason: 'the next cell');
    // Within the area the API takes.
    expect((a.north - a.south) * (a.east - a.west), lessThan(0.01));
  });
}
