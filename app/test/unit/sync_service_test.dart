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

final class _Store implements SyncStore {
  final Map<String, String> cursors = {};
  final List<ChangeSet> pages = [];
  int resets = 0;
  final Map<String, DateTime> fullStarts = {};
  final List<String> events = [];

  /// How many stale places the sweep finds.
  int stale = 0;

  @override
  Future<DateTime?> fullSyncStart(String region) async => fullStarts[region];

  @override
  Future<void> beginFullSync(String region, DateTime at) async {
    events.add('begin');
    cursors.remove(region);
    fullStarts[region] = at;
  }

  @override
  Future<int> finishFullSync(String region, GeoBounds bounds) async {
    events.add('sweep');
    fullStarts.remove(region);
    return stale;
  }

  @override
  Future<String?> cursorFor(String region) async => cursors[region];

  @override
  Future<void> applyPage(String region, ChangeSet page, DateTime syncedAt) async {
    events.add('page');
    pages.add(page);
    cursors[region] = page.cursor;
  }

  @override
  Future<void> reset(String region) async {
    resets++;
    cursors.remove(region);
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
    expect(server.requests.map((r) => r.since), [null, '1000', '2000']);
    expect(server.requests.every((r) => r.first == 1000), isTrue);
    expect(result.pages, 3);
    expect(result.upserted, 2500);
    expect(result.deleted, 1);
    expect(progress, [1000, 2000, 2500]);
    expect(store.cursors['r'], '2500');
  });

  test('resumes from the stored cursor', () async {
    final server = _Server(2500);
    final store = _Store()..cursors['r'] = '2000';
    await SyncService(source: server, store: store).sync(region);
    expect(server.requests.map((r) => r.since), ['2000']);
  });

  test('a sync from scratch forgets the cursor first', () async {
    final server = _Server(10);
    final store = _Store()..cursors['r'] = '2000';
    await SyncService(source: server, store: store).sync(region, fromScratch: true);
    expect(store.resets, 1);
    expect(server.requests.first.since, isNull);
  });

  test('stops when the server says hasMore without moving the cursor', () async {
    final server = _Server(5000, stuckAt: '1000');
    final store = _Store();
    final result = await SyncService(source: server, store: store).sync(region);
    expect(result.pages, 2);
  });

  test('a first sync is a full one, swept at the end of what the server no longer has', () async {
    final store = _Store()..stale = 3;
    final result = await SyncService(source: _Server(1500), store: store).sync(region);
    expect(store.events, ['begin', 'page', 'page', 'sweep']);
    expect(result.deleted, 1 + 3);
    expect(store.fullStarts, isEmpty);
  });

  test('a delta sync sweeps nothing', () async {
    final store = _Store()..cursors['r'] = '1000';
    await SyncService(source: _Server(1500), store: store).sync(region);
    expect(store.events, ['page']);
  });

  test(
    'a cursor the server calls foreign is dropped for a sync from scratch, then swept',
    () async {
      final server = _Server(1500)..foreign = {'stale'};
      final store = _Store()..cursors['r'] = 'stale';
      final result = await SyncService(source: server, store: store).sync(region);
      expect(server.requests.map((r) => r.since), ['stale', null, '1000']);
      expect(store.events, ['begin', 'page', 'page', 'sweep']);
      expect(store.resets, 0, reason: 'the places and favourites stay until the sweep');
      expect(store.cursors['r'], '1500');
      expect(result.upserted, 1500);
    },
  );

  test('a sync from scratch the server still refuses fails rather than loops', () async {
    final server = _Server(10)..foreign = {null};
    final store = _Store();
    await expectLater(
      SyncService(source: server, store: store).sync(region),
      throwsA(isA<GraphQLResponseException>()),
    );
    expect(server.requests, hasLength(1));
  });

  test('a full sync cut short sweeps when a later sync completes it', () async {
    final server = _Server(1500)..failAfter = StateError('offline');
    final store = _Store();
    await expectLater(SyncService(source: server, store: store).sync(region), throwsStateError);
    expect(store.events, ['begin', 'page']);
    server.failAfter = null;
    await SyncService(source: server, store: store).sync(region);
    expect(store.events, ['begin', 'page', 'page', 'sweep']);
  });

  test('a failure mid-way keeps the pages already stored, for a later resume', () async {
    final server = _Server(2500)..failAfter = StateError('offline');
    final store = _Store();
    await expectLater(SyncService(source: server, store: store).sync(region), throwsStateError);
    expect(store.cursors['r'], '1000');
  });
}
