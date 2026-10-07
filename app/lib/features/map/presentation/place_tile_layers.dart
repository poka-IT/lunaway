import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// The places' layers as a style document writes them (MapLibre GL JS):
/// the dots of the low zooms, a dot under each place from the zoom of the
/// pins, the pins. The desktop map page and the web's first map
/// (`web/premap.js`) draw these, as `GlPlaceTiles` does on maplibre_gl.
List<Map<String, Object?>> placeTileStyleLayers(PlaceTilesView view, {required bool dark}) {
  final filter = placeTileFilter(view.filter);
  final dotPaint = {
    'circle-color': placeTileDotColor(MapLook.familyColor),
    'circle-radius': MapLook.dotRadius,
    'circle-stroke-width': MapLook.dotStrokeWidth,
    'circle-stroke-color': MapLook.dotStroke(dark: dark),
    'circle-opacity': MapLook.dotOpacity,
  };
  final dotLayout = {'circle-sort-key': placeTileRank()};
  return [
    {
      'id': PlaceTiles.dotsLayer,
      'type': 'circle',
      'source': PlaceTiles.source,
      'source-layer': PlaceTiles.dotsSourceLayer,
      'maxzoom': PlaceTiles.pinZoom,
      'filter': filter,
      'layout': dotLayout,
      'paint': dotPaint,
    },
    {
      'id': PlaceTiles.pinDotsLayer,
      'type': 'circle',
      'source': PlaceTiles.source,
      'source-layer': PlaceTiles.pinsSourceLayer,
      'minzoom': PlaceTiles.pinZoom,
      'filter': filter,
      'layout': dotLayout,
      'paint': dotPaint,
    },
    {
      'id': PlaceTiles.pinsLayer,
      'type': 'symbol',
      'source': PlaceTiles.source,
      'source-layer': PlaceTiles.pinsSourceLayer,
      'minzoom': PlaceTiles.pinZoom,
      'filter': filter,
      'layout': {
        'icon-image': placeTilePinImage(),
        'icon-size': MapLook.pinSize(1),
        'icon-anchor': 'bottom',
        'icon-allow-overlap': false,
        'icon-ignore-placement': false,
        'icon-padding': 0,
        'symbol-sort-key': placeTileRank(placement: true),
      },
    },
  ];
}
