import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/place_tile_layers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';

/// Version of what the app keeps for the web page's first map
/// (`web/premap.js`): the page ignores a state of another version.
const premapVersion = 1;

/// What the web page draws before the app has started: the last view, its
/// basemap (Aube or Minuit, in the reader's language) and the places' layers
/// with the filters in force. The app writes it as the user moves the map;
/// the page reads it at the next visit, and draws the map while the engine
/// loads.
Map<String, Object?> premapState({
  required String basemapBase,
  required String placesTileJson,
  required bool dark,
  required String language,
  required LatLng center,
  required double zoom,
  PlaceFilter filter = PlaceFilter.none,
}) => {
  'v': premapVersion,
  'base': basemapBase,
  'places': placesTileJson,
  'style': dark ? 'minuit' : 'aube',
  'lang': basemapLanguage(language),
  'center': [center.lon, center.lat],
  'zoom': zoom,
  'layers': placeTileStyleLayers(
    PlaceTilesView(tileJsonUrl: placesTileJson, filter: filter),
    dark: dark,
  ),
};

/// What the page draws at a first visit, nothing kept yet: the public hosts,
/// France, no filter, both basemaps' layers (the page picks by the hour).
/// `web/premap.js` holds a copy, which a test keeps equal to this.
Map<String, Object?> premapDefaults() {
  const places = '${AppConfig.publicApi}/places/tiles.json';
  const france = GeoBounds.metropolitanFrance;
  const view = PlaceTilesView(tileJsonUrl: places);
  return {
    'v': premapVersion,
    'base': AppConfig.publicBasemap,
    'places': places,
    'bounds': [france.west, france.south, france.east, france.north],
    'layers': {
      'aube': placeTileStyleLayers(view, dark: false),
      'minuit': placeTileStyleLayers(view, dark: true),
    },
  };
}
