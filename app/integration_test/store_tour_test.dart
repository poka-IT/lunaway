import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// The scenes of the store and site screenshots (`docs/screenshots.md`),
/// against the real API: the map around Annecy, a motorhome area's page and
/// what is around it, the filters, a route for a low-profile motorhome, the
/// fuel prices around and along the route with how a station's price moved,
/// the offline maps, the regions kept, the favourites, the profile, the
/// vehicle, a guidance through a French danger zone with the limit beside
/// the speed (a simulated drive), and the road report sheet opened from it.
/// It sends no contribution. The vehicle, the filters, the language
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

/// A camera move, waited for a few seconds at most: on the iOS simulator
/// the engine does not always say when an animation ends.
Future<void> move(WidgetTester tester, Future<void> moving) async {
  var done = false;
  unawaited(moving.whenComplete(() => done = true));
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  // The host captures the screen when it reads this line.
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

/// Toward Chambéry by the N201, where France lists a danger zone about
/// 1.5 km after the start.
const _driveFrom = LatLng(45.6008, 5.9086);
const _driveTo = LatLng(45.5646, 5.9178);

/// The device's position for the guidance, until its scene drives a
/// simulated one.
final class _TourFeed implements LocationFeed {
  final LocationFeed device = const GeolocatorFeed();
  List<Fix>? fixes;
  Duration pace = const Duration(milliseconds: 60);

  /// The start of a route: the drive's first fix, else [_here], where the
  /// device stands for the scenes (asking the device would raise the
  /// system's permission dialog on iOS).
  @override
  Future<Fix?> current() async =>
      fixes?.first ?? Fix(position: _here, accuracyM: 5, at: DateTime.now().toUtc());

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    final drive = fixes;
    if (drive == null) {
      yield* device.guidance(notice);
      return;
    }
    for (final f in drive) {
      await Future<void>.delayed(pace);
      yield f;
    }
  }
}

/// No notification permission asked in the middle of the captures.
final class _NoNotifications implements NotificationAccess {
  const new();

  @override
  Future<bool> wouldAsk() async => false;

  @override
  Future<void> ask() async {}
}

Future<void> until(WidgetTester tester, bool Function() done, {required String what}) async {
  final end = DateTime.now().add(const Duration(minutes: 3));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store tour', (tester) async {
    final feed = _TourFeed();
    await app.runLunaway(
      overrides: [
        locationFeedProvider.overrideWithValue(feed),
        notificationAccessProvider.overrideWithValue(const _NoNotifications()),
      ],
    );
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
    // host grants the permission when it reads this line. The iOS simulator
    // keeps asking through a system dialog no test can answer: there the
    // scenes go without the dot.
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      debugPrint('GRANT LOCATION');
      await settle(tester, const Duration(seconds: 2));
      await waitFor(tester, map.locateUser());
    }

    // The device gets its vehicle, filters, language and theme back however
    // the scenes end.
    try {
      await move(tester, map.moveTo(_here, zoom: 11.3));
      await settle(tester, const Duration(seconds: 5));
      await shot(tester, '01-map');

      container.read(selectionProvider.notifier).select(const PlaceSelection(_placeId));
      final place = await waitFor(
        tester,
        container.read(placesRepositoryProvider).watchPlace(_placeId).first,
      );
      if (place != null) await move(tester, map.moveTo(place.position, zoom: 14));
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
        // The stations along the route, the price with the detour.
        final along = find.text(t.navigation.fuel.action);
        if (along.evaluate().isNotEmpty) {
          await tester.tap(along.first);
          await settle(tester, const Duration(seconds: 6));
          await shot(tester, '11-fuel-route');
          Navigator.of(tester.element(find.text(t.navigation.fuel.action).first)).maybePop();
          await settle(tester, const Duration(seconds: 1));
        }
        router.pop();
        await settle(tester, const Duration(seconds: 2));
      }

      // The fuel prices around, the cheapest first.
      container.read(poiLayerProvider.notifier).toggle(PoiCategory.fuel);
      await move(tester, map.moveTo(const LatLng(45.905, 6.115), zoom: 13.3));
      await settle(tester, const Duration(seconds: 7));
      await shot(tester, '06-fuel');
      // The cheapest station's page, down to how its gazole moved.
      final offers = await waitFor(tester, container.read(cheapestFuelProvider.future)) ?? const [];
      if (offers.isNotEmpty) {
        final station = offers.first.station;
        container.read(selectionProvider.notifier).select(PoiSelection(station.feature));
        await move(tester, map.moveTo(station.position, zoom: 15));
        await settle(tester, const Duration(seconds: 4));
        final trend = find.text(t.poi.trend.title(fuel: t.poi.fuel.diesel));
        final details = find
            .descendant(of: find.byType(PoiDetails), matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(trend, 200, scrollable: details);
        // The card's title near the top of the sheet, its chart below.
        await tester.drag(trend, const Offset(0, -260), warnIfMissed: false);
        await settle(tester, const Duration(seconds: 2));
        await shot(tester, '12-fuel-trend');
        container.read(selectionProvider.notifier).select(null);
      }
      container.read(poiLayerProvider.notifier).clear();
      await move(tester, map.moveTo(_here, zoom: 11.3));
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

      // The regions whose places the device keeps, France unfolded.
      unawaited(showRegionPicker(tester.element(find.byType(Scaffold).first)));
      await until(
        tester,
        () => find.text(t.regions.wholeFrance).evaluate().isNotEmpty,
        what: 'the regions',
      );
      await settle(tester, const Duration(seconds: 1));
      await tester.tap(find.byTooltip(t.regions.showFrance));
      await settle(tester, const Duration(seconds: 2));
      await shot(tester, '13-regions');
      Navigator.of(tester.element(find.byType(RegionPicker))).pop();
      await settle(tester, const Duration(seconds: 1));

      router.go(AppRoutes.profile);
      await shot(tester, '09-profile');

      final editor = showVehicleEditor(tester.element(find.byType(Scaffold).first));
      await shot(tester, '10-vehicle');
      Navigator.of(tester.element(find.byType(VehicleEditor))).pop();
      await waitFor(tester, editor);

      // A guidance through a danger zone, the limit beside the speed: a
      // real route of the API, driven by a simulated position below the
      // limit.
      router.go(AppRoutes.map);
      await settle(tester, const Duration(seconds: 1));
      final vehicle = await waitFor(tester, vehicles.watch().first);
      final plan = await waitFor(
        tester,
        container
            .read(routeServiceProvider)
            .route(
              RouteRequest(
                origin: _driveFrom,
                destination: _driveTo,
                vehicle: checkVehicle(vehicle).profile!,
                avoid: const AvoidOptions(),
                language: _locale == 'en' ? RouteLanguage.en : RouteLanguage.fr,
              ),
            ),
      );
      final route = plan.routes.first;
      feed
        ..fixes = drive(
          route.line,
          stepM: 13,
          start: DateTime.now().toUtc(),
          tick: const Duration(seconds: 1),
          // 47 km/h: under every limit of the way, so the speed reads plain.
          speedMps: 13,
        )
        ..pace = const Duration(milliseconds: 250);
      final guidance = container.read(guidanceControllerProvider.notifier);
      await waitFor(
        tester,
        guidance.start(
          plan: plan,
          routeIndex: route.index,
          target: const RouteTarget(destination: _driveTo, label: 'Chambéry'),
          words: TranslatedWording(t, DistanceUnits.metric),
        ),
      );
      // The emulator has no French voice: its notice is no part of the scene.
      final voiceBefore = container.read(guidanceControllerProvider)?.voiceOn ?? true;
      await waitFor(tester, guidance.setVoice(on: false));
      unawaited(router.push(NavigationRoutes.guidance));
      GuidanceSession? session() => container.read(guidanceControllerProvider);
      await until(tester, () => session()?.aids.alert != null, what: 'the zone ahead');
      feed.pace = const Duration(seconds: 1);
      await shot(tester, '14-guidance');
      // A report on the road, from the guidance: the passenger's word, the
      // kind chosen, nothing sent.
      await tester.tap(find.byTooltip(t.roadReport.actionHint));
      await settle(tester, const Duration(seconds: 1));
      await tester.tap(find.text(t.roadReport.passenger));
      await settle(tester, const Duration(seconds: 1));
      await tester.tap(find.text(t.roadReport.kinds.lowClearance));
      await shot(tester, '15-road-report');
      Navigator.of(tester.element(find.text(t.roadReport.title))).pop();
      await settle(tester, const Duration(seconds: 1));
      await waitFor(tester, guidance.setVoice(on: voiceBefore));
      guidance.stop();
      feed.fixes = null;
      await settle(tester, const Duration(seconds: 1));
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
