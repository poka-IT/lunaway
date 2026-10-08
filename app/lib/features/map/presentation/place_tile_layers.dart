import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// The places' layers as a style document writes them (MapLibre GL JS):
/// the glow of the country's view and the dots of the low zooms, each with
/// the basemap layer it goes under (`before`, [labels]: the first layer of
/// names), then a dot under each place from the zoom of the pins and the
/// pins, on top. The desktop map page and the web's first map
/// (`web/premap.js`) draw these, as `GlPlaceTiles` does on maplibre_gl;
/// both take `before` out of the layer and add it before that layer.
List<Map<String, Object?>> placeTileStyleLayers(
  PlaceTilesView view, {
  required bool dark,
  String? labels = PlaceTiles.basemapFirstLabel,
}) {
  final filter = placeTileFilter(view.filter);
  final dotPaint = {
    'circle-color': placeTileDotColor(MapLook.familyColor),
    'circle-radius': MapLook.dotRadius,
    'circle-stroke-width': MapLook.dotStrokeWidth,
    'circle-stroke-color': MapLook.dotStroke(dark: dark),
    'circle-opacity': MapLook.dotOpacity,
    'circle-stroke-opacity': MapLook.dotStrokeOpacity,
  };
  final dotLayout = {'circle-sort-key': placeTileRank()};
  return [
    {
      'id': PlaceTiles.heatLayer,
      'type': 'heatmap',
      'source': PlaceTiles.source,
      'source-layer': PlaceTiles.dotsSourceLayer,
      'maxzoom': MapLook.heatMaxZoom,
      'filter': filter,
      'paint': placeTileHeatPaint(dark: dark),
      'before': ?labels,
    },
    {
      'id': PlaceTiles.dotsLayer,
      'type': 'circle',
      'source': PlaceTiles.source,
      'source-layer': PlaceTiles.dotsSourceLayer,
      'maxzoom': PlaceTiles.pinZoom,
      'filter': filter,
      'layout': dotLayout,
      'paint': dotPaint,
      'before': ?labels,
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

/// The glow's paint ([MapLook.heatColor]), as a style document writes it.
Map<String, Object?> placeTileHeatPaint({required bool dark}) => {
  'heatmap-radius': MapLook.heatRadius,
  'heatmap-intensity': MapLook.heatIntensity,
  'heatmap-color': MapLook.heatColor(dark: dark),
  'heatmap-opacity': MapLook.heatOpacity,
};
