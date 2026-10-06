import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/app_database.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() async {
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
  _registerLicences();
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

  final config = AppConfig.fromEnvironment();
  final db = AppDatabase.open(demo: config.demo);
  final settings = await SettingsRepository(db).load();
  final locale = settings.localeCode;
  if (locale == null) {
    await LocaleSettings.useDeviceLocale();
  } else {
    await LocaleSettings.setLocale(AppLocaleUtils.parse(locale));
  }
  final version = (await PackageInfo.fromPlatform()).version;

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        appDatabaseProvider.overrideWithValue(db),
        appVersionProvider.overrideWithValue(version),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: TranslationProvider(child: const LunawayApp()),
    ),
  );
}

/// Licences of what ships inside the app without a package of its own: the
/// typeface and the desktop map library.
void _registerLicences() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Atkinson Hyperlegible Next',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'MapLibre GL JS',
    ], await rootBundle.loadString('assets/map/LICENSE-maplibre-gl.txt'));
  });
}
