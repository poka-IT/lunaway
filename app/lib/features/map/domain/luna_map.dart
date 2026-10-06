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

  /// The device position, after asking for the permission if needed; null
  /// when it is refused or unavailable.
  Future<LatLng?> locateUser();
}

/// The map widget contract: data in, gestures out. A screen builds it
/// through the `lunaMapBuilder` provider, so tests swap the platform view for
/// a plain widget.
@immutable
final class LunaMapProps {
  const new({
    required this.styleUrl,
    required this.initialCenter,
    required this.initialZoom,
    required this.places,
    required this.selectedId,
    required this.onPlaceTap,
    required this.onLongPress,
    required this.onViewportChanged,
    required this.onMapReady,
    this.markedPoint,
    this.padding = EdgeInsets.zero,
  });

  final String styleUrl;
  final LatLng initialCenter;
  final double initialZoom;
  final List<PlaceSummary> places;
  final String? selectedId;

  /// A point the user long-pressed, marked until the selection changes.
  final LatLng? markedPoint;
  final ValueChanged<String> onPlaceTap;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<MapViewport> onViewportChanged;
  final ValueChanged<LunaMapController> onMapReady;

  /// Space covered by floating panels, so camera moves centre on what the
  /// user can see.
  final EdgeInsets padding;
}

typedef LunaMapBuilder = Widget Function(BuildContext context, LunaMapProps props);
