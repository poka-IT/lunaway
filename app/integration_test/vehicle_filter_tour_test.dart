import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
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
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The map's row of quick filters for a user whose motorhome is already
/// described (an A-class, 2.95 m high) and who never touched "my vehicle
/// fits", for screenshots: the settings are read as the app reads them at
/// launch, so the shot shows what such a user finds on opening the app.
/// The map stands on Annecy, against the real API.
///
///     python3 tool/screens/tour_web.py --test integration_test/vehicle_filter_tour_test.dart \
///         --viewport 412x732 --locale fr --out ../plan/screenshots/filtre-vehicule/apres
///
/// The shots are named after the browser's viewport, so one build serves
/// a phone and a desktop (`--no-build --viewport 1440x900`).
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');

/// Annecy, by the old town.
const _annecy = LatLng(45.8992, 6.1294);

/// The position is set by the tour, never asked: no system prompt to
/// answer, and the map does not look for a fix of its own.
final class _NotAsked implements LocationPermissions {
  @override
  Future<LocationAccess> status() async => LocationAccess.notGranted;

  @override
  Future<LocationAccess> request() async => LocationAccess.notGranted;

  @override
  Future<bool> openSettings() async => false;
}

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits until [done] for [timeout] at most; whether it came.
Future<bool> came(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('quick filters: the row a user with a described vehicle opens on', (tester) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final view = tester.view;
    final size = view.physicalSize / view.devicePixelRatio;
    final tag = '$_locale-web${size.width.round()}x${size.height.round()}-$_theme';
    final config = AppConfig.fromEnvironment();
    final basemap = await BasemapTemplates.load();
    DriftWebOptions web() => DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    );
    final cache = CacheDatabase(
      driftDatabase(
        name: 'lunaway_vehicle_filter_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
    );
    final user = UserDatabase(
      driftDatabase(
        name: 'lunaway_user_vehicle_filter_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
    );
    // A user of an earlier version: a vehicle described, no setting kept
    // about the filter.
    await user.delete(user.settings).go();
    await DriftVehicleRepository(user).save(Vehicle.typical(VehicleType.integrated));
    final stored = await SettingsRepository(user).load();
    final settings = stored.copyWith(
      localeCode: () => _locale,
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
          locationPermissionsProvider.overrideWithValue(_NotAsked()),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    if (!await came(
      tester,
      () =>
          container.read(mapControllerProvider) != null && container.read(viewportProvider) != null,
    )) {
      throw TestFailure('the map did not come');
    }
    container.read(userLocationProvider.notifier).update(_annecy);
    // A browser's map fits France once its style has loaded, which can
    // come after a move made as soon as the controller is ready: moved
    // again until the camera stays on Annecy.
    bool onAnnecy() => (container.read(viewportProvider)?.center.distanceTo(_annecy) ?? 1e9) < 2000;
    var steady = 0;
    for (var i = 0; i < 10 && steady < 2; i++) {
      if (onAnnecy()) {
        steady++;
      } else {
        steady = 0;
        // Not awaited: the camera's move ends with frames the tour pumps.
        unawaited(container.read(mapControllerProvider)!.moveTo(_annecy, zoom: 13));
        await came(tester, onAnnecy, timeout: const Duration(seconds: 8));
      }
      await settle(tester, const Duration(seconds: 3));
    }
    await settle(tester, const Duration(seconds: 4));
    debugPrint('SHOT $tag-carte');
    await settle(tester, const Duration(milliseconds: 1500));
    // After the shot, so a regression still leaves its picture.
    expect(container.read(placeFilterProvider).fitsMyVehicle, isTrue);
    debugPrint('TOUR DONE');
  });
}
