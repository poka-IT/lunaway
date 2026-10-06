import 'package:flutter/widgets.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/place.dart';

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
    required this.selectedId,
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
  });

  /// The basemap: a style URL or a style document (JSON text).
  final String style;

  /// The night basemap is on: clusters switch to their night colours.
  final bool dark;
  final LatLng initialCenter;
  final double initialZoom;
  final List<PlaceSummary> places;
  final String? selectedId;

  /// A point the user long-pressed, marked until the selection changes.
  final LatLng? markedPoint;
  final ValueChanged<String> onPlaceTap;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<MapViewport> onViewportChanged;

  /// A tap where there is no pin, no cluster and no marker: closes what the
  /// map had open, as in every map app.
  final VoidCallback? onEmptyTap;
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
}

typedef LunaMapBuilder = Widget Function(
  BuildContext context,
  LunaMapProps props,
);
