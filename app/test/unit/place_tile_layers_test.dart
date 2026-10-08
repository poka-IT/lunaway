import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/map/presentation/place_tile_layers.dart';
import 'package:lunaway/features/map/presentation/web_view_map.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/map_look.dart';

double _at(List<Object> expression, double zoom) => interpolateStops([
  for (var i = 3; i + 1 < expression.length; i += 2)
    ((expression[i] as num).toDouble(), (expression[i + 1] as num).toDouble()),
], zoom);

void main() {
  const view = PlaceTilesView(
    tileJsonUrl: 'https://api.lunaway.net/places/tiles.json',
    filter: PlaceFilter(families: {KindFamily.campsites}),
  );

  test("the first layer of names is the same in both of the app's basemaps", () {
    for (final name in ['aube', 'minuit']) {
      final style = jsonDecode(
        File('assets/map/styles/$name.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final firstSymbol = (style['layers']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((l) => l['type'] == 'symbol');
      expect(firstSymbol['id'], PlaceTiles.basemapFirstLabel, reason: name);
    }
  });

  test("the country's view draws a glow and fine dots under the towns' names, the pins above", () {
    final layers = placeTileStyleLayers(view, dark: true);
    final byId = {for (final l in layers) l['id']: l};
    expect(byId[PlaceTiles.glowLayer]!['type'], 'circle');
    expect(byId[PlaceTiles.glowLayer]!['source-layer'], PlaceTiles.dotsSourceLayer);
    expect(byId[PlaceTiles.glowLayer]!['before'], PlaceTiles.basemapFirstLabel);
    expect(byId[PlaceTiles.dotsLayer]!['before'], PlaceTiles.basemapFirstLabel);
    expect(byId[PlaceTiles.pinsLayer]!.containsKey('before'), isFalse);
    expect(byId[PlaceTiles.pinDotsLayer]!.containsKey('before'), isFalse);
    expect(
      layers.indexWhere((l) => l['id'] == PlaceTiles.glowLayer),
      lessThan(layers.indexWhere((l) => l['id'] == PlaceTiles.dotsLayer)),
      reason: 'the dots over the glow',
    );
    // A map whose style has no names to go under (the desktop's, before its
    // style is known) adds them on top.
    expect(
      placeTileStyleLayers(view, dark: true, labels: null).any((l) => l.containsKey('before')),
      isFalse,
    );
  });

  test("the desktop's page sets a new filter on every layer of the places that has one", () {
    final spec = webViewMapSpec(dark: false, language: 'fr', tiles: view);
    final filtered = [
      for (final l in (spec['layers']! as List).cast<Map<String, Object?>>())
        if (l['source'] == PlaceTiles.source && l.containsKey('filter')) l['id'],
    ];
    expect(filtered, containsAll(<String>[PlaceTiles.glowLayer, PlaceTiles.dotsLayer]));
    expect(
      ((spec['placeTiles']! as Map<String, Object?>)['layers']! as List).toSet(),
      filtered.toSet(),
      reason: 'setPlaceTiles filters these layers: the glow among them',
    );
    expect(PlaceTiles.filteredLayers.toSet(), filtered.toSet());
  });

  test('the glow follows the filters, as the dots do', () {
    for (final layer in placeTileStyleLayers(view, dark: false)) {
      expect(layer['filter'], placeTileFilter(view.filter), reason: '${layer['id']}');
    }
  });

  test('both engines draw the same glow, in the colours of the theme', () {
    for (final dark in [false, true]) {
      expect(
        GlPlaceTiles.glow(dark: dark).toJson(),
        {...placeTileGlowPaint(dark: dark)}..removeWhere((_, v) => v == null),
      );
    }
    expect(MapLook.glowColor(dark: true), isNot(MapLook.glowColor(dark: false)));
    expect(MapLook.glowBlur, 1, reason: 'a disc with no edge');
  });

  test('the glow gives way to the dots from zoom 7, before the pins', () {
    for (final dark in [false, true]) {
      expect(_at(MapLook.glowOpacity(dark: dark), 6), greaterThan(0));
      expect(_at(MapLook.glowOpacity(dark: dark), MapLook.glowMaxZoom), 0);
    }
    expect(MapLook.glowMaxZoom, lessThan(PlaceTiles.pinZoom));
    expect(_at(MapLook.dotOpacity, 7), MapLook.dotOpacity.last);
    expect(_at(MapLook.dotStrokeOpacity, 5), 0, reason: 'no rim on a grain');
    expect(_at(MapLook.dotStrokeOpacity, 7), 1);
    // Fine grains in the country's view: a dot of a finger's map at zoom
    // 5.5 was 2.9 px wide in radius (15.3 physical px across on the
    // emulator), and 38 % of the map was dots.
    expect(_at(MapLook.touchDotRadius, 5.5), lessThan(2));
    expect(_at(MapLook.dotRadius, 5.5), lessThan(1.5));
  });
}
