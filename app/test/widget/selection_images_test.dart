import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/sprites.dart';

import '../helpers/map_engine.dart';

/// The main map on a phone keeps the images of selected pins out of the
/// engine until a pin shows selected: one shows at a time, and the engine
/// held the hundred of them decoded, 11 MB at the 3x ratio
/// (`plan/research/139-memoire-android.md`).

final String _aube = File('assets/map/styles/aube.json').readAsStringSync();

const _parking = PlaceSummary(
  id: 'p1',
  kind: PlaceKind.parking,
  lat: 45.9,
  lon: 6.13,
  overnight: OvernightStatus.allowed,
);

const _bakery = PoiFeature(id: 'n1', kind: PoiKind.bakery, position: LatLng(45.9, 6.13));

LunaMapProps _props({PlaceSummary? selected, PoiFeature? point}) => LunaMapProps(
  style: _aube,
  dark: false,
  initialCenter: const LatLng(45.9, 6.13),
  initialZoom: 15,
  places: const [],
  selectedPlace: selected,
  onPlaceTap: (_, {hint}) {},
  onLongPress: (_) {},
  onViewportChanged: (_) {},
  onMapReady: (_) {},
  pois: PoiLayerView(tileJsonUrl: 'https://api.example/poi/tiles.json', selected: point),
  placeTiles: const PlaceTilesView(tileJsonUrl: 'https://api.example/places/tiles.json'),
);

List<String> _images(LayerStackEngine engine) => [
  for (final call in engine.calls)
    if (call.method == 'style#addImage')
      (call.arguments as Map<Object?, Object?>)['name']! as String,
];

/// Where in the engine's calls [source] first got a feature.
int _filled(LayerStackEngine engine, String source) => engine.calls.indexWhere(
  (c) =>
      c.method == 'source#setGeoJson' &&
      (c.arguments as Map<Object?, Object?>)['sourceId'] == source &&
      ((c.arguments as Map<Object?, Object?>)['geojson']! as String).contains('Feature"'),
);

int _added(LayerStackEngine engine, String image) => engine.calls.indexWhere(
  (c) => c.method == 'style#addImage' && (c.arguments as Map<Object?, Object?>)['name'] == image,
);

Future<LayerStackEngine> _drawn(WidgetTester tester) async {
  final engine = LayerStackEngine(_aube)..install(tester);
  await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props())));
  // Set up once the last pin image of the style is in.
  await engine.loadStyle(tester, () => _images(engine).contains(markedPointImageId));
  await until(tester, () => _images(engine).length > 100);
  return engine;
}

void main() {
  setUpAll(() => PinSprites.load(PinSprites.ratioFor(3), bundle: BlankAssets()));

  testWidgets('the style takes the pins but none of their selected images', (tester) async {
    final engine = await _drawn(tester);
    final images = _images(engine);
    expect(images, contains(pinImageId(PlaceKind.parking, OvernightStatus.allowed)));
    expect(images, contains(PoiMapStyle.imageId(PoiKind.bakery)));
    expect(images.where((id) => id.endsWith('-selected')), isEmpty);
  });

  testWidgets("a place selected brings its selected pin's image before the pin is drawn", (
    tester,
  ) async {
    final engine = await _drawn(tester);
    final setUp = engine.calls.length;
    await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props(selected: _parking))));
    await until(tester, () => _filled(engine, MapStyle.selectionSource) >= 0);

    final image = pinImageId(PlaceKind.parking, OvernightStatus.allowed, selected: true);
    expect(_added(engine, image), greaterThanOrEqualTo(setUp));
    expect(_added(engine, image), lessThan(_filled(engine, MapStyle.selectionSource)));
    expect(_images(engine).where((id) => id.endsWith('-selected')), [image]);
    // The pin's pop runs out.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("a point selected brings its selected pin's image before the pin is drawn", (
    tester,
  ) async {
    final engine = await _drawn(tester);
    final setUp = engine.calls.length;
    await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props(point: _bakery))));
    await until(tester, () => _filled(engine, PoiMapStyle.selectionSource) >= 0);

    final image = PoiMapStyle.selectedImageId(PoiKind.bakery);
    expect(_added(engine, image), greaterThanOrEqualTo(setUp));
    expect(_added(engine, image), lessThan(_filled(engine, PoiMapStyle.selectionSource)));
  });

  testWidgets('a pin selected twice brings its image once', (tester) async {
    final engine = await _drawn(tester);
    await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props(selected: _parking))));
    await until(tester, () => _filled(engine, MapStyle.selectionSource) >= 0);
    await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props())));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props(selected: _parking))));
    // The second selection's calls, on both clocks.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }

    final image = pinImageId(PlaceKind.parking, OvernightStatus.allowed, selected: true);
    expect(_images(engine).where((id) => id == image), hasLength(1));
  });
}
