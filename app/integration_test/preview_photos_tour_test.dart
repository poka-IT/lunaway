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
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The route preview's places near the route, against the real API, for
/// screenshots: a short route along the Rhône from Viviers, its map close
/// enough for the places that matter most to stand out, drawn in the look
/// the guidance uses by default (photos). Run through
/// `tool/screens/capture.py --test integration_test/preview_photos_tour_test.dart
/// --api https://api.lunaway.net`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'apercu');

/// Viviers, by the Rhône.
const _start = LatLng(44.4826, 4.6893);

const _target = RouteTarget(destination: LatLng(44.5262, 4.6868), label: 'Le Teil');

const _vehicle = Vehicle(
  type: VehicleType.overcab,
  heightM: 3.1,
  widthM: 2.3,
  lengthM: 7,
  weightT: 3.5,
  fuel: FuelType.diesel,
  consumptionL100: 11.5,
);

/// The device at the start; the preview asks for nothing more.
final class _Feed implements LocationFeed {
  @override
  Future<Fix?> current() async =>
      Fix(position: _start, accuracyM: 5, at: DateTime.now().toUtc(), speedMps: 0);

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the preview from Viviers, its places near the route drawn large', (tester) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final cache = CacheDatabase.open(demo: false);
    final user = UserDatabase.open(demo: false);
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(localeCode: _locale, theme: ThemePreference.light);
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
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    // The guidance's own choice of places from a clean slate: every place,
    // in photos.
    await container.read(routeSettingsStoreProvider).save(const NavigationSettings());
    container.invalidate(routeSettingsControllerProvider);

    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(_target)));
    final start = find.text(t.navigation.preview.start);
    await until(tester, () => start.evaluate().isNotEmpty, what: 'the route');
    // The places near the route, their photos and the map's tiles.
    await settle(tester, const Duration(seconds: 12));
    debugPrint('SHOT $_tag-00-apercu');
    await settle(tester, const Duration(seconds: 1));
  });
}
