import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_layer_order.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/web_view_route_map.dart';
import 'package:lunaway/shared/map/sprites.dart';

import '../helpers/map_engine.dart';

/// The basemaps the route maps load, as shipped.
final String _aube = File('assets/map/styles/aube.json').readAsStringSync();
final String _minuit = File('assets/map/styles/minuit.json').readAsStringSync();

/// What every route map draws, bottom to top, whatever its engine: the
/// basemap's roads and their names; the danger zones' band, under the
/// other routes, under the chosen route (casing, then line); the names of
/// places, over the lines, from the quarters'; the pins of the shops, then
/// of the places, which the route never hides; the towns' names, to which
/// a pin gives way (the PO's rule of 2026-10-10); the route's marks (minor
/// ones, the others, the numbered stops); the places drawn large; the start
/// and the arrival; the vehicle, on top. Each id must come after the one
/// before it.
const _expected = [
  'roads_labels_major',
  'lw-route-zones-line',
  'lw-route-alternatives-casing',
  'lw-route-alternatives-line',
  'lw-route-casing',
  'lw-route-line',
  'places_subplace',
  'lw-route-poi-pins',
  'lw-route-poi-pins-more',
  'lw-route-place-pins',
  'places_locality',
  'places_country',
  'lw-route-minor-badges',
  'lw-route-marks-badges',
  'lw-route-stops-badges',
  'lw-route-rich-marks',
  'lw-route-ends-badges',
  'lw-route-vehicle',
];

/// What [drawn] (bottom to top) breaks of [_expected], and of the one order
/// all engines take from [RouteLayerOrder]; empty when nothing.
List<String> _misplaced(List<String> drawn, String style) {
  final basemap = {for (final l in styleLayers(style)) l['id']! as String};
  final out = outOfOrder(drawn, _expected);
  final own = [
    for (final id in drawn)
      if (!basemap.contains(id)) id,
  ];
  if (!listEquals(own, RouteLayerOrder.layers)) out.add('own layers $own');
  if (drawn.last != 'lw-route-vehicle') out.add('${drawn.last} over the vehicle');
  return out;
}

/// A short route through Valence, and the places' tiles.
final _line = [const LatLng(44.93, 4.89), const LatLng(44.94, 4.90), const LatLng(44.95, 4.91)];

const _places = RouteMapPlaces(
  placeTileJsonUrl: 'https://api.example/places/tiles.json',
  poiTileJsonUrl: 'https://api.example/poi/tiles.json',
  placeFilter: ['has', 'kind'],
  poiFilter: ['has', 'kind'],
);

RouteMapProps _props({RouteMapPlaces? places = _places, String? style}) => RouteMapProps(
  style: style ?? _aube,
  dark: false,
  lines: [
    RouteMapLine(index: 0, points: _line, selected: true),
    RouteMapLine(index: 1, points: _line.reversed.toList(), selected: false),
  ],
  camera: FitCamera(GeoBounds.around(_line)!),
  places: places,
);

/// Draws [props] on the phone's engine, its style loaded, and gives the
/// engine once the vehicle's layer, added last, is in.
Future<LayerStackEngine> _drawn(WidgetTester tester, RouteMapProps props) async {
  final engine = LayerStackEngine(props.style)..install(tester);
  expect(tester.view.devicePixelRatio, _ratio);
  await tester.pumpWidget(MaterialApp(home: GlRouteMap(props)));
  await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
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
/// stand-in for MapLibre's map that keeps its layers in order and turns a
/// new style through the page's own `transformStyle`: the layers once the
/// style is set up, then after a change of theme.
const _desktopScript = '''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const clone = (o) => JSON.parse(JSON.stringify(o));
let map = null;
let controls = 0;
class FakeMap {
  constructor(options) {
    this.layers = clone(options.style.layers);
    this.sources = {};
    this.handlers = {};
    map = this;
  }
  on(name, f) { (this.handlers[name] = this.handlers[name] || []).push(f); }
  fire(name) { (this.handlers[name] || []).forEach((f) => f({})); }
  addControl() { controls++; }
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
  setStyle(style, options) {
    const next = options.transformStyle({ layers: this.layers }, clone(style));
    this.layers = next.layers;
  }
  getCanvasContainer() {
    return { addEventListener() {}, appendChild() {}, dispatchEvent() {}, classList: { toggle() {}, add() {}, remove() {} } };
  }
  getZoom() { return 12; }
  getCenter() { return { lat: 45, lng: 5 }; }
  getBounds() { return { getSouth() { return 0; }, getWest() { return 0; }, getNorth() { return 1; }, getEast() { return 1; }, toArray() { return []; } }; }
}
globalThis.maplibregl = { Map: FakeMap, AttributionControl: class {}, Marker: class {} };
globalThis.document = { addEventListener() {} };
globalThis.window = {};
new Function(input.source)();
const ids = () => map.layers.map((l) => l.id);
window.lunaway.init({ style: input.style, spec: input.spec, images: {}, pixelRatio: 2, lat: 45, lon: 5, zoom: 12 });
map.fire('style.load');
setTimeout(() => {
  const first = ids();
  window.lunaway.setStyle(input.next, input.spec);
  process.stdout.write(JSON.stringify({ first: first, themed: ids(), controls: controls }));
}, 50);
''';

/// Runs the web page's `keepOwn` (`web/lunaway_maplibre.js`, the change of
/// theme in the browser) on the layers drawn and a new basemap: the layers
/// after the change.
const _keepOwnScript = r'''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const keepOwn = new Function(input.block + '\nreturn keepOwn;')();
const out = keepOwn(input.previous, input.next);
process.stdout.write(JSON.stringify(out.layers.map((l) => l.id)));
''';

Future<Object?> _node(String script, Map<String, Object?> input) async {
  final process = await Process.start('node', ['-e', script]);
  process.stdin.write(jsonEncode(input));
  await process.stdin.close();
  final output = await process.stdout.transform(utf8.decoder).join();
  final errors = await process.stderr.transform(utf8.decoder).join();
  expect(await process.exitCode, 0, reason: errors);
  return jsonDecode(output);
}

/// The test view's pixel ratio.
const _ratio = 3.0;

void main() {
  // The images the map keeps from one map to the next, made once outside
  // any test's clock: a future kept from one test's clock never completes
  // in the next. The pins' do not matter here.
  setUpAll(() async {
    await routeBadgePngs(_ratio);
    await PinSprites.load(PinSprites.ratioFor(_ratio), bundle: BlankAssets());
  });

  test('the order is one list with each layer once, the lines under the names of places', () {
    expect(RouteLayerOrder.layers.toSet(), hasLength(RouteLayerOrder.layers.length));
    for (final (name, style) in [('aube', _aube), ('minuit', _minuit)]) {
      final layers = styleLayers(style);
      final (:placeNames, :townNames) = RouteLayerOrder.namesOf(style);
      expect(placeNames, 'places_subplace', reason: name);
      expect(townNames, 'places_locality', reason: name);
      // What stays over the route's lines: names of places only, no road's;
      // the towns' among them, over the pins.
      final over = layers.skipWhile((l) => l['id'] != placeNames).toList();
      expect(over.map((l) => l['id']), contains(townNames), reason: name);
      for (final l in over) {
        expect(l['type'], 'symbol', reason: '$name: ${l['id']}');
        expect(l['source-layer'], RouteLayerOrder.basemapPlaceNames, reason: '$name: ${l['id']}');
      }
    }
    expect(RouteLayerOrder.placeNamesOf('https://tiles.example/style.json'), isNull);
  });

  test('a layer added late goes in its place: a pin under the towns, a line under the places', () {
    final all = RouteLayerOrder.layers.toSet();
    final pinsLate = all.difference(RouteLayerOrder.pins.toSet());
    expect(
      RouteLayerOrder.below('lw-route-place-pins', present: pinsLate.contains),
      'lw-route-minor-halo',
      reason: "a basemap without the towns' names: under the marks",
    );
    expect(
      RouteLayerOrder.below(
        'lw-route-place-pins',
        present: pinsLate.contains,
        placeNames: 'places_subplace',
        townNames: 'places_locality',
      ),
      'places_locality',
    );
    expect(
      RouteLayerOrder.below(
        'lw-route-poi-pins',
        present: all.contains,
        townNames: 'places_locality',
      ),
      'lw-route-poi-pins-more',
      reason: 'under the pins above it',
    );
    expect(
      RouteLayerOrder.below('lw-route-line', present: (_) => false, placeNames: 'places_subplace'),
      'places_subplace',
    );
    final lineLate = all.difference({'lw-route-line'});
    expect(
      RouteLayerOrder.below(
        'lw-route-line',
        present: lineLate.contains,
        placeNames: 'places_subplace',
        townNames: 'places_locality',
      ),
      'places_subplace',
      reason: 'over the other lines, under the names of places',
    );
    expect(
      RouteLayerOrder.below('lw-route-casing', present: all.contains, placeNames: 'x'),
      'lw-route-line',
    );
    expect(
      RouteLayerOrder.below('lw-route-line', present: lineLate.contains),
      'lw-route-place-probe',
      reason: 'a basemap without names of towns: still under the pins',
    );
    expect(RouteLayerOrder.below('lw-route-vehicle', present: all.contains), isNull);
  });

  testWidgets(
    'a phone draws the route maps in the one order',
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
    (tester) async {
      final engine = await _drawn(tester, _props());
      expect(_misplaced(engine.layers, _aube), isEmpty);
    },
  );

  testWidgets('places that come after the route go in their place, under the marks', (
    tester,
  ) async {
    final engine = await _drawn(tester, _props(places: null));
    expect(engine.layers, isNot(contains('lw-route-place-pins')));
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props())));
    await until(tester, () => engine.layers.contains('lw-route-place-pins'));
    expect(_misplaced(engine.layers, _aube), isEmpty);
  });

  testWidgets('a style loaded again (a theme, a language) is set up in the same order', (
    tester,
  ) async {
    final engine = await _drawn(tester, _props());
    // The engine drops the app's layers with the old style.
    engine.layers
      ..clear()
      ..addAll([for (final l in styleLayers(_minuit)) l['id']! as String]);
    await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
    expect(_misplaced(engine.layers, _minuit), isEmpty);
  });

  testWidgets('by night too', (tester) async {
    final engine = await _drawn(tester, _props(style: _minuit));
    expect(_misplaced(engine.layers, _minuit), isEmpty);
  });

  final node = _hasNode();
  final skip = node ? false : 'needs node on the PATH (the CI has it)';

  test(
    'the desktop page draws them in the same order, and keeps it at a change of theme',
    () async {
      final seen = await _node(_desktopScript, {
        'source': File('assets/map/lunaway_map.js').readAsStringSync(),
        'style': jsonDecode(_aube),
        'next': jsonDecode(_minuit),
        'spec': routePageSpec(style: _aube, dark: false, places: _places, ratio: 2),
      });
      if (seen is! Map<String, Object?>) fail('the page answered $seen');
      final first = (seen['first']! as List).cast<String>();
      expect(_misplaced(first, _aube), isEmpty);
      expect(_misplaced((seen['themed']! as List).cast<String>(), _minuit), isEmpty);
      // The app draws the map's credit over the web view (MapCredit): no
      // second, foreign one from MapLibre.
      expect(seen['controls'], 0);
    },
    skip: skip,
  );

  // The browser's map is the phone's code through maplibre_gl's web
  // plugin; a change of theme then turns the style in place (keepOwn).
  testWidgets("the browser's change of theme keeps the order", (tester) async {
    final page = File('web/lunaway_maplibre.js').readAsStringSync();
    final block = RegExp(r'  // BEGIN KEEP OWN\n([\s\S]*?)  // END KEEP OWN\n')
        .firstMatch(page)
        ?.group(1);
    expect(block, isNotNull, reason: 'web/lunaway_maplibre.js lost its KEEP OWN markers');
    final engine = await _drawn(tester, _props());
    final basemap = {for (final l in styleLayers(_aube)) l['id']! as String: l};
    final drawn = [
      for (final id in engine.layers) basemap[id] ?? {'id': id, 'source': 'lw-route'},
    ];
    final themed = await tester.runAsync(
      () => _node(_keepOwnScript, {
        'block': block,
        'previous': {
          'layers': drawn,
          'sources': {'lw-route': <String, Object?>{}},
        },
        'next': jsonDecode(_minuit),
      }),
    );
    expect(_misplaced((themed! as List).cast<String>(), _minuit), isEmpty);
  }, skip: !node);
}
