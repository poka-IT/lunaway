import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/map_view.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_state.g.dart';

/// What the map points at: a place, or a point the user long-pressed.
@immutable
sealed class MapSelection {
  const new();
}

final class PlaceSelection extends MapSelection {
  const new(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is PlaceSelection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class PointSelection extends MapSelection {
  const new(this.position);

  final LatLng position;

  @override
  bool operator ==(Object other) => other is PointSelection && other.position == position;

  @override
  int get hashCode => position.hashCode;
}

// keepAlive: the selection survives a switch to another tab and back.
@Riverpod(keepAlive: true)
class Selection extends _$Selection {
  @override
  MapSelection? build() => null;

  void select(MapSelection? selection) => state = selection;

  void clear() => state = null;
}

/// France as a whole: the first view before the user moves or is located.
const initialMapCenter = LatLng(46.6, 2.5);
const initialMapZoom = 5.0;
const initialViewport = MapViewport(
  bounds: GeoBounds.metropolitanFrance,
  center: initialMapCenter,
  zoom: initialMapZoom,
);

// keepAlive: the last camera position, restored when the map tab returns.
@Riverpod(keepAlive: true)
class Viewport extends _$Viewport {
  @override
  MapViewport? build() => null;

  void update(MapViewport viewport) {
    if (viewport != state) state = viewport;
  }
}

/// The controller of the live map, once it is ready; null before.
// keepAlive: the list, the search and the favourites move the same map.
@Riverpod(keepAlive: true)
class MapController extends _$MapController {
  @override
  LunaMapController? build() => null;

  void attach(LunaMapController controller) => state = controller;
}

/// The last known device position.
// keepAlive: distances in the list keep using it across tabs.
@Riverpod(keepAlive: true)
class UserLocation extends _$UserLocation {
  @override
  LatLng? build() => null;

  void update(LatLng? position) => state = position;
}

/// The places in the viewport, nearest to the user (or to the map centre)
/// first: the list beside the map.
@riverpod
Stream<List<PlaceSummary>> nearbyPlaces(Ref ref) {
  // Before the map reports its camera (or where it cannot run), the list
  // covers France around the initial centre.
  final viewport = ref.watch(viewportProvider) ?? initialViewport;
  final filter = ref.watch(placeFilterProvider);
  final user = ref.watch(userLocationProvider);
  final center = user != null && viewport.bounds.contains(user) ? user : viewport.center;
  return ref.watch(placesRepositoryProvider).watchInBounds(viewport.bounds, filter, center: center);
}

/// The map widget, swapped for a fake in widget tests where platform views do
/// not render.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
LunaMapBuilder lunaMapBuilder(Ref ref) => buildPlatformMap;

/// What the user typed in the map's search field.
@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void change(String text) => state = text;
}
