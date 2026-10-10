import 'package:logging/logging.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/regions/data/region_operations.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/data/region_store.dart';
import 'package:lunaway/features/regions/domain/regions.dart';

final _log = Logger('sync');

/// Where the pages of a region's feed come from: the API, or the demo.
abstract interface class RegionChangesSource {
  Future<RegionChangeSet> changes({required String region, required int first, String? since});
}

/// The API as a [RegionChangesSource].
final class GraphQLRegionChangesSource implements RegionChangesSource {
  new(this.client);

  final GraphQLClient client;

  @override
  Future<RegionChangeSet> changes({required String region, required int first, String? since}) =>
      client.execute(regionChangesOperation, {'region': region, 'since': since, 'first': first});
}

/// Where a run of the sync stands, for the screens.
typedef RegionSyncProgress = ({
  /// The region being synced.
  String region,

  /// Places written so far by the run, packs and pages together.
  int places,

  /// Bytes of the region's pack received, and its size; zero when the
  /// region syncs from its feed.
  int packBytes,
  int packSize,
});

/// Syncs one region: its pack first, when the device holds nothing of the
/// region and can import one, then its feed from the pack's cursor
/// (docs/region-packs.md). Without a pack (the web, none built, a pack the
/// server answers wrongly), the feed from the start, swept at its end.
final class RegionSyncService {
  new({
    required this.changes,
    required this.store,
    required this.packs,
    required this.downloader,
    required this.packUrl,
    this.pageSize = syncPageSize,
    this.maxPages = 1000,
  });

  final RegionChangesSource changes;
  final RegionStore store;
  final RegionPackFiles packs;
  final PackDownloader downloader;

  /// The address of a pack the manifest names; null for one the app does
  /// not fetch.
  final Uri? Function(String url) packUrl;
  final int pageSize;

  /// A guard against a server that keeps answering `hasMore` without moving
  /// its cursor.
  final int maxPages;

  Future<SyncProgress> sync(
    RegionInfo region, {
    void Function(RegionSyncProgress progress)? onProgress,
    DateTime Function() clock = DateTime.now,
  }) async {
    final code = region.code;
    var places = 0;
    void report({int packBytes = 0, int packSize = 0}) =>
        onProgress?.call((region: code, places: places, packBytes: packBytes, packSize: packSize));

    /// Starts the region over: its pack when there is one to import, else
    /// its feed from the start. Answers the cursor to continue from.
    Future<String?> startOver() async {
      final pack = region.pack;
      final url = pack == null || !pack.importable || !packs.supported ? null : packUrl(pack.url);
      if (pack != null && url != null) {
        try {
          final path = await packs.fetch(
            pack,
            url,
            downloader: downloader,
            onProgress: (received) => report(packBytes: received, packSize: pack.bytes),
          );
          try {
            places += await store.importPack(code, path, cursor: pack.cursor);
          } finally {
            await packs.release(path);
          }
          report(packBytes: pack.bytes, packSize: pack.bytes);
          _log.info('$code: pack ${pack.version} imported, $places places');
          return pack.cursor;
        } on PackDownloadException catch (e) {
          // No network: the run stops here, to resume. A pack that is not
          // what the manifest says: the feed gives the same places.
          if (e.failure == PackDownloadFailure.network ||
              e.failure == PackDownloadFailure.storage) {
            rethrow;
          }
          _log.warning('$code: pack refused ($e), syncing from the feed');
        }
      }
      await store.beginFullSync(code);
      return null;
    }

    final state = await store.stateOf(code);
    String? since;
    if (state.running) {
      // An interrupted run carries on from its cursor, as it was.
      since = state.cursor;
    } else if (state.cursor == null) {
      since = await startOver();
    } else {
      await store.beginDeltaSync(code);
      since = state.cursor;
    }
    var pages = 0;
    var deleted = 0;
    var complete = false;
    while (pages < maxPages) {
      final RegionChangeSet page;
      try {
        page = await changes.changes(region: code, since: since, first: pageSize);
      } on GraphQLResponseException catch (e) {
        // The cursor comes from another copy of the server's feed (a
        // restore): the region starts over. Without a cursor the same
        // refusal would loop, so it surfaces.
        if (since == null || !e.hasCode(GraphQLError.resync)) rethrow;
        _log.warning('$code: the server asks for a sync from scratch');
        since = await startOver();
        continue;
      }
      await store.applyPage(code, page);
      pages++;
      places += page.places.length;
      deleted += page.deleted.length + page.left.length;
      report();
      if (!page.hasMore) {
        complete = true;
        break;
      }
      if (page.cursor == since) {
        _log.warning('$code: server says hasMore but the cursor did not move; stopping');
        break;
      }
      since = page.cursor;
    }
    if (complete) deleted += await store.completeRun(code, clock().toUtc());
    _log.info(
      '$code: $pages page(s), $places written, $deleted removed, '
      '${complete ? 'complete' : 'to be resumed'}',
    );
    return SyncProgress(pages: pages, upserted: places, deleted: deleted, complete: complete);
  }
}

/// The regions the device keeps, as a choice made or to make.
abstract interface class KeptRegions {
  /// Null until the first choice.
  Future<Set<String>?> load();

  /// Keeps [regions]; [guessed] when no position chose them.
  Future<void> save(Set<String> regions, {bool guessed = false});
}

/// The region where the user is, for the first choice: `located` when a
/// position said it, rather than the map's view or the phone's country.
typedef RegionHere = ({String code, bool located});

/// The sync of everything the device keeps: the regions of the manifest
/// the user keeps (until a choice, the one region where the user is), each
/// from its pack then its feed; the regions no longer kept are removed.
/// Against an API without regions, the sync by box of metropolitan France
/// that came before.
final class PlacesSync {
  new({
    required this.catalog,
    required this.kept,
    required this.regions,
    required this.store,
    required this.legacy,
    required this.here,
  });

  /// The manifest, read online; null when the API has no regions.
  final Future<RegionCatalog?> Function() catalog;
  final KeptRegions kept;

  /// The sync of a region and the store of the regions, built on first use:
  /// against an API without regions, neither opens anything.
  final RegionSyncService Function() regions;
  final RegionStore Function() store;

  /// The sync by box, for an API without regions.
  final SyncService legacy;

  /// Where the user is, as a region of [catalog]: for the first choice
  /// (`guess`, whatever says it best), then to sync first the region the
  /// user is in (a position only).
  final Future<RegionHere?> Function(RegionCatalog catalog, {required bool guess}) here;

  /// Syncs every region kept. Without [updates] (a metered network the
  /// user keeps for other things), only the regions never downloaded whole
  /// run: a first download, or one cut short; those downloaded wait.
  Future<SyncProgress> run({
    bool fromScratch = false,
    bool updates = true,
    void Function(RegionSyncProgress progress)? onProgress,
    DateTime Function() clock = DateTime.now,
  }) async {
    final manifest = await catalog();
    if (manifest == null) {
      return await legacy.sync(
        SyncRegion.metropolitanFrance,
        fromScratch: fromScratch,
        clock: clock,
        onProgress: (p) => onProgress?.call((
          region: SyncRegion.metropolitanFrance.id,
          places: p.upserted,
          packBytes: 0,
          packSize: 0,
        )),
      );
    }
    final regions = this.regions();
    final store = this.store();
    var chosen = await kept.load();
    final local = await here(manifest, guess: chosen == null);
    // A choice the user made while the region was looked for wins.
    chosen ??= await kept.load();
    if (chosen == null) {
      final first = manifest.firstChoice(local?.code);
      // No region known yet (the view at sea, a country the server does
      // not cover): nothing is kept, and a later run chooses again.
      if (first.isEmpty) {
        _log.info('no region where the user is yet: nothing downloaded');
        return const SyncProgress(pages: 0, upserted: 0, deleted: 0, complete: true);
      }
      await kept.save(first, guessed: !(local?.located ?? false));
      chosen = await kept.load() ?? first;
    }
    for (final held in await store.regions()) {
      if (!chosen.contains(held) || fromScratch) await store.forget(held);
    }
    // Where the user is goes first: the map there is usable soonest.
    final order = [
      for (final r in manifest.regions)
        if (chosen.contains(r.code)) r,
    ]..sort((a, b) => (b.code == local?.code ? 1 : 0).compareTo(a.code == local?.code ? 1 : 0));
    var total = const SyncProgress(pages: 0, upserted: 0, deleted: 0, complete: true);
    var written = 0;
    for (final region in order) {
      if (!updates && !fromScratch) {
        final state = await store.stateOf(region.code);
        if (state.completedAt != null && !state.running) continue;
      }
      final done = await regions.sync(
        region,
        clock: clock,
        onProgress: (p) => onProgress?.call((
          region: p.region,
          places: written + p.places,
          packBytes: p.packBytes,
          packSize: p.packSize,
        )),
      );
      written += done.upserted;
      total = SyncProgress(
        pages: total.pages + done.pages,
        upserted: total.upserted + done.upserted,
        deleted: total.deleted + done.deleted,
        complete: total.complete && done.complete,
      );
    }
    if (total.complete) {
      final dropped = await store.dropUnregioned();
      if (dropped > 0) _log.info('$dropped places of the sync by box dropped');
    }
    return total;
  }
}
