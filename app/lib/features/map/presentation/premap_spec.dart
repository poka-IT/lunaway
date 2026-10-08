import 'dart:math' as math;

import 'package:flutter/material.dart' show EdgeInsets, Rect, Size, VisualDensity;
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/coverage.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/features/map/data/last_view.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_screen.dart';
import 'package:lunaway/features/map/presentation/place_tile_layers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/shared/adaptive_shell.dart';

/// Version of what the app keeps for the web page's first map
/// (`web/premap.js`): the page ignores a state of another version.
const premapVersion = 1;

/// What the web page draws before the app has started: the last view, its
/// basemap (Aube or Minuit, in the reader's language) and the places' layers
/// with the filters in force. The app writes it as the user moves the map;
/// the page reads it at the next visit, and draws the map while the engine
/// loads. The view is kept as coarse as the phones keep theirs
/// (`DriftLastViewStore`): a tenth of a degree, zoom 10 at most, since the
/// map often rests on the user, and a finer copy in the browser would say
/// where the van spent the night.
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
  'center': [coarse(center).lon, coarse(center).lat],
  'zoom': math.min(zoom, DriftLastViewStore.maxZoom),
  'layers': placeTileStyleLayers(
    PlaceTilesView(tileJsonUrl: placesTileJson, filter: filter),
    dark: dark,
  ),
};

/// [p] as the phones keep a position: to a tenth of a degree.
LatLng coarse(LatLng p) => DriftLastPositionStore.coarsen(p);

/// What the page draws at a first visit, nothing kept yet: the public hosts,
/// France, no filter, both basemaps' layers (the page picks by the hour).
/// `web/premap.js` holds a copy, which a test keeps equal to this.
Map<String, Object?> premapDefaults() {
  const places = '${AppConfig.publicApi}/places/tiles.json';
  const france = GeoBounds.metropolitanFrance;
  const view = PlaceTilesView(tileJsonUrl: places);
  final dense = VisualDensity.compact.baseSizeAdjustment.dy;
  return {
    'v': premapVersion,
    'base': AppConfig.publicBasemap,
    'places': places,
    'bounds': [france.west, france.south, france.east, france.north],
    // Where the places are: a view kept with its centre elsewhere is not
    // opened again (premap.js, usable).
    'covered': [
      for (final b in placeCoverage) [b.west, b.south, b.east, b.north],
    ],
    'maxZoom': DriftLastViewStore.maxZoom,
    // A click on a dot comes at least this close (zoomForDot).
    'pinZoom': PlaceTiles.pinZoom,
    'layers': {
      'aube': placeTileStyleLayers(view, dark: false),
      'minuit': placeTileStyleLayers(view, dark: true),
    },
    // Where the app's map will stand in a window the app has not measured
    // yet (a first visit, another window size), so that the first map
    // frames France where the app would: each pair is [touch, mouse].
    'frame': {
      'mediumFrom': WindowSize.mediumFrom,
      'expandedFrom': WindowSize.expandedFrom,
      'railFolded': [
        railWidth(extended: false, dense: false),
        railWidth(extended: false, dense: true),
      ],
      'railExtended': [
        railWidth(extended: true, dense: false),
        railWidth(extended: true, dense: true),
      ],
      'pane': [mapPaneWidth(0), mapPaneWidth(mapPaneWideFrom)],
      'paneWideFrom': mapPaneWideFrom,
      'overlay': [mapOverlayHeight(0), mapOverlayHeight(dense)],
      'listPeek': mapListPeek,
      'dock': dockSpace,
      'fit': fitInitialMargin,
    },
  };
}

/// Where the app's map stands in the window and the room its first fit
/// leaves, as the web page's first map reads it (`lunaway.premapFrame`):
/// [window] the window's size, [map] the map's rectangle in it, [fit] the
/// padding of the fit inside the map (the overlays and the margin). All in
/// logical pixels, which the browser calls CSS pixels.
Map<String, Object?> premapFrame({
  required Size window,
  required Rect map,
  required EdgeInsets fit,
}) {
  double round(double v) => (v * 10).roundToDouble() / 10;
  return {
    'w': round(window.width),
    'h': round(window.height),
    'l': round(map.left),
    't': round(map.top),
    'r': round(window.width - map.right),
    'b': round(window.height - map.bottom),
    'pl': round(fit.left),
    'pt': round(fit.top),
    'pr': round(fit.right),
    'pb': round(fit.bottom),
  };
}
