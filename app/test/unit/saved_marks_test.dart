import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/presentation/map_hit_shapes.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/map/presentation/web_view_map.dart';

/// The saved points on the map, the same on every engine: what their layer
/// is given, how a tap on one is read, and that the desktop page says it.
void main() {
  const mark = SavedMark('a1b2', LatLng(48.850699, 2.308628));

  test('a saved point goes to the map as its id and its marker, nothing of its name', () {
    final feature =
        (savedPointsFeatureCollection([mark])['features']! as List<Object?>)
                .single!
            as Map<String, Object?>;
    expect(feature['properties'], {
      'id': 'a1b2',
      'kind': 'saved',
      'icon': savedPointImageId,
    });
    expect((feature['geometry']! as Map)['coordinates'], [2.308628, 48.850699]);
    expect(
      allPinImageIds(),
      contains(savedPointImageId),
      reason: 'the sprite loader has it',
    );
  });

  test('a tap on its marker opens it, whichever engine found it', () {
    final properties = {
      'id': 'a1b2',
      'kind': 'saved',
      'icon': savedPointImageId,
    };
    expect(mapTapFor(properties, [2.3, 48.8]), const TapSaved('a1b2'));
    expect(hitLayerOf(properties, pin: true), MapStyle.savedLayer);
    expect(pinHitLayers, contains(MapStyle.savedLayer));
    expect(MapStyle.tappableLayers, contains(MapStyle.savedLayer));
    final shape = hitShapeOf(mapHitShapes, MapStyle.savedLayer, properties);
    expect(shape, isNotNull, reason: 'a pointer picks it');
    expect(
      shape!.marker,
      isFalse,
      reason: 'a saved point opens, it is no bare point',
    );
  });

  test('the desktop page draws the layer under the selection and sends its taps back', () {
    final spec = webViewMapSpec(dark: false, language: 'fr');
    final layers = [
      for (final l in spec['layers']! as List<Object?>) (l! as Map)['id'],
    ];
    expect(
      layers,
      containsAllInOrder([MapStyle.placesLayer, MapStyle.savedLayer]),
    );
    expect(
      layers.indexOf(MapStyle.savedLayer),
      lessThan(layers.indexOf(MapStyle.selectionPinLayer)),
      reason: 'the point being looked at stands over the saved ones',
    );
    expect(spec['tappable'], contains(MapStyle.savedLayer));
    final page = File('assets/map/lunaway_map.js').readAsStringSync();
    expect(page, contains("p.kind === '$savedFeatureKind'"));
    expect(page, contains("send({ type: 'saved', id: p.id })"));
  });
}
