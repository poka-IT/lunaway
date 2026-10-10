import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show Factory, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_layer_order.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/web_view_route_map.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// The basemaps the route maps load, as shipped.
final String _aube = File('assets/map/styles/aube.json').readAsStringSync();
final String _minuit = File('assets/map/styles/minuit.json').readAsStringSync();

List<Map<String, Object?>> _styleLayers(String style) => [
  for (final l in (jsonDecode(style) as Map<String, Object?>)['layers']! as List)
    l as Map<String, Object?>,
];

/// What every route map draws, bottom to top, whatever its engine: the
/// basemap's roads and their names; the danger zones' band, under the
/// other routes, under the chosen route (casing, then line); the names of
/// towns, over the lines; the pins of the shops, then of the places, which
/// the route never hides; the route's marks (minor ones, the others, the
/// numbered stops); the places drawn large; the start and the arrival; the
/// vehicle, on top. Each id must come after the one before it.
const _expected = [
  'roads_labels_major',
  'lw-route-zones-line',
  'lw-route-alternatives-casing',
  'lw-route-alternatives-line',
  'lw-route-casing',
  'lw-route-line',
  'places_subplace',
  'places_locality',
  'places_country',
  'lw-route-poi-pins',
  'lw-route-poi-pins-more',
  'lw-route-place-pins',
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
  final basemap = {for (final l in _styleLayers(style)) l['id']! as String};
  final out = <String>[
    for (final id in _expected)
      if (!drawn.contains(id)) '$id missing',
    for (var i = 1; i < _expected.length; i++)
      if (drawn.contains(_expected[i - 1]) &&
          drawn.contains(_expected[i]) &&
          drawn.indexOf(_expected[i - 1]) > drawn.indexOf(_expected[i]))
        '${_expected[i - 1]} over ${_expected[i]}',
  ];
  final own = [
    for (final id in drawn)
      if (!basemap.contains(id)) id,
  ];
  if (!listEquals(own, RouteLayerOrder.layers)) out.add('own layers $own');
  if (drawn.last != 'lw-route-vehicle') out.add('${drawn.last} over the vehicle');
  return out;
}

/// MapLibre's channel on a phone, with a style of its own: each layer the
/// map adds goes where the engine puts it (under `belowLayerId`, else on
/// top), so the test reads the order the map draws, the basemap's layers
/// included.
final class _Engine extends gl.MapLibreMethodChannel {
  new(String style) : layers = [for (final l in _styleLayers(style)) l['id']! as String];

  /// Bottom to top.
  final List<String> layers;

  bool _created = false;

  /// The view is made once, as a platform view is, whatever the rebuilds.
  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    gl.OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    if (!_created) {
      _created = true;
      onPlatformViewCreated(0);
    }
    return const SizedBox.expand();
  }

  Future<Object?> answer(MethodCall call) async {
    final args = call.arguments is Map
        ? call.arguments as Map<Object?, Object?>
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'symbolLayer#add' || 'lineLayer#add' || 'circleLayer#add' || 'fillLayer#add':
        final id = args['layerId']! as String;
        final below = args['belowLayerId'] as String?;
        if (layers.contains(id)) throw PlatformException(code: 'layerExists', message: id);
        if (below == null) {
          layers.add(id);
        } else {
          final at = layers.indexOf(below);
          if (at < 0) throw PlatformException(code: 'noLayer', message: below);
          layers.insert(at, id);
        }
      case 'style#removeLayer':
        layers.remove(args['layerId']);
    }
    return null;
  }
}

final class _Blank extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(1);
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

/// Waits on real time until [done], a few seconds at most.
/// The map's work runs on both clocks: its images are drawn on real time,
/// its calls to the engine on the test's.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!done() && DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Draws [props] on the phone's engine, its style loaded, and gives the
/// engine once the vehicle's layer, added last, is in.
Future<_Engine> _drawn(WidgetTester tester, RouteMapProps props) async {
  final engine = _Engine(props.style);
  const channel = MethodChannel('plugins.flutter.io/maplibre_gl_0');
  final messenger = tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(channel, engine.answer);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final previous = gl.MapLibrePlatform.createInstance;
  gl.MapLibrePlatform.createInstance = () => engine;
  addTearDown(() => gl.MapLibrePlatform.createInstance = previous);
  expect(tester.view.devicePixelRatio, _ratio);
  await tester.pumpWidget(MaterialApp(home: GlRouteMap(props)));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  engine.onMapStyleLoadedPlatform(null);
  await _until(tester, () => engine.layers.contains('lw-route-vehicle'));
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
    await PinSprites.load(PinSprites.ratioFor(_ratio), bundle: _Blank());
  });

  test('the order is one list with each layer once, the lines under the names of towns', () {
    expect(RouteLayerOrder.layers.toSet(), hasLength(RouteLayerOrder.layers.length));
    for (final (name, style) in [('aube', _aube), ('minuit', _minuit)]) {
      final layers = _styleLayers(style);
      final names = RouteLayerOrder.townNamesOf(style);
      expect(names, 'places_subplace', reason: name);
      // What stays over the route's lines: names of places only, no road's.
      final over = layers.skipWhile((l) => l['id'] != names);
      for (final l in over) {
        expect(l['type'], 'symbol', reason: '$name: ${l['id']}');
        expect(l['source-layer'], RouteLayerOrder.basemapPlaceNames, reason: '$name: ${l['id']}');
      }
    }
    expect(RouteLayerOrder.townNamesOf('https://tiles.example/style.json'), isNull);
  });

  test('a layer added late goes in its place: a pin under the marks, a line under the towns', () {
    final all = RouteLayerOrder.layers.toSet();
    final pinsLate = all.difference(RouteLayerOrder.pins.toSet());
    expect(
      RouteLayerOrder.below('lw-route-place-pins', present: pinsLate.contains),
      'lw-route-minor-halo',
    );
    expect(
      RouteLayerOrder.below('lw-route-line', present: (_) => false, townNames: 'places_subplace'),
      'places_subplace',
    );
    final lineLate = all.difference({'lw-route-line'});
    expect(
      RouteLayerOrder.below(
        'lw-route-line',
        present: lineLate.contains,
        townNames: 'places_subplace',
      ),
      'places_subplace',
      reason: 'over the other lines, under the names of towns',
    );
    expect(
      RouteLayerOrder.below('lw-route-casing', present: all.contains, townNames: 'x'),
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
    await _until(tester, () => engine.layers.contains('lw-route-place-pins'));
    expect(_misplaced(engine.layers, _aube), isEmpty);
  });

  testWidgets('a style loaded again (a theme, a language) is set up in the same order', (
    tester,
  ) async {
    final engine = await _drawn(tester, _props());
    // The engine drops the app's layers with the old style.
    engine.layers
      ..clear()
      ..addAll([for (final l in _styleLayers(_minuit)) l['id']! as String]);
    engine.onMapStyleLoadedPlatform(null);
    await _until(tester, () => engine.layers.contains('lw-route-vehicle'));
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
    final basemap = {for (final l in _styleLayers(_aube)) l['id']! as String: l};
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
