import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';

import '../helpers/pump.dart' show FixedRegionCatalog;

Place _place(int i) => Place(
  id: 'p$i',
  kind: PlaceKind.parking,
  lat: 45 + i / 10000,
  lon: 4,
  overnight: OvernightStatus.unknown,
  updatedAt: DateTime.utc(2026),
);

/// 2500 places in pages of 1000; [cutAfterFirstPage] drops the connection
/// on the second request.
final class _Server implements ChangesSource {
  bool cutAfterFirstPage = false;
  final List<String?> requests = [];

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) async {
    requests.add(since);
    if (cutAfterFirstPage && requests.length > 1) {
      throw GraphQLNetworkException('connection lost', null);
    }
    final start = int.tryParse(since ?? '') ?? 0;
    final end = (start + first).clamp(0, 2500);
    return ChangeSet(
      places: [for (var i = start; i < end; i++) _place(i)],
      deleted: const [],
      cursor: '$end',
      hasMore: end < 2500,
    );
  }
}

/// The first download of a region, cut short and resumed, on the real drift
/// store and through the controller the app runs.
void main() {
  late CacheDatabase db;
  late _Server server;
  late DateTime now;
  late ProviderContainer container;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    server = _Server();
    now = DateTime.utc(2026, 10, 6, 8);
    final repo = DriftPlacesRepository(db);
    container = ProviderContainer.test(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(db),
        driftPlacesRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
        syncRetryDelaysProvider.overrideWithValue(const []),
        syncServiceProvider.overrideWithValue(
          SyncService(source: server, store: repo, pageSize: 1000),
        ),
        // An API without regions: the sync by box runs.
        regionCatalogControllerProvider.overrideWith(() => FixedRegionCatalog(null)),
        userDatabaseProvider.overrideWithValue(UserDatabase(NativeDatabase.memory())),
      ],
    );
  });
  tearDown(() => db.close());

  // The screens listen to these providers; so does the test, which keeps
  // them alive while it reads them.
  Future<SyncState> syncState() {
    container.listen(syncStateProvider, (_, _) {});
    return container.read(syncStateProvider.future);
  }

  Future<int> placeCount() {
    container.listen(placeCountProvider, (_, _) {});
    return container.read(placeCountProvider.future);
  }

  test('a first sync cut after its first page is not recorded as a completed sync', () async {
    server.cutAfterFirstPage = true;
    await container.read(syncControllerProvider.notifier).syncIfStale();

    expect(container.read(syncControllerProvider), isA<SyncFailed>());
    final state = await syncState();
    expect(state.completedAt, isNull, reason: 'the map says the download is incomplete');
    expect(state.running, isTrue);
    expect(state.cursor, '1000');
    expect(await placeCount(), 1000);
  });

  test('an hour later, the next occasion resumes from the cursor and completes', () async {
    server.cutAfterFirstPage = true;
    await container.read(syncControllerProvider.notifier).syncIfStale();
    server
      ..cutAfterFirstPage = false
      ..requests.clear();
    now = now.add(const Duration(hours: 1));

    await container.read(syncControllerProvider.notifier).syncIfStale();

    expect(server.requests.first, '1000', reason: 'resumed, not started over, not skipped');
    expect(container.read(syncControllerProvider), isA<SyncDone>());
    final state = await syncState();
    expect(state.completedAt, now);
    expect(state.running, isFalse);
    expect(await placeCount(), 2500);
  });

  test('a completed sync younger than twelve hours is left alone', () async {
    await container.read(syncControllerProvider.notifier).syncIfStale();
    server.requests.clear();
    now = now.add(const Duration(hours: 11));
    await container.read(syncControllerProvider.notifier).syncIfStale();
    expect(server.requests, isEmpty);
    now = now.add(const Duration(hours: 2));
    await container.read(syncControllerProvider.notifier).syncIfStale();
    expect(server.requests, ['2500'], reason: 'an old sync is refreshed as a delta');
  });

  test('a failed sync says why, in terms the screens turn into words', () async {
    server.cutAfterFirstPage = true;
    await container.read(syncControllerProvider.notifier).sync();
    final failed = container.read(syncControllerProvider) as SyncFailed;
    expect(failed.failure, SyncFailure.offline);
    expect(
      SyncFailure.of(GraphQLRateLimitedException(const Duration(minutes: 5))),
      SyncFailure.busy,
    );
    expect(
      SyncFailure.of(GraphQLResponseException(const [GraphQLError('no')])),
      SyncFailure.refused,
    );
  });
}
