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
import 'package:lunaway/core/licences.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/core/plural_rules.dart';
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
    // Debug and profile builds also echo to the console a developer runs
    // them from: on Android that is logcat, whose timestamps time the
    // start-up of a profile build ("places drawn").
    if (!kReleaseMode) {
      debugPrint(
        '${r.level.name} ${r.loggerName}: ${r.message}${r.error == null ? '' : ' (${r.error})'}',
      );
    }
  });
  registerBundledLicences();
  if (kIsWeb) {
    // Shipped with the web build: no CDN sees the visitors, and the map loads
    // from the same origin as the app. The page imports it while the engine
    // starts (web/lunaway_maplibre.js), and publishes a map that keeps the
    // app's layers across a change of theme.
    MapLibreMap.webLibrarySource = const MapLibreJsSource.preloaded();
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // The map draws into a TextureView, which Flutter composes as a texture
    // layer. Its default SurfaceView sends Flutter to a virtual display, and
    // a pause and resume of the app (the system's location prompt) can leave
    // that display frozen: Flutter makes it again while its image reader is
    // still connected to the old one ("BufferQueue has no connected
    // producer" in logcat), and the map keeps its last frame and takes no
    // gesture until the app leaves the screen and comes back. Seen once in
    // six grants on the emulator (`plan/research/73-fix-carte.md`).
    MapLibreMap.useHybridComposition = true;
  }
  // The status bar floats over the map, which runs under it edge to edge.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final config = AppConfig.fromEnvironment();
  final cache = CacheDatabase.open(demo: config.demo);
  final user = UserDatabase.open(demo: config.demo);
  // Read together, not one after the other: on the web each is a round trip
  // to the database's worker or to the server, and the first frame waits
  // for all of them.
  final (settings, position, view, basemap, version) = await (
    SettingsRepository(user).load(),
    // The last position only tunes the automatic theme: a cache that cannot
    // be read (a damaged file, a full disk) must not hold the app on its
    // splash.
    _orNull(DriftLastPositionStore(cache).load(), 'the last position'),
    // Where the map was left, for the same reason: a damaged row opens the
    // map on France.
    _orNull(DriftLastViewStore(cache).load(), 'the last view'),
    BasemapTemplates.load(),
    PackageInfo.fromPlatform().then((info) => info.version),
  ).wait;
  await registerPluralRules();
  final locale = settings.localeCode;
  if (locale == null) {
    await LocaleSettings.useDeviceLocale();
  } else {
    await LocaleSettings.setLocale(AppLocaleUtils.parse(locale));
  }
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

/// [read]'s value, or null when it fails (logged as [what]).
Future<T?> _orNull<T>(Future<T?> read, String what) async {
  try {
    return await read;
  } on Object catch (error, stack) {
    Logger('startup').warning('$what could not be read', error, stack);
    return null;
  }
}
