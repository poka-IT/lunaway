import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The restaurants and the sights against the real API, for screenshots:
/// the map of Annecy without a chip, with "Restaurants et cafés", with
/// "À voir", the pages of a restaurant, a market and a wash that takes
/// lorries, then "Sur le trajet" from Annecy to Chamonix on both chips.
/// Run through `tool/screens/capture.py --test
/// integration_test/categories_tour_test.dart --api https://api.lunaway.net`;
/// the points are named by their ids in that database (`--define`).
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'categories');
const _restaurant = String.fromEnvironment('LUNAWAY_TOUR_RESTAURANT');
const _market = String.fromEnvironment('LUNAWAY_TOUR_MARKET');
const _wash = String.fromEnvironment('LUNAWAY_TOUR_WASH');

/// Annecy, by the old town.
const _annecy = LatLng(45.8992, 6.1294);

/// Chamonix.
const _target = RouteTarget(destination: LatLng(45.9237, 6.8694), label: 'Chamonix');

const _vehicle = Vehicle(
  type: VehicleType.overcab,
  heightM: 3.1,
  widthM: 2.3,
  lengthM: 7,
  weightT: 3.5,
  fuel: FuelType.diesel,
  consumptionL100: 11.5,
);

/// The device in Annecy.
final class _Feed implements LocationFeed {
  @override
  Future<Fix?> current() async =>
      Fix(position: _annecy, accuracyM: 5, at: DateTime.now().toUtc(), speedMps: 0);

  @override
  Stream<Fix> guidance(BackgroundNotice notice) => const Stream.empty();
}

/// The permission to notify, out of the tour: its system dialog would wait
/// for a tap no test gives.
final class _NoNotifications implements NotificationAccess {
  const new();

  @override
  Future<bool> wouldAsk() async => false;

  @override
  Future<void> ask() async {}
}

final class _Granted implements LocationPermissions {
  @override
  Future<LocationAccess> status() async => LocationAccess.granted;

  @override
  Future<LocationAccess> request() async => LocationAccess.granted;

  @override
  Future<bool> openSettings() async => true;
}

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> until(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
  String what = 'a condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 1500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restaurants and sights, from the map to "On the way"', (tester) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final cache = CacheDatabase.open(demo: false);
    final user = UserDatabase.open(demo: false);
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          cacheDatabaseProvider.overrideWithValue(cache),
          userDatabaseProvider.overrideWithValue(user),
          initialSettingsProvider.overrideWithValue(settings),
          basemapTemplatesProvider.overrideWithValue(basemap),
          locationPermissionsProvider.overrideWithValue(_Granted()),
          notificationAccessProvider.overrideWithValue(const _NoNotifications()),
          locationFeedProvider.overrideWithValue(_Feed()),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    await container.read(routeSettingsStoreProvider).save(const NavigationSettings());
    container.invalidate(routeSettingsControllerProvider);

    // The map of Annecy at street zoom, then each chip of the new
    // categories (the tiles of every category load with them).
    await until(tester, () => container.read(mapControllerProvider) != null, what: 'the map');
    // Not awaited: the camera's move ends with frames the tour pumps.
    unawaited(container.read(mapControllerProvider)!.moveTo(_annecy, zoom: 15.5));
    await settle(tester, const Duration(seconds: 6));
    await shot(tester, '01-carte-sans-puce');
    Future<void> mapChip(PoiCategory c, String name, {double? zoom}) async {
      final chip = find.text(t.poiCategory(c));
      await tester.ensureVisible(chip);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chip);
      if (zoom != null) {
        unawaited(container.read(mapControllerProvider)!.moveTo(_annecy, zoom: zoom));
      }
      await settle(tester, const Duration(seconds: 8));
      // The row puts a chosen chip first; scrolled back to it for the shot.
      await tester.ensureVisible(find.text(t.poiCategory(c)));
      await shot(tester, name);
    }

    await mapChip(PoiCategory.food, '02-carte-restaurants-et-cafes');
    await mapChip(PoiCategory.sights, '03-carte-a-voir', zoom: 15);
    // The chip off again.
    await tester.tap(find.text(t.poiCategory(PoiCategory.sights)));
    await settle(tester, const Duration(seconds: 1));

    // Each page, then scrolled to what its kind adds: the market's days,
    // the vehicles a wash takes.
    for (final (id, name, below) in [
      (_restaurant, '04-fiche-restaurant', null),
      (_market, '05-fiche-marche', t.poi.marketDays),
      (_wash, '06-fiche-lavage', t.poi.vehicles.hgvYes),
    ]) {
      if (id.isEmpty) continue;
      container.read(routerProvider).go('/map?poi=$id');
      await settle(tester, const Duration(seconds: 6));
      await shot(tester, name);
      if (below == null) continue;
      await tester.ensureVisible(find.text(below));
      await shot(tester, '$name-suite');
    }
    container.read(routerProvider).go('/map');
    await settle(tester, const Duration(seconds: 2));

    // "On the way", from Annecy to Chamonix.
    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(_target)));
    final start = find.text(t.navigation.preview.start);
    await until(tester, () => start.evaluate().isNotEmpty, what: 'the route');
    // A TextButton.icon is a subtype the type finder does not match: the
    // label alone, once the route that shows it has come.
    final open = find.text(t.navigation.onTheWay.title);
    await until(tester, () => open.evaluate().isNotEmpty, what: 'the button of "On the way"');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await settle(tester, const Duration(seconds: 4));
    Future<void> wayChip(PoiCategory c, String name) async {
      final chip = find.widgetWithText(ChoiceChip, t.poiCategory(c));
      await tester.ensureVisible(chip);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chip);
      await until(
        tester,
        () => find.text(t.navigation.onTheWay.loading).evaluate().isEmpty,
        what: t.poiCategory(c),
      );
      await settle(tester, const Duration(seconds: 2));
      await shot(tester, name);
    }

    await wayChip(PoiCategory.food, '07-trajet-restaurants-et-cafes');
    await wayChip(PoiCategory.sights, '08-trajet-a-voir');
    await tester.tapAt(const Offset(20, 40));
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE');
  });
}
