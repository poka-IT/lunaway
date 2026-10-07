import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/licences.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/data/last_view.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/demo/demo_server.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show MapLibreJsSource, MapLibreMap, setHttpHeaders;
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() => runLunaway();

/// Starts the app; [overrides] come after the app's own, for a tour on a
/// device that drives a simulated position.
Future<void> runLunaway({List<Override> overrides = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = kReleaseMode ? Level.INFO : Level.FINE;
  Logger.root.onRecord.listen((r) {
    developer.log(
      r.message,
      name: r.loggerName,
      level: r.level.value,
      error: r.error,
      stackTrace: r.stackTrace,
    );
    // Debug builds also echo to the console a developer runs them from.
    if (kDebugMode) {
      debugPrint(
        '${r.level.name} ${r.loggerName}: ${r.message}${r.error == null ? '' : ' (${r.error})'}',
      );
    }
  });
  registerBundledLicences();
  if (kIsWeb) {
    // Shipped with the web build: no CDN sees the visitors, and the map loads
    // from the same origin as the app.
    // Absolute URLs: a module import refuses a bare relative path, and the
    // app may be served under a sub-path (/app/).
    MapLibreMap.webLibrarySource = MapLibreJsSource.urls(
      scriptUrl: Uri.base.resolve('maplibre-gl/maplibre-gl.mjs').toString(),
      styleUrl: Uri.base.resolve('maplibre-gl/maplibre-gl.css').toString(),
    );
  }
  // The status bar floats over the map, which runs under it edge to edge.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final config = AppConfig.fromEnvironment();
  final cache = CacheDatabase.open(demo: config.demo);
  final user = UserDatabase.open(demo: config.demo);
  final settings = await SettingsRepository(user).load();
  // The last position only tunes the automatic theme: a cache that cannot be
  // read (a damaged file, a full disk) must not hold the app on its splash.
  LatLng? position;
  try {
    position = await DriftLastPositionStore(cache).load();
  } on Object catch (error, stack) {
    Logger('startup').warning('the last position could not be read', error, stack);
  }
  // Where the map was left, for the same reason: a damaged row opens the
  // map on France.
  SavedView? view;
  try {
    view = await DriftLastViewStore(cache).load();
  } on Object catch (error, stack) {
    Logger('startup').warning('the last view could not be read', error, stack);
  }
  final basemap = await BasemapTemplates.load();
  final locale = settings.localeCode;
  if (locale == null) {
    await LocaleSettings.useDeviceLocale();
  } else {
    await LocaleSettings.setLocale(AppLocaleUtils.parse(locale));
  }
  final version = (await PackageInfo.fromPlatform()).version;
  // The map engine's own requests (tiles, style, fonts) name the app as the
  // app's other requests do, rather than the device's system and model.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await setHttpHeaders({'User-Agent': AppConfig.userAgent(version)});
    } on Object catch (error, stack) {
      Logger('startup').warning('the map keeps its own User-Agent', error, stack);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        cacheDatabaseProvider.overrideWithValue(cache),
        userDatabaseProvider.overrideWithValue(user),
        appVersionProvider.overrideWithValue(version),
        initialSettingsProvider.overrideWithValue(settings),
        initialPositionProvider.overrideWithValue(position),
        initialViewProvider.overrideWithValue(view),
        basemapTemplatesProvider.overrideWithValue(basemap),
        // A constant condition: a release build drops the demo server and
        // its data entirely.
        if (demoBuild)
          httpClientProvider.overrideWithValue(
            demoApiClient(demoPlaces(), apiBase: config.apiBase),
          ),
        ...overrides,
      ],
      child: TranslationProvider(child: const LunawayApp()),
    ),
  );
}
