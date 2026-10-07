import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/domain/packs.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/data/region_operations.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/data/region_store.dart';
import 'package:lunaway/features/regions/data/region_sync_service.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

import '../helpers/navigation.dart';
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
  generatedAt: DateTime.utc(2026, 10, 6),
);

final _catalog = RegionCatalog([
  RegionInfo(
    code: 'FR-BRE',
    country: 'FR',
    name: 'Brittany',
    nameFr: 'Bretagne',
    pack: _pack(400 * 1024, 2854),
  ),
  RegionInfo(
    code: 'FR-NOR',
    country: 'FR',
    name: 'Normandy',
    nameFr: 'Normandie',
    pack: _pack(300 * 1024, 1900),
  ),
  const RegionInfo(code: 'FR', country: 'FR', name: 'France', nameFr: 'France'),
  RegionInfo(
    code: 'ES',
    country: 'ES',
    name: 'Spain',
    nameFr: 'Espagne',
    pack: _pack(1200 * 1024, 7800),
  ),
  RegionInfo(
    code: 'IT',
    country: 'IT',
    name: 'Italy',
    nameFr: 'Italie',
    pack: _pack(900 * 1024, 5100),
  ),
]);

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

/// A sync that stays running on the region [region], for the first-sync
/// banner.
final class _Running extends SyncController {
  new(this.region);

  final String region;

  @override
  SyncStatus build() => SyncRunning(120, region: region, packBytes: 1000, packSize: 4000);

  @override
  void start() {}
}

/// "4 754 lieux, 700 Ko", as the French screens write it.
String _info(int places, int bytes) =>
    t.regions.packInfo(n: places, count: t.number(places), size: t.fileSize(bytes));

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  List<Override> quietSync(_Quiet feed) => [
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

  testWidgets('the profile lists the regions kept; one removed comes back with "Annuler"', (
    tester,
  ) async {
    final feed = _Quiet();
    final app = await pumpLunaway(
      tester,
      regions: _catalog,
      overrides: [
        ...quietSync(feed),
        regionPlaceCountsProvider.overrideWith(
          (ref) => Stream.value({'FR-BRE': 2854, 'FR-NOR': 1900, 'ES': 7800}),
        ),
        regionStatesProvider.overrideWith(
          (ref) => Stream.value({
            for (final c in ['FR-BRE', 'FR-NOR', 'FR', 'ES'])
              c: SyncState(cursor: 'c', completedAt: testNow.subtract(const Duration(hours: 2))),
          }),
        ),
      ],
    );
    await KeptRegionsStore(app.user).save({'FR-BRE', 'FR-NOR', 'FR', 'ES'});
    app.container(tester).invalidate(keptRegionsControllerProvider);
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    await tester.scrollUntilVisible(find.text('Régions sur cet appareil'), 200);
    await settleShort(tester);

    expect(find.text('Toute la France'), findsOneWidget, reason: 'France kept whole: one line');
    expect(find.textContaining(_info(4754, 700 * 1024)), findsOneWidget);
    expect(find.text('Espagne'), findsOneWidget);
    expect(find.textContaining(_info(7800, 1200 * 1024)), findsOneWidget);

    await tester.tap(find.byTooltip('Retirer Espagne'));
    await settleShort(tester);
    final container = app.container(tester);
    expect(container.read(keptRegionsControllerProvider).value, isNot(contains('ES')));
    expect(find.text('Espagne : lieux retirés de cet appareil'), findsOneWidget);
    expect(await KeptRegionsStore(app.user).load(), isNot(contains('ES')));

    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(container.read(keptRegionsControllerProvider).value, contains('ES'));
    expect(feed.asked, contains('ES'), reason: 'the region put back syncs again');
  });

  testWidgets('the first download names its region; the picker adds a country', (tester) async {
    final feed = _Quiet();
    final app = await pumpLunaway(
      tester,
      places: const [],
      regions: _catalog,
      overrides: [
        ...quietSync(feed),
        syncControllerProvider.overrideWith(() => _Running('FR-BRE')),
      ],
    );
    await KeptRegionsStore(app.user).save({'FR-BRE', 'FR-NOR', 'FR'});
    app.container(tester).invalidate(keptRegionsControllerProvider);
    await settleShort(tester);
    expect(find.text('Téléchargement des lieux : Bretagne'), findsOneWidget);

    await tester.tap(find.text('Choisir les régions'));
    await settleShort(tester);
    expect(find.text('Quels lieux garder sur cet appareil ?'), findsOneWidget);
    expect(find.text('Toute la France'), findsOneWidget);
    expect(find.text(_info(4754, 700 * 1024)), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget, reason: 'nothing to download yet');

    await tester.tap(find.text('Italie'));
    await settleShort(tester);
    final download = 'Télécharger, ${t.fileSize(900 * 1024)}';
    expect(find.text(download), findsOneWidget);
    await tester.tap(find.text(download));
    await settleShort(tester);
    expect(await KeptRegionsStore(app.user).load(), {'FR-BRE', 'FR-NOR', 'FR', 'IT'});
  });

  testWidgets('on a small phone the choice of regions stays in reach above the list', (
    tester,
  ) async {
    final feed = _Quiet();
    await pumpLunaway(
      tester,
      size: const Size(360, 640),
      places: const [],
      viewPadding: const FakeViewPadding(top: 24, bottom: 24),
      regions: _catalog,
      overrides: [
        ...quietSync(feed),
        syncControllerProvider.overrideWith(() => _Running('FR-BRE')),
      ],
    );
    expect(find.text('Choisir les régions').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Choisir les régions'));
    await settleShort(tester);
    expect(find.text('Quels lieux garder sur cet appareil ?'), findsOneWidget);
  });

  testWidgets('"Trouver ma région" asks for the position once and ticks the region there', (
    tester,
  ) async {
    final feed = _Quiet();
    final app = await pumpLunaway(
      tester,
      regions: _catalog,
      overrides: [
        ...quietSync(feed),
        // The outlines read at once: the asset is decoded in an isolate.
        packOutlinesProvider.overrideWith(
          (ref) async =>
              PackOutlines.parse(File('assets/map/offline/regions.json').readAsStringSync()),
        ),
        // Somewhere in Andalusia: Spain's region.
        locationFeedProvider.overrideWithValue(
          FakeLocationFeed(position: const LatLng(37.39, -5.99)),
        ),
      ],
    );
    await KeptRegionsStore(app.user).save({'FR-BRE', 'FR-NOR', 'FR'});
    app.container(tester).invalidate(keptRegionsControllerProvider);
    await settleShort(tester);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(showRegionPicker(context));
    await settleShort(tester);
    await tester.tap(find.text('Trouver ma région'));
    await settleShort(tester);
    expect(find.text('Près de vous : Espagne'), findsOneWidget);
    expect(find.text('Télécharger, ${t.fileSize(1200 * 1024)}'), findsOneWidget);
  });

  testWidgets('"Trouver ma région" that fails stops turning and says so', (tester) async {
    final feed = _Quiet();
    final app = await pumpLunaway(
      tester,
      regions: _catalog,
      overrides: [...quietSync(feed), locationFeedProvider.overrideWithValue(const _NoFix())],
    );
    await KeptRegionsStore(app.user).save({'FR-BRE', 'FR-NOR', 'FR'});
    app.container(tester).invalidate(keptRegionsControllerProvider);
    await settleShort(tester);
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(showRegionPicker(context));
    await settleShort(tester);
    await tester.tap(find.text('Trouver ma région'));
    await settleShort(tester);
    expect(find.text('Pas encore de région Lunaway autour de vous'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('the defaults keep France, and the country where the user is', () {
    expect(_catalog.defaults(), {'FR-BRE', 'FR-NOR', 'FR'});
    expect(_catalog.defaults(here: 'ES'), {'FR-BRE', 'FR-NOR', 'FR', 'ES'});
    expect(_catalog.defaults(homeCountry: 'it'), {'FR-BRE', 'FR-NOR', 'FR', 'IT'});
    expect(_catalog.defaults(here: 'FR-BRE'), {'FR-BRE', 'FR-NOR', 'FR'});
    expect(_catalog.defaults(homeCountry: 'DE'), {'FR-BRE', 'FR-NOR', 'FR'}, reason: 'not offered');
  });

  test('a region the server sent without its names is named by its code', () {
    expect(regionFromJson({'code': 'ES', 'country': 'ES'})!.nameIn('fr'), 'ES');
  });
}

/// A position lookup that fails, as geolocator's does when the location
/// service is off.
final class _NoFix implements LocationFeed {
  const new();

  @override
  Future<Fix?> current() async => throw StateError('location service off');

  @override
  Stream<Fix> guidance(BackgroundNotice notice) => const Stream.empty();
}
