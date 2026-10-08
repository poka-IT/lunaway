import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/place_tile_layers.dart';
import 'package:lunaway/features/map/presentation/premap_spec.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';

/// The block of `web/premap.js` that holds its copy of [premapDefaults].
final _block = RegExp(r'/\* BEGIN DEFAULTS \*/([\s\S]*?)/\* END DEFAULTS \*/');

void main() {
  test("the page's first map draws what the app draws at a first visit", () {
    final file = File('web/premap.js');
    final text = file.readAsStringSync();
    final match = _block.firstMatch(text);
    expect(match, isNotNull, reason: 'web/premap.js lost its DEFAULTS markers');
    final expected = premapDefaults();
    if (Platform.environment['UPDATE_PREMAP'] == '1') {
      file.writeAsStringSync(
        text.replaceFirst(
          _block,
          '/* BEGIN DEFAULTS */ ${jsonEncode(expected)} /* END DEFAULTS */',
        ),
      );
      return;
    }
    expect(
      jsonDecode(match!.group(1)!),
      jsonDecode(jsonEncode(expected)),
      reason: 'run UPDATE_PREMAP=1 fvm flutter test test/unit/premap_test.dart',
    );
  });

  test('the state kept for the next visit names the view, the theme and the filters', () {
    final state = premapState(
      basemapBase: 'https://tiles.example.org',
      placesTileJson: 'https://api.example.org/places/tiles.json',
      dark: true,
      language: 'fr-FR',
      center: const LatLng(45.9, 6.1),
      zoom: 11.5,
      filter: const PlaceFilter(freeOnly: true),
    );
    expect(state['v'], premapVersion);
    expect(state['style'], 'minuit');
    expect(state['lang'], 'fr');
    expect(state['center'], [6.1, 45.9], reason: 'MapLibre reads longitude first');
    expect(state['zoom'], 10, reason: 'no finer than the phones keep their last view');
    final fine = premapState(
      basemapBase: 'https://tiles.example.org',
      placesTileJson: 'https://api.example.org/places/tiles.json',
      dark: false,
      language: 'en',
      center: const LatLng(45.91234, 6.12891),
      zoom: 16,
    );
    expect(fine['center'], [6.1, 45.9], reason: 'a tenth of a degree, never the spot');
    expect(fine['zoom'], 10);
    final layers = (state['layers']! as List).cast<Map<String, Object?>>();
    expect(layers.map((l) => l['id']), [PlaceTiles.heatLayer, ...PlaceTiles.tappable.reversed]);
    expect(
      [for (final l in layers) l['before']],
      [PlaceTiles.basemapFirstLabel, PlaceTiles.basemapFirstLabel, null, null],
      reason: "the glow and the country's dots under the towns' names, the pins above",
    );
    for (final layer in layers) {
      expect(layer['filter'], placeTileFilter(const PlaceFilter(freeOnly: true)));
    }
    expect(
      layers,
      placeTileStyleLayers(
        const PlaceTilesView(
          tileJsonUrl: 'https://api.example.org/places/tiles.json',
          filter: PlaceFilter(freeOnly: true),
        ),
        dark: true,
      ),
    );
  });
}
