import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// The image id of a pin: one per kind and overnight status, and a larger
/// haloed one for the selected place. The sprite generator
/// (tool/map_sprites/) writes the images under the same ids.
String pinImageId(PlaceKind kind, OvernightStatus overnight, {bool selected = false}) =>
    'pin-${kind.name}-${overnight.name}${selected ? '-selected' : ''}';

/// The image id of the marker on a point the user long-pressed.
const markedPointImageId = 'pin-point';

/// The image id of the marker on a point saved in the favourites.
const savedPointImageId = 'pin-saved';

/// Every image id the map layers use, for the sprite loader.
List<String> allPinImageIds() => [
  markedPointImageId,
  savedPointImageId,
  for (final kind in PlaceKind.values)
    for (final overnight in OvernightStatus.values) ...[
      pinImageId(kind, overnight),
      pinImageId(kind, overnight, selected: true),
    ],
];

/// Feature kinds, so a tap can tell a place from the point marker and from
/// a saved point.
const _placeFeature = 'place';
const _pointFeature = 'point';
const savedFeatureKind = 'saved';

/// The GeoJSON of the saved points the map marks: their id and their
/// marker, nothing of their name or note.
Map<String, Object?> savedPointsFeatureCollection(List<SavedMark> points) => {
  'type': 'FeatureCollection',
  'features': [
    for (final p in points)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [p.position.lon, p.position.lat],
        },
        'properties': {'id': p.id, 'kind': savedFeatureKind, 'icon': savedPointImageId},
      },
  ],
};

/// The GeoJSON of the synced places for the map's clustered source. Only
/// what the style reads travels: id, icon and a sort key, so 16 000 places
/// stay a few hundred kilobytes.
Map<String, Object?> placesFeatureCollection(List<PlaceSummary> places) {
  final features = [
    for (final p in places)
      {
        'type': 'Feature',
        'id': p.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [p.lon, p.lat],
        },
        'properties': {
          'id': p.id,
          'kind': _placeFeature,
          'icon': pinImageId(p.kind, p.overnight),
          // Nights allowed draw on top of the rest where pins collide.
          'rank': placeRank(p.overnight),
        },
      },
  ];
  return {'type': 'FeatureCollection', 'features': features};
}

/// The selection layers' single feature: the selected place under its
/// haloed pin, or else a long-pressed point under the point marker.
Map<String, Object?> pointFeatureCollection(PlaceSummary? place, {LatLng? point}) => {
  'type': 'FeatureCollection',
  'features': [
    if (place != null)
      {
        'type': 'Feature',
        'id': place.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [place.lon, place.lat],
        },
        'properties': {
          'id': place.id,
          'kind': _placeFeature,
          'icon': pinImageId(place.kind, place.overnight, selected: true),
        },
      }
    else if (point != null)
      {
        'type': 'Feature',
        'id': _pointFeature,
        'geometry': {
          'type': 'Point',
          'coordinates': [point.lon, point.lat],
        },
        'properties': {'kind': _pointFeature, 'icon': markedPointImageId},
      },
  ],
};

/// Where pins collide, the higher rank draws on top: a night allowed first.
int placeRank(OvernightStatus o) => switch (o) {
  .allowed => 4,
  .tolerated => 3,
  .unknown => 2,
  .dayOnly => 1,
  .forbidden => 0,
};

/// What a tap on the map does, from the topmost feature under the finger.
@immutable
sealed class MapTap {
  const new();
}

/// Opens a place.
final class TapPlace extends MapTap {
  const new(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is TapPlace && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Zooms into a cluster.
final class TapCluster extends MapTap {
  const new(this.clusterId, this.at);

  final int clusterId;
  final LatLng at;

  @override
  bool operator ==(Object other) =>
      other is TapCluster && other.clusterId == clusterId && other.at == at;

  @override
  int get hashCode => Object.hash(clusterId, at);
}

/// Opens a point saved in the favourites.
final class TapSaved extends MapTap {
  const new(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is TapSaved && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Nothing: an empty spot, or the marker of a long-pressed point, which
/// already shows its details.
final class TapNothing extends MapTap {
  const new();
}

/// The action for a tap on a feature with [properties] at [coordinates]
/// (`[lon, lat]`). The desktop map page (`assets/map/lunaway_map.js`)
/// applies the same rule.
MapTap mapTapFor(Map<Object?, Object?>? properties, List<Object?>? coordinates) {
  if (properties == null) return const TapNothing();
  if (properties.containsKey('point_count')) {
    final id = properties['cluster_id'];
    if (id is! num || coordinates == null || coordinates.length < 2) return const TapNothing();
    final lon = coordinates[0];
    final lat = coordinates[1];
    if (lon is! num || lat is! num) return const TapNothing();
    return TapCluster(id.toInt(), LatLng(lat.toDouble(), lon.toDouble()));
  }
  final id = properties['id'];
  if (properties['kind'] == _placeFeature && id is String) return TapPlace(id);
  if (properties['kind'] == savedFeatureKind && id is String) return TapSaved(id);
  return const TapNothing();
}

/// [placesFeatureCollection] off the UI thread: building 16 000 features
/// takes long enough to drop frames while the user pans.
Future<Map<String, Object?>> placesFeatureCollectionInBackground(List<PlaceSummary> places) =>
    places.length < 500
    ? Future.value(placesFeatureCollection(places))
    : compute(placesFeatureCollection, places);

/// The same as JSON text, for the web view map.
Future<String> placesGeoJsonInBackground(List<PlaceSummary> places) => places.length < 500
    ? Future.value(jsonEncode(placesFeatureCollection(places)))
    : compute(_encodedPlaces, places);

String _encodedPlaces(List<PlaceSummary> places) => jsonEncode(placesFeatureCollection(places));
