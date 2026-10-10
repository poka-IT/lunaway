import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/map/data/last_view.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_view.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_state.g.dart';

final _log = Logger('map');

/// What the map points at: a place, a point the user long-pressed or an
/// address the search found, or a point of interest.
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
  const new(this.position, {this.address, this.saved});

  final LatLng position;

  /// The address the search found there, when the point came from it: the
  /// details name it and credit its source.
  final AddressMatch? address;

  /// The point as the favourites held it when it was opened from them: its
  /// card names it at once, where "Here" showed for a frame while the
  /// saved copy was read. Not part of the selection's identity.
  final SavedPoint? saved;

  @override
  bool operator ==(Object other) =>
      other is PointSelection && other.position == position && other.address == address;

  @override
  int get hashCode => Object.hash(position, address);
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

  void select(MapSelection? selection) {
    // The same place chosen again (from the search, the list, its pin)
    // changes no state: [Reselections] says so to its open page.
    if (selection != null && selection == state) ref.read(reselectionsProvider.notifier).bump();
    state = selection;
  }

  void clear() => state = null;
}

/// How many times the selection was chosen again while it showed: the page
/// open goes back to its top, as for a place newly opened.
// keepAlive: a count of the run, read by whichever page is open.
@Riverpod(keepAlive: true)
class Reselections extends _$Reselections {
  @override
  int build() => 0;

  void bump() => state++;
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
    this.query,
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

  /// The request this page answers, which the next page repeats with
  /// [cursor]: never the view or the filters of a later moment.
  final NearbyQuery? query;
  final bool loadingMore;

  /// The last attempt at the next page failed; the list offers a retry.
  final bool moreFailed;

  NearbyPage copyWith({bool? loadingMore, bool? moreFailed}) => NearbyPage(
    places,
    total: total,
    hasMore: hasMore,
    cursor: cursor,
    query: query,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// What the list asks the API: the view and the point it ranks from, and
/// the filters. The client snaps the view and the point to a grid
/// ([placesQueryBox], [searchAnchor]) before they leave the device.
typedef NearbyQuery = ({GeoBounds bounds, LatLng near, PlaceFilter filter});

/// How long the list waits for the map to report the places of a view at
/// the zoom of the names before it asks the API.
const nearbyReportWait = Duration(seconds: 6);

/// Rows per page of the list asked of the API: three screens of a phone.
const nearbyPageSize = 30;

/// The rows the device's own list stops at: past that, the area is too wide
/// for a useful list.
const nearbyLocalLimit = 200;

/// Rows asked of the API at once when the list is ordered otherwise than by
/// distance: it ranks the nearest this many, and asks no further page.
const nearbyRankedLimit = 200;

/// The list beside the map. With the places from the tiles: from the zoom
/// of their names, the places the tiles hold inside the view, read on the
/// device without a request (exact, at once, and nothing of where the user
/// looks leaves it beyond the tiles themselves), except when the tiles
/// cannot answer: no map yet, a tile that failed, or a view whose tiles
/// hold no place, which the API's first page answers; below it, a page of the
/// API at a time, the view widened to a grid of 0.05 degree and ranked
/// from a point of that grid, never the device's position. Either way
/// sorted again on the device from the user when the map shows them.
/// Otherwise the places the device holds. A network failure is not asked
/// again behind the user's back ([nearbyRetry]): the list says at once
/// that there is no connection, and the network's return rebuilds it.
@Riverpod(retry: nearbyRetry)
class NearbyPlacesPage extends _$NearbyPlacesPage {
  LatLng _from = initialMapCenter;

  @override
  Future<NearbyPage> build() async {
    final viewport = ref.watch(viewportProvider) ?? initialViewport;
    final filter = ref.watch(effectiveFilterProvider);
    final user = ref.watch(userLocationProvider);
    final ranked = ref.watch(settingsProvider.select((s) => s.listSort)) != ListSort.distance;
    _from = user != null && viewport.bounds.contains(user) ? user : viewport.center;
    // The browser's word that the network went or came back asks again;
    // a phone follows it through [placesFromTilesProvider].
    ref.watch(basemapReachabilityProvider.select((r) => r == false));
    if (ref.watch(placesFromTilesProvider)) {
      if (viewport.zoom >= PlaceTiles.nameZoom) {
        final report = ref.watch(placesInViewProvider);
        final covered = report.covers(viewport);
        if (tilePlacesOf(viewport, report) case final inView?) {
          // The filter applied on the device, as the filters' sheet counts
          // ([filterPreviewCount]): the report holds every place of the view.
          final places = _sorted(inView.where(filter.matches));
          return NearbyPage(places, total: places.length);
        }
        // The map reports the places of a view once its tiles are in: until
        // it has for this one, the list keeps the rows it shows. The API
        // answers at once when the tiles cannot: no map to report yet, a
        // tile that failed, or a view whose tiles hold no place (a failure
        // the native maps do not report looks the same, and a view without
        // places costs one page of the API). A map that stays busy (tiles
        // that do not come) leaves the list to the API after a while, whose
        // failure says so.
        final map = ref.watch(mapControllerProvider);
        if (!covered && map != null) {
          final wait = Completer<void>();
          final timer = Timer(nearbyReportWait, wait.complete);
          ref.onDispose(timer.cancel);
          await wait.future;
          if (!ref.mounted) return const NearbyPage([]);
        }
      }
      final query = (
        bounds: placesQueryBox(viewport.bounds),
        near: searchAnchor(viewport.center),
        filter: filter,
      );
      try {
        final page = await ref
            .read(onlinePlacesProvider)
            .inBounds(
              query.bounds,
              filter,
              near: query.near,
              first: ranked ? nearbyRankedLimit : nearbyPageSize,
            );
        return NearbyPage(
          _sorted(page.places),
          total: page.total,
          hasMore: page.hasNextPage,
          cursor: page.endCursor,
          query: query,
        );
      } on GraphQLNetworkException catch (e) {
        // The network went before the map noticed: the host is asked at
        // once, so a phone turns to the places it holds; meanwhile those
        // places, when it holds some, rather than an error.
        if (e is! GraphQLRateLimitedException) {
          unawaited(ref.read(basemapReachabilityProvider.notifier).probe());
        }
        final local = ref.read(placesRepositoryProvider);
        if (await local.watchCount().first == 0) rethrow;
        final places = await local.watchInBounds(viewport.bounds, filter, center: _from).first;
        return NearbyPage(places, total: places.length < nearbyLocalLimit ? places.length : null);
      }
    }
    // The places the device holds: every one of the view, or, past the
    // limit, the nearest, which the title says (the filters' sheet then
    // counts the whole view).
    final places = await ref.watch(nearbyPlacesProvider.future);
    return NearbyPage(places, total: places.length < nearbyLocalLimit ? places.length : null);
  }

  List<PlaceSummary> _sorted(Iterable<PlaceSummary> places) =>
      places.toList()
        ..sort((a, b) => a.position.distanceTo(_from).compareTo(b.position.distanceTo(_from)));

  /// Appends the next page of the API's list: the same request as the page
  /// shown, from its cursor. Nothing while the list reloads for another
  /// view or other filters, whose first page replaces this one.
  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.cursor;
    final query = current?.query;
    if (state.isLoading ||
        current == null ||
        cursor == null ||
        query == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final asking = current.copyWith(loadingMore: true, moreFailed: false);
    state = AsyncData(asking);
    // Whether the list still shows what this request continues: a pan or a
    // filter rebuilds it meanwhile, and the next page of the old request
    // would then land on the new list.
    bool still() => ref.mounted && identical(state.value, asking) && !state.isLoading;
    try {
      final next = await ref
          .read(onlinePlacesProvider)
          .inBounds(
            query.bounds,
            query.filter,
            near: query.near,
            first: nearbyPageSize,
            after: cursor,
          );
      if (!still()) return;
      final seen = {for (final p in current.places) p.id};
      state = AsyncData(
        NearbyPage(
          // A page comes nearest first: sorted on its own, it follows the
          // rows already shown, which never jump.
          [...current.places, ..._sorted(next.places.where((p) => !seen.contains(p.id)))],
          total: next.total,
          hasMore: next.hasNextPage,
          cursor: next.endCursor,
          query: query,
        ),
      );
    } on Object catch (e) {
      _log.info('the next page of the list failed: $e');
      if (!still()) return;
      state = AsyncData(current.copyWith(moreFailed: true));
    }
  }
}

/// The list's retries: none after a network failure, which the list shows
/// at once; Riverpod's own for the rest (a server that refused for a
/// while).
Duration? nearbyRetry(int count, Object error) =>
    error is GraphQLNetworkException && error is! GraphQLRateLimitedException
    ? null
    : ProviderContainer.defaultRetry(count, error);

/// The places of the tiles inside [viewport] when they answer for it: from
/// the zoom of the names, a report of this very view, no tile failed, and
/// at least one place (a failure the native maps do not report looks like
/// an empty view). Null when the API answers instead. The list beside the
/// map and the count of the filters' sheet both read the view's places
/// here, so they never tell two numbers for one view.
List<PlaceSummary>? tilePlacesOf(MapViewport viewport, PlacesInViewReport report) {
  if (viewport.zoom < PlaceTiles.nameZoom || !report.covers(viewport) || report.failed) {
    return null;
  }
  final inView = [
    for (final p in report.places)
      if (viewport.bounds.contains(p.position)) p,
  ];
  return inView.isEmpty ? null : inView;
}

/// Every place of the tiles inside a view of the map, whatever the filter,
/// as the map reported them once it settled: the list beside the map and
/// the count of the filters' sheet from the zoom of their names, and what
/// the points of interest leave room for (filtered by each of them).
@immutable
final class PlacesInViewReport {
  const new(this.places, {this.bounds, this.failed = false});

  static const none = PlacesInViewReport([]);

  final List<PlaceSummary> places;

  /// The view they are the places of; null before the first report.
  final GeoBounds? bounds;

  /// A tile of the view failed to load: [places] may lack some, or all.
  final bool failed;

  /// Whether this report is of [viewport]: the map reports once its tiles
  /// are in, after the camera has come to rest.
  bool covers(MapViewport viewport) {
    final b = bounds;
    if (b == null) return false;
    // The same rest of the camera: within a hundredth of the view's size.
    final tolerance = (viewport.bounds.north - viewport.bounds.south).abs() / 100;
    return (b.south - viewport.bounds.south).abs() <= tolerance &&
        (b.north - viewport.bounds.north).abs() <= tolerance &&
        (b.west - viewport.bounds.west).abs() <= tolerance &&
        (b.east - viewport.bounds.east).abs() <= tolerance;
  }
}

// keepAlive: the map reports them; the list and the points' state read them.
@Riverpod(keepAlive: true)
class PlacesInView extends _$PlacesInView {
  @override
  PlacesInViewReport build() => PlacesInViewReport.none;

  void report(List<PlaceSummary> places, GeoBounds bounds, {bool failed = false}) {
    if (state.bounds == bounds && state.failed == failed && listEquals(places, state.places)) {
      return;
    }
    state = PlacesInViewReport(places, bounds: bounds, failed: failed);
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
