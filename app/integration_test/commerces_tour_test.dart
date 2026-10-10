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
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_search.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The search of the establishments against the real API, for screenshots:
/// a search by kind around the user ("coiffeur"), one in a town ("pizzeria
/// annecy"), the town itself ("Annecy": the town and the places first, the
/// establishments after), then the page of one establishment of each
/// profile, found by a search as a user would: a restaurant, a hairdresser,
/// a dental practice (no rating of its own), a hotel, a tyre shop, a
/// garage, a cinema. Each is the first result of the expected kind, the
/// one named in [_cards] when the API lists it, so a name gone from the
/// data changes the shot, never the run. Each page is shot as it opens,
/// then scrolled to what its kind adds (`-suite`); two of them down to
/// their ratings and the link to Google Maps (`-avis`). A `WRITE` line
/// names the establishment of each page in `<tag>-fiches.txt`.
///
/// The user stands in Annecy (no location prompt: the position is set,
/// never asked), and so does the map: the search ranks from its centre.
/// The stores are the tour's own, beside the device's.
///
///     python3 tool/screens/tour_web.py --test integration_test/commerces_tour_test.dart \
///         --viewport 412x732 --locale fr --out ../plan/screenshots/commerces/web-phone
///
/// On Android, with an application id of its own beside the others on a
/// shared emulator:
///
///     ORG_GRADLE_PROJECT_testIdSuffix=.commerces python3 tool/screens/capture.py \
///         --device android:emulator-5554 --size 1080x1920 \
///         --test integration_test/commerces_tour_test.dart --api https://api.lunaway.net \
///         --out ../plan/screenshots/commerces/android
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'commerces');

/// Annecy, by the old town.
const _annecy = LatLng(45.8992, 6.1294);

/// One page of the tour: the search that finds it, the kinds accepted, a
/// name preferred when listed, and whether the page is scrolled down to
/// its reviews for a second shot.
typedef _Card = ({String query, List<PoiKind> kinds, String? prefer, String name, bool reviews});

const List<_Card> _cards = [
  (
    query: 'restaurant annecy',
    kinds: [PoiKind.restaurant],
    prefer: 'Beignet Alpin',
    name: '04-fiche-restaurant',
    reviews: true,
  ),
  (
    query: 'coiffeur annecy',
    kinds: [PoiKind.hairdresser],
    prefer: 'Intimiste',
    name: '05-fiche-coiffeur',
    reviews: false,
  ),
  (
    query: 'dentiste lyon',
    kinds: [PoiKind.dentist],
    prefer: 'Dentego',
    name: '06-fiche-dentiste',
    reviews: true,
  ),
  (
    query: 'hotel nice',
    kinds: [PoiKind.hotel],
    prefer: 'Ibis',
    name: '07-fiche-hotel',
    reviews: false,
  ),
  (
    query: 'pneus annecy',
    kinds: [PoiKind.tyres, PoiKind.carRepair],
    prefer: null,
    name: '08-fiche-pneus',
    reviews: false,
  ),
  (
    query: 'garage annecy',
    kinds: [PoiKind.carRepair],
    prefer: null,
    name: '09-fiche-garage',
    reviews: false,
  ),
  (
    query: 'cinema annecy',
    kinds: [PoiKind.cinema],
    prefer: null,
    name: '10-fiche-cinema',
    reviews: false,
  ),
];

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

/// Waits until [done], or fails after [timeout] naming [what].
Future<void> until(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (!await came(tester, done, timeout: timeout)) {
    throw TestFailure('timed out waiting for $what');
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 1500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('establishments: searches by kind and by town, and a page of each profile', (
    tester,
  ) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    DriftWebOptions web() => DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    );
    final cache = CacheDatabase(
      driftDatabase(
        name: 'lunaway_commerces_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
    );
    final user = UserDatabase(
      driftDatabase(
        name: 'lunaway_user_commerces_tour',
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
          locationPermissionsProvider.overrideWithValue(_NotAsked()),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();

    await until(
      tester,
      () =>
          container.read(mapControllerProvider) != null && container.read(viewportProvider) != null,
      what: 'the map and its first camera',
    );
    container.read(userLocationProvider.notifier).update(_annecy);
    // The search ranks from the map's centre, never from the user: the map
    // must stand on Annecy before "coiffeur" is typed. A browser's map
    // fits France when its style has loaded, which can come after a move
    // made once the controller is ready: moved again until the camera
    // stays on Annecy over two looks.
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
    if (!onAnnecy()) throw TestFailure('the map did not stay on Annecy');
    debugPrint('CAMERA ${container.read(viewportProvider)?.center}');

    final field = find.descendant(of: find.byType(MapSearch), matching: find.byType(TextField));
    final tiles = find.descendant(
      of: find.byType(PoiSearchSection),
      matching: find.byType(ListTile),
    );

    // The text as typed: the field shows it and the search runs on it. A
    // profile build ignores the test's keyboard, and a phone's own would
    // cover the results.
    Future<void> type(String text) async {
      tester.widget<TextField>(field.first).controller!.text = text;
      container.read(searchQueryProvider.notifier).change(text);
      await tester.pump();
    }

    // The search's answer as the section reads it: the user stands in
    // Annecy, so the request's `near` is Annecy. Null while it runs.
    OnlineMatches? answer(String text) => container
        .read(onlineSearchProvider(text, near: _annecy, language: _locale, pois: true))
        .value;
    // The list of results, not the field's own Scrollable above it.
    final list = find.descendant(
      of: find.descendant(of: find.byType(MapSearch), matching: find.byType(ListView)),
      matching: find.byType(Scrollable),
    );

    // A search from an empty field: the section of the previous one is
    // gone, so what is found is this search's. Typed again twice when the
    // API lists no establishment, as a user would. Whether it listed some:
    // an empty answer is said, and the tour goes on. The section may stand
    // below the towns and the places, out of the built part of the list.
    final missing = <String>[];
    Future<bool> search(String text) async {
      for (var attempt = 0; attempt < 3; attempt++) {
        await type('');
        await settle(tester, Duration(milliseconds: 800 + 4000 * attempt));
        final camera = container.read(viewportProvider);
        debugPrint('SEARCH $text from ${camera?.center} at zoom ${camera?.zoom}');
        await type(text);
        await came(
          tester,
          () => tiles.evaluate().isNotEmpty || answer(text) != null,
          timeout: const Duration(seconds: 20),
        );
        final found = answer(text);
        if (tiles.evaluate().isNotEmpty || (found?.pois.pois.isNotEmpty ?? false)) {
          // The other sections and the pictograms settle.
          await settle(tester, const Duration(seconds: 3));
          return true;
        }
        debugPrint(
          'EMPTY $text (attempt ${attempt + 1}): '
          '${found == null ? 'no answer' : 'match ${found.pois.match.name}, offline ${found.offline}'}',
        );
      }
      debugPrint('NO MATCH $text: no establishment listed');
      missing.add(text);
      return false;
    }

    if (await search('coiffeur')) await shot(tester, '01-recherche-coiffeur');
    if (await search('pizzeria annecy')) await shot(tester, '02-recherche-pizzeria-annecy');
    if (await search('Annecy')) {
      await shot(tester, '03-recherche-annecy');
      // The list scrolled to the establishments, under the town and the
      // places.
      final section = find.text(t.poi.searchSection);
      await tester.scrollUntilVisible(section, 200, scrollable: list.first);
      await Scrollable.ensureVisible(tester.element(section), alignment: 0.05);
      await shot(tester, '03-recherche-annecy-commerces');
    }

    for (final card in _cards) {
      if (!await search(card.query)) continue;
      if (tiles.evaluate().isEmpty) {
        await tester.scrollUntilVisible(tiles.first, 200, scrollable: list.first);
      }
      final labels = [for (final k in card.kinds) t.poiKind(k)];
      bool ofKind(ListTile tile) {
        final line = (tile.subtitle as Text?)?.data ?? '';
        return labels.any((l) => line == l || line.startsWith('$l · '));
      }

      final candidates = tester.widgetList<ListTile>(tiles).where(ofKind).toList();
      if (candidates.isEmpty) {
        debugPrint('NO MATCH ${card.query}: no ${card.kinds.map((k) => k.code).join(' or ')}');
        missing.add(card.query);
        continue;
      }
      final prefer = card.prefer?.toLowerCase();
      final chosen =
          candidates
              .where(
                (c) =>
                    prefer != null &&
                    ((c.title as Text?)?.data ?? '').toLowerCase().contains(prefer),
              )
              .firstOrNull ??
          candidates.first;
      final tile = find.byWidget(chosen);
      await tester.ensureVisible(tile);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(tile);
      await until(
        tester,
        () => container.read(selectionProvider) is PoiSelection,
        what: 'the page of ${card.query}',
      );
      final id = (container.read(selectionProvider)! as PoiSelection).feature.id;
      await until(
        tester,
        () => container.read(poiPageProvider(id)).value?.value != null,
        what: 'the page of $id',
      );
      final kind = (container.read(selectionProvider)! as PoiSelection).feature.kind;
      debugPrint(
        'WRITE $_tag-fiches.txt ${card.name} | ${card.query} | '
        '${(chosen.title as Text?)?.data} | ${t.poiKind(kind)} | $id',
      );
      // The map's move, the pin, the photo.
      await settle(tester, const Duration(seconds: 5));
      await shot(tester, card.name);
      // What the page says of this kind, under "Still there?": the sheet
      // of a phone raised, the list scrolled to it.
      final details = find.byType(PoiDetails);
      await tester.drag(details.first, const Offset(0, -300), warnIfMissed: false);
      await settle(tester, const Duration(seconds: 1));
      final gone = find.descendant(of: details, matching: find.text(t.poi.gone));
      if (gone.evaluate().isNotEmpty) {
        await Scrollable.ensureVisible(tester.element(gone.first), alignment: 0.02);
      }
      await shot(tester, '${card.name}-suite');
      if (card.reviews) {
        final title = find.descendant(of: details, matching: find.text(t.place.reviewsTitle));
        await tester.scrollUntilVisible(
          title,
          250,
          scrollable: find.descendant(of: details, matching: find.byType(Scrollable)).first,
        );
        await settle(tester, const Duration(seconds: 1));
        await Scrollable.ensureVisible(tester.element(title), alignment: 0.02);
        await until(
          tester,
          () => !container.read(pointReviewsProvider(id)).isLoading,
          what: 'the reviews of $id',
        );
        await shot(tester, '${card.name}-avis');
      }
      container.read(mapFlowProvider.notifier).select(null);
      await settle(tester, const Duration(seconds: 2));
    }
    if (missing.isNotEmpty) debugPrint('MISSING ${missing.join(', ')}');
    debugPrint('TOUR DONE');
  });
}
