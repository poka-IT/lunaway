import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';
import 'package:lunaway/features/navigation/presentation/web_view_route_map.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/shared/map/sprites.dart';

import '../helpers/map_engine.dart';

final String _aube = File('assets/map/styles/aube.json').readAsStringSync();

/// A short route through Valence, and the places' tiles.
final _line = [const LatLng(44.93, 4.89), const LatLng(44.94, 4.90), const LatLng(44.95, 4.91)];

const _places = RouteMapPlaces(
  placeTileJsonUrl: 'https://api.example/places/tiles.json',
  poiTileJsonUrl: 'https://api.example/poi/tiles.json',
  placeFilter: ['has', 'kind'],
  poiFilter: ['has', 'kind'],
);

RouteMapProps _props(List<FuelLabel> prices, {double? traveledM}) => RouteMapProps(
  style: _aube,
  dark: false,
  lines: [RouteMapLine(index: 0, points: _line, selected: true)],
  camera: FitCamera(GeoBounds.around(_line)!),
  places: _places,
  fuelPrices: prices,
  traveledM: traveledM,
);

/// The calls that changed the properties of [layers], in order.
List<Map<Object?, Object?>> _updates(LayerStackEngine engine, Set<String> layers) => [
  for (final c in engine.calls)
    if (c.method == 'layer#setProperties' && layers.contains((c.arguments as Map)['layerId']))
      c.arguments as Map<Object?, Object?>,
];

/// The test view's pixel ratio.
const _ratio = 3.0;

void main() {
  // Made once outside any test's clock, as in route_layer_order_test.dart.
  setUpAll(() async {
    await routeBadgePngs(_ratio);
    await PinSprites.load(PinSprites.ratioFor(_ratio), bundle: BlankAssets());
  });

  // maplibre_gl's typed properties send every property they know, the
  // unset ones as null, and a null resets it on every engine: a new price
  // sent so took the pins' image, size and anchor with it.
  testWidgets("a new price changes the text of the stations' pins and its colour, nothing else", (
    tester,
  ) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    expect(tester.view.devicePixelRatio, _ratio);
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(const []))));
    await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
    // The changes of the pins' layers; the route's own (its grey behind the
    // vehicle) are not this test's.
    const pins = {'lw-route-poi-pins', 'lw-route-poi-pins-more'};
    expect(engine.layers, containsAll(pins));
    List<Map<Object?, Object?>> updates() => _updates(engine, pins);
    expect(updates(), isEmpty, reason: 'the pins came with the prices known');

    const prices = [
      FuelLabel(id: 'station-a', position: LatLng(44.94, 4.90), text: '1,789', rank: 0),
      FuelLabel(id: 'station-b', position: LatLng(44.95, 4.91), text: '1,859', rank: 1),
    ];
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(prices))));
    await until(tester, () => updates().length >= 2);

    final expected = {
      'text-field': RoutePlaceLayers.priceText(prices),
      'text-color': RoutePlaceLayers.priceColor(prices, dark: false),
    };
    expect(
      {for (final u in updates()) u['layerId']: u['properties']},
      {'lw-route-poi-pins': expected, 'lw-route-poi-pins-more': expected},
    );
    // The same prices in a new list, at the next fix: nothing is sent.
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props([...prices]))));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(updates(), hasLength(2));
  });

  testWidgets("the grey behind the vehicle changes the route's gradient, nothing else", (
    tester,
  ) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(const []))));
    await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
    const lines = {'lw-route-casing', 'lw-route-line'};
    final before = _updates(engine, lines).length;
    // 1.2 km driven of a route of about 2.7.
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(const [], traveledM: 1200))));
    await until(tester, () => _updates(engine, lines).length >= before + 2);
    final sent = _updates(engine, lines).skip(before).toList();
    expect([for (final u in sent) u['layerId']], ['lw-route-casing', 'lw-route-line']);
    for (final u in sent) {
      expect((u['properties']! as Map).keys, ['line-gradient'], reason: '${u['layerId']}');
    }
  });

  // The phone's layer lists the layout's properties one by one: one left
  // out there (the order of placement, under which a price took the room of
  // the pin below it) is missing on Android and iOS alone.
  testWidgets("a phone's stations' pins take the whole layout the desktop page gives them", (
    tester,
  ) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(const []))));
    await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
    final layout = RoutePlaceLayers.poiLayout(1);
    expect(layout['symbol-z-order'], 'viewport-y', reason: 'the pins placed from the bottom up');
    for (final id in ['lw-route-poi-pins', 'lw-route-poi-pins-more']) {
      final added = engine.calls.lastWhere(
        (c) => c.method == 'symbolLayer#add' && (c.arguments as Map)['layerId'] == id,
      );
      final properties = (added.arguments as Map)['properties'] as Map;
      for (final MapEntry(:key, :value) in layout.entries) {
        // Sized to the pins the phone loads.
        if (key == 'icon-size') continue;
        expect(properties[key], value, reason: '$id $key');
      }
    }
  });

  test("the desktop page's pins write the prices known from its first frame", () {
    const prices = [
      FuelLabel(id: 'station-a', position: LatLng(44.94, 4.90), text: '1,789', rank: 0),
    ];
    final spec = routePageSpec(style: _aube, dark: true, places: _places, ratio: 2, prices: prices);
    final pins = {
      for (final l in (spec['layers']! as List).cast<Map<String, Object?>>())
        if (l['id'] case 'lw-route-poi-pins' || 'lw-route-poi-pins-more') l['id']: l,
    };
    expect(pins, hasLength(2));
    for (final l in pins.values) {
      expect((l['layout']! as Map)['text-field'], RoutePlaceLayers.priceText(prices));
      expect((l['paint']! as Map)['text-color'], RoutePlaceLayers.priceColor(prices, dark: true));
    }
  });
}
