import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
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
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_state.g.dart';

final _log = Logger('map');

/// What the map points at: a place, a point the user long-pressed, or a
/// point of interest.
@immutable
sealed class MapSelection {
  const new();
}

final class PlaceSelection extends MapSelection {
  const new(this.id, {this.hint});

  final String id;

  /// What the tap or the row already knew of the place (its name, kind,
  /// night and position): the page and the selected pin show it at once
  /// while the place itself is read. Not part of the selection's identity.
  final PlaceSummary? hint;

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

/// The selected place as the map draws its pin and the sheet titles it:
/// the place once read, what the tap or the row knew before that.
@riverpod
PlaceSummary? selectedPlace(Ref ref) {
  final selection = ref.watch(selectionProvider);
  if (selection is! PlaceSelection) return null;
  return ref.watch(placeProvider(selection.id)).value?.summary ?? selection.hint;
}

/// The list beside the map: the places of the view passing the filters,
/// nearest to the user (or to the map's centre) first.
@immutable
final class NearbyPage {
  const new(
    this.places, {
    this.total,
    this.hasMore = false,
    this.cursor,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<PlaceSummary> places;

  /// Every place of the view passing the filters; null when the list stops
  /// at its limit without knowing how many the view holds.
  final int? total;

  /// Another page follows ([NearbyPlacesPage.loadMore]).
  final bool hasMore;
  final String? cursor;
  final bool loadingMore;

  /// The last attempt at the next page failed; the list offers a retry.
  final bool moreFailed;

  NearbyPage copyWith({bool? loadingMore, bool? moreFailed}) => NearbyPage(
    places,
    total: total,
    hasMore: hasMore,
    cursor: cursor,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// Rows per page of the list asked of the API: three screens of a phone.
const nearbyPageSize = 30;

/// The rows the device's own list stops at: past that, the area is too wide
/// for a useful list.
const nearbyLocalLimit = 200;

/// The list beside the map. With the places from the tiles, a page of the
/// API at a time, nearest to the map's centre (the device's position is
/// never sent), sorted again on the device from the user when the map
/// shows them; otherwise the places the device holds.
@riverpod
class NearbyPlacesPage extends _$NearbyPlacesPage {
  LatLng _from = initialMapCenter;

  @override
  Future<NearbyPage> build() async {
    final viewport = ref.watch(viewportProvider) ?? initialViewport;
    final filter = ref.watch(effectiveFilterProvider);
    final user = ref.watch(userLocationProvider);
    _from = user != null && viewport.bounds.contains(user) ? user : viewport.center;
    if (ref.watch(placesFromTilesProvider)) {
      try {
        final page = await ref
            .read(onlinePlacesProvider)
            .inBounds(viewport.bounds, filter, near: viewport.center, first: nearbyPageSize);
        return NearbyPage(
          _sorted(page.places),
          total: page.total,
          hasMore: page.hasNextPage,
          cursor: page.endCursor,
        );
      } on GraphQLNetworkException {
        // The network went before the map noticed: the places the device
        // holds, when it holds some, rather than an error.
        final local = ref.read(placesRepositoryProvider);
        if (await local.watchCount().first == 0) rethrow;
        final places = await local.watchInBounds(viewport.bounds, filter, center: _from).first;
        return NearbyPage(places, total: places.length < nearbyLocalLimit ? places.length : null);
      }
    }
    final places = await ref.watch(nearbyPlacesProvider.future);
    return NearbyPage(places, total: places.length < nearbyLocalLimit ? places.length : null);
  }

  List<PlaceSummary> _sorted(Iterable<PlaceSummary> places) =>
      places.toList()
        ..sort((a, b) => a.position.distanceTo(_from).compareTo(b.position.distanceTo(_from)));

  /// Appends the next page of the API's list.
  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.cursor;
    if (current == null || cursor == null || !current.hasMore || current.loadingMore) return;
    final viewport = ref.read(viewportProvider) ?? initialViewport;
    final filter = ref.read(effectiveFilterProvider);
    state = AsyncData(current.copyWith(loadingMore: true, moreFailed: false));
    try {
      final next = await ref
          .read(onlinePlacesProvider)
          .inBounds(
            viewport.bounds,
            filter,
            near: viewport.center,
            first: nearbyPageSize,
            after: cursor,
          );
      if (!ref.mounted) return;
      final seen = {for (final p in current.places) p.id};
      state = AsyncData(
        NearbyPage(
          // A page comes nearest first: sorted on its own, it follows the
          // rows already shown, which never jump.
          [...current.places, ..._sorted(next.places.where((p) => !seen.contains(p.id)))],
          total: next.total,
          hasMore: next.hasNextPage,
          cursor: next.endCursor,
        ),
      );
    } on Object catch (e) {
      _log.info('the next page of the list failed: $e');
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(moreFailed: true));
    }
  }
}

/// The places of the tiles under the map's view, as the map reported them
/// once it settled at the zoom of the pins: what the points of interest
/// leave room for.
// keepAlive: the map reports them; the points' state reads them at each tick.
@Riverpod(keepAlive: true)
class PlacesInView extends _$PlacesInView {
  @override
  List<LatLng> build() => const [];

  void report(List<LatLng> positions) {
    if (!listEquals(positions, state)) state = positions;
  }
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
