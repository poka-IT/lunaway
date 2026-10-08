import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/platform/network_state.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/data/region_operations.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/data/region_store.dart';
import 'package:lunaway/features/regions/data/region_sync_service.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

RegionPack _pack(int bytes, int places) => RegionPack(
  url: '/packs/places/X-1-0123456789ab.sqlite.gz',
  format: RegionPack.supportedFormat,
  bytes: bytes,
  rawBytes: bytes * 8,
  sha256: 'a' * 64,
  version: '1',
  cursor: 'c',
  places: places,
  bounds: const GeoBounds(south: 0, west: 0, north: 1, east: 1),
  generatedAt: DateTime.utc(2026, 10, 8),
);

final _catalog = RegionCatalog([
  RegionInfo(
    code: 'FR-BRE',
    country: 'FR',
    name: 'Brittany',
    nameFr: 'Bretagne',
    pack: _pack(1814145, 6528),
  ),
  RegionInfo(
    code: 'FR-NOR',
    country: 'FR',
    name: 'Normandy',
    nameFr: 'Normandie',
    pack: _pack(1179746, 4283),
  ),
  RegionInfo(
    code: 'FR-CVL',
    country: 'FR',
    name: 'Centre-Loire Valley',
    nameFr: 'Centre-Val de Loire',
    pack: _pack(985138, 3570),
  ),
  const RegionInfo(code: 'FR', country: 'FR', name: 'France', nameFr: 'France'),
  RegionInfo(
    code: 'ES',
    country: 'ES',
    name: 'Spain',
    nameFr: 'Espagne',
    pack: _pack(3526038, 19214),
  ),
]);

const _rennes = LatLng(48.11, -1.68);

/// The map at rest over Rennes, at the zoom of a town.
FakeMap _overRennes() => FakeMap()
  ..viewport = const MapViewport(
    bounds: GeoBounds(south: 47.95, west: -1.95, north: 48.27, east: -1.41),
    center: _rennes,
    zoom: 11,
  );

/// A feed with nothing new, so a sync the screens start ends at once.
final class _Quiet implements RegionChangesSource {
  final List<String> asked = [];

  @override
  Future<RegionChangeSet> changes({
    required String region,
    required int first,
    String? since,
  }) async {
    asked.add(region);
    return RegionChangeSet(
      places: const [],
      deleted: const [],
      left: const [],
      cursor: since ?? '0',
      hasMore: false,
    );
  }
}

/// A feed the network does not reach while [offline].
final class _Flaky extends _Quiet {
  bool offline = true;

  @override
  Future<RegionChangeSet> changes({
    required String region,
    required int first,
    String? since,
  }) async {
    if (offline) throw GraphQLNetworkException('offline', null);
    return await super.changes(region: region, first: first, since: since);
  }
}

final class _NoPacks implements RegionPackFiles {
  const new();

  @override
  bool get supported => false;

  @override
  Future<String> fetch(
    RegionPack pack,
    Uri url, {
    required PackDownloader downloader,
    void Function(int received)? onProgress,
  }) => throw UnsupportedError('none');

  @override
  Future<void> release(String path) async {}

  @override
  Future<int> usedBytes() async => 0;
}

List<Override> _quietSync(_Quiet feed) => [
  regionSyncServiceProvider.overrideWith(
    (ref) => RegionSyncService(
      changes: feed,
      store: ref.watch(regionStoreProvider),
      packs: const _NoPacks(),
      downloader: PackDownloader(
        client: MockClient((_) async => http.Response('', 404)),
        userAgent: null,
      ),
      packUrl: (_) => null,
    ),
  ),
];

Future<void> _keep(
  TestApp app,
  WidgetTester tester,
  Set<String> codes, {
  bool guessed = false,
}) async {
  final store = KeptRegionsStore(app.user);
  await store.save(codes);
  await store.saveGuessed(guessed: guessed);
  app.container(tester).invalidate(keptRegionsControllerProvider);
  await settleShort(tester);
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('the list offline', () {
    testWidgets('says at once there is no connection, and leads to the offline maps', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        reachable: false,
        regions: _catalog,
        map: _overRennes(),
        overrides: _quietSync(_Quiet()),
        settle: false,
      );
      // Under two seconds from the start of the app.
      await settleShort(tester, const Duration(milliseconds: 1500));
      expect(
        find.text('Pas de connexion').hitTestable(),
        findsOneWidget,
        reason: 'in sight above the dock, the sheet at rest',
      );
      expect(find.text('Rien de cette zone sur cet appareil.'), findsOneWidget);
      expect(app.container(tester).read(missedRegionsProvider), {'FR-BRE'});

      // The action too, above the dock with the sheet at rest.
      final action = find.widgetWithText(OutlinedButton, 'Cartes hors ligne').hitTestable();
      expect(action, findsOneWidget);
      await tester.tap(action);
      await settleShort(tester);
      expect(find.text('Lieux'), findsOneWidget, reason: 'the offline maps, places first');
    });

    testWidgets('in a region the device holds, an empty list is the filters, not the network', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        reachable: false,
        regions: _catalog,
        map: _overRennes(),
        overrides: [
          ..._quietSync(_Quiet()),
          regionPlaceCountsProvider.overrideWith((ref) => Stream.value({'FR-BRE': 6528})),
        ],
      );
      await _keep(app, tester, {'FR-BRE', 'FR'});
      expect(find.text('Pas de connexion'), findsNothing);
    });

    testWidgets('once the network is back, it offers the region it missed', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(
        tester,
        // The list beside the map, whole.
        size: desktop,
        places: const [],
        reachable: false,
        online: online,
        tilesFollowReachability: true,
        regions: _catalog,
        map: _overRennes(),
        overrides: _quietSync(_Quiet()),
      );
      await settleShort(tester);
      expect(find.text('Pas de connexion'), findsOneWidget);
      expect(find.text('Télécharger cette région'), findsNothing, reason: 'not while offline');

      app.container(tester).read(basemapReachabilityProvider.notifier).assume(reachable: true);
      await settleShort(tester, const Duration(seconds: 2));
      expect(find.text('Pas de connexion'), findsNothing);
      expect(find.text("Bretagne n'est pas sur cet appareil"), findsOneWidget);
      final download = find.text('Télécharger cette région');
      await tester.ensureVisible(download);
      await tester.tap(download);
      await settleShort(tester);
      expect(await KeptRegionsStore(app.user).load(), contains('FR-BRE'));
      expect(find.text("Bretagne n'est pas sur cet appareil"), findsNothing);
    });
  });

  group('the region where the user goes', () {
    testWidgets('is offered once, over the map, and downloads on a tap', (tester) async {
      final feed = _Quiet();
      final app = await pumpLunaway(tester, regions: _catalog, overrides: _quietSync(feed));
      await _keep(app, tester, {'FR-NOR', 'FR'});
      app.container(tester).read(userLocationProvider.notifier).update(_rennes);
      await settleShort(tester);
      expect(find.text('Bretagne : garder ses lieux hors connexion ?'), findsOneWidget);
      expect(
        find.text(t.regions.packInfo(n: 6528, count: t.number(6528), size: t.fileSize(1814145))),
        findsOneWidget,
      );
      await tester.tap(find.text('Télécharger cette région'));
      await settleShort(tester);
      expect(await KeptRegionsStore(app.user).load(), {'FR-NOR', 'FR-BRE', 'FR'});
      expect(feed.asked, contains('FR-BRE'));
      expect(find.text('Bretagne : garder ses lieux hors connexion ?'), findsNothing);
    });

    testWidgets('closed, it does not come back for that region', (tester) async {
      final app = await pumpLunaway(tester, regions: _catalog, overrides: _quietSync(_Quiet()));
      await _keep(app, tester, {'FR-NOR', 'FR'});
      final container = app.container(tester);
      container.read(userLocationProvider.notifier).update(_rennes);
      await settleShort(tester);
      await tester.tap(find.byTooltip('Plus tard'));
      await settleShort(tester);
      expect(find.text('Bretagne : garder ses lieux hors connexion ?'), findsNothing);
      container.read(userLocationProvider.notifier).update(const LatLng(47.66, -2.76));
      await settleShort(tester);
      expect(find.text('Bretagne : garder ses lieux hors connexion ?'), findsNothing);
      expect(await KeptRegionsStore(app.user).loadOffered(), {'FR-BRE'});
      expect(await KeptRegionsStore(app.user).load(), {'FR-NOR', 'FR'});
    });

    testWidgets('replaces a first choice the app guessed without a position', (tester) async {
      final feed = _Quiet();
      final app = await pumpLunaway(tester, regions: _catalog, overrides: _quietSync(feed));
      await _keep(app, tester, {'FR-CVL', 'FR'}, guessed: true);
      app.container(tester).read(userLocationProvider.notifier).update(_rennes);
      await settleShort(tester);
      expect(await KeptRegionsStore(app.user).load(), {'FR-BRE', 'FR'});
      expect(await KeptRegionsStore(app.user).loadGuessed(), isFalse);
      expect(find.text('Bretagne : garder ses lieux hors connexion ?'), findsNothing);
      expect(feed.asked, contains('FR-BRE'));
    });
  });

  group('the updates of the regions downloaded', () {
    Future<TestApp> pumpKept(WidgetTester tester, _Quiet feed, FakeNetworkMonitor network) async {
      final app = await pumpLunaway(
        tester,
        regions: _catalog,
        network: network,
        overrides: _quietSync(feed),
      );
      await _keep(app, tester, {'FR-BRE', 'FR'});
      final store = app.container(tester).read(regionStoreProvider);
      for (final code in ['FR-BRE', 'FR']) {
        await store.beginFullSync(code);
        await store.completeRun(code, testNow);
      }
      await settleShort(tester);
      feed.asked.clear();
      return app;
    }

    testWidgets('wait for Wi-Fi on mobile data, unless asked for or allowed', (tester) async {
      final feed = _Quiet();
      final network = FakeNetworkMonitor(const NetworkState(connected: true, metered: true));
      final app = await pumpKept(tester, feed, network);
      final sync = app.container(tester).read(syncControllerProvider.notifier);
      unawaited(sync.sync());
      await settleShort(tester);
      expect(feed.asked, isEmpty, reason: 'every region kept was downloaded: they wait');

      unawaited(sync.sync(asked: true));
      await settleShort(tester);
      expect(feed.asked, contains('FR-BRE'), reason: 'the user asked');

      feed.asked.clear();
      await app.container(tester).read(regionUpdatesOnMobileProvider.notifier).set(allowed: true);
      unawaited(sync.sync());
      await settleShort(tester);
      expect(feed.asked, contains('FR-BRE'), reason: 'mobile data allowed');
    });

    testWidgets('go on Wi-Fi', (tester) async {
      final feed = _Quiet();
      final network = FakeNetworkMonitor(const NetworkState(connected: true, metered: false));
      final app = await pumpKept(tester, feed, network);
      unawaited(app.container(tester).read(syncControllerProvider.notifier).sync());
      await settleShort(tester);
      expect(feed.asked, contains('FR-BRE'));
    });

    testWidgets('a sync the network failed goes again as soon as it is back', (tester) async {
      final feed = _Flaky();
      final app = await pumpLunaway(
        tester,
        regions: _catalog,
        reachable: false,
        overrides: _quietSync(feed),
      );
      await _keep(app, tester, {'FR-BRE', 'FR'});
      final container = app.container(tester);
      unawaited(container.read(syncControllerProvider.notifier).sync());
      await settleShort(tester);
      expect(container.read(syncControllerProvider), isA<SyncFailed>());
      feed.offline = false;
      container.read(basemapReachabilityProvider.notifier).assume(reachable: true);
      await settleShort(tester);
      expect(feed.asked, contains('FR-BRE'));
      expect(container.read(syncControllerProvider), isA<SyncDone>());
    });

    testWidgets('a region added downloads on mobile data', (tester) async {
      final feed = _Quiet();
      final network = FakeNetworkMonitor(const NetworkState(connected: true, metered: true));
      final app = await pumpKept(tester, feed, network);
      await app.container(tester).read(keptRegionsControllerProvider.notifier).add({'ES'});
      await settleShort(tester);
      expect(feed.asked, ['ES'], reason: 'a new download goes over any network; Bretagne waits');
    });
  });
}
