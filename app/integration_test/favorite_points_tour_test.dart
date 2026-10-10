import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// The points saved outside the places, on the real app and the real map:
/// an address the search finds, saved in one gesture, named and given a
/// note in the lists' sheet; a bare point of the map; both in the
/// favourites, and marked on the map. Every `SHOT <name>` line is a screen
/// for `tool/screens/capture.py`, run against an API that finds addresses.
/// The address is a ministry's, the one the address tests use.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'favoris');

/// A bare point in Annecy, near the lake.
const _lake = LatLng(45.8992, 6.1294);

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

/// Waits until [finder] finds something, or [limit].
Future<void> until(
  WidgetTester tester,
  Finder finder, {
  Duration limit = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(limit);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved points tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLocale(AppLocaleUtils.parse(_locale));
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    final t = AppLocaleUtils.parse(_locale).buildSync();
    final end = DateTime.now().add(const Duration(minutes: 2));
    while (container.read(mapControllerProvider) == null && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final map = container.read(mapControllerProvider)!;
    // A device that kept an earlier run's points starts without them.
    final repo = container.read(favoritesRepositoryProvider);
    for (final list in await repo.watchLists().first) {
      for (final e in await repo.watchPoints(list.id).first) {
        await repo.removePointEverywhere(e.point.id);
      }
    }
    await settle(tester, const Duration(seconds: 2));

    // An address the search finds: its card, and Save where a place has it.
    await tester.enterText(find.byType(TextField).first, '20 avenue de segur paris');
    final address = find.text('20 Avenue de Ségur');
    await until(tester, address);
    await tester.tap(address.first);
    // The street map comes in its tiles.
    await settle(tester, const Duration(seconds: 10));
    await shot(tester, '01-adresse');

    final bar = find.byType(PointActionBar);
    await tester.tap(find.descendant(of: bar, matching: find.text(t.place.save)));
    await shot(tester, '02-adresse-enregistree');

    // The lists' sheet: the name the user gives it, a note, the lists.
    await tester.longPress(find.descendant(of: bar, matching: find.text(t.place.saved)));
    await settle(tester, const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const Key('point-name')),
      _locale == 'fr' ? 'Rendez-vous Ségur' : 'Meeting at Ségur',
    );
    await tester.enterText(
      find.byKey(const Key('point-note')),
      _locale == 'fr'
          ? 'Entrée côté jardin, se garer avenue de Saxe'
          : 'Garden entrance, park on avenue de Saxe',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(tester, '03-feuille');
    await tester.tap(find.text(t.common.done));
    await settle(tester, const Duration(seconds: 2));
    await shot(tester, '04-adresse-nommee');

    // A bare point of the map, saved as the point of the day.
    container.read(selectionProvider.notifier).select(const PointSelection(_lake));
    await pumping(tester, map.moveTo(_lake, zoom: 15));
    await settle(tester, const Duration(seconds: 3));
    await tester.tap(
      find.descendant(of: find.byType(PointActionBar), matching: find.text(t.place.save)),
    );
    await shot(tester, '05-point-enregistre');
    container.read(selectionProvider.notifier).select(null);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).hideCurrentSnackBar();
    await settle(tester, const Duration(seconds: 2));

    // The favourites: the places and the points of the list.
    await tester.tap(find.text(t.nav.favorites).hitTestable().last);
    await shot(tester, '06-favoris');

    // Back on the map: the saved points marked, the address open.
    await tester.tap(find.text(_locale == 'fr' ? 'Rendez-vous Ségur' : 'Meeting at Ségur'));
    await settle(tester, const Duration(seconds: 4));
    await pumping(tester, map.moveTo(const LatLng(48.8507, 2.3086), zoom: 15));
    await shot(tester, '07-carte-adresse-ouverte');
    container.read(selectionProvider.notifier).select(null);
    await pumping(tester, map.moveTo(const LatLng(48.8507, 2.3086), zoom: 14));
    await shot(tester, '08-carte-marque');
    debugPrint('TOUR DONE');
  });
}
