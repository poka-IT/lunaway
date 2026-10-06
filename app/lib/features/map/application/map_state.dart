import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/data/last_view.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/map_view.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_state.g.dart';

/// What the map points at: a place, a point the user long-pressed, or a
/// point of interest.
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

/// A point of interest, opened from the map, a place's surroundings or the
/// search. It carries what the tile said, so its page opens at once and
/// offline.
final class PoiSelection extends MapSelection {
  const new(this.feature, {this.from});

  final PoiFeature feature;

  /// The place whose surroundings it was opened from, to go back to.
  final String? from;

  @override
  bool operator ==(Object other) =>
      other is PoiSelection && other.feature.id == feature.id && other.from == from;

  @override
  int get hashCode => Object.hash(feature.id, from);
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

/// Whether [viewport] is still the map's first camera, before its fit to
/// the region and before any move: the map reports it as soon as it is
/// made.
bool isFirstCamera(MapViewport viewport) =>
    (viewport.zoom - initialMapZoom).abs() < 1e-6 &&
    viewport.center.distanceTo(initialMapCenter) < 1;

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

/// The location permission of the platform; a fake in widget tests.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
LocationPermissions locationPermissions(Ref ref) => const PlatformLocationPermissions();

/// Where the last known position is kept between runs.
// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
LastPositionStore lastPositionStore(Ref ref) =>
    DriftLastPositionStore(ref.watch(cacheDatabaseProvider));

/// The coarse position stored by the previous run, read in `main` before the
/// first frame so the automatic theme is right from the start.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
LatLng? initialPosition(Ref ref) => null;

/// Where the map was left between runs.
// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
LastViewStore lastViewStore(Ref ref) => DriftLastViewStore(ref.watch(cacheDatabaseProvider));

/// The view the previous run left the map on, read in `main` before the
/// first frame: the map opens there, null on a first launch.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
SavedView? initialView(Ref ref) => null;

/// The basemap style templates, read from the assets in `main` before the
/// first frame, so the map never waits on a file to get its style.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
BasemapTemplates basemapTemplates(Ref ref) => BasemapTemplates.blank;

/// The basemap style the map loads: Minuit when [dark], Aube otherwise,
/// pointed at the configured tile host, labelled in [language]; while the
/// host does not answer, at the pack downloaded for the view, with the
/// glyphs and sprites the app carries.
@riverpod
String basemapStyle(Ref ref, {required bool dark, required String language}) {
  final template = ref.watch(basemapTemplatesProvider).of(dark: dark);
  final pack = ref.watch(activeOfflinePackProvider);
  final files = ref.watch(offlineStyleFilesProvider);
  if (pack != null && files != null) {
    return fillOfflineBasemapStyle(
      template,
      pack: '${files.directory}/${pack.fileName}',
      assets: files.styleAssets,
      language: language,
    );
  }
  return fillBasemapStyle(
    template,
    base: ref.watch(appConfigProvider).basemapBase,
    language: language,
  );
}

/// The device position located during this run.
// keepAlive: distances in the list keep using it across tabs.
@Riverpod(keepAlive: true)
class UserLocation extends _$UserLocation {
  @override
  LatLng? build() => null;

  void update(LatLng? position) {
    state = position;
    if (position != null) unawaited(ref.read(lastPositionStoreProvider).save(position));
  }
}

/// The position the sun is computed at for the automatic theme: this run's,
/// else the one the previous run stored.
@riverpod
LatLng? sunPosition(Ref ref) =>
    ref.watch(userLocationProvider) ?? ref.watch(initialPositionProvider);

/// The places in the viewport, nearest to the user (or to the map centre)
/// first: the list beside the map.
@riverpod
Stream<List<PlaceSummary>> nearbyPlaces(Ref ref) {
  // Before the map reports its camera (or where it cannot run), the list
  // covers France around the initial centre.
  final viewport = ref.watch(viewportProvider) ?? initialViewport;
  final filter = ref.watch(effectiveFilterProvider);
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
