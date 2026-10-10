import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

const _view = GeoBounds(south: 45.86, west: 6.06, north: 45.94, east: 6.24);

MapViewport _viewport(GeoBounds b) => MapViewport(bounds: b, center: b.center, zoom: 13);

Map<String, Object?> _feature(String id, double lat, double lon) => {
  'geometry': {
    'coordinates': [lon, lat],
  },
  'properties': {'id': id, 'kind': 'parking', 'night': 'allowed'},
};

/// A map engine that answers the queries of the places' tiles from
/// [features] and keeps the filter each query asked with. Installing the
/// layers draws nothing.
final class _Engine implements gl.MapLibreMapController {
  final filters = <List<Object>?>[];
  List<Object?> features = const [];

  @override
  Future<List<Object?>> querySourceFeatures(
    String sourceId,
    String? sourceLayerId,
    List<Object>? filter,
  ) async {
    filters.add(filter);
    return features;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => Future<void>.value();
}

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

  test('the probe reads every place of the tiles, whatever the filter on the map', () async {
    // The list and the filters' count filter this report on the device: a
    // report already filtered by the map would count a filter twice, and
    // the count of another filter would start from the wrong places.
    final engine = _Engine()..features = [_feature('a', 45.9, 6.1)];
    final tiles = GlPlaceTiles();
    await tiles.install(
      engine,
      const PlaceTilesView(
        tileJsonUrl: 'https://api.example/places/tiles.json',
        filter: PlaceFilter(freeOnly: true, minRating: 4),
      ),
      pinScale: 1,
      dark: false,
      current: () => true,
    );
    final found = await tiles.probe(engine, zoom: PlaceTiles.nameZoom, camera: 1, bounds: _view);
    expect(engine.filters, [placeTileFilter(PlaceFilter.none)]);
    expect(found?.map((p) => p.id), ['a']);
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

  test('of two copies of a place, the one that names it stays, whatever their order', () {
    // MapLibre Native keeps the tiles four zooms below the view's: at street
    // zoom a place also comes from a tile of zoom 10, without its name.
    Map<String, Object?> named(String id) => {
      ..._feature(id, 45.9, 6.1),
      'properties': {
        'id': id,
        'kind': 'motorhome_area',
        'night': 'allowed',
        'name': 'Camping-car Park Viviers',
        'city': 'Viviers',
      },
    };
    for (final raw in [
      [_feature('a', 45.9, 6.1), named('a')],
      [named('a'), _feature('a', 45.9, 6.1)],
      [jsonEncode(_feature('a', 45.9, 6.1)), jsonEncode(named('a'))],
    ]) {
      final places = placesOfFeatures(raw, _view);
      expect(places, hasLength(1));
      expect(places.single.name, 'Camping-car Park Viviers', reason: '$raw');
      expect(places.single.city, 'Viviers');
    }
  });

  test('of two copies of a place without a name, the one with its street stays', () {
    Map<String, Object?> unnamed(String id, {String? street}) => {
      ..._feature(id, 45.9, 6.1),
      'properties': {
        'id': id,
        'kind': 'parking',
        'night': 'unknown',
        'city': 'Viviers',
        'st': ?street,
      },
    };
    for (final raw in [
      [unnamed('a'), unnamed('a', street: '4 Rue de la Gare')],
      [unnamed('a', street: '4 Rue de la Gare'), unnamed('a')],
    ]) {
      expect(placesOfFeatures(raw, _view).single.street, '4 Rue de la Gare', reason: '$raw');
    }
  });

  group('the places of a view the list and the filters read', () {
    final view = _viewport(_view);
    const inside = PlaceSummary(
      id: 'a',
      kind: PlaceKind.parking,
      lat: 45.9,
      lon: 6.1,
      overnight: OvernightStatus.allowed,
    );
    const outside = PlaceSummary(
      id: 'b',
      kind: PlaceKind.parking,
      lat: 45.99,
      lon: 6.1,
      overnight: OvernightStatus.allowed,
    );

    test('come from a report of this view, inside it', () {
      expect(tilePlacesOf(view, const PlacesInViewReport([inside, outside], bounds: _view)), [
        inside,
      ]);
    });

    test('come from the API below the zoom of the names, or when the report cannot answer', () {
      expect(
        tilePlacesOf(
          MapViewport(bounds: _view, center: _view.center, zoom: 11.9),
          const PlacesInViewReport([inside], bounds: _view),
        ),
        isNull,
        reason: 'no name in the tiles yet',
      );
      expect(
        tilePlacesOf(view, const PlacesInViewReport([inside], bounds: _view, failed: true)),
        isNull,
        reason: 'a tile failed',
      );
      expect(
        tilePlacesOf(view, const PlacesInViewReport([outside], bounds: _view)),
        isNull,
        reason: 'no place of the tiles in view: maybe a failure the engine kept quiet',
      );
      expect(tilePlacesOf(view, PlacesInViewReport.none), isNull, reason: 'no report yet');
    });
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
