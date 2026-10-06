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

/// Where pages of changes come from: the API, or the demo data.
abstract interface class ChangesSource {
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since});
}

/// Where pages of changes go. A page and its cursor are written in one
/// transaction, so an interrupted sync resumes from the last whole page.
abstract interface class SyncStore {
  Future<String?> cursorFor(String region);

  Future<void> applyPage(String region, ChangeSet page, DateTime syncedAt);

  /// Forgets the cursor and every place, for a sync from scratch.
  Future<void> reset(String region);

  /// When the sync from scratch in progress for [region] started, if one is.
  Future<DateTime?> fullSyncStart(String region);

  /// Drops the cursor of [region] and records that a sync from scratch
  /// starts at [at]; the places stay on the device meanwhile.
  Future<void> beginFullSync(String region, DateTime at);

  /// Ends the sync from scratch of [region]: removes the places inside
  /// [bounds] that it did not write, which the server no longer has, and
  /// returns how many.
  Future<int> finishFullSync(String region, GeoBounds bounds);
}

@immutable
final class SyncProgress {
  const new({required this.pages, required this.upserted, required this.deleted});

  final int pages;
  final int upserted;
  final int deleted;
}

/// Pages through `changes(bbox, since, first)` until the server says there is
/// no more, storing the cursor after every page.
final class SyncService {
  new({required this.source, required this.store, this.pageSize = 1000, this.maxPages = 500});

  final ChangesSource source;
  final SyncStore store;
  final int pageSize;

  /// A guard against a server that keeps answering `hasMore` without moving
  /// the cursor; 500 pages of 1000 is far beyond France.
  final int maxPages;

  Future<SyncProgress> sync(
    SyncRegion region, {
    bool fromScratch = false,
    void Function(SyncProgress progress)? onProgress,
    DateTime Function() clock = DateTime.now,
  }) async {
    if (fromScratch) await store.reset(region.id);
    var since = await store.cursorFor(region.id);
    // Without a cursor the server sends every place but no deletion: the
    // sweep at the end removes what it no longer has.
    var full = since == null;
    if (full && await store.fullSyncStart(region.id) == null) {
      await store.beginFullSync(region.id, clock().toUtc());
    }
    var progress = const SyncProgress(pages: 0, upserted: 0, deleted: 0);
    var complete = false;
    while (progress.pages < maxPages) {
      final ChangeSet page;
      try {
        page = await source.changes(bbox: region.bounds, since: since, first: pageSize);
      } on GraphQLResponseException catch (e) {
        // The cursor comes from another copy of the server's change feed (a
        // restore): start again from scratch, keeping the places until the
        // sweep and the favourites for good.
        if (full || !e.hasCode(GraphQLError.resync)) rethrow;
        _log.warning('${region.id}: the server asks for a sync from scratch');
        await store.beginFullSync(region.id, clock().toUtc());
        since = null;
        full = true;
        continue;
      }
      await store.applyPage(region.id, page, clock().toUtc());
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
    if (complete && await store.fullSyncStart(region.id) != null) {
      final swept = await store.finishFullSync(region.id, region.bounds);
      progress = SyncProgress(
        pages: progress.pages,
        upserted: progress.upserted,
        deleted: progress.deleted + swept,
      );
    }
    _log.info(
      '${region.id}: ${progress.pages} page(s), ${progress.upserted} upserted, ${progress.deleted} deleted',
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
