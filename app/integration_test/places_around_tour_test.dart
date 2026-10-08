import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

import 'fixtures/listened.dart';

/// The shops and services and the offline maps, against the real API, for
/// screenshots: the points on the map, a point's page, "around this place",
/// the search, a vending machine to add, and the offline maps (a small pack
/// downloaded, shown offline, then removed). Run through
/// `tool/screens/capture.py --test integration_test/places_around_tour_test.dart`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'tour');

/// Annecy: dense enough for every category.
const _town = LatLng(45.8992, 6.1294);

/// The pack the tour downloads: Andorra, 7 MB, quick on any network.
const _packId = 'ad';
const _packCentre = LatLng(42.507, 1.521);

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumping(WidgetTester tester, Future<void> work) async {
  var done = false;
  unawaited(work.whenComplete(() => done = true));
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<T> waitFor<T>(WidgetTester tester, Future<T> work) async {
  late T value;
  await pumping(tester, work.then((v) => value = v));
  return value;
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shops, services and offline maps tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLocale(AppLocaleUtils.parse(_locale));
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    await settings.setFilter(PlaceFilter.none);
    final t = AppLocaleUtils.parse(_locale).buildSync();
    final ready = DateTime.now().add(const Duration(minutes: 4));
    while ((container.read(syncStateProvider).value?.completedAt == null ||
            container.read(viewportProvider) == null) &&
        DateTime.now().isBefore(ready)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final map = container.read(mapControllerProvider)!;
    final layer = container.read(poiLayerProvider.notifier)..clear();
    // The first view fits the region once the style is up: a move sent
    // before it would be undone.
    await settle(tester, const Duration(seconds: 4));

    // Every point, quiet and small, at street zoom with no chip on.
    await pumping(tester, map.moveTo(const LatLng(45.8995, 6.1255), zoom: 16.2));
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'poi-quiet');

    // One category: where its points gather, then its pins, closed ones faded.
    layer.toggle(PoiCategory.groceries);
    await pumping(tester, map.moveTo(_town, zoom: 10.5));
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'poi-dots');
    await pumping(tester, map.moveTo(const LatLng(45.9005, 6.1235), zoom: 14.6));
    await settle(tester, const Duration(seconds: 5));
    await shot(tester, 'poi-pins');
    layer.setOpenNowOnly(on: true);
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'poi-open-now');
    layer.setOpenNowOnly(on: false);

    // A fuel station's page, with its prices.
    final stations = await waitFor(
      tester,
      container.read(poiRepositoryProvider).search('total', near: _town),
    );
    final station =
        stations.where((p) => p.kind == PoiKind.fuelStation).firstOrNull ?? stations.first;
    layer.toggle(PoiCategory.fuel);
    container.read(selectionProvider.notifier).select(PoiSelection(station.feature));
    await pumping(tester, map.moveTo(station.position, zoom: 15));
    await shot(tester, 'poi-station');
    await tester.drag(find.byType(PoiDetails).first, const Offset(0, -500), warnIfMissed: false);
    await shot(tester, 'poi-station-more');

    // "Around this place", on a place of the town.
    layer.clear();
    final places = await waitFor(tester, listened(container, mapPlacesProvider.future));
    final place =
        (places.where((p) => p.position.distanceTo(_town) < 8000 && p.name != null).toList()
              ..sort((a, b) {
                int score(PlaceSummary p) => p.kind == PlaceKind.motorhomeArea ? 0 : 1;
                return score(a).compareTo(score(b));
              }))
            .first;
    container.read(selectionProvider.notifier).select(PlaceSelection(place.id));
    await pumping(tester, map.moveTo(place.position, zoom: 14));
    await settle(tester, const Duration(seconds: 3));
    final around = find.text(t.poi.around);
    await tester.scrollUntilVisible(
      around,
      300,
      scrollable: find
          .descendant(of: find.byType(PlaceDetailsBody).first, matching: find.byType(Scrollable))
          .first,
    );
    await shot(tester, 'place-around');
    container.read(selectionProvider.notifier).select(null);
    await settle(tester, const Duration(seconds: 1));

    // The search, with its shops and services.
    await tester.enterText(find.byType(TextField).first, 'lidl');
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'search-poi');
    await tester.enterText(find.byType(TextField).first, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, const Duration(seconds: 1));

    // A chosen point: a place, or a vending machine, to add there.
    const point = LatLng(45.8981, 6.1248);
    container.read(selectionProvider.notifier).select(const PointSelection(point));
    await pumping(tester, map.moveTo(point, zoom: 15));
    await tester.drag(
      find.text(t.contribute.addPlaceHere),
      const Offset(0, -300),
      warnIfMissed: false,
    );
    await shot(tester, 'point-vending');
    container.read(selectionProvider.notifier).select(null);
    await settle(tester, const Duration(seconds: 1));

    // The offline maps: the region where the traveller is suggested, a
    // download under way, then the region kept.
    container.read(userLocationProvider.notifier).update(_town);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first))
      ..go(AppRoutes.offlineMaps);
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'offline-list');
    final catalog = await waitFor(tester, container.read(packCatalogProvider.future));
    final pack = catalog.manifest.byId(_packId)!;
    final packs = container.read(offlinePacksProvider.notifier);
    if ((await waitFor(
      tester,
      container.read(offlinePacksProvider.future),
    )).installed.containsKey(_packId)) {
      await waitFor(tester, packs.delete(_packId));
    }
    unawaited(packs.download(pack, catalog));
    final progress = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(progress)) {
      await tester.pump(const Duration(milliseconds: 100));
      final transfer = container.read(offlinePacksProvider).value?.transfers[_packId];
      if (transfer != null && transfer.progress > 0.2) break;
    }
    debugPrint('SHOT $_tag-offline-progress');
    final installed = DateTime.now().add(const Duration(minutes: 3));
    while (!(container.read(offlinePacksProvider).value?.installed.containsKey(_packId) ?? false) &&
        DateTime.now().isBefore(installed)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.drag(find.text(t.offlineMaps.intro), const Offset(0, 300), warnIfMissed: false);
    await shot(tester, 'offline-installed');

    // Offline: the map draws the pack, and says so.
    router.go(AppRoutes.map);
    await settle(tester, const Duration(seconds: 2));
    container.read(basemapReachabilityProvider.notifier).assume(reachable: false);
    await pumping(tester, map.moveTo(_packCentre, zoom: 13.5));
    await settle(tester, const Duration(seconds: 6));
    await shot(tester, 'offline-map');

    // Back online, and the pack removed: the device ends as it began.
    container.read(basemapReachabilityProvider.notifier).assume(reachable: true);
    await waitFor(tester, packs.delete(_packId));
    final left = await waitFor(tester, container.read(offlinePacksProvider.future));
    debugPrint('PACKS LEFT ${left.installed.keys.toList()} ${left.usedBytes}');
    await pumping(tester, map.moveTo(_town, zoom: 9));
    debugPrint('TOUR DONE');
    expect(left.installed.containsKey(_packId), isFalse);
  });
}
