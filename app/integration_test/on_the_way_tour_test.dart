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
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// "On the way" against the real API, for screenshots: the preview of a
/// trip from Lyon to Annecy, the sheet on fuel (the vehicle's, then the
/// choice of another), a night, groceries, water, what lies further on,
/// then the guidance, where the sheet opens at half height. Run through
/// `tool/screens/capture.py --test integration_test/on_the_way_tour_test.dart
/// --api https://api.lunaway.net`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'trajet');

/// Villeurbanne, on the Cours Émile Zola: a start a motorhome of 3.1 m
/// leaves (the Part-Dieu station's block is under a bridge of 2.6 m).
const _start = LatLng(45.7700, 4.8790);

/// Annecy, by the lake.
const _target = RouteTarget(destination: LatLng(45.8992, 6.1294), label: 'Annecy');

const _vehicle = Vehicle(
  type: VehicleType.overcab,
  heightM: 3.1,
  widthM: 2.3,
  lengthM: 7,
  weightT: 3.5,
  fuel: FuelType.diesel,
  consumptionL100: 11.5,
);

/// The device at the start until the guidance, then driving the route
/// the preview drew, at 25 m/s.
final class _Feed implements LocationFeed {
  List<Fix> fixes = const [];

  @override
  Future<Fix?> current() async =>
      Fix(position: _start, accuracyM: 5, at: DateTime.now().toUtc(), speedMps: 0);

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    for (final f in fixes) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      yield f;
    }
  }
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

  testWidgets('on the way, from Lyon to Annecy', (tester) async {
    final feed = _Feed();
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
          locationFeedProvider.overrideWithValue(feed),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    // The route settings from a clean slate: an earlier run leaves its own.
    await container.read(routeSettingsStoreProvider).save(const NavigationSettings());
    container.invalidate(routeSettingsControllerProvider);

    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(_target)));
    final start = find.text(t.navigation.preview.start);
    await until(tester, () => start.evaluate().isNotEmpty, what: 'the route');
    await shot(tester, '01-apercu');

    // Fuel first, the vehicle's, in one line.
    final open = find.widgetWithText(TextButton, t.navigation.onTheWay.title);
    await tester.ensureVisible(open);
    await tester.tap(open);
    await until(
      tester,
      () =>
          find.text(t.navigation.fuel.add).evaluate().isNotEmpty ||
          find.text(t.navigation.fuel.empty).evaluate().isNotEmpty,
      what: 'the stations',
    );
    await shot(tester, '02-carburant-du-vehicule');
    await tester.tap(find.text(t.navigation.onTheWay.otherFuel));
    await shot(tester, '03-autre-carburant');

    Future<void> chip(String label, String name) async {
      final c = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(c);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(c);
      await until(
        tester,
        () =>
            find.text(t.navigation.onTheWay.loading).evaluate().isEmpty &&
            find.text(t.navigation.onTheWay.title).evaluate().isNotEmpty,
        what: label,
      );
      await shot(tester, name);
    }

    await chip(t.navigation.onTheWay.categories.sleep, '04-dormir');
    final further = find.textContaining(t.navigation.onTheWay.further(n: '').split('(').first);
    if (further.evaluate().isNotEmpty) {
      await tester.ensureVisible(further.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(further.first);
      await shot(tester, '05-dormir-plus-loin');
    }
    await chip(t.navigation.onTheWay.categories.groceries, '06-courses');
    await chip(t.navigation.onTheWay.categories.water, '07-eau-et-vidange');
    await chip(t.navigation.onTheWay.categories.toilets, '08-toilettes');
    await tester.tapAt(const Offset(20, 40));
    await settle(tester, const Duration(seconds: 1));

    // The guidance along the route the preview drew.
    final route = container.read(routePreviewControllerProvider(_target)).value!.route!;
    feed.fixes = drive(
      route.line,
      stepM: 25,
      start: DateTime.now().toUtc(),
      tick: const Duration(seconds: 1),
      speedMps: 25,
    );
    await tester.tap(start);
    await settle(tester, const Duration(seconds: 1));
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    await until(tester, () => (session()?.snapshot?.distanceAlongM ?? 0) > 3000, what: '3 km in');
    await tester.tap(find.byTooltip(t.navigation.onTheWay.title));
    // The chip chosen in the preview holds for the trip: the list opens on
    // it.
    await until(
      tester,
      () =>
          find.textContaining(t.navigation.fuel.add).evaluate().isNotEmpty ||
          find.text(t.navigation.onTheWay.empty).evaluate().isNotEmpty ||
          find.text(t.common.retry).evaluate().isNotEmpty,
      what: 'what lies ahead',
    );
    await shot(tester, '09-guidage-mi-hauteur');
    await tester.tapAt(const Offset(20, 40));
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE');
  });
}
