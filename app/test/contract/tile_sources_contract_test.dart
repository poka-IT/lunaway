import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/tile_json_source.dart';

/// What MapLibre GL JS reads from a vector source's TileJSON, and how: a
/// key the source states itself wins over the TileJSON's
/// (`loadTileJson`: `pick(extend(tileJSON, options), keys)`, in
/// `assets/map/maplibre-gl.js` and `web/maplibre-gl/`).
const _tileJsonKeys = [
  'tiles',
  'minzoom',
  'maxzoom',
  'attribution',
  'bounds',
  'scheme',
  'tileSize',
  'encoding',
];

Map<String, Object?> _asLoadedByGlJs(Map<String, Object?> source, Map<String, Object?> tileJson) =>
    {
      for (final key in _tileJsonKeys)
        if (source.containsKey(key))
          key: source[key]
        else if (tileJson.containsKey(key))
          key: tileJson[key],
    };

Map<String, Object?> _vectorLayer(Map<String, Object?> tileJson, String id) =>
    (tileJson['vector_layers']! as List<Object?>).cast<Map<String, Object?>>().singleWhere(
      (l) => l['id'] == id,
      orElse: () => fail('the TileJSON has no layer $id'),
    );

/// The map's sources against the TileJSON the API serves, as the backend
/// exports it (`schema/tilejson.json`, `cargo run -p lunaway-api --bin
/// export-schema`, held to the code by `committed_tilejson_matches_the_code`):
/// when either side changes, this names what drifted.
void main() {
  final contract =
      jsonDecode(File('../schema/tilejson.json').readAsStringSync()) as Map<String, Object?>;
  final places = contract['places']! as Map<String, Object?>;
  final poi = contract['poi']! as Map<String, Object?>;

  for (final (name, tileJson) in [('places', places), ('poi', poi)]) {
    test('the $name source asks for the zooms and the area its TileJSON serves', () {
      final url = 'https://api.lunaway.net/$name/tiles.json';
      final source = tileJsonSource(url).toJson();
      final loaded = _asLoadedByGlJs(source, tileJson);
      expect(source['url'], url);
      expect(loaded['minzoom'], tileJson['minzoom'], reason: 'below it the API answers 404');
      expect(loaded['maxzoom'], tileJson['maxzoom'], reason: 'above it the API answers 404');
      expect(loaded['bounds'], tileJson['bounds']);
      expect(loaded['tiles'], tileJson['tiles']);
    });
  }

  test("the places' layers read the tile layers at the zooms they hold", () {
    final pins = _vectorLayer(places, PlaceTiles.pinsSourceLayer);
    final dots = _vectorLayer(places, PlaceTiles.dotsSourceLayer);
    expect(pins['minzoom'], PlaceTiles.pinZoom, reason: 'the pins start where the tiles do');
    expect(dots['maxzoom'], PlaceTiles.pinZoom - 1, reason: 'the dots stop below the pins');
    final fields = (pins['fields']! as Map<String, Object?>).keys;
    expect(
      fields,
      containsAll(<String>[
        PlaceTiles.id,
        PlaceTiles.kind,
        PlaceTiles.night,
        PlaceTiles.services,
        PlaceTiles.price,
        PlaceTiles.height,
        PlaceTiles.rating,
        PlaceTiles.name,
        PlaceTiles.city,
      ]),
    );
    // The filters run on the device over both layers (placeTileFilter).
    expect(
      (dots['fields']! as Map<String, Object?>).keys,
      containsAll(<String>[
        PlaceTiles.kind,
        PlaceTiles.night,
        PlaceTiles.services,
        PlaceTiles.price,
        PlaceTiles.height,
        PlaceTiles.rating,
      ]),
    );
    final nameFrom = RegExp(r'from zoom (\d+)')
        .firstMatch((pins['fields']! as Map<String, Object?>)[PlaceTiles.name]! as String)
        ?.group(1);
    expect(nameFrom, '${PlaceTiles.nameZoom.toInt()}', reason: 'the list reads names from there');
  });

  test("the points' layers read the tile layers at the zooms they hold", () {
    final points = _vectorLayer(poi, PoiMapStyle.pointsLayer);
    final clusters = _vectorLayer(poi, PoiMapStyle.clustersLayer);
    final vending = _vectorLayer(poi, PoiMapStyle.vendingClustersLayer);
    expect(points['minzoom'], PoiMapStyle.pointsMinZoom);
    expect(clusters['maxzoom'], PoiMapStyle.pointsMinZoom - 1);
    expect(vending['maxzoom'], PoiMapStyle.pointsMinZoom - 1);
  });
}
