import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// A walk through the main screens of the real app, for screenshots. Every
/// `SHOT <name>` line it prints is a moment to capture; the host script
/// (`tool/screens/capture.py`) takes the screen then. Run through that
/// script, which sets the screen size, the language and the theme, and
/// points the app at an API (real data) or at the demo.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'tour');

/// Start from an empty device: the first launch, its download included.
const _fresh = bool.fromEnvironment('LUNAWAY_TOUR_FRESH');

/// Where the region shots are taken, and a town to search for.
const _area = LatLng(45.90, 6.13);
const _search = 'annec';

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Awaits [work] while pumping frames: a camera move waits for the next frame,
/// which the test binding only produces when the test pumps.
Future<void> pumping(WidgetTester tester, Future<void> work) async {
  var done = false;
  unawaited(work.whenComplete(() => done = true));
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  // The host captures the screen when it reads this line.
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

/// The most telling place near [around]: a named motorhome area with
/// services, else any named place.
PlaceSummary pickPlace(List<PlaceSummary> places, LatLng around) {
  int score(PlaceSummary p) =>
      (p.name == null ? 0 : 4) +
      (p.kind == PlaceKind.motorhomeArea ? 3 : 0) +
      (p.overnight.nightOk ? 2 : 0) +
      p.services.length.clamp(0, 4);
  final near = places.where((p) => p.position.distanceTo(around) < 25000).toList()
    ..sort((a, b) {
      final s = score(b).compareTo(score(a));
      return s != 0 ? s : a.position.distanceTo(around).compareTo(b.position.distanceTo(around));
    });
  return near.isEmpty ? places.first : near.first;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_fresh && !demoBuild) return;
    final dir = await CacheDatabase.directory();
    const prefix = demoBuild ? 'lunaway_demo' : 'lunaway';
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${dir.path}/$prefix.sqlite$suffix');
      if (file.existsSync()) file.deleteSync();
    }
  });

  testWidgets('screens tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLocale(AppLocaleUtils.parse(_locale));
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    await settings.setFilter(PlaceFilter.none);
    final t = AppLocaleUtils.parse(_locale).buildSync();

    if (_fresh) {
      await settle(tester, const Duration(seconds: 2));
      await shot(tester, 'first-launch');
    }
    // Wait for the sync to finish (the whole region on a fresh device) and
    // for the map.
    final ready = DateTime.now().add(const Duration(minutes: 4));
    while ((container.read(syncStateProvider).value?.completedAt == null ||
            container.read(viewportProvider) == null) &&
        DateTime.now().isBefore(ready)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final map = container.read(mapControllerProvider)!;
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'map-france');

    await pumping(tester, map.moveTo(_area, zoom: 9.6));
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'map-region');

    await pumping(tester, map.moveTo(_area, zoom: 12.4));
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'map-close');

    final places = await container.read(mapPlacesProvider.future);
    final place = pickPlace(places, _area);
    container.read(selectionProvider.notifier).select(PlaceSelection(place.id));
    await pumping(tester, map.moveTo(place.position, zoom: 13.5));
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'place');

    // Saved: the message floats above the place's actions, never over them.
    // On a device that kept an earlier tour's favourites, the place is
    // already saved: the tap then takes it out, with its own message.
    final save = find.text(t.place.save).hitTestable();
    await tester.tap(
      save.evaluate().isNotEmpty ? save.first : find.text(t.place.saved).hitTestable().first,
    );
    await shot(tester, 'place-saved');
    ScaffoldMessenger.of(tester.element(find.byType(PlaceDetailsBody).first)).hideCurrentSnackBar();

    // Further down the details: services, hours, coordinates, sources.
    await tester.drag(
      find.byType(PlaceDetailsBody).first,
      const Offset(0, -600),
      warnIfMissed: false,
    );
    await shot(tester, 'place-details');

    // A point the user long-pressed, brought into view as the app does.
    const point = LatLng(45.899200, 6.129400);
    container.read(selectionProvider.notifier).select(const PointSelection(point));
    await pumping(tester, map.moveTo(point));
    await shot(tester, 'point');
    container.read(selectionProvider.notifier).select(null);
    await settle(tester, const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField).first, _search);
    await shot(tester, 'search');
    await tester.enterText(find.byType(TextField).first, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, const Duration(seconds: 1));

    await tester.tap(find.text(t.map.filters).first);
    await shot(tester, 'filters');
    Navigator.of(tester.element(find.text(t.filters.title).last)).pop();
    await settle(tester, const Duration(seconds: 1));

    // Favourites: a few real places in the default list, and a second list.
    final repo = container.read(favoritesRepositoryProvider);
    final near = places
        .where((p) => p.name != null && p.position.distanceTo(_area) < 40000)
        .take(4);
    for (final p in near) {
      await repo.addToDefault(p);
    }
    await repo.createList(_locale == 'fr' ? 'Bretagne 2027' : 'Brittany 2027');
    await tester.tap(find.text(t.nav.favorites).last);
    await shot(tester, 'favorites');

    await container.read(vehicleRepositoryProvider).save(Vehicle.typical(VehicleType.campervan));
    await tester.tap(find.text(t.nav.profile).last);
    await shot(tester, 'profile');

    debugPrint('TOUR DONE');
  });
}
