import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/demo/demo_server.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'places_providers.g.dart';

final _log = Logger('places');

// keepAlive: one client for the run; in demo mode it talks to the
// in-process demo API instead of the network.
@Riverpod(keepAlive: true)
GraphQLClient graphQLClient(Ref ref) {
  final config = ref.watch(appConfigProvider);
  return GraphQLClient(
    endpoint: config.graphqlEndpoint,
    httpClient: config.demo ? demoApiClient(demoPlaces()) : ref.watch(httpClientProvider),
    userAgent: ref.watch(userAgentProvider),
  );
}

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
DriftPlacesRepository driftPlacesRepository(Ref ref) =>
    DriftPlacesRepository(ref.watch(appDatabaseProvider));

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

/// Where a sync stands, for the offline data panel and the map banner.
@immutable
sealed class SyncStatus {
  const new();
}

final class SyncIdle extends SyncStatus {
  const new();
}

final class SyncRunning extends SyncStatus {
  const new(this.received);

  final int received;
}

final class SyncDone extends SyncStatus {
  const new(this.received);

  final int received;
}

final class SyncFailed extends SyncStatus {
  const new(this.error);

  final Object error;
}

/// Runs the sync of the region and reports its progress.
// keepAlive: a sync outlives the screen that started it.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  /// A sync older than this is refreshed at startup.
  static const staleAfter = Duration(hours: 12);

  @override
  SyncStatus build() => const SyncIdle();

  Future<void> syncIfStale() async {
    final last = await ref
        .read(placesRepositoryProvider)
        .watchLastSync(SyncRegion.metropolitanFrance.id)
        .first;
    if (!ref.mounted) return;
    final now = ref.read(clockProvider)();
    if (last != null && now.difference(last) < staleAfter) return;
    await sync();
  }

  Future<void> sync({bool fromScratch = false}) async {
    if (state is SyncRunning) return;
    state = const SyncRunning(0);
    try {
      final result = await ref
          .read(syncServiceProvider)
          .sync(
            SyncRegion.metropolitanFrance,
            fromScratch: fromScratch,
            onProgress: (p) {
              if (ref.mounted) state = SyncRunning(p.upserted);
            },
          );
      if (!ref.mounted) return;
      state = SyncDone(result.upserted);
    } on Object catch (e, st) {
      _log.warning('sync failed', e, st);
      if (!ref.mounted) return;
      state = SyncFailed(e);
    }
  }
}

/// Every place passing the filter, for the map.
@riverpod
Stream<List<PlaceSummary>> mapPlaces(Ref ref) =>
    ref.watch(placesRepositoryProvider).watchAll(ref.watch(placeFilterProvider));

@riverpod
Stream<Place?> place(Ref ref, String id) => ref.watch(placesRepositoryProvider).watchPlace(id);

@riverpod
Stream<int> placeCount(Ref ref) => ref.watch(placesRepositoryProvider).watchCount();

/// How many places a filter keeps, before the user applies it.
@riverpod
Future<int> filterPreviewCount(Ref ref, PlaceFilter filter) {
  // Re-count when a sync writes.
  ref.watch(placeCountProvider);
  return ref.watch(placesRepositoryProvider).countMatching(filter);
}

@riverpod
Stream<DateTime?> lastSync(Ref ref) =>
    ref.watch(placesRepositoryProvider).watchLastSync(SyncRegion.metropolitanFrance.id);

@riverpod
Future<int> storageSize(Ref ref) {
  // Re-read when a sync writes.
  ref.watch(placeCountProvider);
  return ref.watch(placesRepositoryProvider).storageSizeBytes();
}

// keepAlive: a repository over the app-wide database and client.
@Riverpod(keepAlive: true)
PlaceExtrasRepository placeExtrasRepository(Ref ref) => PlaceExtrasRepository(
  db: ref.watch(appDatabaseProvider),
  source: GraphQLPlaceExtrasSource(ref.watch(graphQLClientProvider)),
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
/// ones appended on demand.
@riverpod
class PlaceReviews extends _$PlaceReviews {
  @override
  Future<ReviewList> build(String placeId) async {
    final extras = await ref.watch(placeExtrasProvider(placeId).future);
    return ReviewList(extras?.reviews ?? ReviewPage.empty);
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

/// Local search; [near] ranks the nearest matches first.
@riverpod
Future<SearchResults> searchResults(Ref ref, String query, {LatLng? near}) =>
    ref.watch(placesRepositoryProvider).search(query, near: near);
