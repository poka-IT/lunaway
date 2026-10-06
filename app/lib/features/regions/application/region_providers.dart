import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/regions/data/region_operations.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/data/region_store.dart';
import 'package:lunaway/features/regions/data/region_sync_service.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'region_providers.g.dart';

final _log = Logger('sync');

// keepAlive: a store over the app-wide database.
@Riverpod(keepAlive: true)
RegionStore regionStore(Ref ref) =>
    DriftRegionStore(ref.watch(cacheDatabaseProvider), ref.watch(driftPlacesRepositoryProvider));

// keepAlive: a store over the app-wide database.
@Riverpod(keepAlive: true)
KeptRegionsStore keptRegionsStore(Ref ref) => KeptRegionsStore(ref.watch(userDatabaseProvider));

// keepAlive: a store over the app-wide database.
@Riverpod(keepAlive: true)
RegionCatalogCopy regionCatalogCopy(Ref ref) => RegionCatalogCopy(ref.watch(cacheDatabaseProvider));

/// The packs' files; a stand-in that keeps none on the web.
// keepAlive: one folder for the run.
@Riverpod(keepAlive: true)
RegionPackFiles regionPackFiles(Ref ref) => RegionPackFiles.platformFiles();

/// The country of the device's region settings (`FR` for fr_FR), a hint
/// of where the user lives before any position is known; replaced in tests.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
String? deviceCountry(Ref ref) => PlatformDispatcher.instance.locale.countryCode;

/// The regions of the manifest: the copy of the last one read at once,
/// the fresh one once read; null against an API without regions (the sync
/// by box then runs, as before).
// keepAlive: the sync, the map and the profile read it for the whole run.
@Riverpod(keepAlive: true, retry: noRetry)
class RegionCatalogController extends _$RegionCatalogController {
  @override
  Future<RegionCatalog?> build() async {
    final copy = await ref.watch(regionCatalogCopyProvider).load();
    return copy ?? await _fetch();
  }

  /// Reads the manifest online and keeps it. A network failure keeps what
  /// was there, and surfaces.
  Future<RegionCatalog?> refresh() async {
    final fresh = await _fetch();
    if (ref.mounted) state = AsyncData(fresh);
    return fresh;
  }

  Future<RegionCatalog?> _fetch() async {
    try {
      final regions = await ref.read(graphQLClientProvider).execute(regionsOperation);
      final catalog = RegionCatalog(regions);
      await ref.read(regionCatalogCopyProvider).save(catalog);
      return catalog;
    } on GraphQLResponseException catch (e) {
      if (e.errors.any((error) => error.unknownField)) {
        _log.info('the API has no regions yet: the sync by box goes on');
        return null;
      }
      rethrow;
    }
  }
}

/// The regions the user keeps; null until a first choice.
// keepAlive: the sync and the profile read it for the whole run.
@Riverpod(keepAlive: true)
class KeptRegionsController extends _$KeptRegionsController {
  @override
  Future<Set<String>?> build() => ref.watch(keptRegionsStoreProvider).load();

  /// Keeps [chosen] from now on, and syncs: what is added downloads, what
  /// is no longer kept leaves the device.
  Future<void> choose(Set<String> chosen, {bool sync = true}) async {
    // The few French places outside every commune (`FR`) go with any
    // French region kept, and leave with the last one.
    final regions = {...chosen};
    regions.any((c) => c.startsWith('FR-')) ? regions.add('FR') : regions.remove('FR');
    state = AsyncData(Set.unmodifiable(regions));
    await ref.read(keptRegionsStoreProvider).save(regions);
    if (sync && ref.mounted) unawaited(ref.read(syncControllerProvider.notifier).sync());
  }

  Future<void> add(Iterable<String> codes) async {
    final now = {...?await future.catchError((Object _) => null), ...codes};
    if (!ref.mounted) return;
    await choose(now);
  }

  Future<void> remove(Iterable<String> codes) async {
    final now = {...?await future.catchError((Object _) => null)}..removeAll(codes);
    if (!ref.mounted) return;
    await choose(now);
  }
}

/// [KeptRegions] through [KeptRegionsController], so a first choice the
/// sync makes shows on the screens at once.
final class _KeptThroughController implements KeptRegions {
  new(this._ref);

  final Ref _ref;

  @override
  Future<Set<String>?> load() => _ref.read(keptRegionsControllerProvider.future);

  @override
  Future<void> save(Set<String> regions) =>
      _ref.read(keptRegionsControllerProvider.notifier).choose(regions, sync: false);
}

/// Syncs one region, its pack then its feed.
// keepAlive: a stateless service, wired once.
@Riverpod(keepAlive: true)
RegionSyncService regionSyncService(Ref ref) {
  final config = ref.watch(appConfigProvider);
  return RegionSyncService(
    changes: GraphQLRegionChangesSource(ref.watch(graphQLClientProvider)),
    store: ref.watch(regionStoreProvider),
    packs: ref.watch(regionPackFilesProvider),
    downloader: PackDownloader(
      client: ref.watch(httpClientProvider),
      userAgent: kIsWeb ? null : ref.watch(userAgentProvider),
    ),
    packUrl: (url) => placesPackUrl(config, url),
  );
}

/// The sync of every region kept, or of France by box against an API
/// without regions.
// keepAlive: a stateless service, wired once.
@Riverpod(keepAlive: true)
PlacesSync placesSync(Ref ref) => PlacesSync(
  catalog: () => ref.read(regionCatalogControllerProvider.notifier).refresh(),
  kept: _KeptThroughController(ref),
  regions: () => ref.read(regionSyncServiceProvider),
  store: () => ref.read(regionStoreProvider),
  legacy: ref.watch(syncServiceProvider),
  here: (catalog) => regionHere(ref, catalog),
);

/// The region where the user is, for a first choice: from the last
/// position the map kept (coarse, on the device only), else the country of
/// the device's settings; null when neither is a region of [catalog].
Future<String?> regionHere(Ref ref, RegionCatalog catalog) async {
  final position = await ref.read(lastPositionStoreProvider).load();
  if (position != null) {
    final outlines = await ref.read(packOutlinesProvider.future);
    final at = catalog.regionAt(position, outlines);
    if (at != null) return at;
  }
  final country = ref.read(deviceCountryProvider)?.toUpperCase();
  return country == null ? null : catalog.byCode(country)?.code;
}

/// The state of each region held, and the places of each.
@riverpod
Stream<Map<String, SyncState>> regionStates(Ref ref) =>
    ref.watch(regionStoreProvider).watchStates();

@riverpod
Stream<Map<String, int>> regionPlaceCounts(Ref ref) => ref.watch(regionStoreProvider).watchCounts();

/// Where the sync of everything kept stands, as one state: complete when
/// every region kept completed once (at the oldest of their dates), running
/// when one runs. A device that synced by box before regions keeps that
/// date until its regions have all synced.
SyncState overallSyncState({
  required Set<String>? kept,
  required RegionCatalog? catalog,
  required Map<String, SyncState> states,
}) {
  final legacy = states[DriftRegionStore.legacyRegion] ?? SyncState.none;
  if (kept == null || catalog == null) return legacy;
  final codes = [
    for (final r in catalog.regions)
      if (kept.contains(r.code)) r.code,
  ];
  if (codes.isEmpty) return legacy;
  final each = [for (final c in codes) states[c] ?? SyncState.none];
  final running = each.any((s) => s.running) || legacy.running;
  final dates = each.map((s) => s.completedAt).toList();
  final complete = dates.every((d) => d != null);
  final completedAt = complete
      ? dates.nonNulls.reduce((a, b) => a.isBefore(b) ? a : b)
      : legacy.completedAt;
  return SyncState(cursor: complete ? 'regions' : null, running: running, completedAt: completedAt);
}
