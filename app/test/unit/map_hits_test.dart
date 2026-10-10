import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_hit_shapes.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// The pages that pick features themselves, each with the same block.
const _pages = ['web/lunaway_maplibre.js', 'assets/map/lunaway_map.js'];
final _block = RegExp(r'  // BEGIN MAP HITS\n[\s\S]*?  // END MAP HITS\n');
final _shapes = RegExp(r'/\* BEGIN HIT SHAPES \*/([\s\S]*?)/\* END HIT SHAPES \*/');

final Map<String, HitShape> _shapesByLayer = {
  ...mapHitShapes,
  ...routeHitShapes,
  ...routePlaceHitShapes,
};

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
    name: "on a place's exact point, its pin is picked as on its head, not the dot under it",
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinDotsLayer, [_here], {'kind': 'parking', 'id': 'a'}),
      _c(PlaceTiles.pinsLayer, [_here], {'kind': 'parking', 'id': 'a'}),
    ],
    expected: (1, 0),
  ),
  (
    name: 'just under the point, out of the dot, still the pin',
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinDotsLayer, [_here - const Offset(0, 9)], {'kind': 'parking', 'id': 'a'}),
      _c(PlaceTiles.pinsLayer, [_here - const Offset(0, 9)], {'kind': 'parking', 'id': 'a'}),
    ],
    expected: (1, 0),
  ),
  (
    name: "another place's dot under the pointer beats a pin whose tip is near",
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinsLayer, [_here + const Offset(9, 0)], {'kind': 'parking', 'id': 'a'}),
      _c(PlaceTiles.pinDotsLayer, [_here], {'kind': 'campsite', 'id': 'b'}),
    ],
    expected: (1, 0),
  ),
  (
    name: "a finger on bare ground 20 px under a point of interest's pin is no tap on it",
    at: _here,
    zoom: 15,
    tolerance: _touch,
    candidates: [
      _c(PoiMapStyle.pinsLayerId, [_here - const Offset(0, 20)], {'kind': 'bakery', 'id': 'p'}),
    ],
    expected: null,
  ),
  (
    name: "nor under a pin of the device's places, which has no dot under it",
    at: _here,
    zoom: 13,
    tolerance: _touch,
    candidates: [
      _c(MapStyle.placesLayer, [_here - const Offset(0, 20)], {'kind': 'place', 'id': 'a'}),
    ],
    expected: null,
  ),
  (
    name: "on a selected place's point, the selection wins over the pin it stands on",
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(MapStyle.selectionPinLayer, [_here], {'kind': 'place', 'id': 'a'}),
      _c(PlaceTiles.pinsLayer, [_here], {'kind': 'parking', 'id': 'a'}),
      _c(PlaceTiles.pinDotsLayer, [_here], {'kind': 'parking', 'id': 'a'}),
    ],
    expected: (0, 0),
  ),
  (
    name: "on a selected point of interest's point, the selection wins over its pin",
    at: _here,
    zoom: 15,
    tolerance: _mouse,
    candidates: [
      _c(PoiMapStyle.pinsLayerId, [_here], {'kind': 'bakery', 'id': 'p'}),
      _c(PoiMapStyle.selectionLayerId, [_here], {'kind': 'bakery', 'id': 'p'}),
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
    name: "a point of the category chosen over a place's pin: the point, drawn on top",
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PlaceTiles.pinsLayer, [_here + const Offset(0, 20)], {'kind': 'parking', 'id': 'a'}),
      _c(PoiMapStyle.pinsLayerId, [_here + const Offset(0, 18)], {'kind': 'museum', 'id': 'm'}),
    ],
    expected: (1, 0),
  ),
  (
    name: "offline, a device's place over a point of the category chosen: the place, drawn on top",
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PoiMapStyle.pinsLayerId, [_here + const Offset(0, 18)], {'kind': 'museum', 'id': 'm'}),
      _c(MapStyle.placesLayer, [_here + const Offset(0, 20)], {'kind': 'place', 'id': 'a'}),
    ],
    expected: (1, 0),
  ),
  (
    name: 'a saved point over a point of the category chosen: the saved point, drawn on top',
    at: _here,
    zoom: 13,
    tolerance: _mouse,
    candidates: [
      _c(PoiMapStyle.pinsLayerId, [_here + const Offset(0, 18)], {'kind': 'museum', 'id': 'm'}),
      _c(MapStyle.savedLayer, [_here + const Offset(0, 22)], {'kind': savedFeatureKind, 'id': 's'}),
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
    name: 'a minor route mark, drawn smaller, is a smaller target',
    at: _here,
    zoom: 0,
    tolerance: _touch,
    candidates: [
      _c(
        RouteLayers.badgesOf(RouteLayers.minorSource),
        [_here + const Offset(36, 0)],
        {'kind': 'place', 'mark': 'place:1', 'size': routeMinorScale},
      ),
      _c(
        RouteLayers.badgesOf(RouteLayers.marksSource),
        [_here + const Offset(36, 0)],
        {'kind': 'works', 'mark': 'event:0:1', 'size': 1},
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
        RouteLayers.badgesOf(RouteLayers.stopsSource),
        [_here + const Offset(20, 0)],
        {'kind': 'stop', 'mark': 'stop:0', 'size': 1},
      ),
    ],
    expected: (1, 0),
  ),
  (
    name: 'a place drawn large over a stop: the place, drawn on top',
    at: _here,
    zoom: 15,
    tolerance: _touch,
    candidates: [
      _c(
        RouteLayers.badgesOf(RouteLayers.stopsSource),
        [_here + const Offset(4, 0)],
        {'kind': 'stop', 'mark': 'stop:0', 'size': 1},
      ),
      // Its head, 20 px wide, 30 px over its place: on the pointer.
      _c(RichLayers.marks, [_here + const Offset(0, 30)], {'id': 'p', 'hr': 20, 'lift': 30}),
    ],
    expected: (1, 0),
  ),
  (
    name: 'the arrival over a place drawn large: the arrival, drawn on top',
    at: _here,
    zoom: 15,
    tolerance: _touch,
    candidates: [
      _c(RichLayers.marks, [_here + const Offset(0, 30)], {'id': 'p', 'hr': 20, 'lift': 30}),
      _c(
        RouteLayers.badgesOf(RouteLayers.endsSource),
        [_here + const Offset(4, 0)],
        {'kind': 'destination', 'mark': 'destination', 'size': 1},
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

    test('the marker of a bare point is picked as the marker, no empty map', () {
      final hit = nearestHit(
        _here,
        [
          _c(MapStyle.selectionPinLayer, [_here + const Offset(0, 27)], {'kind': 'point'}),
        ],
        shapes: mapHitShapes,
        zoom: 14,
        tolerance: _touch,
      );
      expect(hit?.marker, isTrue);
    });
  });

  group("a finger's dots in the country view", () {
    double at(List<Object> expression, double zoom) => interpolateStops([
      for (var i = 3; i + 1 < expression.length; i += 2)
        ((expression[i] as num).toDouble(), (expression[i + 1] as num).toDouble()),
    ], zoom);

    test('the phone apps draw them larger from zoom 7, as a mouse does from the street, and the '
        "same grains on the country's glow", () {
      for (final zoom in [6.5, 7.0, 8.0]) {
        expect(
          at(MapLook.touchDotRadius, zoom),
          greaterThan(at(MapLook.dotRadius, zoom) * 1.2),
          reason: 'zoom $zoom',
        );
      }
      for (final zoom in [3.0, 4.0, 5.0]) {
        expect(at(MapLook.touchDotRadius, zoom), at(MapLook.dotRadius, zoom), reason: 'zoom $zoom');
      }
      expect(at(MapLook.touchDotRadius, 12), at(MapLook.dotRadius, 12));
      expect(GlPlaceTiles.dots(dark: false, touch: true).circleRadius, MapLook.touchDotRadius);
      expect(GlPlaceTiles.dots(dark: false, touch: false).circleRadius, MapLook.dotRadius);
    });

    test("only the phone and tablet apps draw and pick a finger's dots; the browser keeps the "
        "mouse's", () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(fingerDots(web: false, platform: platform), isTrue, reason: '$platform');
        expect(fingerDots(web: true, platform: platform), isFalse, reason: 'browser on $platform');
      }
      expect(placeHitShapes(fingerDots: true), same(touchMapHitShapes));
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        expect(fingerDots(web: false, platform: platform), isFalse, reason: '$platform');
      }
      expect(placeHitShapes(fingerDots: false), same(mapHitShapes));
    });

    test('a touch picks the dot within 22 px of the larger dot drawn, and no further', () {
      const zoom = 7.0;
      final drawn = at(MapLook.touchDotRadius, zoom) + at(MapLook.dotStrokeWidth, zoom);
      expect(
        touchMapHitShapes[PlaceTiles.dotsLayer]!.radius.at(zoom, const {}),
        closeTo(drawn, 1e-9),
      );
      HitCandidate dotAt(double dx) =>
          _c(PlaceTiles.dotsLayer, [_here + Offset(dx, 0)], {'kind': 'parking'});
      MapHit? pick(double dx) =>
          nearestHit(_here, [dotAt(dx)], shapes: touchMapHitShapes, zoom: zoom, tolerance: _touch);
      // A hair inside the edge of the reach: the two sums of the stops may
      // round apart in the last bit.
      expect(pick(drawn + _touch - 1e-9), isNotNull);
      expect(pick(drawn + _touch + 0.5), isNull);
      // The browser keeps the mouse's dot: its pages read mapHitShapes.
      expect(mapHitShapes[PlaceTiles.dotsLayer]!.radius.at(zoom, const {}), lessThan(drawn - 0.5));
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

    group('shows one look per place under the mouse', () {
      // A place of the tiles at zoom 13, its point on screen at _here: the
      // pin and the dot under its tip are the same feature of the same
      // source, drawn by two layers.
      const zoom = 13.0;
      const place = {'kind': 'parking', 'night': 'allowed', 'id': 'a'};
      Map<String, Object?> tileFeature(String layer) => {
        'source': PlaceTiles.source,
        'sourceLayer': PlaceTiles.pinsSourceLayer,
        'layer': {
          'id': layer,
          'layout': {
            if (layer == PlaceTiles.pinsLayer) 'icon-image': {'name': 'pin-parking-allowed'},
          },
        },
      };
      Map<String, Object?> candidate(
        String layer,
        Map<String, Object?> properties,
        Map<String, Object?> feature, {
        Offset at = _here,
      }) => {
        'layer': layer,
        'properties': properties,
        'points': [
          [at.dx, at.dy],
        ],
        'coordinates': [
          [1.5, 43.5],
        ],
        'feature': feature,
      };
      final pinAndDot = [
        candidate(PlaceTiles.pinsLayer, place, tileFeature(PlaceTiles.pinsLayer)),
        candidate(PlaceTiles.pinDotsLayer, place, tileFeature(PlaceTiles.pinDotsLayer)),
      ];
      final head = _here - Offset(0, mapHitShapes[PlaceTiles.pinsLayer]!.lift.at(zoom, place));
      final dotRing =
          mapHitShapes[PlaceTiles.pinDotsLayer]!.radius.at(zoom, place) + MapLook.hoverRingGap;

      /// What the page's hover shows with the mouse at each point of [at]
      /// over [candidates], as `lunawayHits.look` describes it.
      Future<List<Map<String, Object?>?>> looks(
        List<Offset> at,
        List<Map<String, Object?>> candidates,
      ) async {
        final block = _block.firstMatch(File(_pages.first).readAsStringSync())!.group(0)!;
        const script = r'''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const hits = new Function(input.block + '\nreturn lunawayHits;')();
const out = input.at.map((at) => {
  const h = hits.nearest(at, input.candidates, input.zoom, input.tolerance);
  if (!h) return null;
  const c = input.candidates[h.index];
  return hits.look({
    layer: c.layer,
    properties: c.properties,
    point: c.points[h.pointIndex],
    coordinates: c.coordinates[h.pointIndex],
    shape: hits.shapeOf(c.layer, c.properties),
    zoom: input.zoom,
    marker: h.marker,
    feature: c.feature
  });
});
process.stdout.write(JSON.stringify(out));
''';
        final process = await Process.start('node', ['-e', script]);
        process.stdin.write(
          jsonEncode({
            'block': block,
            'zoom': zoom,
            'tolerance': _mouse,
            'candidates': candidates,
            'at': [
              for (final p in at) [p.dx, p.dy],
            ],
          }),
        );
        await process.stdin.close();
        final output = await process.stdout.transform(utf8.decoder).join();
        final errors = await process.stderr.transform(utf8.decoder).join();
        expect(await process.exitCode, 0, reason: errors);
        return [
          for (final l in jsonDecode(output) as List<Object?>) (l as Map?)?.cast<String, Object?>(),
        ];
      }

      test('the pin from its head and from its exact point: one ring around the point, the '
          'pin grown', () async {
        final [fromHead, fromPoint, fromBelow] = await looks([
          head,
          _here,
          _here + const Offset(0, 8),
        ], pinAndDot);
        expect(fromHead, isNotNull);
        expect(fromPoint, fromHead);
        expect(fromBelow, fromHead);
        expect([fromHead!['x'], fromHead['y']], [_here.dx, _here.dy], reason: 'on the point');
        expect(fromHead['ring']! as num, closeTo(dotRing, 1e-9));
        expect(fromHead['pin'], {
          'image': 'pin-parking-allowed',
          // Full size from zoom 12 (MapLook.pinSize).
          'size': 1,
        });
      });

      test('a dot whose pin found no room: the same ring, nothing grows', () async {
        final [look] = await looks([_here], [pinAndDot.last]);
        final [pinLook] = await looks([_here], pinAndDot);
        expect(look!['key'], isNot(pinLook!['key']), reason: 'a pin drawn later shows anew');
        expect(
          [look['x'], look['y'], look['ring'], look['pin']],
          [pinLook['x'], pinLook['y'], pinLook['ring'], null],
        );
      });

      test("a cluster's ring goes around its disc", () async {
        const props = {'point_count': 50, 'cluster_id': 7};
        final [look] = await looks(
          [_here],
          [
            candidate(MapStyle.clustersLayer, props, {'source': MapStyle.placesSource, 'id': 7}),
          ],
        );
        final r = mapHitShapes[MapStyle.clustersLayer]!.radius.at(zoom, props);
        expect(look!['ring']! as num, closeTo(r + MapLook.hoverRingGap, 1e-9));
        expect(look['pin'], isNull);
      });

      test('a route mark is told the mouse is on it, a group is not', () async {
        final layer = RouteLayers.badgesOf(RouteLayers.marksSource);
        final [mark, group] = await looks(
          [_here, _here + const Offset(200, 0)],
          [
            candidate(
              layer,
              {'mark': 'event:0:1', 'kind': 'works', 'size': 1},
              {'source': RouteLayers.marksSource, 'id': 1000000003},
            ),
            candidate(
              layer,
              {'point_count': 3, 'cluster_id': 9, 'size': 1},
              {'source': RouteLayers.marksSource, 'id': 9},
              at: _here + const Offset(200, 0),
            ),
          ],
        );
        expect(mark!['state'], {'source': RouteLayers.marksSource, 'id': 1000000003});
        expect(mark['ring']! as num, closeTo(15.5 + MapLook.hoverRingGap, 1e-9));
        expect(group!['state'], isNull);
      });

      test("a point of interest's pin grows over the same ring; drawn faded, it keeps its look; "
          'a selection keeps its own', () async {
        const zoom15 = {'kind': 'bakery', 'id': 'p'};
        Map<String, Object?> poi(String layer, {double opacity = 1, String image = 'poi-bakery'}) =>
            candidate(layer, zoom15, {
              'source': PoiMapStyle.source,
              'sourceLayer': PoiMapStyle.pointsLayer,
              'layer': {
                'id': layer,
                'layout': {
                  'icon-image': {'name': image},
                },
                'paint': {'icon-opacity': opacity},
              },
            });
        final [open, closed, chosen] = await Future.wait([
          looks([_here], [poi(PoiMapStyle.pinsLayerId)]),
          looks([_here], [poi(PoiMapStyle.pinsLayerId, opacity: 0.42)]),
          looks([_here], [poi(PoiMapStyle.selectionLayerId, image: 'poi-bakery-selected')]),
        ]);
        expect(open.single!['ring']! as num, closeTo(dotRing, 1e-9), reason: "a place's ring");
        expect((open.single!['pin']! as Map)['image'], 'poi-bakery');
        expect(closed.single!['pin'], isNull);
        expect(chosen.single!['pin'], isNull);
        expect(chosen.single!['ring']! as num, closeTo(dotRing, 1e-9));
      });
    }, skip: node ? false : 'needs node on the PATH (the CI has it)');

    test('the hover drops the copy of a pin a click redraws, and grows it again from the new '
        'drawing', () async {
      final block = _block.firstMatch(File(_pages.first).readAsStringSync())!.group(0)!;
      // A page reduced to what the hover touches: elements that hold
      // children, a map whose query answers [features], frames run on
      // demand. Coordinates are screen pixels (the projection is the
      // identity).
      const script = r'''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
function El(tag) {
  this.tagName = tag.toUpperCase();
  this.children = [];
  this.parentNode = null;
  this.style = {};
  const set = new Set();
  this.classList = { toggle: (c, on) => (on ? set.add(c) : set.delete(c)), add: (c) => set.add(c), remove: (c) => set.delete(c) };
}
El.prototype.appendChild = function (c) { if (c.parentNode) c.remove(); c.parentNode = this; this.children.push(c); return c; };
El.prototype.remove = function () { const p = this.parentNode; if (p) { p.children = p.children.filter((x) => x !== this); this.parentNode = null; } };
El.prototype.getContext = function () { return { putImageData() {} }; };
El.prototype.dispatchEvent = function (e) { hovers.push(e.detail ? e.detail.layer : null); };
Object.defineProperty(El.prototype, 'offsetWidth', { get() { return 0; } });
Object.defineProperty(El.prototype, 'textContent', { set() { this.children.slice().forEach((c) => c.remove()); } });
const hovers = [];
let frames = [];
globalThis.document = { createElement: (t) => new El(t), addEventListener() {} };
globalThis.ImageData = function () {};
globalThis.CustomEvent = function (type, init) { this.type = type; this.detail = init.detail; };
globalThis.requestAnimationFrame = (f) => { frames.push(f); return frames.length; };
globalThis.cancelAnimationFrame = () => {};
const hits = new Function(input.block + '\nreturn lunawayHits;')();
const container = new El('div');
const handlers = {};
let features = [];
const map = {
  on(type, f) { (handlers[type] = handlers[type] || []).push(f); },
  getCanvasContainer: () => container,
  getLayer: () => ({}),
  queryRenderedFeatures: () => features,
  project: (c) => ({ x: c[0], y: c[1] }),
  unproject: (p) => ({ lng: p[0], lat: p[1] }),
  getZoom: () => 13,
  getImage: () => ({ data: { width: 4, height: 6, data: new Uint8Array(96) }, pixelRatio: 2 }),
  getSource: () => null,
  setFeatureState() {}
};
function fire(type, e) {
  (handlers[type] || []).forEach((f) => f(e || {}));
  const due = frames;
  frames = [];
  due.forEach((f) => f());
}
// What is on screen: each look, as the tags of its parts.
function looks() {
  return container.children.flatMap((root) => root.children.map((l) => l.children.map((c) => c.tagName)));
}
hits.hover(map);
features = input.pinAndDot;
const out = {};
fire('mousemove', { point: { x: 500, y: 385 } });
out.hovered = looks();
fire('mousedown');
out.pressed = looks();
fire('idle');
out.settledSame = looks();
fire('mousedown');
features = [input.selection].concat(input.pinAndDot);
fire('idle');
out.settledSelected = looks();
out.hovers = hovers.slice();
fire('movestart');
out.moved = looks();
process.stdout.write(JSON.stringify(out));
setTimeout(() => process.exit(0), 0);
''';
      Map<String, Object?> feature(
        String layer,
        String source,
        Map<String, Object?> properties, {
        String? image,
        Object? id,
      }) => {
        'layer': {
          'id': layer,
          'layout': {
            'icon-image': ?(image == null ? null : {'name': image}),
          },
          'paint': <String, Object?>{},
        },
        'source': source,
        'sourceLayer': source == PlaceTiles.source ? PlaceTiles.pinsSourceLayer : null,
        'id': ?id,
        'properties': properties,
        'geometry': {
          'type': 'Point',
          'coordinates': [_here.dx, _here.dy],
        },
      };
      const place = {'kind': 'parking', 'night': 'allowed', 'id': 'a'};
      final process = await Process.start('node', ['-e', script]);
      process.stdin.write(
        jsonEncode({
          'block': block,
          'pinAndDot': [
            feature(PlaceTiles.pinsLayer, PlaceTiles.source, place, image: 'pin-parking-allowed'),
            feature(PlaceTiles.pinDotsLayer, PlaceTiles.source, place),
          ],
          'selection': feature(
            MapStyle.selectionPinLayer,
            MapStyle.selectionSource,
            const {'kind': 'place', 'id': 'a', 'icon': 'pin-parking-allowed-selected'},
            image: 'pin-parking-allowed-selected',
            id: 1,
          ),
        }),
      );
      await process.stdin.close();
      final output = await process.stdout.transform(utf8.decoder).join();
      final errors = await process.stderr.transform(utf8.decoder).join();
      expect(await process.exitCode, 0, reason: errors);
      final seen = jsonDecode(output) as Map<String, Object?>;
      expect(seen['hovered'], [
        ['DIV', 'CANVAS'],
      ], reason: 'a ring and the grown copy of the pin');
      expect(seen['pressed'], [
        ['DIV'],
      ], reason: 'the copy goes on the press: the click may redraw the pin under it');
      expect(seen['settledSame'], [
        ['DIV', 'CANVAS'],
      ], reason: 'the map settled, nothing new under the mouse: the copy grows again');
      expect(
        (seen['settledSelected']! as List).expand((l) => l as List),
        isNot(contains('CANVAS')),
        reason: 'the pin drawn selected keeps its own look: no copy of the old one over it',
      );
      expect(seen['hovers'], [PlaceTiles.pinsLayer, MapStyle.selectionPinLayer]);
      expect(seen['moved'], isEmpty, reason: 'the looks do not follow the map: they go');
    }, skip: node ? false : 'needs node on the PATH (the CI has it)');
  });
}
