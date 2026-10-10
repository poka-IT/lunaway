import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/features/navigation/presentation/route_settings_section.dart';
import 'package:lunaway/features/places/application/place_external_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

import 'fixtures/listened.dart';

/// The scenes of the store and site screenshots (`docs/screenshots.md`),
/// against the real API, in the language the host asks for: the map around
/// Annecy and the view of France, a campsite's page with its photos and its
/// reviews, a search of an establishment, the filters, a route for a
/// low-profile motorhome with the places along it, what lies on the way,
/// the whole route with two stops, a guidance through a French danger zone
/// and one past an Italian speed camera, the voice's three modes, the
/// offline maps, the regions kept, the favourites with places and points,
/// the vehicle.
///
/// It sends no contribution and refuses a device with an account, before
/// any change: the favourites it adds would go to the account's lists. The
/// voice is a silent one that every language has, so no notice about a
/// missing voice shows on a device without it, and nothing is heard.
/// France's camera positions stay off, as by default. The vehicle, the
/// filters, the language, the theme, the guidance settings, the driving
/// aids and the regions kept are put back at the end, each on its own, and
/// the favourites it added are taken out; the last position and view stay
/// Annecy's. Built as the app and launched like it by
/// `tool/screens/capture.py --release --test
/// integration_test/store_tour_test.dart` (a release build of its own on
/// Android, `legal.p2p.lunaway.shots`).
///
/// A scene that fails prints `SCENE FAILED <name>` and the tour goes on
/// with the next one from the map, so one missing frame never costs the
/// others; the run then ends red.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'store');

/// The scenes to take, by name and comma separated; every scene when empty.
const _only = String.fromEnvironment('LUNAWAY_TOUR_ONLY');

/// A campsite of the lake's west shore, at Saint-Jorioz: Camping
/// International du Lac d'Annecy, the end of the route whose map draws the
/// places along it.
const _routePlaceId = '01a10f0e-2a5f-70f9-a1a0-a03fa2a3f83b';

/// The lake shore at Annecy, a public park: where the scenes stand.
const _here = LatLng(45.9006, 6.1291);

/// A motorhome area with services and shops around, at the south of the
/// lake: Aire de Camping Car Doussard, where the route goes.
const _placeId = '01a10f0e-2a68-7650-bd10-132ddc5c7e20';

/// A campsite above the town whose page has photos of an open source
/// (Wikimedia Commons) besides the external community source's, and many
/// reviews: Le Belvédère.
const _photoPlaceId = '01a10f0e-2a5f-70f9-a1a0-a07079af0ed3';

/// Two stops on the way to the area, along the lake.
const _stops = [
  RouteStop(position: LatLng(45.8636, 6.1410), label: 'Sevrier'),
  RouteStop(position: LatLng(45.8289, 6.1987), label: 'Duingt'),
];

/// Toward Chambéry by the N201, where France lists a danger zone about
/// 1.5 km after the start.
const _driveFrom = LatLng(45.6008, 5.9086);
const _driveTo = LatLng(45.5646, 5.9178);

/// Padua's ring road from Abano Terme, where Italy's fixed cameras stand
/// on the Corso Australia.
const _cameraFrom = LatLng(45.3700, 11.8200);
const _cameraTo = LatLng(45.4300, 11.9500);

/// A viewpoint over the lake, the Col de la Forclaz: a point of the map
/// saved with a name and a note.
const _viewpoint = LatLng(45.8126, 6.2470);

/// What a user of each language types and names.
typedef _Words = ({String search, String trip, String point, String note});

const _allWords = <String, _Words>{
  'fr': (
    search: 'fromagerie Annecy',
    trip: 'Alpes 2027',
    point: 'Vue sur le lac',
    note: 'Pique-nique, accès à pied',
  ),
  'en': (
    search: 'cheese shop Annecy',
    trip: 'Alps 2027',
    point: 'Lake view',
    note: 'Picnic, on foot',
  ),
  'de': (
    search: 'Käserei Annecy',
    trip: 'Alpen 2027',
    point: 'Blick auf den See',
    note: 'Picknick, zu Fuß erreichbar',
  ),
  'es': (
    search: 'quesería Annecy',
    trip: 'Alpes 2027',
    point: 'Vista al lago',
    note: 'Pícnic, acceso a pie',
  ),
  'it': (
    search: 'formaggeria Annecy',
    trip: 'Alpi 2027',
    point: 'Vista sul lago',
    note: 'Picnic, accesso a piedi',
  ),
  'nl': (
    search: 'kaaswinkel Annecy',
    trip: 'Alpen 2027',
    point: 'Uitzicht op het meer',
    note: 'Picknick, te voet bereikbaar',
  ),
};

final _Words _words = _allWords[_locale] ?? _allWords['en']!;

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<T> waitFor<T>(WidgetTester tester, Future<T> work) async {
  var done = false;
  Object? error;
  late T value;
  unawaited(
    work.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (error != null) throw TestFailure('$error');
  if (!done) throw TestFailure('timed out waiting for a result');
  return value;
}

/// A camera move, waited for a few seconds at most: on the iOS simulator
/// the engine does not always say when an animation ends.
Future<void> move(WidgetTester tester, Future<void> moving) async {
  var done = false;
  unawaited(moving.whenComplete(() => done = true));
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(
  WidgetTester tester,
  String name, {
  Duration before = const Duration(milliseconds: 1500),
}) async {
  await settle(tester, before);
  // The host captures the screen when it reads this line.
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

Future<void> until(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The device's position for the scenes, then the drives the guidance
/// scenes give it: one fix every [pace].
final class _TourFeed implements LocationFeed {
  List<Fix>? fixes;
  Duration pace = const Duration(milliseconds: 250);

  /// Whether the drive has handed out its fixes to the end.
  bool drained = false;

  /// The start of a route: the drive's first fix, else [_here], where the
  /// device stands for the scenes (asking the device would raise the
  /// system's permission dialog on iOS).
  @override
  Future<Fix?> current() async =>
      fixes?.first ?? Fix(position: _here, accuracyM: 5, at: DateTime.now().toUtc(), speedMps: 0);

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    final drive = fixes ?? [Fix(position: _here, accuracyM: 5, at: DateTime.now().toUtc())];
    drained = false;
    for (final f in drive) {
      await Future<void>.delayed(pace);
      yield Fix(
        position: f.position,
        accuracyM: f.accuracyM,
        at: DateTime.now().toUtc(),
        courseDeg: f.courseDeg,
        speedMps: f.speedMps,
      );
    }
    drained = true;
  }
}

/// No notification permission asked in the middle of the captures.
final class _NoNotifications implements NotificationAccess {
  const new();

  @override
  Future<bool> wouldAsk() async => false;

  @override
  Future<void> ask() async {}
}

/// A voice every language has and nobody hears: the guidance shows its
/// full mode without a notice about a voice to install (an emulator has
/// few), and a run in a shared room stays quiet.
final class _SilentVoice implements VoiceOutput {
  const new();

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async => VoiceReadiness.ready;

  @override
  bool get chimes => false;

  @override
  Future<bool> say(String text, {bool chime = false}) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<bool> installVoices() async => false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store tour', (tester) async {
    final feed = _TourFeed();
    await app.runLunaway(
      overrides: [
        locationFeedProvider.overrideWithValue(feed),
        notificationAccessProvider.overrideWithValue(const _NoNotifications()),
        voiceOutputProvider.overrideWithValue(const _SilentVoice()),
      ],
    );
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    final language = RouteLanguage.of(_locale);

    // A device with an account is refused before anything changes: the
    // tour's favourites would go to the account's lists.
    await until(
      tester,
      () => container.read(accountControllerProvider) is! AccountLoading,
      what: 'the account',
    );
    if (container.read(accountControllerProvider) is SignedIn) {
      throw TestFailure('the store tour runs on a device without an account');
    }

    // Everything the tour changes, read before the first change, so the
    // end puts it back whatever fails.
    final settings = container.read(settingsProvider.notifier);
    final filterBefore = container.read(placeFilterProvider);
    final localeBefore = container.read(settingsProvider).localeCode;
    final themeBefore = container.read(settingsProvider).theme;
    final routeStore = container.read(routeSettingsStoreProvider);
    final routeBefore = await waitFor(tester, routeStore.load());
    final aids = container.read(drivingAidsSettingsControllerProvider.notifier);
    final aidsBefore = await waitFor(
      tester,
      container.read(drivingAidsSettingsControllerProvider.future),
    );
    final vehicles = container.read(vehicleRepositoryProvider);
    final vehicleBefore = await waitFor(tester, vehicles.watch().first);
    final kept = container.read(keptRegionsControllerProvider.notifier);
    final keptBefore = await waitFor(tester, container.read(keptRegionsControllerProvider.future));
    final favorites = container.read(favoritesRepositoryProvider);
    final added = _Added();
    final failed = <String>[];

    try {
      await settings.setLocale(AppLocaleUtils.parse(_locale));
      await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
      await settings.setFilter(PlaceFilter.none);
      // The guidance settings from a clean slate: the places along a route
      // drawn as pictograms (the photos of the marks would show the
      // external community source's), the legend already seen, the full
      // voice.
      await waitFor(
        tester,
        routeStore.save(
          const NavigationSettings(
            legendSeen: true,
            guidancePlaces: GuidancePlaces(look: GuidanceLook.pictograms),
          ),
        ),
      );
      container.invalidate(routeSettingsControllerProvider);
      // France's camera positions stay off: zones only in France.
      if (aidsBefore.exactIn.contains('FR')) {
        await waitFor(tester, aids.setExactPositions('FR', on: false));
      }

      await until(
        tester,
        () =>
            container.read(mapControllerProvider) != null &&
            container.read(viewportProvider) != null,
        what: 'the map',
      );
      // The places of Auvergne-Rhône-Alpes on the device: the route's map
      // draws those near it, the favourites take a few.
      final regionStates = container.listen(regionStatesProvider, (_, _) {});
      await waitFor(tester, kept.add({'FR-ARA'}));
      await until(
        tester,
        () => regionStates.read().value?['FR-ARA']?.completedAt != null,
        what: 'the places of the region',
        timeout: const Duration(minutes: 5),
      );
      regionStates.close();
      final map = container.read(mapControllerProvider)!;
      final router = container.read(routerProvider);
      final flow = container.read(mapFlowProvider.notifier);
      container.read(poiLayerProvider.notifier).clear();
      flow.select(null);

      // A low-profile motorhome on gazole, the one of docs/screenshots.md.
      await waitFor(
        tester,
        vehicles.save(
          Vehicle.typical(VehicleType.lowProfile)
              .copyWith(fuel: () => FuelType.diesel, consumptionL100: () => 11),
        ),
      );
      container.read(userLocationProvider.notifier).update(_here);
      // The blue dot of the device, which the emulator or the simulator
      // places at [_here]. The host grants the permission: on Android when
      // it reads this line, on the simulator before the launch (`simctl
      // privacy`), since no test can answer the system's dialog there.
      debugPrint('GRANT LOCATION');
      await settle(tester, const Duration(seconds: 2));
      await move(tester, map.locateUser());

      // Back to the map with nothing open and no filter, after a scene that
      // failed half way.
      Future<void> home() async {
        final navigator = Navigator.maybeOf(
          tester.element(find.byType(Scaffold).first),
          rootNavigator: true,
        );
        navigator?.popUntil((route) => route.isFirst);
        router.go(AppRoutes.map);
        flow.select(null);
        await settings.setFilter(PlaceFilter.none);
        container.read(searchQueryProvider.notifier).change('');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester, const Duration(seconds: 1));
      }

      Future<void> scene(String name, Future<void> Function() body) async {
        // A run of a few scenes only, to take one again.
        if (_only.isNotEmpty && !_only.split(',').contains(name)) return;
        try {
          await body();
        } on Object catch (e, st) {
          failed.add(name);
          debugPrint('SCENE FAILED $name: $e\n$st');
          guidanceStop(container);
          feed.fixes = null;
          await home();
        }
      }

      // The map as a traveller looking for the night sets it: the places
      // where the night is allowed or tolerated.
      const night = PlaceFilter(overnight: {OvernightStatus.allowed, OvernightStatus.tolerated});
      await scene('01-map', () async {
        await settings.setFilter(night);
        // The lake and the campsites of its shores below the user's dot.
        await move(tester, map.moveTo(const LatLng(45.874, 6.16), zoom: 11.2));
        await settle(tester, const Duration(seconds: 4));
        // A fresh fix: the dot of a position some time old turns grey.
        debugPrint('GRANT LOCATION');
        await settle(tester, const Duration(seconds: 2));
        await shot(tester, '01-map');
      });

      await scene('02-france', () async {
        await settings.setFilter(night);
        await move(tester, map.fitBounds(GeoBounds.metropolitanFrance));
        await settle(tester, const Duration(seconds: 6));
        await shot(tester, '02-france');
      });
      await settings.setFilter(PlaceFilter.none);

      // A campsite's page: its photos of an open source in view, then
      // its reviews.
      await scene('03-place', () async {
        flow.select(const PlaceSelection(_photoPlaceId));
        final place = await waitFor(
          tester,
          container.read(placesRepositoryProvider).watchPlace(_photoPlaceId).first,
        );
        if (place != null) await move(tester, map.moveTo(place.position, zoom: 14));
        final strip = find.descendant(
          of: find.byType(PlacePhotos),
          matching: find.byType(Scrollable),
        );
        await until(
          tester,
          () =>
              strip.evaluate().isNotEmpty &&
              (container
                      .read(placeExternalProvider(_photoPlaceId))
                      .value
                      ?.content
                      .photos
                      .isNotEmpty ??
                  false),
          what: 'the photos',
        );
        await settle(tester, const Duration(seconds: 2));
        // The strip from the first photo of an open source: the external
        // community source's come first.
        final photos = container.read(placeExternalProvider(_photoPlaceId)).value!.content.photos;
        final firstOpen = photos.indexWhere((p) => p.sourceId != extcomSourceId);
        // A strip of the external source's photos alone stays out of the
        // stores (docs/screenshots.md): no shot rather than that one.
        if (firstOpen < 0) throw TestFailure('no photo of an open source on the page');
        if (firstOpen > 0) {
          final scrollable = tester.state<ScrollableState>(strip.first);
          final position = scrollable.position;
          // Each photo is as wide as its tile plus the gap; read from the
          // strip's extent, which holds the photos and the tile to add one.
          final perPhoto =
              (position.maxScrollExtent + position.viewportDimension) / (photos.length + 1);
          position.jumpTo((firstOpen * perPhoto).clamp(0, position.maxScrollExtent));
          await settle(tester, const Duration(seconds: 1));
          // Then exactly from the left edge of the first open source's
          // photo, whose credit sits a gap inside it.
          final open = find.descendant(
            of: find.byType(PlacePhotos),
            matching: find.textContaining('Wikimedia'),
          );
          if (open.evaluate().isEmpty) throw TestFailure('the open source photo not in view');
          final left = open
              .evaluate()
              .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)).left)
              .reduce((a, b) => a < b ? a : b);
          final stripLeft = tester.getRect(strip.first).left;
          position.jumpTo(
            (position.pixels + left - 8 - stripLeft).clamp(0, position.maxScrollExtent),
          );
        }
        await settle(tester, const Duration(seconds: 2));
        // The page up until the strip shows whole above the actions.
        final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final below = tester.getRect(strip.first).bottom - (height - 140);
        if (below > 0) {
          // A drag, not a jump of the list: on a phone the drag lifts the
          // sheet, its title kept in view, where a jump would scroll the
          // title away.
          await tester.drag(find.byType(PlaceDetailsBody).first, Offset(0, -below - 20));
        }
        await settle(tester, const Duration(seconds: 4));
        await shot(tester, '03-place');
      });

      // Further down the same page: a review in another language,
      // translated. A scene of its own: the translation server may be
      // away while the page is not.
      await scene('04-reviews', () async {
        if (find.byType(PlaceDetailsBody).evaluate().isEmpty) {
          flow.select(const PlaceSelection(_photoPlaceId));
          await until(
            tester,
            () => find.byType(PlaceDetailsBody).evaluate().isNotEmpty,
            what: 'the page',
          );
          await settle(tester, const Duration(seconds: 3));
        }
        final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final body = find
            .descendant(of: find.byType(PlaceDetailsBody), matching: find.byType(Scrollable))
            .first;
        final translate = find.descendant(
          of: find.byType(PlaceDetailsBody),
          matching: find.text(t.translation.translate),
        );
        final original = find.text(t.translation.showOriginal);
        final unsupported = find.text(t.translation.unsupported);
        // The reviews in order, until one translates: a language the
        // server does not translate (Swedish) says so, and its button goes.
        for (var tries = 0; tries < 5 && original.evaluate().isEmpty; tries++) {
          // Down the page until a review offers its translation (`first`
          // of an empty finder throws: the plain finder is asked).
          for (var i = 0; i < 60 && translate.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(body, const Offset(0, -300), warnIfMissed: false);
            await settle(tester, const Duration(milliseconds: 700));
          }
          // In the middle of the page: at its foot the bar of actions
          // would take the touch.
          await Scrollable.ensureVisible(tester.element(translate.first), alignment: 0.5);
          await settle(tester, const Duration(seconds: 1));
          final refused = unsupported.evaluate().length;
          await tester.tap(translate.first);
          await until(
            tester,
            () => original.evaluate().isNotEmpty || unsupported.evaluate().length > refused,
            what: 'the translation',
            timeout: const Duration(seconds: 40),
          );
        }
        if (original.evaluate().isEmpty) throw TestFailure('no review translated');
        await settle(tester, const Duration(seconds: 1));
        // Set, not dragged: a drag's fling would carry the page past it.
        final lift = tester.getRect(original.first).bottom - height * 0.78;
        final page = tester.state<ScrollableState>(body).position;
        page.jumpTo((page.pixels + lift).clamp(0, page.maxScrollExtent));
        await settle(tester, const Duration(seconds: 3));
        await shot(tester, '04-reviews');
        flow.select(null);
        await settle(tester, const Duration(seconds: 1));
      });

      // An establishment found by its kind and its town.
      await scene('05-search', () async {
        flow.select(null);
        await move(tester, map.moveTo(_here, zoom: 13));
        await settle(tester, const Duration(seconds: 2));
        final field = find.descendant(of: find.byType(MapSearch), matching: find.byType(TextField));
        // The text as typed: a release build ignores the test's keyboard,
        // and a phone's own would cover the results.
        tester.widget<TextField>(field.first).controller!.text = _words.search;
        container.read(searchQueryProvider.notifier).change(_words.search);
        await tester.pump();
        await until(
          tester,
          () =>
              container
                  .read(
                    onlineSearchProvider(_words.search, near: _here, language: _locale, pois: true),
                  )
                  .value
                  ?.pois
                  .pois
                  .isNotEmpty ??
              false,
          what: 'the establishments',
          timeout: const Duration(seconds: 40),
        );
        await settle(tester, const Duration(seconds: 3));
        await shot(tester, '05-search');
        final found = container
            .read(onlineSearchProvider(_words.search, near: _here, language: _locale, pois: true))
            .value!
            .pois
            .pois
            .first;
        foundPoi = poiDraft(t, found.feature, address: found.address);
        tester.widget<TextField>(field.first).controller!.text = '';
        container.read(searchQueryProvider.notifier).change('');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester, const Duration(seconds: 1));
      });

      // The filters with a choice made: the night allowed, water.
      await scene('06-filters', () async {
        await move(tester, map.moveTo(_here, zoom: 11.3));
        await settings.setFilter(
          const PlaceFilter(overnight: {OvernightStatus.allowed}, amenities: {Amenity.water}),
        );
        await settle(tester, const Duration(seconds: 2));
        await tester.tap(find.text(t.map.filters).first);
        await shot(tester, '06-filters', before: const Duration(seconds: 3));
        Navigator.of(tester.element(find.text(t.filters.title).last)).pop();
        await settings.setFilter(PlaceFilter.none);
        await settle(tester, const Duration(seconds: 1));
      });

      // The route for the motorhome to the area, from the lake shore, the
      // places along it; what lies on the way; then the trip with two
      // stops, driven a little, and the whole of it.
      final place = await waitFor(
        tester,
        container.read(placesRepositoryProvider).watchPlace(_placeId).first,
      );
      final target = RouteTarget(
        destination: place?.position ?? const LatLng(45.7891, 6.2174),
        label: place?.name ?? 'Doussard',
        placeId: _placeId,
      );
      final start = find.text(t.navigation.preview.start);
      bool startable() {
        final button = find.ancestor(of: start, matching: find.bySubtype<ButtonStyleButton>());
        return button.evaluate().isNotEmpty &&
            tester.widget<ButtonStyleButton>(button.first).onPressed != null;
      }

      // A route close enough for its map to draw the places along it
      // (from zoom 10): to a campsite of the lake's west shore.
      await scene('07-route', () async {
        final campsite = await waitFor(
          tester,
          container.read(placesRepositoryProvider).watchPlace(_routePlaceId).first,
        );
        final near = RouteTarget(
          destination: campsite?.position ?? const LatLng(45.8301, 6.1777),
          label: campsite?.name ?? 'Saint-Jorioz',
          placeId: _routePlaceId,
        );
        unawaited(router.push(NavigationRoutes.previewOf(near)));
        await until(tester, () => start.evaluate().isNotEmpty && startable(), what: 'the route');
        // The places near the route and the map's tiles.
        await settle(tester, const Duration(seconds: 10));
        await shot(tester, '07-route');
        router.pop();
        await settle(tester, const Duration(seconds: 2));
      });

      await scene('08-on-the-way', () async {
        unawaited(router.push(NavigationRoutes.previewOf(target)));
        await until(tester, () => start.evaluate().isNotEmpty && startable(), what: 'the route');
        await settle(tester, const Duration(seconds: 2));

        final open = find.widgetWithText(TextButton, t.navigation.onTheWay.title);
        if (open.evaluate().isNotEmpty) {
          await tester.ensureVisible(open.first);
          await settle(tester, const Duration(milliseconds: 500));
          await tester.tap(open.first);
        } else {
          // Below the routes on a phone, out of the sheet's built part when
          // a long name or a second route pushes it down: opened as its
          // button does, the preview's map left in view.
          final route = container.read(routePreviewControllerProvider(target)).value!.route!;
          final page = tester.element(find.text(t.navigation.preview.recommended).first);
          unawaited(openPreviewOnTheWay(page, target, route));
        }
        await settle(tester, const Duration(seconds: 2));
        final sleep = find.widgetWithText(ChoiceChip, t.navigation.onTheWay.categories.sleep);
        await until(tester, () => sleep.evaluate().isNotEmpty, what: 'the chips on the way');
        await tester.ensureVisible(sleep.first);
        await settle(tester, const Duration(milliseconds: 300));
        await tester.tap(sleep.first);
        // The fuel list the sheet opened on has its own "Add" buttons: the
        // sleep chip chosen first, then its list loaded.
        await until(
          tester,
          () => tester.widget<ChoiceChip>(sleep.first).selected,
          what: 'the sleep chip chosen',
        );
        await settle(tester, const Duration(milliseconds: 500));
        await until(
          tester,
          () =>
              find.text(t.navigation.onTheWay.loading).evaluate().isEmpty &&
              find.textContaining(t.navigation.fuel.add).evaluate().isNotEmpty,
          what: 'the places to sleep on the way',
          timeout: const Duration(seconds: 40),
        );
        await shot(tester, '08-on-the-way', before: const Duration(seconds: 3));
        Navigator.of(tester.element(find.text(t.navigation.onTheWay.title).last)).maybePop();
        await settle(tester, const Duration(seconds: 2));
      });

      await scene('11-stops', () async {
        if (start.evaluate().isEmpty) {
          unawaited(router.push(NavigationRoutes.previewOf(target)));
          await until(tester, () => start.evaluate().isNotEmpty, what: 'the route');
        }
        container.read(routeStopsControllerProvider(target).notifier).set(_stops);
        await settle(tester, const Duration(seconds: 1));
        await until(tester, startable, what: 'the route through the stops');
        final route = container.read(routePreviewControllerProvider(target)).value!.route!;
        feed
          ..fixes = drive(
            route.line,
            stepM: 13,
            start: DateTime.now().toUtc(),
            tick: const Duration(seconds: 1),
            speedMps: 13,
          ).take(90).toList()
          ..pace = const Duration(milliseconds: 120);
        await tester.tap(start);
        await until(
          tester,
          () => container.read(guidanceControllerProvider) != null,
          what: 'the guidance',
        );
        await until(tester, () => feed.drained, what: 'the first kilometre');
        await settle(tester, const Duration(seconds: 2));
        await tester.tap(find.byTooltip(t.navigation.guidance.overview));
        await shot(tester, '11-stops', before: const Duration(seconds: 4));
        guidanceStop(container);
        feed.fixes = null;
        await home();
      });

      // A guidance through a danger zone, the limit beside the speed: a
      // real route of the API, driven by a simulated position below the
      // limit.
      Future<void> guide(
        LatLng from,
        LatLng to,
        String label,
        bool Function(GuidanceSession) shown,
      ) async {
        final vehicle = await waitFor(tester, vehicles.watch().first);
        final plan = await waitFor(
          tester,
          container
              .read(routeServiceProvider)
              .route(
                RouteRequest(
                  origin: from,
                  destination: to,
                  vehicle: checkVehicle(vehicle).profile!,
                  avoid: const AvoidOptions(),
                  language: language,
                ),
              ),
        );
        final route = plan.routes.first;
        feed
          ..fixes = drive(
            route.line,
            stepM: 13,
            start: DateTime.now().toUtc(),
            tick: const Duration(seconds: 1),
            // 47 km/h: under every limit of the way, so the speed reads
            // plain.
            speedMps: 13,
          )
          ..pace = const Duration(milliseconds: 120);
        final guidance = container.read(guidanceControllerProvider.notifier);
        await waitFor(
          tester,
          guidance.start(
            plan: plan,
            routeIndex: route.index,
            target: RouteTarget(destination: to, label: label),
            words: TranslatedWording(t, DistanceUnits.metric),
          ),
        );
        unawaited(router.push(NavigationRoutes.guidance));
        GuidanceSession? session() => container.read(guidanceControllerProvider);
        await until(
          tester,
          () => session() != null && shown(session()!),
          what: 'the alert ahead',
          timeout: const Duration(minutes: 3),
        );
        feed.pace = const Duration(seconds: 1);
      }

      await scene('09-guidance', () async {
        await guide(
          _driveFrom,
          _driveTo,
          'Chambéry',
          (s) => s.aids.alert?.kind == EnforcementKind.zone && (s.aids.alert?.aheadM ?? 0) > 150,
        );
        await shot(tester, '09-guidance', before: const Duration(milliseconds: 1200));
        guidanceStop(container);
        feed.fixes = null;
        await home();
      });

      await scene('10-camera', () async {
        await guide(
          _cameraFrom,
          _cameraTo,
          'Padova',
          (s) =>
              s.aids.alert?.kind == EnforcementKind.camera &&
              s.aids.alert?.limitKmh != null &&
              (s.aids.alert?.aheadM ?? 0) > 150 &&
              (s.aids.alert?.aheadM ?? 1e9) < 700,
        );
        await shot(tester, '10-camera', before: const Duration(milliseconds: 1200));
        guidanceStop(container);
        feed.fixes = null;
        await home();
      });

      // The voice's three modes and France's camera positions, off, in
      // the profile's guidance settings.
      await scene('12-voice', () async {
        router.go(AppRoutes.profile);
        await settle(tester, const Duration(seconds: 2));
        final section = find.byType(RouteSettingsSection);
        final list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text(t.navigation.settings.voice),
          300,
          scrollable: list,
        );
        await settle(tester, const Duration(milliseconds: 500));
        // The voice's choice near the top, France's positions below it.
        final top = tester.getRect(find.text(t.navigation.settings.voice)).top;
        await tester.drag(list, Offset(0, -(top - 110)), warnIfMissed: false);
        await settle(tester, const Duration(seconds: 1));
        expect(section, findsOneWidget);
        await shot(tester, '12-voice');
      });

      // The offline maps from their top: the places of the region kept,
      // updated today, then the maps.
      await scene('13-offline', () async {
        router.go(AppRoutes.offlineMaps);
        await settle(tester, const Duration(seconds: 4));
        await shot(tester, '13-offline');
      });

      // The regions whose places the device keeps, France unfolded.
      await scene('14-regions', () async {
        router.go(AppRoutes.offlineMaps);
        await settle(tester, const Duration(seconds: 1));
        unawaited(showRegionPicker(tester.element(find.byType(Scaffold).first)));
        await until(
          tester,
          () => find.text(t.regions.wholeFrance).evaluate().isNotEmpty,
          what: 'the regions',
        );
        await settle(tester, const Duration(seconds: 1));
        await tester.tap(find.byTooltip(t.regions.showFrance));
        await settle(tester, const Duration(seconds: 2));
        await shot(tester, '14-regions');
        Navigator.of(tester.element(find.byType(RegionPicker))).pop();
        await settle(tester, const Duration(seconds: 1));
      });

      // Favourites: a few real places of the area, the cheese shop the
      // search found, a viewpoint saved from the map with a note, and a
      // trip list.
      await scene('15-favorites', () async {
        router.go(AppRoutes.map);
        await move(tester, map.moveTo(_here, zoom: 11.3));
        await settle(tester, const Duration(seconds: 2));
        final repo = favorites;
        final list = await waitFor(tester, repo.defaultListId());
        final near = (await waitFor(tester, listened(container, mapPlacesProvider.future)))
            .where((p) {
              final d = p.position.distanceTo(_here);
              return p.name != null &&
                  p.overnight == OvernightStatus.allowed &&
                  d > 3000 &&
                  d < 30000;
            })
            .take(3);
        for (final p in near) {
          if (!(await waitFor(tester, repo.watchListsOf(p.id).first)).contains(list)) {
            await waitFor(tester, repo.addToDefault(p));
            added.places.add(p.id);
          }
        }
        final viewpoint = SavedPoint.normalized(
          id: savedPointIdAt(_viewpoint),
          kind: SavedPointKind.point,
          name: _words.point,
          fallback: _words.point,
          position: _viewpoint,
          note: _words.note,
        );
        for (final point in [?foundPoi, viewpoint]) {
          if (await waitFor(tester, repo.watchPoint(point.id).first) == null) {
            await waitFor(tester, repo.addPointToDefault(point));
            added.points.add(point.id);
          }
        }
        final lists = await waitFor(tester, repo.watchLists().first);
        if (!lists.any((l) => l.name == _words.trip)) {
          added.lists.add(await waitFor(tester, repo.createList(_words.trip)));
        }
        router.go(AppRoutes.favorites);
        await shot(tester, '15-favorites', before: const Duration(seconds: 3));
      });

      await scene('16-vehicle', () async {
        router.go(AppRoutes.profile);
        await settle(tester, const Duration(seconds: 1));
        final editor = showVehicleEditor(tester.element(find.byType(Scaffold).first));
        await shot(tester, '16-vehicle');
        Navigator.of(tester.element(find.byType(VehicleEditor))).pop();
        await waitFor(tester, editor);
      });
    } finally {
      // Each part put back on its own: one that fails leaves the others to
      // be put back.
      Future<void> restore(String what, Future<void> Function() work) async {
        try {
          await waitFor(tester, work());
        } on Object catch (e) {
          debugPrint('NOT RESTORED $what: $e');
        }
      }

      guidanceStop(container);
      feed.fixes = null;
      await restore('the favourites', () async {
        final list = await favorites.defaultListId();
        for (final id in added.places) {
          await favorites.remove(list, id);
        }
        for (final id in added.points) {
          await favorites.removePointEverywhere(id);
        }
        for (final id in added.lists) {
          await favorites.deleteList(id);
        }
      });
      await restore(
        'the vehicle',
        () => vehicleBefore == null ? vehicles.clear() : vehicles.save(vehicleBefore),
      );
      await restore('the guidance settings', () async {
        await routeStore.save(routeBefore);
        container.invalidate(routeSettingsControllerProvider);
      });
      if (aidsBefore.exactIn.contains('FR')) {
        await restore('the camera positions', () => aids.setExactPositions('FR', on: true));
      }
      // A device that had chosen no region yet keeps the one the tour took:
      // the choice has no way back to "none chosen".
      if (keptBefore != null && !keptBefore.contains('FR-ARA')) {
        await restore('the regions kept', () => kept.remove({'FR-ARA'}));
      }
      await restore('the filters', () => settings.setFilter(filterBefore));
      await restore('the theme', () => settings.setTheme(themeBefore));
      await restore(
        'the language',
        () => settings.setLocale(localeBefore == null ? null : AppLocaleUtils.parse(localeBefore)),
      );
      container.read(routerProvider).go(AppRoutes.map);
    }
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE ${failed.isEmpty ? 'all scenes' : 'failed: ${failed.join(' ')}'}');
    expect(failed, isEmpty);
  });
}

/// The cheese shop the search found, saved with the favourites.
SavedPoint? foundPoi;

/// What the tour added to the favourites, taken out at its end: only what
/// was not there before.
final class _Added {
  final places = <String>[];
  final points = <String>[];
  final lists = <int>[];
}

void guidanceStop(ProviderContainer container) {
  if (container.read(guidanceControllerProvider) != null) {
    container.read(guidanceControllerProvider.notifier).stop();
  }
}
