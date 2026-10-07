import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_hit_shapes.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';

/// The pages that pick features themselves, each with the same block.
const _pages = ['web/lunaway_maplibre.js', 'assets/map/lunaway_map.js'];
final _block = RegExp(r'  // BEGIN MAP HITS\n[\s\S]*?  // END MAP HITS\n');
final _shapes = RegExp(r'/\* BEGIN HIT SHAPES \*/([\s\S]*?)/\* END HIT SHAPES \*/');

final Map<String, HitShape> _shapesByLayer = {...mapHitShapes, ...routeHitShapes};

/// A case of the rule, which both the app and the pages' code must decide
/// alike.
typedef _Case = ({
  String name,
  Offset at,
  double zoom,
  double tolerance,
  List<HitCandidate> candidates,
  (int, int)? expected,
});

HitCandidate _c(String layer, List<Offset> points, [Map<Object?, Object?> properties = const {}]) =>
    HitCandidate(layer: layer, properties: properties, points: points);

const _mouse = 14.0;
const _touch = 22.0;
const _here = Offset(500, 400);

final List<_Case> _cases = [
  (
    name: 'the nearer of two dots in reach wins, whatever their order',
    at: _here,
    zoom: 5,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.dotsLayer, [_here + const Offset(9, 0)], {'kind': 'parking'}),
      _c(PlaceTiles.dotsLayer, [_here + const Offset(0, 5)], {'kind': 'campsite'}),
    ],
    expected: (1, 0),
  ),
  (
    name: 'a dot of the country view 13 px off is still clicked',
    at: _here,
    zoom: 5,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.dotsLayer, [_here + const Offset(13, 0)], {'kind': 'parking'}),
    ],
    expected: (0, 0),
  ),
  (
    name: 'a dot 20 px off is out of a mouse reach',
    at: _here,
    zoom: 5,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.dotsLayer, [_here + const Offset(20, 0)], {'kind': 'parking'}),
    ],
    expected: null,
  ),
  (
    name: 'the same dot is in reach of a finger',
    at: _here,
    zoom: 5,
    tolerance: _touch,
    candidates: [
      _c(PlaceTiles.dotsLayer, [_here + const Offset(20, 0)], {'kind': 'parking'}),
    ],
    expected: (0, 0),
  ),
  (
    name: "a click on a pin's head picks the pin over a dot nearer its tip",
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinDotsLayer, [_here + const Offset(4, 3)], {'kind': 'parking', 'id': 'b'}),
      // Its tip 20 px under the click: the head is centred there.
      _c(PlaceTiles.pinsLayer, [_here + const Offset(0, 20)], {'kind': 'parking', 'id': 'a'}),
    ],
    expected: (1, 0),
  ),
  (
    name: 'under two shapes, the selected pin wins over the pin it covers',
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinsLayer, [_here + const Offset(0, 20)], {'kind': 'parking', 'id': 'a'}),
      _c(MapStyle.selectionPinLayer, [_here + const Offset(0, 26)], {'kind': 'place', 'id': 'b'}),
    ],
    expected: (1, 0),
  ),
  (
    name: 'two pins under the pointer: the one drawn on top',
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinsLayer, [_here + const Offset(3, 20)], {'kind': 'parking', 'id': 'a'}),
      _c(PlaceTiles.pinsLayer, [_here + const Offset(-3, 20)], {'kind': 'parking', 'id': 'b'}),
    ],
    expected: (0, 0),
  ),
  (
    name: "a cluster's edge counts, not its centre",
    at: _here,
    zoom: 8,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.dotsLayer, [_here + const Offset(0, 12)], {'kind': 'parking'}),
      // 1000 places: a disc of 24.5 px with its rim, 30 px away.
      _c(
        MapStyle.clustersLayer,
        [_here + const Offset(30, 0)],
        {'point_count': 1000, 'cluster_id': 7},
      ),
    ],
    expected: (1, 0),
  ),
  (
    name: 'the point of a MultiPoint nearest the click',
    at: _here,
    zoom: 6,
    tolerance: _mouse,
    candidates: [
      _c(
        PlaceTiles.dotsLayer,
        [_here + const Offset(12, 0), _here + const Offset(-4, 2), _here + const Offset(40, 40)],
        {'kind': 'nature'},
      ),
    ],
    expected: (0, 1),
  ),
  (
    name: 'a route mark without an id is not a target',
    at: _here,
    zoom: 0,
    tolerance: _touch,
    candidates: [
      _c(RouteLayers.marks, [_here], {'kind': 'warning', 'radius': 8}),
      _c(
        RouteLayers.marks,
        [_here + const Offset(15, 0)],
        {'kind': 'place', 'id': 'place:1', 'radius': 4},
      ),
    ],
    expected: (1, 0),
  ),
  (
    name: 'a mark in reach beats another route that passes there',
    at: _here,
    zoom: 0,
    tolerance: _touch,
    candidates: [
      _c(RouteLayers.alternatives, const [], {'index': 1}),
      _c(
        RouteLayers.marks,
        [_here + const Offset(20, 0)],
        {'kind': 'place', 'id': 'stop:0', 'radius': 8},
      ),
    ],
    expected: (1, 0),
  ),
  (
    name: 'another route alone in reach is picked',
    at: _here,
    zoom: 0,
    tolerance: _touch,
    candidates: [
      _c(RouteLayers.alternatives, const [], {'index': 1}),
    ],
    expected: (0, 0),
  ),
  (
    name: 'a gathering dot of points grows with its count',
    at: _here,
    zoom: 11,
    tolerance: _mouse,
    candidates: [
      _c(
        PoiMapStyle.vendingDotsLayerId,
        [_here + const Offset(24, 0)],
        {'kind': 'vending_pizza', 'count': 60},
      ),
    ],
    expected: (0, 0),
  ),
  (
    name: 'nothing in reach',
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PoiMapStyle.pinsLayerId, [_here + const Offset(60, 0)], {'kind': 'bakery', 'id': 'p'}),
    ],
    expected: null,
  ),
];

(int, int)? _decide(_Case c) {
  final hit = nearestHit(
    c.at,
    c.candidates,
    shapes: _shapesByLayer,
    zoom: c.zoom,
    tolerance: c.tolerance,
  );
  return hit == null ? null : (hit.index, hit.pointIndex);
}

Map<String, Object?> _caseJson(_Case c) => {
  'at': [c.at.dx, c.at.dy],
  'zoom': c.zoom,
  'tolerance': c.tolerance,
  'candidates': [
    for (final x in c.candidates)
      {
        'layer': x.layer,
        'properties': x.properties.map((k, v) => MapEntry('$k', v)),
        'points': [
          for (final p in x.points) [p.dx, p.dy],
        ],
      },
  ],
};

void main() {
  group('the nearest feature in reach', () {
    for (final c in _cases) {
      test(c.name, () => expect(_decide(c), c.expected));
    }

    test('a finger reaches 44 px across, a mouse 28', () {
      expect(hitTolerance(PointerKind.touch) * 2, greaterThanOrEqualTo(44));
      expect(hitTolerance(PointerKind.mouse) * 2, inInclusiveRange(24, 32));
    });

    test('the long-press marker absorbs a tap without leading anywhere', () {
      final hit = nearestHit(
        _here,
        [
          _c(MapStyle.selectionPinLayer, [_here + const Offset(0, 27)], {'kind': 'point'}),
        ],
        shapes: mapHitShapes,
        zoom: 14,
        tolerance: _touch,
      );
      expect(hit?.inert, isTrue);
    });
  });

  group('features answered without their layer', () {
    test('a place of the tiles is a pin from the pins query, a dot otherwise', () {
      const place = {'kind': 'parking', 'id': 'x'};
      expect(hitLayerOf(place, pin: true), PlaceTiles.pinsLayer);
      expect(hitLayerOf(place, pin: false), PlaceTiles.pinDotsLayer);
      expect(hitLayerOf(const {'kind': 'parking'}, pin: false), PlaceTiles.dotsLayer);
    });

    test('the selection, the marker, the clusters and the points of interest', () {
      expect(
        hitLayerOf(const {'kind': 'place', 'icon': 'pin-parking-allowed-selected'}, pin: true),
        MapStyle.selectionPinLayer,
      );
      expect(
        hitLayerOf(const {'kind': 'place', 'icon': 'pin-parking-allowed'}, pin: true),
        MapStyle.placesLayer,
      );
      expect(hitLayerOf(const {'kind': 'point'}, pin: true), MapStyle.selectionPinLayer);
      expect(
        hitLayerOf(const {'point_count': 3, 'cluster_id': 1}, pin: false),
        MapStyle.clustersLayer,
      );
      expect(hitLayerOf(const {'kind': 'bakery', 'id': 'p'}, pin: true), PoiMapStyle.pinsLayerId);
      expect(
        hitLayerOf(const {'kind': 'bakery', 'id': 'p', 'icon': 'poi-bakery-selected'}, pin: true),
        PoiMapStyle.selectionLayerId,
      );
      expect(
        hitLayerOf(const {'category': 'vending', 'count': 4}, pin: false),
        PoiMapStyle.dotsLayerId,
      );
      expect(hitLayerOf(const {'kind': 'bakery', 'id': 'p'}, pin: false), PoiMapStyle.quietLayerId);
    });

    test('every layer a tap queries has a shape', () {
      for (final layer in [...pinHitLayers, ...otherHitLayers, ...MapStyle.tappableLayers]) {
        expect(mapHitShapes, contains(layer), reason: layer);
      }
      for (final layer in [...PlaceTiles.tappable, ...PoiMapStyle.tappable]) {
        expect([...pinHitLayers, ...otherHitLayers], contains(layer), reason: layer);
      }
    });
  });

  test('a point is drawn where Web Mercator puts it, the nearer way round the world', () {
    const reference = LatLng(45, 6);
    const at = Offset(100, 100);
    // One degree east at zoom 10: 512 * 1024 / 360 px.
    final east = screenOf(const LatLng(45, 7), reference: reference, referenceAt: at, zoom: 10);
    expect(east.dx - at.dx, closeTo(512 * 1024 / 360, 1e-6));
    expect(east.dy, closeTo(100, 1e-9));
    final north = screenOf(const LatLng(45.01, 6), reference: reference, referenceAt: at, zoom: 10);
    expect(north.dy, lessThan(100));
    final across = screenOf(
      const LatLng(0, -179),
      reference: const LatLng(0, 179),
      referenceAt: Offset.zero,
      zoom: 0,
    );
    expect(across.dx, closeTo(512 * 2 / 360, 1e-9));
  });

  test('the points of a geometry', () {
    expect(
      pointsOfGeometry(const {
        'type': 'MultiPoint',
        'coordinates': [
          [6.1, 45.9],
          [6.2, 46.0],
        ],
      }),
      const [LatLng(45.9, 6.1), LatLng(46, 6.2)],
    );
    expect(pointsOfGeometry(const {'type': 'LineString', 'coordinates': <Object>[]}), isEmpty);
  });

  group("the map pages' copy of the rule", () {
    test('is the same block in every page', () {
      final blocks = [
        for (final page in _pages) _block.firstMatch(File(page).readAsStringSync())?.group(0),
      ];
      expect(blocks.first, isNotNull, reason: '${_pages.first} lost its MAP HITS markers');
      for (var i = 1; i < blocks.length; i++) {
        expect(blocks[i], blocks.first, reason: '${_pages[i]} differs from ${_pages.first}');
      }
    });

    test("reads the app's shapes", () {
      final expected = hitShapesJson();
      for (final page in _pages) {
        final file = File(page);
        final text = file.readAsStringSync();
        final match = _shapes.firstMatch(text);
        expect(match, isNotNull, reason: '$page lost its HIT SHAPES markers');
        if (Platform.environment['UPDATE_MAP_HITS'] == '1') {
          file.writeAsStringSync(
            text.replaceFirst(
              _shapes,
              '/* BEGIN HIT SHAPES */ ${jsonEncode(expected)} /* END HIT SHAPES */',
            ),
          );
          continue;
        }
        expect(
          jsonDecode(match!.group(1)!),
          jsonDecode(jsonEncode(expected)),
          reason: 'run UPDATE_MAP_HITS=1 fvm flutter test test/unit/map_hits_test.dart',
        );
      }
    });

    bool hasNode() {
      try {
        return Process.runSync('node', ['--version']).exitCode == 0;
      } on ProcessException {
        return false;
      }
    }

    final node = hasNode();
    test('decides every case as the app does', () async {
      final block = _block.firstMatch(File(_pages.first).readAsStringSync())!.group(0)!;
      const script = r'''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const hits = new Function(input.block + '\nreturn lunawayHits;')();
const out = input.cases.map((c) => {
  const h = hits.nearest(c.at, c.candidates, c.zoom, c.tolerance);
  return h ? [h.index, h.pointIndex] : null;
});
process.stdout.write(JSON.stringify(out));
''';
      final process = await Process.start('node', ['-e', script]);
      process.stdin.write(jsonEncode({'block': block, 'cases': _cases.map(_caseJson).toList()}));
      await process.stdin.close();
      final output = await process.stdout.transform(utf8.decoder).join();
      final errors = await process.stderr.transform(utf8.decoder).join();
      expect(await process.exitCode, 0, reason: errors);
      final decided = jsonDecode(output) as List<Object?>;
      for (var i = 0; i < _cases.length; i++) {
        final e = _cases[i].expected;
        expect(decided[i], e == null ? null : [e.$1, e.$2], reason: _cases[i].name);
      }
    }, skip: node ? false : 'needs node on the PATH (the CI has it)');
  });
}
