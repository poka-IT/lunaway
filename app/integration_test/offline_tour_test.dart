import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// A first launch online, the region downloaded, then the network cut and
/// the app used as on the road: the map, the search of the device's towns
/// and places, a place's page, the filters, the favourites, a route asked
/// for; then a region the device does not hold, and the network's return.
///
/// The network is a local relay in front of the API and the basemap host
/// (`tool/offline/relay.py`), which the tour cuts and restores through its
/// control port, and asks for the screenshots: a simulator shares the
/// computer's network and has no airplane mode. Built as the app's target,
/// it runs on a simulator launched like the app (`xcrun simctl launch`),
/// the relay running:
///
///     fvm flutter build ios --simulator --debug -t integration_test/offline_tour_test.dart \
///       --dart-define=LUNAWAY_API_URL=http://127.0.0.1:18781 \
///       --dart-define=LUNAWAY_BASEMAP_URL=http://127.0.0.1:18782
///
/// The built app takes `NSAllowsLocalNetworking` in its Info.plist, for
/// MapLibre's requests to the relay. The link's speed is the relay's
/// (`/shape`), set before the launch.
///
/// Each step prints `TOUR <step> <ms> <ok|FAIL> <detail>`, milliseconds
/// from the start.
const _control = String.fromEnvironment('LUNAWAY_TOUR_CONTROL', defaultValue: '127.0.0.1:18790');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'apres-ios');

const _rennes = LatLng(48.1105, -1.6795);
const _annecy = LatLng(45.8992, 6.1294);

final _clock = Stopwatch();
final _failed = <String>[];

Future<void> _relay(String action) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('http://$_control/$action'));
    await (await request.close()).drain<void>();
  } finally {
    client.close();
  }
}

void _step(String step, {required bool ok, String detail = ''}) {
  if (!ok) _failed.add(step);
  final line = '$step ${_clock.elapsedMilliseconds} ${ok ? 'ok' : 'FAIL'} $detail';
  debugPrint('TOUR $line');
  // The host's log too: a simulator's console does not always reach it.
  unawaited(_relay('mark?what=${Uri.encodeQueryComponent(line)}'));
}

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits until [done], or [limit]; answers whether it came.
Future<bool> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester, const Duration(milliseconds: 1200));
  // The screenshot is taken by the host while the frames go on.
  final asked = _relay('shot?name=$_tag-$name');
  await _settle(tester, const Duration(milliseconds: 1500));
  await asked;
}

bool _shows(Finder finder) => finder.hitTestable().evaluate().isNotEmpty;

/// Taps [finder] where it shows; a step that finds nothing is reported,
/// and the tour goes on.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  final shown = finder.hitTestable();
  if (shown.evaluate().isEmpty) {
    _step('tap', ok: false, detail: finder.describeMatch(Plurality.zero));
    return;
  }
  await tester.tap(shown.first, warnIfMissed: false);
  await _settle(tester, const Duration(milliseconds: 800));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline tour', (tester) async {
    // The link's speed is the host's to set (`/shape` of the relay).
    await _relay('online');
    _clock.start();
    await app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = LocaleSettings.currentLocale.buildSync();
    // The tour's own listeners: a provider no widget watches would go.
    container
      ..listen(placeCountProvider, (_, _) {})
      ..listen(keptRegionsControllerProvider, (_, _) {})
      ..listen(syncControllerProvider, (_, _) {});

    // A first launch online: one region, the user's, and the time to it.
    final mapShown = await _until(tester, () => container.read(viewportProvider) != null);
    _step('map', ok: mapShown);
    final rows = await _until(
      tester,
      () => find.byType(PlaceTile).evaluate().isNotEmpty,
      limit: const Duration(seconds: 30),
    );
    _step('list-rows', ok: rows);
    final synced = await _until(
      tester,
      () => container.read(syncControllerProvider) is SyncDone,
      limit: const Duration(minutes: 3),
    );
    final kept = container.read(keptRegionsControllerProvider).value ?? const <String>{};
    final places = container.read(placeCountProvider).value ?? 0;
    _step(
      'first-download',
      ok: synced && kept.where((c) => c.startsWith('FR-')).length == 1,
      detail: '${kept.toList()..sort()} $places places',
    );
    await _shot(tester, 'premier-lancement');

    // The places of a town of the region kept, then the network cut.
    unawaited(container.read(mapControllerProvider)?.moveTo(_annecy, zoom: 12));
    await _settle(tester, const Duration(seconds: 3));
    await _relay('offline');
    final cutAt = _clock.elapsedMilliseconds;
    // A phone hears of it from its system at once. A simulator shares the
    // computer's network, which stays up: as on a network that carries
    // nothing, the map at rest asks the host again once its last answer is
    // 30 s old, and the user's next move shows it.
    bool cut() => container.read(basemapReachabilityProvider) == false;
    var how = 'system';
    var offline = await _until(tester, cut, limit: const Duration(seconds: 5));
    if (!offline) {
      how = 'map at rest after 30 s';
      await _settle(tester, const Duration(seconds: 26));
      unawaited(container.read(mapControllerProvider)?.moveTo(_annecy, zoom: 12.5));
      offline = await _until(tester, cut, limit: const Duration(seconds: 15));
    }
    _step('offline-seen', ok: offline, detail: '${_clock.elapsedMilliseconds - cutAt} ms, $how');
    await _settle(tester, const Duration(seconds: 2));
    _step('offline-list', ok: find.byType(PlaceTile).evaluate().isNotEmpty);
    await _shot(tester, 'carte-hors-ligne');

    // The search of the towns and places the device holds.
    await tester.enterText(find.byType(TextField).first, 'Annecy');
    await _settle(tester, const Duration(seconds: 2));
    final town = find.textContaining('74000');
    _step('search-town', ok: town.evaluate().isNotEmpty);
    _step('search-places', ok: find.byType(PlaceTile).evaluate().isNotEmpty);
    await _shot(tester, 'recherche-hors-ligne');
    if (town.evaluate().isNotEmpty) await _tap(tester, town);
    await _settle(tester, const Duration(seconds: 2));

    // A place's page, saved to the favourites.
    final row = find.byType(PlaceTile);
    if (row.evaluate().isNotEmpty) await _tap(tester, row);
    await _settle(tester, const Duration(seconds: 2));
    final save = find.text(t.place.save);
    _step('place-page', ok: save.evaluate().isNotEmpty);
    await _shot(tester, 'fiche-hors-ligne');
    if (save.evaluate().isNotEmpty) await _tap(tester, save);

    // A route asked for offline: the vehicle known, the start where the
    // simulator says the user is.
    await container.read(vehicleRepositoryProvider).save(Vehicle.typical(VehicleType.campervan));
    final directions = find.text(t.place.directions);
    if (directions.evaluate().isNotEmpty) await _tap(tester, directions);
    final noRoute = await _until(
      tester,
      () => _shows(find.text(t.navigation.states.offlineTitle)),
      limit: const Duration(seconds: 20),
    );
    _step('route-offline', ok: noRoute);
    await _shot(tester, 'itineraire-hors-ligne');
    container.read(routerProvider).pop();
    await _settle(tester, const Duration(seconds: 1));
    // The place closed: the dock comes back in place of its actions.
    container.read(mapFlowProvider.notifier).select(null);
    await _settle(tester, const Duration(seconds: 1));

    // The favourites.
    await _tap(tester, find.text(t.nav.favorites));
    _step('favourites', ok: find.byType(PlaceTile).evaluate().isNotEmpty);
    await _shot(tester, 'favoris-hors-ligne');
    await _tap(tester, find.text(t.nav.map));

    // The filters, on the device's places.
    await _tap(tester, find.text(t.map.filters));
    await _tap(tester, find.text(t.overnight.allowed));
    final apply = find.textContaining(RegExp(t.filters.show(n: 2, count: '#').split('#').first));
    _step('filters', ok: apply.evaluate().isNotEmpty);
    await _shot(tester, 'filtres-hors-ligne');
    if (apply.evaluate().isNotEmpty) await _tap(tester, apply);
    await _tap(tester, find.text(t.map.filters));
    await _tap(tester, find.text(t.filters.reset));
    if (apply.evaluate().isNotEmpty) await _tap(tester, apply);

    // A region the device does not hold: no connection, said at once.
    final movedAt = _clock.elapsedMilliseconds;
    unawaited(container.read(mapControllerProvider)?.moveTo(_rennes, zoom: 12));
    final said = await _until(
      tester,
      () => _shows(find.text(t.list.offlineTitle)),
      limit: const Duration(seconds: 10),
    );
    _step(
      'offline-not-here',
      ok: said && _clock.elapsedMilliseconds - movedAt < 2000,
      detail: '${_clock.elapsedMilliseconds - movedAt} ms',
    );
    await _shot(tester, 'liste-hors-ligne-region-absente');

    // The network back: the list offers the region it missed.
    await _relay('online');
    final backAt = _clock.elapsedMilliseconds;
    final offer = find.text(t.regions.downloadThis);
    final offered = await _until(
      tester,
      () => offer.evaluate().isNotEmpty,
      limit: const Duration(seconds: 40),
    );
    _step('offer-on-return', ok: offered, detail: '${_clock.elapsedMilliseconds - backAt} ms');
    await _shot(tester, 'retour-telecharger-region');
    if (offered) {
      await tester.ensureVisible(offer.first);
      await _tap(tester, offer);
      final downloaded = await _until(
        tester,
        () =>
            (container.read(keptRegionsControllerProvider).value?.contains('FR-BRE') ?? false) &&
            container.read(syncControllerProvider) is SyncDone,
        limit: const Duration(minutes: 2),
      );
      _step(
        'region-downloaded',
        ok: downloaded,
        detail: '${container.read(keptRegionsControllerProvider).value?.toList()}',
      );
      await _shot(tester, 'region-telechargee');
    }

    debugPrint('TOUR done ${jsonEncode(_failed)}');
    expect(_failed, isEmpty);
  });
}
