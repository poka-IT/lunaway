import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// The image id of a pin: one per family and overnight status, registered
/// once with the map style.
String pinImageId(KindFamily family, OvernightStatus overnight) =>
    'pin-${family.name}-${overnight.name}';

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
          'icon': pinImageId(p.kind.family, p.overnight),
          // Nights allowed draw on top of the rest where pins collide.
          'rank': _rank(p.overnight),
        },
      },
  ];
  return {'type': 'FeatureCollection', 'features': features};
}

/// The image id of the marker on a point the user long-pressed.
const markedPointImageId = 'pin-point';

/// The selection layers' single feature: the selected place under its own
/// pin, or else a long-pressed point under the point marker.
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
        'properties': {'id': place.id, 'icon': pinImageId(place.kind.family, place.overnight)},
      }
    else if (point != null)
      {
        'type': 'Feature',
        'id': 'point',
        'geometry': {
          'type': 'Point',
          'coordinates': [point.lon, point.lat],
        },
        'properties': {'id': 'point', 'icon': markedPointImageId},
      },
  ],
};

int _rank(OvernightStatus o) => switch (o) {
  .allowed => 4,
  .tolerated => 3,
  .unknown => 2,
  .dayOnly => 1,
  .forbidden => 0,
};

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
