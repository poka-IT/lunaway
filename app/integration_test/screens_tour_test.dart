import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;
import 'package:path_provider/path_provider.dart';

/// A walk through the main screens of the real app, for screenshots. Every
/// `SHOT <name>` line it prints is a moment to capture; the host script
/// (`tool/screens/capture.py`) takes the window then. Run through that
/// script, which sets the window size, the language and the theme.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'tour');

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
  // The host captures the window when it reads this line.
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await getApplicationSupportDirectory();
    for (final name in [
      'lunaway_demo.sqlite',
      'lunaway_demo.sqlite-wal',
      'lunaway_demo.sqlite-shm',
    ]) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) file.deleteSync();
    }
  });

  testWidgets('screens tour', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = _theme == 'dark'
        ? Brightness.dark
        : Brightness.light;
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    await container.read(settingsProvider.notifier).setLocale(AppLocaleUtils.parse(_locale));
    final t = AppLocaleUtils.parse(_locale).buildSync();

    // Wait for the demo sync and the map.
    final ready = DateTime.now().add(const Duration(seconds: 60));
    while ((container.read(placeCountProvider).value != 420 ||
            container.read(viewportProvider) == null) &&
        DateTime.now().isBefore(ready)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final map = container.read(mapControllerProvider)!;
    await container.read(settingsProvider.notifier).setFilter(PlaceFilter.initial);
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'map-france');

    // Around Annecy, where the demo has a few dozen places.
    await pumping(tester, map.moveTo(const LatLng(45.92, 6.13), zoom: 10.2));
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'map-region');

    // A place with photos and reviews.
    final places = await container.read(mapPlacesProvider.future);
    final rated = places.where((p) => p.ratingCount > 30 && p.city == 'Annecy').toList()
      ..sort((a, b) => b.ratingCount.compareTo(a.ratingCount));
    final place = (rated.isEmpty ? places.first : rated.first);
    container.read(selectionProvider.notifier).select(PlaceSelection(place.id));
    await pumping(tester, map.moveTo(place.position, zoom: 13));
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'place');

    // Further down the details: services, coordinates, reviews.
    await tester.drag(
      find.byType(PlaceDetailsBody).first,
      const Offset(0, -520),
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

    // Search.
    await tester.enterText(find.byType(TextField).first, 'ann');
    await shot(tester, 'search');
    await tester.enterText(find.byType(TextField).first, '');
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester, const Duration(seconds: 1));

    // Filters.
    await tester.tap(find.text(t.map.filters).first);
    await shot(tester, 'filters');
    Navigator.of(tester.element(find.text(t.filters.title).last)).pop();
    await settle(tester, const Duration(seconds: 1));

    // Favourites.
    final repo = container.read(favoritesRepositoryProvider);
    for (final p in places.take(4)) {
      await repo.addToDefault(p);
    }
    await repo.createList(_locale == 'fr' ? 'Bretagne 2027' : 'Brittany 2027');
    await tester.tap(find.text(t.nav.favorites).last);
    await shot(tester, 'favorites');

    // Profile.
    await tester.tap(find.text(t.nav.profile).last);
    await shot(tester, 'profile');

    debugPrint('TOUR DONE');
  });
}
