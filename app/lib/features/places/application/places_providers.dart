import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/platform/network_state.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/online_places.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/town_names.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'places_providers.g.dart';

final _log = Logger('places');

// keepAlive: one client for the run (a demo build swaps the HTTP client for
// the in-process demo API, in main).
@Riverpod(keepAlive: true)
GraphQLClient graphQLClient(Ref ref) => GraphQLClient(
  endpoint: ref.watch(appConfigProvider).graphqlEndpoint,
  httpClient: ref.watch(httpClientProvider),
  userAgent: ref.watch(userAgentProvider),
  persistedQueries: true,
);

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
DriftPlacesRepository driftPlacesRepository(Ref ref) =>
    DriftPlacesRepository(ref.watch(cacheDatabaseProvider));

/// The read side every screen uses; tests replace it with a fake.
// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
PlacesRepository placesRepository(Ref ref) => ref.watch(driftPlacesRepositoryProvider);

// keepAlive: a stateless service, wired once.
@Riverpod(keepAlive: true)
SyncService syncService(Ref ref) => SyncService(
  source: GraphQLChangesSource(ref.watch(graphQLClientProvider)),
  store: ref.watch(driftPlacesRepositoryProvider),
);

/// Whether this device keeps places of its own for offline use (regions,
/// packs, the change feed): not the web, which reads them from the API's
/// tiles and queries and keeps only what the user opened.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
bool keepsPlaces(Ref ref) => !kIsWeb || ref.watch(appConfigProvider).demo;

/// How long the first sync of a run waits behind the map: `afterMap` once
/// the map has drawn its first view (the tiles of that view load first),
/// `atLatest` when no map shows; replaced in tests.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
({Duration afterMap, Duration atLatest}) syncStartDelays(Ref ref) =>
    (afterMap: const Duration(seconds: 3), atLatest: const Duration(seconds: 15));

/// Why a sync failed, in the terms the user can act on.
enum SyncFailure {
  /// No connection, a timeout, a server down: it comes back by itself.
  offline,

  /// The server asked to slow down for longer than the app waits.
  busy,

  /// The server failed, or a service behind it is down: it comes back by
  /// itself.
  server,

  /// The server refused the request: retrying the same request will not
  /// help, an update of the app may.
  refused,

  /// Anything else (an answer the app cannot read, a full disk): no cause
  /// the user can act on is known, so the message stays neutral.
  other;

  static SyncFailure of(Object error) => switch (error) {
    GraphQLRateLimitedException() => busy,
    GraphQLNetworkException() => offline,
    PackDownloadException(failure: PackDownloadFailure.network) => offline,
    GraphQLResponseException(transient: true) => server,
    GraphQLResponseException() => refused,
    _ => other,
  };
}

/// Where a sync stands, for the offline data panel and the map banner.
@immutable
sealed class SyncStatus {
  const new();
}

final class SyncIdle extends SyncStatus {
  const new();
}

final class SyncRunning extends SyncStatus {
  const new(this.received, {this.region, this.packBytes = 0, this.packSize = 0});

  /// Places written so far.
  final int received;

  /// The region being synced, when the sync goes by region.
  final String? region;

  /// Bytes of that region's pack received, and its size; zero while the
  /// region syncs from its feed.
  final int packBytes;
  final int packSize;
}

final class SyncDone extends SyncStatus {
  const new(this.received);

  final int received;
}

final class SyncFailed extends SyncStatus {
  const new(this.failure, {this.retryIn});

  final SyncFailure failure;

  /// When the app tries again by itself; null when it will not.
  final Duration? retryIn;
}

/// The waits between automatic retries of a failed sync, the last one
/// repeated; replaced in tests.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
List<Duration> syncRetryDelays(Ref ref) => const [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
  Duration(minutes: 30),
];

/// Runs the sync of the region and reports its progress. Started once by
/// the app: it syncs at launch when the data is old or a run was cut short,
/// again each time the app comes back to the foreground, after the user's
/// contributions reach the server, and retries a failed sync on its own
/// with a growing wait. On a metered network (mobile data) the regions
/// already downloaded wait for another one unless the user allows mobile
/// data or asks for the update; a first download, or one cut short, goes
/// on whatever the network.
// keepAlive: a sync outlives the screen that started it.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  /// A sync older than this is refreshed.
  static const staleAfter = Duration(hours: 12);

  /// The wait before the sync that follows a contribution: the server's
  /// worker recomputes a place's summary in a second or so.
  static const afterContribution = Duration(seconds: 3);

  /// The wait before a second sync, for a worker held up by the conflation
  /// of an import, which can take longer than [afterContribution].
  static const followUp = Duration(seconds: 30);

  AppLifecycleListener? _lifecycle;
  Timer? _retry;
  Timer? _soon;
  Timer? _later;
  var _failures = 0;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _retry?.cancel();
      _soon?.cancel();
      _later?.cancel();
      _lifecycle?.dispose();
    });
    return const SyncIdle();
  }

  /// Brings to the device what a contribution the server just accepted
  /// changed: a sync after [afterContribution], another after [followUp].
  /// Each call restarts both waits, so contributions sent together give
  /// one sync and one follow-up.
  void syncAfterContribution() {
    _soon?.cancel();
    _later?.cancel();
    _soon = Timer(afterContribution, () => unawaited(_contributionSync(isFollowUp: false)));
    _later = Timer(followUp, () => unawaited(_contributionSync(isFollowUp: true)));
  }

  /// A refused request would be refused again, and a rate limit's wait is
  /// the server's: both keep their schedule. A contribution the server just
  /// accepted shows the network is back, so the first sync goes ahead of a
  /// retry still waiting out an earlier failure; the follow-up does not,
  /// and a failure of the first one keeps its growing wait.
  Future<void> _contributionSync({required bool isFollowUp}) async {
    if (state case SyncFailed(:final failure)) {
      if (isFollowUp || failure == SyncFailure.refused || failure == SyncFailure.busy) return;
    }
    // What the user just sent comes back whatever the network: a few
    // places, asked for by the user's own act.
    await sync(asked: true);
  }

  /// Starts the automatic syncs; later calls do nothing, and so does a
  /// device that keeps no places.
  void start() {
    if (_lifecycle != null || !ref.read(keepsPlacesProvider)) return;
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(syncIfStale()));
    // A sync the network failed goes again as soon as the network is back,
    // ahead of its retry's wait.
    final back = ref.listen(basemapReachabilityProvider, (before, now) {
      final failed = state;
      if (before == false &&
          now == true &&
          failed is SyncFailed &&
          failed.failure == SyncFailure.offline) {
        unawaited(sync());
      }
    });
    ref.onDispose(back.close);
    final unmetered = ref.listen(deviceNetworkProvider, (before, now) {
      if (before != null && before.metered && now != null && now.connected && !now.metered) {
        unawaited(syncIfStale());
      }
    });
    ref.onDispose(unmetered.close);
    unawaited(syncIfStale());
  }

  /// Syncs when a run waits to be resumed, when no full sync ever
  /// completed, or when the last one is older than [staleAfter].
  Future<void> syncIfStale() async {
    final state = await _stored();
    if (!ref.mounted) return;
    final last = state.completedAt;
    final now = ref.read(clockProvider)();
    if (!state.running && last != null && now.difference(last) < staleAfter) return;
    await sync();
  }

  /// Where the sync stands on the device, every region kept together.
  Future<SyncState> _stored() async {
    final legacy = await ref
        .read(placesRepositoryProvider)
        .watchSync(SyncRegion.metropolitanFrance.id)
        .first;
    if (!ref.mounted) return legacy;
    final kept = await ref.read(keptRegionsStoreProvider).load();
    if (kept == null || !ref.mounted) return legacy;
    // One read per region kept, rather than the first value of a watch.
    final store = ref.read(regionStoreProvider);
    final states = <String, SyncState>{};
    for (final code in kept) {
      states[code] = await store.stateOf(code);
      if (!ref.mounted) return legacy;
    }
    final catalog =
        ref.read(regionCatalogControllerProvider).value ??
        await ref.read(regionCatalogCopyProvider).load();
    return overallSyncState(
      kept: kept,
      catalog: catalog,
      states: {...states, SyncRegion.metropolitanFrance.id: legacy},
    );
  }

  /// A sync asked for while one runs (a region added meanwhile) runs once
  /// that one ends, as asked by the user when one of them was.
  bool _again = false;
  bool _againAsked = false;

  /// Syncs every region kept. [asked]: the user asked for it (a button), so
  /// the regions downloaded update whatever the network.
  Future<void> sync({bool fromScratch = false, bool asked = false}) async {
    if (!ref.read(keepsPlacesProvider)) return;
    if (state is SyncRunning) {
      _again = true;
      _againAsked |= asked;
      return;
    }
    final updates = asked || fromScratch || await _updatesAllowed();
    if (!ref.mounted) return;
    if (!updates && await _nothingToDownload()) {
      _log.info('metered network: the regions downloaded wait for another one');
      // Nothing failed: a failure shown, its retry and its count go.
      if (ref.mounted && state is SyncFailed) {
        _retry?.cancel();
        _failures = 0;
        state = const SyncIdle();
      }
      return;
    }
    if (!ref.mounted) return;
    // Another run started while this one weighed the network.
    if (state is SyncRunning) {
      _again = true;
      _againAsked |= asked;
      return;
    }
    _again = false;
    _againAsked = false;
    _retry?.cancel();
    state = const SyncRunning(0);
    try {
      final result = await ref
          .read(placesSyncProvider)
          .run(
            fromScratch: fromScratch,
            updates: updates,
            clock: ref.read(clockProvider),
            onProgress: (p) {
              if (ref.mounted) {
                state = SyncRunning(
                  p.places,
                  region: p.region,
                  packBytes: p.packBytes,
                  packSize: p.packSize,
                );
              }
            },
          );
      if (!ref.mounted) return;
      if (_again) {
        state = SyncDone(result.upserted);
        final asked = _againAsked;
        _againAsked = false;
        unawaited(sync(asked: asked));
        return;
      }
      if (!result.complete) {
        // The server said there was more without moving its cursor: the run
        // resumes from its last page at the next attempt.
        _failed(SyncFailure.server);
        return;
      }
      _failures = 0;
      state = SyncDone(result.upserted);
    } on Object catch (e, st) {
      _log.warning('sync failed', e, st);
      if (!ref.mounted) return;
      _failed(SyncFailure.of(e), serverWait: e is GraphQLRateLimitedException ? e.wait : null);
    }
  }

  /// Whether the regions downloaded may update now: on a network the system
  /// does not call metered, or with the user's leave for mobile data. A
  /// platform that says nothing of its network (the desktops) updates.
  Future<bool> _updatesAllowed() async {
    final network =
        ref.read(deviceNetworkProvider) ?? await ref.read(deviceNetworkProvider.notifier).refresh();
    // No network at all: the run fails for want of it, says so and tries
    // again, as it always did.
    if (network == null || !network.connected || !network.metered || !ref.mounted) return true;
    return await ref.read(regionUpdatesOnMobileProvider.future).catchError((Object _) => false);
  }

  /// Whether every region kept was downloaded whole once: then a sync that
  /// may not update has nothing to do, and asks nothing of the network.
  Future<bool> _nothingToDownload() async {
    final kept = await ref.read(keptRegionsStoreProvider).load();
    if (kept == null || !ref.mounted) return false;
    final store = ref.read(regionStoreProvider);
    for (final code in kept) {
      final state = await store.stateOf(code);
      if (!ref.mounted || state.completedAt == null || state.running) return false;
    }
    return true;
  }

  /// Reports [failure] and tries again after the next of [syncRetryDelays],
  /// or after [serverWait] when the server asked for longer. A refused
  /// request fails the same way next time: no automatic retry.
  void _failed(SyncFailure failure, {Duration? serverWait}) {
    final delays = ref.read(syncRetryDelaysProvider);
    var wait = failure == SyncFailure.refused || delays.isEmpty
        ? null
        : delays[_failures.clamp(0, delays.length - 1)];
    if (wait != null && serverWait != null && serverWait > wait) wait = serverWait;
    _failures++;
    state = SyncFailed(failure, retryIn: wait);
    if (wait != null) _retry = Timer(wait, () => unawaited(sync()));
  }
}

/// The filter the map and the list query with: the user's filters, with
/// "my vehicle fits" turned into the stored vehicle's height.
@riverpod
PlaceFilter effectiveFilter(Ref ref) =>
    ref.watch(placeFilterProvider).resolve(vehicleHeightM: ref.watch(vehicleHeightProvider));

/// Every place passing the filter, for the map.
@riverpod
Stream<List<PlaceSummary>> mapPlaces(Ref ref) =>
    ref.watch(placesRepositoryProvider).watchAll(ref.watch(effectiveFilterProvider));

/// One place for its page: the synced copy, the copy of an earlier
/// opening, or the API's ([PlaceReader]). A network failure is not asked
/// again behind the user's back ([placeRetry]): the page says at once that
/// there is no connection, with what the map knew of the place, and the
/// network's return reads it again.
@Riverpod(retry: placeRetry)
Stream<Place?> place(Ref ref, String id) => ref.watch(placeReaderProvider).watch(id);

/// The retries of a place's page: none after a network failure, which the
/// page shows at once (Riverpod's own retries kept it loading for a
/// minute, a skeleton without a word); Riverpod's own for the rest.
Duration? placeRetry(int count, Object error) =>
    error is GraphQLNetworkException && error is! GraphQLRateLimitedException
    ? null
    : ProviderContainer.defaultRetry(count, error);

// keepAlive: a stateless service over the run's client.
@Riverpod(keepAlive: true)
OnlinePlaces onlinePlaces(Ref ref) => GraphQLOnlinePlaces(ref.watch(graphQLClientProvider));

// keepAlive: a repository over the app-wide database and client.
@Riverpod(keepAlive: true)
PlaceReader placeReader(Ref ref) => PlaceReader(
  db: ref.watch(cacheDatabaseProvider),
  local: ref.watch(placesRepositoryProvider),
  // Offline the API is not asked: a place the device does not hold is not
  // there for it.
  online: ref.watch(placesFromTilesProvider) ? ref.watch(onlinePlacesProvider) : null,
  clock: ref.watch(clockProvider),
);

/// The TileJSON of the places' vector tiles on the API.
@riverpod
String placeTileJsonUrl(Ref ref) {
  final base = ref.watch(appConfigProvider).apiBase;
  return base.replace(path: '${base.path}/places/tiles.json').toString();
}

/// Whether the map draws the places from the API's vector tiles, and the
/// list and the search ask the API: always on the web, which keeps no
/// places; on a phone while the network answers (the places the device
/// holds take over offline). A demo build has no server behind its tiles.
// keepAlive: the map, the list and the reader of places follow it all the run.
@Riverpod(keepAlive: true)
bool placesFromTiles(Ref ref) {
  if (ref.watch(appConfigProvider).demo) return false;
  if (kIsWeb) return true;
  return ref.watch(basemapReachabilityProvider) != false;
}

@riverpod
Stream<int> placeCount(Ref ref) => ref.watch(placesRepositoryProvider).watchCount();

/// How many places of the map's view a filter keeps, before the user
/// applies it, counted where the list beside the map counts its own
/// ([NearbyPlacesPage]): the places the device holds; with the places from
/// the tiles, the map's report of the view from the zoom of the names
/// ([tilePlacesOf]), else the API's count of the box the list asks, once
/// the choice pauses. For the filter applied, the sheet's button and the
/// list's title tell the same number.
@riverpod
Future<int> filterPreviewCount(Ref ref, PlaceFilter filter) async {
  final resolved = filter.resolve(vehicleHeightM: ref.watch(vehicleHeightProvider));
  final view = ref.watch(viewportProvider) ?? initialViewport;
  if (!ref.watch(placesFromTilesProvider)) {
    // Re-count when a sync writes.
    ref.watch(placeCountProvider);
    return await ref.watch(placesRepositoryProvider).countMatching(resolved, bounds: view.bounds);
  }
  if (tilePlacesOf(view, ref.watch(placesInViewProvider)) case final inView?) {
    return inView.where(resolved.matches).length;
  }
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!ref.mounted) return 0;
  // At the zoom of the names, the view's own places among the widened
  // view's, as the list keeps them ([NearbyPlacesPage]); below, the count
  // of the widened view the list's title gives too.
  final street = view.zoom >= PlaceTiles.nameZoom;
  final page = await ref
      .read(onlinePlacesProvider)
      .inBounds(view.bounds, resolved, near: view.center, first: street ? nearbyRankedLimit : 1);
  if (street) return page.places.where((p) => view.bounds.contains(p.position)).length;
  return page.total;
}

/// Where the sync stands, as stored: every region kept together
/// ([overallSyncState]), or France by box before any region was chosen.
@riverpod
Stream<SyncState> syncState(Ref ref) {
  final legacy = ref.watch(placesRepositoryProvider).watchSync(SyncRegion.metropolitanFrance.id);
  final kept = ref.watch(keptRegionsControllerProvider).value;
  if (kept == null) return legacy;
  final catalog = ref.watch(regionCatalogControllerProvider).value;
  final states = ref.watch(regionStatesProvider).value ?? const {};
  return legacy.map(
    (l) => overallSyncState(
      kept: kept,
      catalog: catalog,
      states: {...states, SyncRegion.metropolitanFrance.id: l},
    ),
  );
}

@riverpod
Future<int> storageSize(Ref ref) {
  // Re-read when a sync writes.
  ref.watch(placeCountProvider);
  return ref.watch(placesRepositoryProvider).storageSizeBytes();
}

// keepAlive: a repository over the app-wide database and client.
@Riverpod(keepAlive: true)
PlaceExtrasRepository placeExtrasRepository(Ref ref) => PlaceExtrasRepository(
  db: ref.watch(cacheDatabaseProvider),
  // With the account's session when the device has one: the server then
  // adds the reader's own review and leaves out the authors it muted.
  source: GraphQLPlaceExtrasSource(
    ref.watch(graphQLClientProvider),
    headers: () => ref.read(accountServiceProvider).readHeaders(),
  ),
  clock: ref.watch(clockProvider),
);

/// Photos and reviews of a place, online with a cache. A failure without a
/// cached copy surfaces, so the screen can say a connection is needed.
@Riverpod(retry: noRetry)
Stream<PlaceExtras?> placeExtras(Ref ref, String placeId) =>
    ref.watch(placeExtrasRepositoryProvider).watch(placeId);

/// A failure the user must see at once is not retried behind their back.
Duration? noRetry(int _, Object _) => null;

/// The reviews on screen, and whether the next page is on its way.
@immutable
final class ReviewList {
  const new(this.page, {this.loadingMore = false, this.moreFailed = false});

  final ReviewPage page;
  final bool loadingMore;

  /// The last attempt at the next page failed; the button offers a retry.
  final bool moreFailed;
}

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand. Like the extras it reads, a failure surfaces at
/// once instead of being retried behind the user's back.
@Riverpod(retry: noRetry)
class PlaceReviews extends _$PlaceReviews {
  @override
  Future<ReviewList> build(String placeId) async {
    final previous = state.value;
    final extras = await ref.watch(placeExtrasProvider(placeId).future);
    final first = extras?.reviews ?? ReviewPage.empty;
    // The extras emit again when a fresh copy replaces the cached one: pages
    // the user already loaded stay, as long as the first page did not change.
    if (previous != null && previous.page.nodes.length > first.nodes.length) {
      final head = previous.page.nodes.take(first.nodes.length).map((r) => r.id).toList();
      if (_sameIds(head, first.nodes.map((r) => r.id).toList())) return ReviewList(previous.page);
    }
    return ReviewList(first);
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.page.hasNextPage) return;
    state = AsyncData(ReviewList(current.page, loadingMore: true));
    try {
      final next = await ref.read(placeExtrasRepositoryProvider).more(placeId, current.page);
      if (!ref.mounted) return;
      state = AsyncData(ReviewList(next));
    } on Object catch (e) {
      _log.info('more reviews of $placeId failed: $e');
      if (!ref.mounted) return;
      // The reviews already shown stay; the button says it failed.
      state = AsyncData(ReviewList(current.page, moreFailed: true));
    }
  }
}

/// The search of the map; [near] ranks the nearest matches first. On the
/// device when it holds places (no request, and it works in a tunnel),
/// else the API's once typing pauses, with the addresses, named in
/// [language] abroad where the data has it. A browser offline fails it at
/// once, and a request is given up after [searchWait]: the search says
/// there is no connection rather than turn while retries wait (a failure
/// the user must see at once, as for the addresses).
@Riverpod(retry: noRetry)
Future<SearchResults> searchResults(Ref ref, String query, {LatLng? near, String? language}) async {
  final local = ref.watch(placesRepositoryProvider);
  final fromTiles = ref.watch(placesFromTilesProvider);
  // Follows the browser's network (BasemapReachability): a search that
  // failed offline asks again when it is back.
  final reachable = ref.watch(basemapReachabilityProvider);
  if (!fromTiles || await local.watchCount().first > 0) {
    return await local.search(query, near: near);
  }
  final text = query.trim();
  if (text.length < 2) return SearchResults.empty;
  // The browser's word, not the tile host's: the API may answer while the
  // basemap's host does not.
  if (reachable == false && ref.read(browserProvider)?.online == false) {
    throw GraphQLNetworkException('offline', null);
  }
  // Ranked from the map's centre on the search grid, never from the user,
  // as the shops are: the text goes with it.
  final centre = ref.read(viewportProvider)?.center;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!ref.mounted) return SearchResults.empty;
  // One request for the places and the addresses; a query the user typed
  // past is cancelled with its provider, one the network does not answer
  // after [searchWait].
  final abort = Completer<void>();
  void cancel() {
    if (!abort.isCompleted) abort.complete();
  }

  ref.onDispose(cancel);
  final giveUp = Timer(searchWait, cancel);
  ref.onDispose(giveUp.cancel);
  final answer = await ref
      .read(onlinePlacesProvider)
      .searchAll(text, near: centre, language: language, abort: abort.future);
  giveUp.cancel();
  return SearchResults(
    places: answer.places,
    // The API's towns: each with every place it holds, whatever the page of
    // places near the map holds (counted from that page, Viviers had 5, 10
    // or 18 places by the view), and the homonyms of other departments.
    municipalities: answer.towns,
    addresses: answer.addresses,
  );
}

/// The longest wait for the search's request: the server answers in well
/// under a second, a network that takes longer is not carrying it.
const searchWait = Duration(seconds: 8);

/// The addresses under the places of the map's search: those the API
/// gave with its places, else, for a device that searched its own places,
/// the API's once typing pauses, asked from the map's centre on the search
/// grid as the places are, and given up after [addressWait]. Offline, or for
/// fewer than three characters, none: the places and towns the device holds
/// still answer. A query the user typed past is cancelled.
@Riverpod(retry: noRetry)
Future<List<AddressMatch>> addressSearch(
  Ref ref,
  String query, {
  LatLng? near,
  String? language,
}) async {
  final results = ref.watch(searchResultsProvider(query, near: near, language: language).future);
  final online = ref.watch(placesFromTilesProvider);
  final answered = (await results).addresses;
  if (answered != null) return answered;
  final text = query.trim();
  if (!online || text.length < 3) return const [];
  final centre = ref.read(viewportProvider)?.center;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!ref.mounted) return const [];
  // Cancelled when the user types past it, or when it takes longer than
  // the server's own bound on its geocoders could explain: a weak network.
  final abort = Completer<void>();
  void cancel() {
    if (!abort.isCompleted) abort.complete();
  }

  ref.onDispose(cancel);
  final giveUp = Timer(addressWait, cancel);
  ref.onDispose(giveUp.cancel);
  final answer = await ref
      .read(onlinePlacesProvider)
      .searchAll(text, near: centre, places: false, language: language, abort: abort.future);
  giveUp.cancel();
  return answer.addresses;
}

/// The longest wait for the addresses of a device that searched its own
/// places: the server gives its geocoders 700 ms each.
const addressWait = Duration(seconds: 5);

/// [addresses] without the towns already listed in [towns]: the same name
/// in the same area ([sameTownArea]: the French department, else the start
/// of the postcode, when both say), as the server leaves them out of its
/// own list. The device lists its own towns, which the server did not see;
/// Lyon 69001 is the Lyon listed with 69009, Viviers 89700 is not the
/// Viviers of Ardèche.
List<AddressMatch> withoutShownTowns(List<AddressMatch> addresses, List<Municipality> towns) {
  bool shown(AddressMatch a) {
    final name = switch (a.kind) {
      AddressKind.town => a.name,
      AddressKind.postcode => a.city,
      _ => null,
    };
    if (name == null) return false;
    final key = townKey(name);
    return towns.any(
      (t) =>
          townKey(t.name) == key &&
          sameTownArea(t.postcode, a.postcode, aCountry: t.countryCode, bCountry: a.countryCode),
    );
  }

  return [
    for (final a in addresses)
      if (!shown(a)) a,
  ];
}
