import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

const _view = GeoBounds(south: 45.86, west: 6.06, north: 45.94, east: 6.24);

MapViewport _viewport(GeoBounds b) => MapViewport(bounds: b, center: b.center, zoom: 13);

Map<String, Object?> _feature(String id, double lat, double lon) => {
  'geometry': {
    'coordinates': [lon, lat],
  },
  'properties': {'id': id, 'kind': 'parking', 'night': 'allowed'},
};

void main() {
  group('a report of the places in view', () {
    test('covers the view it was made for, and only that one', () {
      const report = PlacesInViewReport([], bounds: _view);
      expect(report.covers(_viewport(_view)), isTrue);
      // The same rest reported twice by an engine, a rounding apart.
      expect(
        report.covers(
          _viewport(const GeoBounds(south: 45.86001, west: 6.06, north: 45.94, east: 6.24)),
        ),
        isTrue,
      );
      // A resize: the same centre and zoom, another view.
      expect(
        report.covers(_viewport(const GeoBounds(south: 45.8, west: 6.06, north: 46, east: 6.24))),
        isFalse,
      );
      expect(
        report.covers(
          _viewport(const GeoBounds(south: 45.86, west: 6.16, north: 45.94, east: 6.34)),
        ),
        isFalse,
        reason: 'a pan',
      );
      expect(PlacesInViewReport.none.covers(_viewport(_view)), isFalse, reason: 'no report yet');
    });
  });

  test('the places of the features are those inside the view, each once', () {
    final raw = <Object?>[
      _feature('a', 45.9, 6.1),
      // A place on the edge of two tiles comes twice.
      _feature('a', 45.9, 6.1),
      // In a tile's margin, outside the view.
      _feature('b', 45.99, 6.1),
      // Android and iOS answer GeoJSON text.
      jsonEncode(_feature('c', 45.88, 6.2)),
      // A dot without an id is no place.
      {
        'geometry': {
          'coordinates': [6.1, 45.9],
        },
        'properties': {'kind': 'parking', 'night': 'allowed'},
      },
    ];
    expect(placesOfFeatures(raw, _view).map((p) => p.id), ['a', 'c']);
  });

  test('the grid of the API widens a box once, and leaves a snapped box as it is', () {
    for (var i = -3600; i <= 3600; i += 7) {
      final v = i / 20;
      final view = GeoBounds(
        south: (v / 2).clamp(-89.0, 89.0),
        west: v.clamp(-179.0, 179.0),
        north: (v / 2 + 0.37).clamp(-89.0, 89.5),
        east: (v + 0.41).clamp(-179.0, 179.5),
      );
      final once = placesQueryBox(view);
      expect(placesQueryBox(once), once, reason: '$view');
      expect(once.south, lessThanOrEqualTo(view.south));
      expect(once.north, greaterThanOrEqualTo(view.north));
      expect(once.west, lessThanOrEqualTo(view.west));
      expect(once.east, greaterThanOrEqualTo(view.east));
      expect(once.north - view.north, lessThan(placesGrid + 1e-9), reason: 'one cell at most');
    }
  });
}
