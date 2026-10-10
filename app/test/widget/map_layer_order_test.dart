import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/map/presentation/web_view_map.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/sprites.dart';

import '../helpers/map_engine.dart';

/// The basemap of the main map by day, as shipped.
final String _aube = File('assets/map/styles/aube.json').readAsStringSync();

/// What the main map draws, bottom to top, the places' tiles and a
/// category of points chosen: the points' gathering dots under the places'
/// glow and dots, under every name of the basemap; the roads' names; the
/// places' dots and pins; the prices and the pins of the category chosen,
/// over the places' (audit 94, m2); the towns' names, to which every one
/// of those pins gives way (m3, the PO's rule of 2026-10-10); the device's
/// places, the saved points, the selection, the open point, which never
/// give way. Each id must come after the one before it.
const List<String> _expected = [
  PoiMapStyle.dotsLayerId,
  PlaceTiles.glowLayer,
  PlaceTiles.dotsLayer,
  PlaceTiles.basemapFirstLabel,
  'roads_labels_major',
  PlaceTiles.pinDotsLayer,
  PlaceTiles.pinsLayer,
  PoiMapStyle.fuelLayerId,
  PoiMapStyle.pinsLayerId,
  PoiMapStyle.morePinsLayerId,
  PlaceTiles.basemapTownNames,
  'places_country',
  MapStyle.clustersLayer,
  MapStyle.placesLayer,
  MapStyle.savedLayer,
  MapStyle.selectionPinLayer,
  PoiMapStyle.selectionLayerId,
];

const _tiles = PlaceTilesView(tileJsonUrl: 'https://api.example/places/tiles.json');
const _pois = PoiLayerView(
  tileJsonUrl: 'https://api.example/poi/tiles.json',
  category: PoiCategory.sights,
);

LunaMapProps _props({PlaceTilesView? tiles = _tiles, PoiLayerView pois = _pois}) => LunaMapProps(
  style: _aube,
  dark: false,
  initialCenter: const LatLng(44.4826, 4.6893),
  initialZoom: 13,
  places: const [],
  selectedPlace: null,
  onPlaceTap: (_, {hint}) {},
  onLongPress: (_) {},
  onViewportChanged: (_) {},
  onMapReady: (_) {},
  pois: pois,
  placeTiles: tiles,
);

/// Draws [props] on the phone's engine, its style loaded, and gives the
/// engine once the open point's layer, added last, is in.
Future<LayerStackEngine> _drawn(WidgetTester tester, LunaMapProps props) async {
  final engine = LayerStackEngine(props.style)..install(tester);
  await tester.pumpWidget(MaterialApp(home: GlLunaMap(props)));
  await engine.loadStyle(tester, () => engine.layers.contains(PoiMapStyle.selectionLayerId));
  return engine;
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Runs the desktop page (`assets/map/lunaway_map.js`) under node with a
/// stand-in for MapLibre's map that keeps its layers in order: the layers
/// once the style is set up.
const _desktopScript = '''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
let map = null;
class FakeMap {
  constructor(options) {
    this.layers = JSON.parse(JSON.stringify(options.style.layers));
    this.sources = {};
    this.handlers = {};
    map = this;
  }
  on(name, f) { (this.handlers[name] = this.handlers[name] || []).push(f); }
  fire(name) { (this.handlers[name] || []).forEach((f) => f({})); }
  addControl() {}
  hasImage() { return false; }
  addImage() {}
  getSource(id) { return this.sources[id]; }
  addSource(id, s) { this.sources[id] = s; }
  getLayer(id) { return this.layers.find((l) => l.id === id); }
  addLayer(layer, before) {
    if (this.getLayer(layer.id)) throw new Error('layer exists: ' + layer.id);
    const at = before === undefined ? -1 : this.layers.findIndex((l) => l.id === before);
    if (before !== undefined && at < 0) throw new Error('no layer ' + before);
    if (at < 0) this.layers.push(layer); else this.layers.splice(at, 0, layer);
  }
  getCanvasContainer() {
    return { addEventListener() {}, appendChild() {}, dispatchEvent() {}, classList: { toggle() {}, add() {}, remove() {} } };
  }
  getZoom() { return 13; }
  getCenter() { return { lat: 44.48, lng: 4.69 }; }
  getBounds() { return { getSouth() { return 0; }, getWest() { return 0; }, getNorth() { return 1; }, getEast() { return 1; }, toArray() { return []; } }; }
  loaded() { return false; }
  querySourceFeatures() { return []; }
}
globalThis.maplibregl = { Map: FakeMap, Marker: class {} };
globalThis.document = { addEventListener() {} };
globalThis.window = {};
new Function(input.source)();
window.lunaway.init({ style: input.style, spec: input.spec, images: {}, pixelRatio: 2, lat: 44.48, lon: 4.69, zoom: 13 });
map.fire('style.load');
setTimeout(() => process.stdout.write(JSON.stringify(map.layers.map((l) => l.id))), 50);
''';

void main() {
  // The pins' images, kept from one map to the next, made once outside any
  // test's clock: a future kept from one test's clock never completes in
  // the next. What they hold does not matter here.
  setUpAll(() => PinSprites.load(PinSprites.ratioFor(3), bundle: BlankAssets()));

  testWidgets(
    "a phone draws the places under the towns' names, a category chosen over the places",
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
    (tester) async {
      final engine = await _drawn(tester, _props());
      expect(outOfOrder(engine.layers, _expected), isEmpty);
    },
  );

  testWidgets('the places back online go where the style first put them', (tester) async {
    final engine = await _drawn(tester, _props(tiles: null));
    expect(engine.layers, isNot(contains(PlaceTiles.pinsLayer)));
    await tester.pumpWidget(MaterialApp(home: GlLunaMap(_props())));
    await until(tester, () => engine.layers.contains(PlaceTiles.pinsLayer));
    expect(outOfOrder(engine.layers, _expected), isEmpty);
  });

  testWidgets('the points read on demand go back where the style first put them', (tester) async {
    final engine = await _drawn(tester, _props());
    final before = engine.added;
    // A chip of a category read on demand reads the tiles of every
    // category: the points' source and its seven layers go again.
    await tester.pumpWidget(
      MaterialApp(
        home: GlLunaMap(
          _props(
            pois: const PoiLayerView(
              tileJsonUrl: 'https://api.example/poi/all/tiles.json',
              category: PoiCategory.food,
            ),
          ),
        ),
      ),
    );
    await until(tester, () => engine.added >= before + 7);
    expect(engine.added, before + 7);
    expect(outOfOrder(engine.layers, _expected), isEmpty);
  });

  test('the desktop page draws them in the same order', () async {
    final process = await Process.start('node', ['-e', _desktopScript]);
    process.stdin.write(
      jsonEncode({
        'source': File('assets/map/lunaway_map.js').readAsStringSync(),
        'style': jsonDecode(_aube),
        'spec': webViewMapSpec(
          dark: false,
          language: 'fr',
          tiles: _tiles,
          pois: _pois,
          style: _aube,
        ),
      }),
    );
    await process.stdin.close();
    final output = await process.stdout.transform(utf8.decoder).join();
    final errors = await process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0, reason: errors);
    final drawn = (jsonDecode(output) as List).cast<String>();
    expect(outOfOrder(drawn, _expected), isEmpty);
  }, skip: _hasNode() ? false : 'needs node on the PATH (the CI has it)');
}
