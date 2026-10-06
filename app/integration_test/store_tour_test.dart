import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// The scenes of the store and site screenshots (`docs/screenshots.md`),
/// against the real API: the map around Annecy, a motorhome area's page and
/// what is around it, the filters, a route for a low-profile motorhome, the
/// fuel prices, the offline maps, the favourites, the profile and the
/// vehicle. It sends no contribution. The vehicle, the filters, the language
/// and the theme the device had are put back at the end; the favourites it
/// adds stay (and follow a signed-in account), and the last position and
/// view become Annecy's. Run on a device without an account. Run through
/// `tool/screens/capture.py --test integration_test/store_tour_test.dart`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'store');

/// The lake shore at Annecy, a public park: where the scenes stand.
const _here = LatLng(45.9006, 6.1291);

/// A motorhome area with services and shops around, at the south of the
/// lake: Aire de Camping Car Doussard.
const _placeId = '01a10f0e-2a68-7650-bd10-132ddc5c7e20';

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<T> waitFor<T>(WidgetTester tester, Future<T> work) async {
  var done = false;
  late T value;
  unawaited(
    work.then((v) {
      value = v;
      done = true;
    }),
  );
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return value;
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  // The host captures the screen when it reads this line.
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    final filterBefore = container.read(placeFilterProvider);
    final localeBefore = container.read(settingsProvider).localeCode;
    final themeBefore = container.read(settingsProvider).theme;
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
    final router = container.read(routerProvider);
    container.read(poiLayerProvider.notifier).clear();
    container.read(selectionProvider.notifier).select(null);

    // A low-profile motorhome on gazole, the one of docs/screenshots.md.
    final vehicles = container.read(vehicleRepositoryProvider);
    final vehicleBefore = await waitFor(tester, vehicles.watch().first);
    await waitFor(
      tester,
      vehicles.save(
        Vehicle.typical(VehicleType.lowProfile)
            .copyWith(fuel: () => FuelType.diesel, consumptionL100: () => 11),
      ),
    );
    container.read(userLocationProvider.notifier).update(_here);
    // The blue dot of the device, which the emulator places at [_here]; the
    // host grants the permission when it reads this line.
    debugPrint('GRANT LOCATION');
    await settle(tester, const Duration(seconds: 2));
    await waitFor(tester, map.locateUser());

    // The device gets its vehicle, filters, language and theme back however
    // the scenes end.
    try {
      await waitFor(tester, map.moveTo(_here, zoom: 11.3));
      await settle(tester, const Duration(seconds: 5));
      await shot(tester, '01-map');

      container.read(selectionProvider.notifier).select(const PlaceSelection(_placeId));
      final place = await waitFor(
        tester,
        container.read(placesRepositoryProvider).watchPlace(_placeId).first,
      );
      if (place != null) await waitFor(tester, map.moveTo(place.position, zoom: 14));
      await settle(tester, const Duration(seconds: 5));
      await shot(tester, '02-place');

      // Further down: services, what is around, the coordinates.
      for (final dy in [-500.0, -700.0]) {
        await tester.drag(find.byType(PlaceDetailsBody).first, Offset(0, dy), warnIfMissed: false);
        await settle(tester, const Duration(milliseconds: 600));
      }
      await shot(tester, '03-place-around');
      container.read(selectionProvider.notifier).select(null);
      await settle(tester, const Duration(seconds: 1));

      await tester.tap(find.text(t.map.filters).first);
      await shot(tester, '04-filters');
      Navigator.of(tester.element(find.text(t.filters.title).last)).pop();
      await settle(tester, const Duration(seconds: 1));

      // The route for the motorhome to the area, from the lake shore.
      if (place != null) {
        unawaited(
          router.push(
            NavigationRoutes.previewOf(
              RouteTarget(destination: place.position, label: place.name, placeId: place.id),
            ),
          ),
        );
        await settle(tester, const Duration(seconds: 12));
        await shot(tester, '05-route');
        router.pop();
        await settle(tester, const Duration(seconds: 2));
      }

      // The fuel prices around, the cheapest first.
      container.read(poiLayerProvider.notifier).toggle(PoiCategory.fuel);
      await waitFor(tester, map.moveTo(const LatLng(45.905, 6.115), zoom: 13.3));
      await settle(tester, const Duration(seconds: 7));
      await shot(tester, '06-fuel');
      container.read(poiLayerProvider.notifier).clear();
      await waitFor(tester, map.moveTo(_here, zoom: 11.3));
      await settle(tester, const Duration(seconds: 2));

      // Favourites: a few real places of the area, and a trip list.
      final repo = container.read(favoritesRepositoryProvider);
      final near = (await waitFor(
        tester,
        container.read(mapPlacesProvider.future),
      )).where((p) => p.name != null && p.position.distanceTo(_here) < 30000).take(4);
      for (final p in near) {
        await waitFor(tester, repo.addToDefault(p));
      }
      final lists = await waitFor(tester, repo.watchLists().first);
      const trip = _locale == 'fr' ? 'Alpes 2027' : 'Alps 2027';
      if (!lists.any((l) => l.name == trip)) await waitFor(tester, repo.createList(trip));
      router.go(AppRoutes.favorites);
      await shot(tester, '07-favorites');

      router.go(AppRoutes.offlineMaps);
      await settle(tester, const Duration(seconds: 3));
      await shot(tester, '08-offline');

      router.go(AppRoutes.profile);
      await shot(tester, '09-profile');

      final editor = showVehicleEditor(tester.element(find.byType(Scaffold).first));
      await shot(tester, '10-vehicle');
      Navigator.of(tester.element(find.byType(VehicleEditor))).pop();
      await waitFor(tester, editor);
    } finally {
      await waitFor(
        tester,
        vehicleBefore == null ? vehicles.clear() : vehicles.save(vehicleBefore),
      );
      await settings.setFilter(filterBefore);
      await settings.setTheme(themeBefore);
      await settings.setLocale(localeBefore == null ? null : AppLocaleUtils.parse(localeBefore));
      router.go(AppRoutes.map);
    }
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE');
  });
}
