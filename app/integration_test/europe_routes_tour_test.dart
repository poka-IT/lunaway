import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// The routes of Europe against the real API, one scene each: a destination
/// the vehicle cannot reach and why (Toulouse, a yard behind an IGN section
/// at 3.20 m), a ferry the route keeps although ferries are avoided
/// (Piombino to Elba), and a route in Spain (Málaga to Granada). The start
/// of each route is set by the tour, not read from the device. It sends no
/// contribution; the vehicle, the avoid options, the language and the theme
/// the device had are put back at the end. Run through
/// `tool/screens/capture.py --test integration_test/europe_routes_tour_test.dart`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'europe');

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<T> _waitFor<T>(WidgetTester tester, Future<T> work) async {
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

Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester, const Duration(milliseconds: 1500));
  // The host captures the screen when it reads this line.
  debugPrint('SHOT $_tag-$name');
  await _settle(tester, const Duration(milliseconds: 2500));
}

/// The start of each route, set by the scene.
final class _StartFeed implements LocationFeed {
  LatLng at = const LatLng(43.6047, 1.4442);

  @override
  Future<Fix?> current() async => Fix(position: at, accuracyM: 5, at: DateTime.now().toUtc());

  @override
  Stream<Fix> guidance(BackgroundNotice notice) => const Stream.empty();
}

final class _NoNotifications implements NotificationAccess {
  const new();

  @override
  Future<bool> wouldAsk() async => false;

  @override
  Future<void> ask() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('europe routes tour', (tester) async {
    final feed = _StartFeed();
    await app.runLunaway(
      overrides: [
        locationFeedProvider.overrideWithValue(feed),
        notificationAccessProvider.overrideWithValue(const _NoNotifications()),
      ],
    );
    await _settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    final localeBefore = container.read(settingsProvider).localeCode;
    final themeBefore = container.read(settingsProvider).theme;
    await settings.setLocale(AppLocaleUtils.parse(_locale));
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    final ready = DateTime.now().add(const Duration(minutes: 2));
    while (container.read(viewportProvider) == null && DateTime.now().isBefore(ready)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final router = container.read(routerProvider);
    final vehicles = container.read(vehicleRepositoryProvider);
    final vehicleBefore = await _waitFor(tester, vehicles.watch().first);
    final routeSettings = container.read(routeSettingsControllerProvider.notifier);
    final avoidBefore = (await _waitFor(
      tester,
      container.read(routeSettingsControllerProvider.future),
    )).avoid;
    // A 3.30 m integrated motorhome, the vehicle of the backend's recordings.
    await _waitFor(
      tester,
      vehicles.save(
        const Vehicle(
          type: VehicleType.integrated,
          heightM: 3.3,
          widthM: 2.3,
          lengthM: 7.4,
          weightT: 3.5,
        ),
      ),
    );
    Future<void> preview(LatLng from, LatLng to, String name) async {
      feed.at = from;
      container.invalidate(previewDevicePositionProvider);
      unawaited(router.push(NavigationRoutes.previewOf(RouteTarget(destination: to, label: name))));
      await _settle(tester, const Duration(seconds: 12));
    }

    try {
      await _waitFor(tester, routeSettings.setAvoid(const AvoidOptions()));
      await preview(
        const LatLng(43.6047, 1.4442),
        const LatLng(43.63648, 1.48074),
        'Chemin de Gabardie',
      );
      await _shot(tester, '16-no-route');
      router.go(AppRoutes.map);
      await _settle(tester, const Duration(seconds: 1));

      await _waitFor(tester, routeSettings.setAvoid(const AvoidOptions(ferries: true)));
      await preview(const LatLng(42.9256, 10.5267), const LatLng(42.8137, 10.3149), 'Portoferraio');
      // The sheet raised, as a hand would: the crossing is below the route.
      await tester.drag(find.textContaining('Portoferraio').first, const Offset(0, -560));
      await _settle(tester, const Duration(seconds: 2));
      await _shot(tester, '17-ferry');
      router.go(AppRoutes.map);
      await _settle(tester, const Duration(seconds: 1));

      await _waitFor(tester, routeSettings.setAvoid(const AvoidOptions()));
      await preview(const LatLng(36.7213, -4.4214), const LatLng(37.1761, -3.5881), 'Granada');
      await _shot(tester, '18-spain');
      router.go(AppRoutes.map);
      await _settle(tester, const Duration(seconds: 1));
    } finally {
      await _waitFor(tester, routeSettings.setAvoid(avoidBefore));
      await _waitFor(
        tester,
        vehicleBefore == null ? vehicles.clear() : vehicles.save(vehicleBefore),
      );
      await settings.setLocale(localeBefore == null ? null : AppLocaleUtils.parse(localeBefore));
      await settings.setTheme(themeBefore);
      await _settle(tester, const Duration(seconds: 1));
    }
  });
}
