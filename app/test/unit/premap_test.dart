import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/place_tile_layers.dart';
import 'package:lunaway/features/map/presentation/premap_spec.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';

/// The block of `web/premap.js` that holds its copy of [premapDefaults].
final _block = RegExp(r'/\* BEGIN DEFAULTS \*/([\s\S]*?)/\* END DEFAULTS \*/');

/// The block of `web/premap.js` that decides whether a kept view opens.
final _usable = RegExp(r'/\* BEGIN USABLE[^*]*\*/([\s\S]*?)/\* END USABLE \*/');

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test('a view kept out at sea is not opened again, one where places are is', () async {
    final block = _usable.firstMatch(File('web/premap.js').readAsStringSync())!.group(1)!;
    Map<String, Object?> kept(double lon, double lat) => premapState(
      basemapBase: AppConfig.publicBasemap,
      placesTileJson: '${AppConfig.publicApi}/places/tiles.json',
      dark: false,
      language: 'fr',
      center: LatLng(lat, lon),
      zoom: 3.9,
    );
    final cases = {
      // What a phone page kept before the viewport tag, at the first and
      // the second visit.
      'first visit': (kept(-11.8, 46.5), false),
      'second visit': (kept(-25.8, 46.5), false),
      'off Brittany': (kept(-9.9, 46.5), false),
      'Annecy': (kept(6.1, 45.9), true),
      'Lisbon': (kept(-9.1, 38.7), true),
    };
    const script = r'''
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const usable = new Function(input.block + '\nreturn usable;')();
process.stdout.write(JSON.stringify(input.states.map((s) => usable(s, input.defaults))));
''';
    final process = await Process.start('node', ['-e', script]);
    process.stdin.write(
      jsonEncode({
        'block': block,
        'defaults': premapDefaults(),
        'states': [for (final c in cases.values) c.$1],
      }),
    );
    await process.stdin.close();
    final output = await process.stdout.transform(utf8.decoder).join();
    final errors = await process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0, reason: errors);
    final decided = (jsonDecode(output) as List<Object?>).cast<bool>();
    expect(Map.fromIterables(cases.keys, decided), cases.map((name, c) => MapEntry(name, c.$2)));
  }, skip: _hasNode() ? false : 'needs node on the PATH (the CI has it)');

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
    expect(layers.map((l) => l['id']), [PlaceTiles.glowLayer, ...PlaceTiles.tappable.reversed]);
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
