import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/domain/packs.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/data/region_store.dart';
import 'package:lunaway/features/regions/data/region_sync_service.dart';
import 'package:lunaway/features/regions/domain/regions.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';

RegionInfo _region(String code, String country) =>
    RegionInfo(code: code, country: country, name: code, nameFr: code);

final _catalog = RegionCatalog([
  _region('FR-BRE', 'FR'),
  _region('FR-NOR', 'FR'),
  _region('FR-CVL', 'FR'),
  _region('FR-ARA', 'FR'),
  _region('FR', 'FR'),
  _region('ES', 'ES'),
  _region('DE', 'DE'),
]);

const _rennes = LatLng(48.11, -1.68);
const _lyon = LatLng(45.76, 4.84);

/// A guidance the test starts and stops, its vehicle at the point it drives at.
final class _Guidance extends GuidanceController {
  @override
  GuidanceSession? build() => null;

  void drive(LatLng at) {
    final plan = routeFixture('limoges_drive');
    state = GuidanceSession(
      target: const RouteTarget(destination: LatLng(45.8, 1.26)),
      plan: plan,
      routeIndex: plan.routes.first.index,
      phase: GuidancePhase.navigating,
      voiceMode: VoiceMode.muted,
      voice: VoiceReadiness.ready,
      lastFix: Fix(position: at, accuracyM: 5, at: DateTime.utc(2026, 10, 8), speedMps: 20),
    );
  }

  @override
  void stop() => state = null;
}

/// A sync that does nothing: the choice alone is under test.
final class _NoSync extends SyncController {
  @override
  SyncStatus build() => const SyncIdle();

  @override
  Future<void> sync({bool fromScratch = false, bool asked = false}) async {}
}

void main() {
  late UserDatabase user;
  late CacheDatabase cache;

  ProviderContainer make({String? country = 'FR', List<Override> more = const []}) {
    user = UserDatabase(memoryDatabase());
    cache = CacheDatabase(memoryDatabase());
    return ProviderContainer.test(
      overrides: [
        userDatabaseProvider.overrideWithValue(user),
        cacheDatabaseProvider.overrideWithValue(cache),
        keepsPlacesProvider.overrideWithValue(true),
        regionCatalogControllerProvider.overrideWith(() => FixedRegionCatalog(_catalog)),
        packOutlinesProvider.overrideWith(
          (ref) async =>
              PackOutlines.parse(File('assets/map/offline/regions.json').readAsStringSync()),
        ),
        syncControllerProvider.overrideWith(_NoSync.new),
        guidanceControllerProvider.overrideWith(_Guidance.new),
        deviceCountryProvider.overrideWithValue(country),
        ...more,
      ],
    );
  }

  Future<RegionHere?> here(ProviderContainer c) =>
      c.read(FutureProvider((ref) => regionHere(ref, _catalog)).future);

  group('the region of the first choice', () {
    test("is the position's, said by a position", () async {
      final c = make();
      c.read(userLocationProvider.notifier).update(_lyon);
      expect(await here(c), (code: 'FR-ARA', located: true));
    });

    test('is the position kept by an earlier run, when this one has none', () async {
      final c = make();
      await DriftLastPositionStore(cache).save(_rennes);
      expect(await here(c), (code: 'FR-BRE', located: true));
    });

    test("is the view's once the user brought the map to a region", () async {
      final c = make(country: 'ES');
      c
          .read(viewportProvider.notifier)
          .update(
            const MapViewport(
              bounds: GeoBounds(south: 47.9, west: -2, north: 48.3, east: -1.4),
              center: _rennes,
              zoom: 9,
            ),
          );
      expect(await here(c), (code: 'FR-BRE', located: false));
    });

    test("is the phone's country when the server keeps it whole", () async {
      final c = make(country: 'es');
      c.read(viewportProvider.notifier).update(initialViewport);
      expect(await here(c), (code: 'ES', located: false));
    });

    test("is the region at the centre of France's first view, never all of France", () async {
      final c = make();
      c.read(viewportProvider.notifier).update(initialViewport);
      final guess = await here(c);
      expect(guess, (code: 'FR-CVL', located: false));
      expect(_catalog.firstChoice(guess?.code), {'FR-CVL'});
    });
  });

  group('the region offered where the user goes', () {
    Future<void> keep(Set<String> codes, {bool guessed = false}) async {
      final store = KeptRegionsStore(user);
      await store.save(codes);
      await store.saveGuessed(guessed: guessed);
    }

    test('waits while the guidance runs, and is offered once it stops', () async {
      final c = make()..listen(regionOfferProvider, (_, _) {});
      await keep({'FR-NOR', 'FR'});
      final guidance = c.read(guidanceControllerProvider.notifier) as _Guidance..drive(_lyon);
      c.read(userLocationProvider.notifier).update(_rennes);
      await pumpEventQueue();
      expect(c.read(regionOfferProvider), isNull, reason: 'nothing over the guidance');
      expect(await KeptRegionsStore(user).loadOffered(), isEmpty);
      guidance.stop();
      await pumpEventQueue();
      expect(c.read(regionOfferProvider)?.code, 'FR-ARA', reason: 'where the guidance ended');
    });

    test('is never a region already kept', () async {
      final c = make()..listen(regionOfferProvider, (_, _) {});
      await keep({'FR-BRE', 'FR'});
      await c.read(regionOfferProvider.notifier).consider(_rennes);
      expect(c.read(regionOfferProvider), isNull);
    });
  });
}
