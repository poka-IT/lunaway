import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The main map's own layers, seen where they crowd each other, against the
/// production API: Viviers (Ardèche) at zoom 13 with no chip, where the
/// places' pins stand around the town's name; then the chip "À voir", at
/// zooms 13, 14 and 15, where the sights compete with the places' pins for
/// room.
///
/// Each capture is named and described in `<tag>-moments.txt` (a `WRITE`
/// line): the zoom the map settled at, the sights the API knows in the
/// view (`Query.pois`), those the map reported from its tiles (the web's
/// engine reports none), and the places of the tiles in view. What the
/// map drew of them is read on the image: no provider says it.
///
///     python3 tool/screens/tour_web.py --test integration_test/map_layers_tour_test.dart \
///         --viewport 1440x900 --locale fr --out ../plan/screenshots/carte \
///         --define LUNAWAY_TOUR_TAG=ordinateur
///     ORG_GRADLE_PROJECT_testIdSuffix=.calques python3 tool/screens/capture.py \
///         --device android:emulator-5554 --size 1080x1920 \
///         --test integration_test/map_layers_tour_test.dart --api https://api.lunaway.net \
///         --out ../plan/screenshots/carte/android --define LUNAWAY_TOUR_TAG=android
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'carte');

/// Viviers, its old town by the Rhône.
const _viviers = LatLng(44.4826, 4.6893);

/// The device in Viviers.
final class _Feed implements LocationFeed {
  @override
  Future<Fix?> current() async =>
      Fix(position: _viviers, accuracyM: 5, at: DateTime.now().toUtc(), speedMps: 0);

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

/// A sight the API knows.
final class _Sight {
  const new({required this.kind, this.name});

  final String kind;
  final String? name;
}

/// The sights of [bounds], one page: a view of the main map holds a few.
GraphQLOperation<List<_Sight>> _sightsIn(GeoBounds bounds) => GraphQLOperation(
  name: 'TourSights',
  document:
      '''
query TourSights {
  pois(bbox: {south: ${bounds.south}, west: ${bounds.west}, north: ${bounds.north}, east: ${bounds.east}},
       categories: [SIGHTS], first: 200) {
    nodes { kind name }
  }
}''',
  parse: (data) => [
    for (final n in (data['pois'] as Map<String, dynamic>)['nodes'] as List<dynamic>)
      if (n case {'kind': final String kind, 'name': final String? name})
        _Sight(kind: kind, name: name),
  ],
);

/// Real time passing. The frames are drawn as the app asks for them
/// ([LiveTestWidgetsFlutterBindingFramePolicy.fullyLive]): a pump would wait
/// for a frame a hidden window does not draw.
Future<void> settle(Duration duration) => Future<void>.delayed(duration);

Future<void> until(
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await settle(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Viviers on the main map: its name and its sights among the pins', (tester) async {
    const notes = '$_tag-moments.txt';
    void note(String line) => debugPrint('WRITE $notes $line');

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final client = GraphQLClient(
      endpoint: config.graphqlEndpoint,
      httpClient: http.Client(),
      userAgent: AppConfig.userAgent('tour-carte'),
    );
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    // Stores of their own, beside the device's: no filter or view of a
    // user's is read or changed.
    DriftWebOptions web() => DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    );
    final cache = CacheDatabase(
      driftDatabase(
        name: 'lunaway_carte_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
    );
    final user = UserDatabase(
      driftDatabase(
        name: 'lunaway_user_carte_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
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
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    // No chip from an earlier run: the layer's choice lives in memory only,
    // so this is the app's own start.
    expect(container.read(poiLayerProvider).category, isNull);

    await until(() => container.read(mapControllerProvider) != null, what: 'the map');
    // The map fits its first camera to the region once its style is in (on
    // the web after the page's first map hands over): a move before that
    // is undone.
    await until(
      () => switch (container.read(viewportProvider)) {
        final v? => !isFirstCamera(v),
        null => false,
      },
      what: 'the map fitted to the region',
    );
    await settle(const Duration(seconds: 3));

    bool at(double zoom) => ((container.read(viewportProvider)?.zoom ?? 0) - zoom).abs() < 0.05;

    /// The camera on Viviers at [zoom], once it rests there and its tiles
    /// are in. A move the map did not make, or that the app's start undid
    /// (the web page hands its first map over to the app's), is made again.
    Future<void> view(double zoom) async {
      for (var attempt = 1; attempt <= 4; attempt++) {
        unawaited(container.read(mapControllerProvider)!.moveTo(_viviers, zoom: zoom));
        final end = DateTime.now().add(const Duration(seconds: 15));
        while (!at(zoom) && DateTime.now().isBefore(end)) {
          await settle(const Duration(milliseconds: 100));
        }
        if (at(zoom)) {
          // The places' and the points' tiles, then the map's report of them.
          await settle(const Duration(seconds: 8));
          if (at(zoom)) return;
        }
        debugPrint('VIEW not at zoom $zoom after attempt $attempt, moving again');
      }
      throw TestFailure('the map did not stay at zoom $zoom');
    }

    Future<void> shot(String name, String what) async {
      final viewport = container.read(viewportProvider);
      final bounds = viewport?.bounds;
      bool inView(LatLng p) => bounds?.contains(p) ?? false;
      // The sights of the view as the API knows them, and as the map
      // reported the points of its tiles (an engine may report none).
      final known = bounds == null ? const <_Sight>[] : await client.execute(_sightsIn(bounds));
      final reported = [
        for (final f in container.read(poisInViewProvider))
          if (f.kind.category == PoiCategory.sights && inView(f.position)) f,
      ];
      final places = [
        for (final p in container.read(placesInViewProvider).places)
          if (inView(LatLng(p.lat, p.lon))) p,
      ];
      final zoom = viewport?.zoom.toStringAsFixed(2).replaceAll('.', ',') ?? '?';
      debugPrint('SHOT $_tag-$name');
      note(
        '$_tag-$name | $what | zoom $zoom'
        ' | sites « À voir » dans la vue (API) : ${known.length}'
        '${known.isEmpty ? '' : ' (${known.map((s) => s.name ?? s.kind).join(', ')})'}'
        ' | sites signalés par la carte : ${reported.length}'
        ' | lieux dans la vue : ${places.length}',
      );
      await settle(const Duration(milliseconds: 1500));
    }

    await view(13);
    await shot('carte-z13', 'carte principale sur Viviers, sans puce');

    // The chip as a user taps it; the provider it sets when the row does
    // not show it at all.
    final label = t.poiCategory(PoiCategory.sights);
    final chip = find.text(label);
    var how = 'puce touchée';
    if (chip.evaluate().isNotEmpty) {
      await tester.ensureVisible(chip.first);
      await settle(const Duration(milliseconds: 500));
      await tester.tap(chip.first);
    } else {
      how = 'puce absente de la rangée, choix posé par le fournisseur';
      container.read(poiLayerProvider.notifier).toggle(PoiCategory.sights);
    }
    await until(
      () => container.read(poiLayerProvider).category == PoiCategory.sights,
      what: 'the chip "$label"',
    );
    await settle(const Duration(seconds: 8));
    await shot('a-voir-z13', '« $label » choisi ($how)');
    for (final zoom in [14.0, 15.0]) {
      await view(zoom);
      await shot('a-voir-z${zoom.round()}', '« $label » choisi');
    }

    container.read(poiLayerProvider.notifier).clear();
    container.read(selectionProvider.notifier).select(null);
    await settle(const Duration(seconds: 1));
    await cache.close();
    await user.close();
    debugPrint('TOUR DONE');
  });
}
