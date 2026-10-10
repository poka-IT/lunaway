import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;
import 'package:maplibre_gl/maplibre_gl.dart' show MapLibreMap;

/// The map of a phone that has not been given the position yet, on a real
/// engine (the Android emulator): the country's view and its invitation,
/// the position granted from the system's own prompt, a map that follows
/// it on screen and under the finger, and the list at street zoom.
///
/// Run through the host script, which takes the permission back first,
/// gives the emulator a position, answers the system prompt when this test
/// prints `ALLOW LOCATION`, and compares the shots a `CHECK MOVED` line
/// names: on Android a pause and resume of the app (the prompt) left the
/// map frozen on its last frame while its engine moved, which only the
/// screen shows.
///
///     python3 tool/screens/capture.py --device android:emulator-5554 --size 1080x1920 \
///         --test integration_test/location_grant_test.dart --api https://api.lunaway.net \
///         --revoke-location --location 44.4846,4.6806 --out ../data/tmp/grant
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'grant');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');

/// Where the emulator says the device is (`--location`): Viviers.
const _here = LatLng(44.4846, 4.6806);

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Awaits [work] while pumping frames: a camera move waits for the next
/// frame, which the test binding only produces when the test pumps.
Future<void> pumping(WidgetTester tester, Future<void> work) async {
  var done = false;
  unawaited(work.whenComplete(() => done = true));
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [ready] holds, for [within] at most; false when it never did.
Future<bool> until(WidgetTester tester, bool Function() ready, {required Duration within}) async {
  final end = DateTime.now().add(within);
  while (!ready() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return ready();
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the position granted at the system prompt, then the street', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLocale(AppLocale.fr);
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    final t = AppLocale.fr.buildSync();
    expect(
      await until(
        tester,
        () => container.read(mapControllerProvider) != null,
        within: const Duration(seconds: 30),
      ),
      isTrue,
      reason: 'the map got ready',
    );
    final map = container.read(mapControllerProvider)!;

    // The country, before anything is known of the user: the button says
    // what it does.
    await pumping(tester, map.moveTo(const LatLng(46.6, 2.5), zoom: 5.2));
    await settle(tester, const Duration(seconds: 3));
    expect(container.read(userLocationProvider), isNull);
    expect(find.text(t.map.aroundMe), findsOneWidget);
    await shot(tester, 'pays');

    // The explanation, then the system's prompt, which the host answers.
    await tester.tap(find.text(t.map.aroundMe));
    expect(
      await until(
        tester,
        () => find.text(t.location.allow).evaluate().isNotEmpty,
        within: const Duration(seconds: 10),
      ),
      isTrue,
      reason: 'the explanation comes before the prompt',
    );
    await tester.tap(find.text(t.location.allow));
    await settle(tester, const Duration(milliseconds: 800));
    debugPrint('ALLOW LOCATION');
    expect(
      await until(
        tester,
        () => container.read(userLocationProvider) != null,
        within: const Duration(seconds: 30),
      ),
      isTrue,
      reason: 'a position came once granted',
    );
    expect(container.read(userLocationProvider)!.distanceTo(_here), lessThan(100));
    // The camera comes to the user, and the screen shows it.
    expect(
      await until(
        tester,
        () => (container.read(viewportProvider)?.zoom ?? 0) > PlaceTiles.countryZoom,
        within: const Duration(seconds: 15),
      ),
      isTrue,
      reason: 'the map went to the position',
    );
    expect(find.text(t.map.aroundMe), findsNothing, reason: 'located: the round button');
    await shot(tester, 'autorise');
    debugPrint('CHECK MOVED $_tag-pays $_tag-autorise');

    // The map still takes the finger.
    final before = container.read(viewportProvider)!.center;
    await tester.timedDrag(
      find.byType(MapLibreMap),
      const Offset(0, -300),
      const Duration(milliseconds: 600),
      warnIfMissed: false,
    );
    expect(
      await until(
        tester,
        () => container.read(viewportProvider)!.center.distanceTo(before) > 200,
        within: const Duration(seconds: 10),
      ),
      isTrue,
      reason: 'a drag moved the camera',
    );
    await shot(tester, 'glisse');
    debugPrint('CHECK MOVED $_tag-autorise $_tag-glisse');

    // At street zoom the list keeps its names: MapLibre Native also holds
    // the tiles four zooms below, whose places carry none. Whatever a touch
    // opened on the way is closed, so the list shows.
    container.read(mapFlowProvider.notifier).select(null);
    await pumping(tester, map.moveTo(const LatLng(44.48230, 4.68016), zoom: 16.2));
    expect(
      await until(tester, () {
        final view = container.read(viewportProvider);
        return view != null &&
            view.zoom > 16 &&
            container.read(placesInViewProvider).covers(view) &&
            container.read(placesInViewProvider).places.isNotEmpty;
      }, within: const Duration(seconds: 20)),
      isTrue,
      reason: 'the map reported the places of the street',
    );
    final report = container.read(placesInViewProvider).places;
    expect(
      report.where((p) => p.name == null && p.city == null),
      isEmpty,
      reason: 'every place of the street with its name or its town',
    );
    await shot(tester, 'rue');
    debugPrint('places at street zoom: ${[for (final p in report) p.name ?? p.city]}');
  });
}
