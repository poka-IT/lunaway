import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';

void main() {
  test('the browser loads every pin and point image the layers name', () {
    // The page loads an image when a layer first draws it, if its id passes
    // this pattern (web/lunaway_maplibre.js). An id it refused stayed
    // undrawn, and its points unclickable: the pizza machines, the fuel
    // stations, every kind whose code holds an underscore.
    final page = File('web/lunaway_maplibre.js').readAsStringSync();
    final source = RegExp('var PIN_ID = /(.+)/;').firstMatch(page)?.group(1);
    expect(source, isNotNull, reason: 'web/lunaway_maplibre.js lost PIN_ID');
    final pattern = RegExp(source!);
    for (final id in [...allPinImageIds(), ...PoiMapStyle.allImageIds()]) {
      expect(pattern.hasMatch(id), isTrue, reason: '$id would never load in the browser');
      for (final ratio in const [2, 3]) {
        expect(
          File('assets/map/pins/${ratio}x/$id.png').existsSync(),
          isTrue,
          reason: 'no ${ratio}x image for $id',
        );
      }
    }
  });
}
