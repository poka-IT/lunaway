import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

Place _place(int i) => Place(
  id: 'p$i',
  kind: PlaceKind.parking,
  lat: 45,
  lon: 4,
  overnight: OvernightStatus.unknown,
  updatedAt: DateTime.utc(2026),
);

/// Serves [total] places in pages and records every request.
final class _Server implements ChangesSource {
  new(this.total, {this.stuckAt});

  final int total;

  /// From this cursor on, the server keeps answering hasMore without moving.
  final String? stuckAt;
  final List<({String? since, int first})> requests = [];
  StateError? failAfter;

  /// Cursors from another copy of the change feed, answered with RESYNC.
  Set<String?> foreign = {};

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) async {
    requests.add((since: since, first: first));
    if (failAfter != null && requests.length > 1) throw failAfter!;
    if (foreign.contains(since)) {
      throw GraphQLResponseException(const [
        GraphQLError('since comes from another copy', code: GraphQLError.resync),
      ]);
    }
    if (since != null && since == stuckAt) {
      return ChangeSet(places: const [], deleted: const [], cursor: since, hasMore: true);
    }
    final start = int.tryParse(since ?? '') ?? 0;
    final end = (start + first).clamp(0, total);
    return ChangeSet(
      places: [for (var i = start; i < end; i++) _place(i)],
      deleted: start == 0 ? const ['gone'] : const [],
      cursor: '$end',
      hasMore: end < total,
    );
  }
}

/// The store contract in memory: a cursor, a generation, the running and
/// full flags, a completion time.
final class _Store implements SyncStore {
  SyncState state = SyncState.none;
  final List<ChangeSet> pages = [];
  int resets = 0;
  final List<String> events = [];

  /// How many stale places the sweep finds.
  int stale = 0;

  @override
  Future<SyncState> stateOf(String region) async => state;

  @override
  Future<void> beginFullSync(String region) async {
    events.add('begin');
    state = SyncState(
      generation: state.generation + 1,
      fullSync: true,
      running: true,
      completedAt: state.completedAt,
    );
  }

  @override
  Future<void> beginDeltaSync(String region) async {
    events.add('delta');
    state = SyncState(
      cursor: state.cursor,
      generation: state.generation,
      running: true,
      completedAt: state.completedAt,
    );
  }

  @override
  Future<void> applyPage(String region, ChangeSet page) async {
    events.add('page');
    pages.add(page);
    state = SyncState(
      cursor: page.cursor,
      generation: state.generation,
      fullSync: state.fullSync,
      running: state.running,
      completedAt: state.completedAt,
    );
  }

  @override
  Future<int> completeRun(String region, GeoBounds bounds, DateTime at) async {
    events.add(state.fullSync ? 'sweep' : 'done');
    final swept = state.fullSync ? stale : 0;
    state = SyncState(cursor: state.cursor, generation: state.generation, completedAt: at);
    return swept;
  }

  @override
  Future<void> reset(String region, GeoBounds bounds) async {
    resets++;
    state = SyncState.none;
  }
}

void main() {
  const region = SyncRegion(id: 'r', bounds: GeoBounds.metropolitanFrance);

  test('pages through the changes until the server has no more', () async {
    final server = _Server(2500);
    final store = _Store();
    final progress = <int>[];
    final result = await SyncService(
      source: server,
      store: store,
    ).sync(region, onProgress: (p) => progress.add(p.upserted));
    // Pages the API serves whole: of 1000, the budget refused them.
    expect(server.requests.map((r) => r.since), [null, '500', '1000', '1500', '2000']);
    expect(server.requests.every((r) => r.first == syncPageSize), isTrue);
    expect(syncPageSize, 500);
    expect(result.pages, 5);
    expect(result.upserted, 2500);
    expect(result.deleted, 1);
    expect(progress, [500, 1000, 1500, 2000, 2500]);
    expect(store.state.cursor, '2500');
    expect(result.complete, isTrue);
  });

  test('resumes from the stored cursor', () async {
    final server = _Server(2500);
    final store = _Store()..state = const SyncState(cursor: '2000');
    await SyncService(source: server, store: store, pageSize: 1000).sync(region);
    expect(server.requests.map((r) => r.since), ['2000']);
    expect(store.events.first, 'delta');
  });

  test('a sync from scratch forgets the cursor first', () async {
    final server = _Server(10);
    final store = _Store()..state = const SyncState(cursor: '2000');
    await SyncService(source: server, store: store, pageSize: 1000).sync(region, fromScratch: true);
    expect(store.resets, 1);
    expect(server.requests.first.since, isNull);
  });

  test('stops when the server says hasMore without moving the cursor', () async {
    final server = _Server(5000, stuckAt: '1000');
    final store = _Store();
    final result = await SyncService(source: server, store: store, pageSize: 1000).sync(region);
    expect(result.pages, 2);
    expect(result.complete, isFalse);
    expect(store.state.running, isTrue, reason: 'it resumes at the next occasion');
  });

  test('a first sync is a full one, swept at the end of what the server no longer has', () async {
    final store = _Store()..stale = 3;
    final result = await SyncService(
      source: _Server(1500),
      store: store,
      pageSize: 1000,
    ).sync(region);
    expect(store.events, ['begin', 'page', 'page', 'sweep']);
    expect(result.deleted, 1 + 3);
    expect(store.state.fullSync, isFalse);
    expect(store.state.completedAt, isNotNull);
  });

  test('a delta sync sweeps nothing', () async {
    final store = _Store()..state = const SyncState(cursor: '1000');
    await SyncService(source: _Server(1500), store: store, pageSize: 1000).sync(region);
    expect(store.events, ['delta', 'page', 'done']);
  });

  test(
    'a cursor the server calls foreign is dropped for a sync from scratch, then swept',
    () async {
      final server = _Server(1500)..foreign = {'stale'};
      final store = _Store()..state = const SyncState(cursor: 'stale');
      final result = await SyncService(source: server, store: store, pageSize: 1000).sync(region);
      expect(server.requests.map((r) => r.since), ['stale', null, '1000']);
      expect(store.events, ['delta', 'begin', 'page', 'page', 'sweep']);
      expect(store.resets, 0, reason: 'the places and favourites stay until the sweep');
      expect(store.state.cursor, '1500');
      expect(result.upserted, 1500);
    },
  );

  test('a sync from scratch the server still refuses fails rather than loops', () async {
    final server = _Server(10)..foreign = {null};
    final store = _Store();
    await expectLater(
      SyncService(source: server, store: store, pageSize: 1000).sync(region),
      throwsA(isA<GraphQLResponseException>()),
    );
    expect(server.requests, hasLength(1));
  });

  test('a full sync cut short sweeps when a later sync completes it', () async {
    final server = _Server(1500)..failAfter = StateError('offline');
    final store = _Store();
    await expectLater(
      SyncService(source: server, store: store, pageSize: 1000).sync(region),
      throwsStateError,
    );
    expect(store.events, ['begin', 'page']);
    expect(store.state.completedAt, isNull, reason: 'a cut run is not a sync');
    server.failAfter = null;
    await SyncService(source: server, store: store, pageSize: 1000).sync(region);
    // Resumed as it was: still the same full sync, no second "begin".
    expect(store.events, ['begin', 'page', 'page', 'sweep']);
    expect(server.requests.last.since, '1000');
  });

  test('a failure mid-way keeps the pages already stored, for a later resume', () async {
    final server = _Server(2500)..failAfter = StateError('offline');
    final store = _Store();
    await expectLater(
      SyncService(source: server, store: store, pageSize: 1000).sync(region),
      throwsStateError,
    );
    expect(store.state.cursor, '1000');
  });
}
