import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:meta/meta.dart';

final _log = Logger('sync');

/// A region the device keeps in full, with its own cursor.
@immutable
final class SyncRegion {
  const new({required this.id, required this.bounds});

  static const metropolitanFrance = SyncRegion(
    id: 'fr-metro',
    bounds: GeoBounds.metropolitanFrance,
  );

  final String id;
  final GeoBounds bounds;
}

/// Where the sync of a region stands, as the store keeps it across runs.
@immutable
final class SyncState {
  const new({
    this.cursor,
    this.generation = 0,
    this.fullSync = false,
    this.running = false,
    this.completedAt,
  });

  static const none = SyncState();

  /// The cursor of the last page written; null before the first page of a
  /// full sync.
  final String? cursor;

  /// The generation of the current or last full sync.
  final int generation;

  /// A full sync is under way: its end removes what it did not write.
  final bool fullSync;

  /// A run started and has not reached its last page: it resumes from
  /// [cursor] at the next occasion, whatever the age of the last sync.
  final bool running;

  /// When a run last reached its last page; null until the first full sync
  /// of the region completes.
  final DateTime? completedAt;

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.cursor == cursor &&
      other.generation == generation &&
      other.fullSync == fullSync &&
      other.running == running &&
      other.completedAt == completedAt;

  @override
  int get hashCode => Object.hash(cursor, generation, fullSync, running, completedAt);
}

/// Where pages of changes come from: the API, or the demo data.
abstract interface class ChangesSource {
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since});
}

/// Where pages of changes go. A page and its cursor are written in one
/// transaction, so an interrupted run resumes from the last whole page.
abstract interface class SyncStore {
  Future<SyncState> stateOf(String region);

  /// Starts a full sync of [region]: a new generation, no cursor, running.
  /// The places stay on the device until the sync ends.
  Future<void> beginFullSync(String region);

  /// Starts a delta run from the stored cursor.
  Future<void> beginDeltaSync(String region);

  /// Writes [page] and its cursor, tagging the places with the current
  /// generation.
  Future<void> applyPage(String region, ChangeSet page);

  /// Ends the run at its last page: when it was a full sync, removes the
  /// places inside [bounds] it did not write (the server no longer has
  /// them) and returns how many; records [at] as the completion time.
  Future<int> completeRun(String region, GeoBounds bounds, DateTime at);

  /// Forgets [region]: its state, and the places inside [bounds].
  Future<void> reset(String region, GeoBounds bounds);
}

@immutable
final class SyncProgress {
  const new({
    required this.pages,
    required this.upserted,
    required this.deleted,
    this.complete = false,
  });

  final int pages;
  final int upserted;
  final int deleted;

  /// The run reached the server's last page.
  final bool complete;
}

/// Pages through `changes(bbox, since, first)` until the server says there is
/// no more, storing the cursor after every page.
final class SyncService {
  new({
    required this.source,
    required this.store,
    this.pageSize = syncPageSize,
    this.maxPages = 1000,
  });

  final ChangesSource source;
  final SyncStore store;
  final int pageSize;

  /// A guard against a server that keeps answering `hasMore` without moving
  /// the cursor; 1000 pages of 500 is far beyond France.
  final int maxPages;

  Future<SyncProgress> sync(
    SyncRegion region, {
    bool fromScratch = false,
    void Function(SyncProgress progress)? onProgress,
    DateTime Function() clock = DateTime.now,
  }) async {
    if (fromScratch) await store.reset(region.id, region.bounds);
    final state = await store.stateOf(region.id);
    // An interrupted run carries on from its cursor, as it was (full or
    // delta). Otherwise a region without a cursor starts a full sync: the
    // server then sends every place but no deletion, and the sweep at the
    // end removes what it no longer has.
    if (!state.running) {
      if (state.cursor == null) {
        await store.beginFullSync(region.id);
      } else {
        await store.beginDeltaSync(region.id);
      }
    }
    var since = state.cursor;
    var progress = const SyncProgress(pages: 0, upserted: 0, deleted: 0);
    var complete = false;
    while (progress.pages < maxPages) {
      final ChangeSet page;
      try {
        page = await source.changes(bbox: region.bounds, since: since, first: pageSize);
      } on GraphQLResponseException catch (e) {
        // The cursor comes from another copy of the server's change feed (a
        // restore): start again from scratch, keeping the places until the
        // sweep and the favourites for good. Without a cursor the request
        // cannot be refused this way: that would loop, so it surfaces.
        if (since == null || !e.hasCode(GraphQLError.resync)) rethrow;
        _log.warning('${region.id}: the server asks for a sync from scratch');
        await store.beginFullSync(region.id);
        since = null;
        continue;
      }
      await store.applyPage(region.id, page);
      progress = SyncProgress(
        pages: progress.pages + 1,
        upserted: progress.upserted + page.places.length,
        deleted: progress.deleted + page.deleted.length,
      );
      onProgress?.call(progress);
      if (!page.hasMore) {
        complete = true;
        break;
      }
      if (page.cursor == since) {
        _log.warning('${region.id}: server says hasMore but the cursor did not move; stopping');
        break;
      }
      since = page.cursor;
    }
    if (complete) {
      final swept = await store.completeRun(region.id, region.bounds, clock().toUtc());
      progress = SyncProgress(
        pages: progress.pages,
        upserted: progress.upserted,
        deleted: progress.deleted + swept,
        complete: true,
      );
    }
    _log.info(
      '${region.id}: ${progress.pages} page(s), ${progress.upserted} upserted, '
      '${progress.deleted} deleted, ${complete ? 'complete' : 'to be resumed'}',
    );
    return progress;
  }
}

/// The API as a [ChangesSource].
final class GraphQLChangesSource implements ChangesSource {
  new(this.client);

  final GraphQLClient client;

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) =>
      client.execute(changesOperation, changesVariables(bbox: bbox, since: since, first: first));
}
