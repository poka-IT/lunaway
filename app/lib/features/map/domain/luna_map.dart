import 'package:flutter/widgets.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';

/// What the map shows of the camera once it stops moving.
@immutable
final class MapViewport {
  const new({required this.bounds, required this.center, required this.zoom});

  final GeoBounds bounds;
  final LatLng center;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is MapViewport &&
      other.bounds == bounds &&
      other.center == center &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(bounds, center, zoom);
}

/// Commands the screens send to the map. Implemented by the MapLibre adapter
/// and by a fake in the widget tests, where platform views do not render.
abstract interface class LunaMapController {
  Future<void> moveTo(LatLng center, {double? zoom});

  Future<void> fitBounds(GeoBounds bounds);

  /// Zooms in (positive) or out (negative) by [delta] levels, around the
  /// centre of the visible part of the map.
  Future<void> zoomBy(double delta);

  /// Shows the device position and returns it; null when none came in
  /// time. The location permission is the screen's business: it asks,
  /// with an explanation, before calling this.
  Future<LatLng?> locateUser();

  /// Marks [position] as the user's, a position the app read itself (the
  /// browser's, on the web), with its radius of uncertainty in metres.
  Future<void> showPosition(LatLng position, {double? accuracy});

  /// The camera's centre now, read from the engine even while the map
  /// still glides after a fling (the viewport is only reported at rest);
  /// null when the engine cannot tell.
  Future<LatLng?> center();
}

/// The map widget contract: data in, gestures out. A screen builds it
/// through the `lunaMapBuilder` provider, so tests swap the platform view for
/// a plain widget.
@immutable
final class LunaMapProps {
  const new({
    required this.style,
    required this.dark,
    required this.initialCenter,
    required this.initialZoom,
    required this.places,
    required this.selectedPlace,
    required this.onPlaceTap,
    required this.onLongPress,
    required this.onViewportChanged,
    required this.onMapReady,
    this.markedPoint,
    this.onEmptyTap,
    this.padding = EdgeInsets.zero,
    this.attributionInset = EdgeInsets.zero,
    this.language = 'en',
    this.fitInitial = false,
    this.pois,
    this.onPoiTap,
    this.onPoisInView,
    this.placeTiles,
    this.onPlacesInView,
  });

  /// The basemap: a style URL or a style document (JSON text).
  final String style;

  /// The night basemap is on: clusters switch to their night colours.
  final bool dark;
  final LatLng initialCenter;
  final double initialZoom;

  /// The places the device holds, drawn in a clustered source when
  /// [placeTiles] is null (offline, a demo build); empty otherwise.
  final List<PlaceSummary> places;

  /// The places from the API's vector tiles, with the filter the map
  /// applies to them; null draws [places] instead.
  final PlaceTilesView? placeTiles;

  /// The open place, drawn large on top: what was read of it, or what the
  /// tap or the row knew before.
  final PlaceSummary? selectedPlace;

  String? get selectedId => selectedPlace?.id;

  /// A point the user long-pressed, marked until the selection changes.
  final LatLng? markedPoint;

  /// A tap on a place, with what the tile said of it as `hint`.
  final void Function(String id, {PlaceSummary? hint}) onPlaceTap;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<MapViewport> onViewportChanged;

  /// A tap where there is no pin, no cluster and no marker within
  /// `FreeTap.freePoint`, at that point, with the map's zoom then. The screen
  /// decides (`bareTapAt`): close what is open, or open the point.
  final void Function(LatLng at, double zoom)? onEmptyTap;
  final ValueChanged<LunaMapController> onMapReady;

  /// Space covered by floating panels, so camera moves centre on what the
  /// user can see.
  final EdgeInsets padding;

  /// Where the basemap attribution sits, from the bottom left corner: above
  /// the sheet and the dock on a phone, in the corner on a desktop.
  final EdgeInsets attributionInset;

  /// The app's language, for the counts of the clusters.
  final String language;

  /// Open on the whole region within [padding] (the first view of a run),
  /// rather than on [initialCenter] at [initialZoom], so no cluster starts
  /// under the search and the chips.
  final bool fitInitial;

  /// The points of interest layer; null leaves it out.
  final PoiLayerView? pois;

  /// A tap on a point of interest.
  final ValueChanged<PoiFeature>? onPoiTap;

  /// The points of the tiles under the view, reported each time the map
  /// settles after a move: their hours and their neighbours decide how
  /// [pois] draws them.
  final ValueChanged<List<PoiFeature>>? onPoisInView;

  /// The places of the tiles inside the view, reported when the map rests
  /// at the zoom of the pins: the list beside the map shows them, and the
  /// points of interest leave room for them. `failed` when a tile of the
  /// places failed to load since the previous report: the places are then
  /// those of the tiles that came, maybe none.
  final void Function(List<PlaceSummary> places, GeoBounds bounds, {bool failed})? onPlacesInView;
}

typedef LunaMapBuilder = Widget Function(BuildContext context, LunaMapProps props);

/// The room the first view's fit (`LunaMapProps.fitInitial`) leaves around
/// the region, inside the map's padding.
const double fitInitialMargin = 16;
