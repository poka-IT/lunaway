import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
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
  /// is no longer kept leaves the device. [guessed] marks the app's own
  /// first choice made without a position; any other choice ends it.
  Future<void> choose(Set<String> chosen, {bool sync = true, bool guessed = false}) async {
    // The few French places outside every commune (`FR`) go with any
    // French region kept, and leave with the last one.
    final regions = {...chosen};
    regions.any((c) => c.startsWith('FR-')) ? regions.add('FR') : regions.remove('FR');
    state = AsyncData(Set.unmodifiable(regions));
    final store = ref.read(keptRegionsStoreProvider);
    await store.save(regions);
    await store.saveGuessed(guessed: guessed);
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
  Future<void> save(Set<String> regions, {bool guessed = false}) => _ref
      .read(keptRegionsControllerProvider.notifier)
      .choose(regions, sync: false, guessed: guessed);
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
  here: (catalog, {required guess}) => regionHere(ref, catalog, guess: guess),
);

/// The region where the user is, for a first choice: from a position
/// (this run's, else the coarse one the map kept, on the device only), else
/// from the map's view when the user brought it to a region's scale, else
/// the country of the phone's settings when the server keeps it whole (a
/// Spanish phone: Spain), else the region at the centre of the view (the
/// map's first view of France: the region in its middle). Without
/// [guess], the position's region only. Null when none is a region of
/// [catalog].
Future<RegionHere?> regionHere(Ref ref, RegionCatalog catalog, {bool guess = true}) async {
  final position =
      ref.read(userLocationProvider) ?? await ref.read(lastPositionStoreProvider).load();
  if (position == null && !guess) return null;
  final outlines = await ref.read(packOutlinesProvider.future);
  if (position != null) {
    final at = catalog.regionAt(position, outlines);
    if (at != null) return (code: at, located: true);
  }
  if (!guess) return null;
  final view = ref.read(viewportProvider);
  String? inView() => view == null ? null : catalog.regionAt(view.center, outlines);
  if (view != null && view.zoom >= regionalZoom) {
    if (inView() case final code?) return (code: code, located: false);
  }
  final country = ref.read(deviceCountryProvider)?.toUpperCase();
  final home = country == null ? null : catalog.byCode(country);
  if (home != null && home.country != 'FR') return (code: home.code, located: false);
  final centre = inView() ?? catalog.regionAt(initialMapCenter, outlines);
  return centre == null ? null : (code: centre, located: false);
}

/// Whether the regions kept may update over mobile data; off until the
/// user allows it.
// keepAlive: the sync reads it each time it runs, the offline maps show it.
@Riverpod(keepAlive: true)
class RegionUpdatesOnMobile extends _$RegionUpdatesOnMobile {
  @override
  Future<bool> build() => ref.watch(keptRegionsStoreProvider).loadUpdatesOnMobile();

  Future<void> set({required bool allowed}) async {
    state = AsyncData(allowed);
    await ref.read(keptRegionsStoreProvider).saveUpdatesOnMobile(allowed: allowed);
    // Allowed on a metered network: what waited for Wi-Fi goes now.
    if (allowed && ref.mounted) unawaited(ref.read(syncControllerProvider.notifier).syncIfStale());
  }
}

/// A region to offer for offline use: the one the user's position entered,
/// neither kept nor offered before (each is offered once, for good), and
/// never while the guidance runs: the region it ends in is offered once it
/// stops. A first choice the app guessed without a position gives way, at
/// the first position, to the region there, without asking: that was the
/// download owed to the user.
// keepAlive: it follows the user's position for the whole run.
@Riverpod(keepAlive: true)
class RegionOffer extends _$RegionOffer {
  LatLng? _guidedTo;

  @override
  RegionInfo? build() {
    if (!ref.watch(keepsPlacesProvider)) return null;
    ref
      ..listen(userLocationProvider, (_, position) {
        if (position != null && ref.read(guidanceControllerProvider) == null) {
          unawaited(consider(position));
        }
      })
      ..listen(guidanceControllerProvider, (before, now) {
        final fix = now?.lastFix?.position;
        if (fix != null) _guidedTo = fix;
        final end = _guidedTo;
        if (before != null && now == null && end != null) {
          _guidedTo = null;
          unawaited(consider(end));
        }
      });
    return null;
  }

  /// Weighs the region at [position]: replaces a guessed first choice, or
  /// offers it.
  @visibleForTesting
  Future<void> consider(LatLng position) async {
    try {
      final catalog = await ref.read(regionCatalogControllerProvider.future);
      final outlines = await ref.read(packOutlinesProvider.future);
      final kept = await ref.read(keptRegionsControllerProvider.future);
      if (!ref.mounted || catalog == null || kept == null) return;
      final code = catalog.regionAt(position, outlines);
      if (code == null || code == 'FR' || kept.contains(code)) return;
      final store = ref.read(keptRegionsStoreProvider);
      if (await store.loadGuessed()) {
        _log.info('the first position replaces the guessed region');
        await store.addOffered(code);
        if (ref.mounted) await ref.read(keptRegionsControllerProvider.notifier).choose({code});
        return;
      }
      if ((await store.loadOffered()).contains(code)) return;
      if (!ref.mounted || ref.read(guidanceControllerProvider) != null) return;
      await store.addOffered(code);
      if (ref.mounted) state = catalog.byCode(code);
    } on Object catch (e) {
      // No manifest or outlines yet: the next position asks again.
      _log.fine('no region to offer at the position: $e');
    }
  }

  /// Keeps the region offered: its places download.
  Future<void> accept() async {
    final region = state;
    if (region == null) return;
    state = null;
    await ref.read(keptRegionsControllerProvider.notifier).add({region.code});
  }

  void dismiss() => state = null;
}

/// The regions the list found missing while offline in this run: once the
/// network is back, the list offers to download the one in view.
// keepAlive: remembered from the moment offline to the return of the network.
@Riverpod(keepAlive: true)
class MissedRegions extends _$MissedRegions {
  @override
  Set<String> build() => const {};

  void add(String code) {
    if (!state.contains(code)) state = {...state, code};
  }

  void remove(String code) {
    if (state.contains(code)) state = {...state}..remove(code);
  }
}

/// The region at the centre of the map's view, and whether the device
/// holds its places (kept, and some of them on the device).
typedef ViewRegion = ({String code, bool held});

/// [ViewRegion] of the map as it stands; null before the manifest and the
/// outlines are read, or at sea.
@riverpod
ViewRegion? viewRegion(Ref ref) {
  final catalog = ref.watch(regionCatalogControllerProvider).value;
  final outlines = ref.watch(packOutlinesProvider).value;
  final view = ref.watch(viewportProvider) ?? initialViewport;
  if (catalog == null || outlines == null) return null;
  final code = catalog.regionAt(view.center, outlines);
  if (code == null) return null;
  final kept = ref.watch(keptRegionsControllerProvider).value ?? const <String>{};
  final count = ref.watch(regionPlaceCountsProvider).value?[code] ?? 0;
  return (code: code, held: kept.contains(code) && count > 0);
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
