import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// The places and points of interest on the guidance map: the main map's
/// vector tiles, drawn lighter. Pins only (no dots of the far zooms, no
/// gathering dots, no price under the stations), smaller, thinned where
/// they would touch and kept off the vehicle's arrow, so the road and the
/// arrow read first. Over the route line, at their own size: the line never
/// hides a pin, and a pin hides only the bit of line under its head
/// (`RouteLayerOrder`).
abstract final class RoutePlaceLayers {
  static const placeSource = 'lw-route-place-tiles';
  static const poiSource = 'lw-route-pois';

  /// The places' pins, from the zoom whose tiles name them.
  static const placePins = 'lw-route-place-pins';

  /// The points' pins, from the zoom of the tiles' points: their layer
  /// `pois`.
  static const poiPins = 'lw-route-poi-pins';

  /// The same, of the kinds the default tiles keep apart (their layer
  /// `pois_more`: the outdoor shops of "Garages et équipement"), so that
  /// showing them needs no tiles of every category. Those tiles hold every
  /// point in `pois` and none here.
  static const poiMorePins = 'lw-route-poi-pins-more';

  /// The points' pins layers, each with the tiles' layer it draws.
  static const List<(String, String)> poiLayers = [
    (poiPins, PoiMapStyle.pointsLayer),
    (poiMorePins, PoiMapStyle.morePointsLayer),
  ];

  /// Bottom to top: the points under the places, as on the main map.
  static const List<String> layers = [poiPins, poiMorePins, placePins];

  /// Topmost first, for a tap.
  static const List<String> tappable = [placePins, poiMorePins, poiPins];

  /// The size of a pin beside the main map's.
  static const placeScale = 0.72;
  static const poiScale = 0.78;

  /// Room around each pin where no other is drawn: a town's pins thin out
  /// instead of covering the streets.
  static const pinPadding = 6.0;

  /// Room around the vehicle's arrow where no pin is drawn.
  static const vehicleClearance = 28.0;

  static const double placeMinZoom = PlaceTiles.pinZoom;
  static const double poiMinZoom = PoiMapStyle.pointsMinZoom;

  /// The size of a place's pin, by the zoom, at [scale] (the engine's image
  /// scale, as for the main map).
  static List<Object> placeSize(double scale) => MapLook.pinSize(scale * placeScale);

  static double poiSize(double scale) => scale * poiScale;

  /// A filter that keeps no feature, for a layer whose filter is not known
  /// yet: a layer is hidden by its visibility, not by this.
  static const List<Object> none = RouteMapPlaces.drawsNothing;

  /// The images the pins draw with: a place's by its kind and night, a
  /// point's by its kind.
  static List<String> imageIds() => [
    for (final kind in PlaceKind.values)
      for (final night in OvernightStatus.values) pinImageId(kind, night),
    for (final kind in PoiKind.values) PoiMapStyle.imageId(kind),
  ];

  /// The sources, as the desktop page takes them.
  static List<Map<String, Object?>> jsonSources(RouteMapPlaces places) => [
    {'id': poiSource, 'vector': true, 'url': places.poiTileJsonUrl},
    {'id': placeSource, 'vector': true, 'url': places.placeTileJsonUrl},
  ];

  /// The layers in the GL JS style syntax, at the page's own scale.
  static List<Map<String, Object?>> jsonLayers(RouteMapPlaces places) => [
    for (final (id, sourceLayer) in poiLayers)
      {
        'id': id,
        'type': 'symbol',
        'source': poiSource,
        'source-layer': sourceLayer,
        'minzoom': poiMinZoom,
        'filter': places.poiFilter ?? none,
        'layout': {...poiLayout(1), 'visibility': places.poiFilter == null ? 'none' : 'visible'},
      },
    {
      'id': placePins,
      'type': 'symbol',
      'source': placeSource,
      'source-layer': PlaceTiles.pinsSourceLayer,
      'minzoom': placeMinZoom,
      'filter': places.placeFilter ?? none,
      'layout': {...placeLayout(1), 'visibility': places.placeFilter == null ? 'none' : 'visible'},
    },
  ];

  /// The layout of the places' pins: the main map's pin by kind and night,
  /// smaller, a pin with no room left out.
  static Map<String, Object?> placeLayout(double scale) => {
    'icon-image': placeTilePinImage(),
    'icon-size': placeSize(scale),
    'icon-anchor': 'bottom',
    'icon-allow-overlap': false,
    'icon-ignore-placement': false,
    'icon-padding': pinPadding,
    'symbol-sort-key': placeTileRank(placement: true),
  };

  /// The layout of the points' pins.
  static Map<String, Object?> poiLayout(double scale) => {
    'icon-image': PoiMapStyle.iconImage(),
    'icon-size': poiSize(scale),
    'icon-anchor': 'bottom',
    'icon-allow-overlap': false,
    'icon-ignore-placement': false,
    'icon-padding': pinPadding,
  };
}
