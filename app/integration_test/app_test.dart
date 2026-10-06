import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/main.dart' as app;
import 'package:path_provider/path_provider.dart';

/// The real app on a real engine, in demo mode: the drift store, the sync
/// through the GraphQL client, the map engine of the platform.
///
///   fvm flutter test integration_test/app_test.dart -d macos --dart-define=LUNAWAY_DEMO=true
///
/// On macOS the map is a web view, which only draws in a window on screen;
/// set LUNAWAY_ALL_SPACES=1 when the current Space is a full-screen app.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $finder');
}

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // A fresh demo store and settings for every run.
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

  testWidgets('demo mode: sync, map, a place, copy, favourite, filter, language', (tester) async {
    await app.main();
    await pumpUntil(tester, find.byType(NavigationRail));

    // The first sync pages the demo API into drift.
    final container = containerOf(tester);
    final synced = DateTime.now().add(const Duration(seconds: 60));
    while (container.read(placeCountProvider).value != 420 && DateTime.now().isBefore(synced)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(container.read(placeCountProvider).value, 420);
    await pumpUntil(tester, find.byType(ListTile));

    // The real map engine reports its camera once its style has loaded.
    await pumpUntil(tester, find.byType(LunawayApp));
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (container.read(viewportProvider) == null && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      container.read(viewportProvider),
      isNotNull,
      reason: 'the map loaded and reported its viewport',
    );
    expect(container.read(mapControllerProvider), isNotNull);

    // Open the nearest place from the list beside the map.
    final firstRow = find.byType(ListTile).first;
    final title = tester
        .widget<Text>(find.descendant(of: firstRow, matching: find.byType(Text)).first)
        .data!;
    await tester.tap(firstRow);
    await pumpUntil(tester, find.text('Itinéraire'));
    expect(container.read(selectionProvider), isA<PlaceSelection>());
    expect(find.text(title), findsWidgets);

    // Save it.
    await tester.tap(find.text('Enregistrer'));
    await pumpUntil(tester, find.text('Enregistré'));

    // Copy the coordinates: the clipboard holds the decimal format.
    final details = find
        .descendant(of: find.byType(PlaceDetailsBody), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.byTooltip('Copier les coordonnées'),
      200,
      scrollable: details,
    );
    await tester.tap(find.byTooltip('Copier les coordonnées'));
    await pumpUntil(tester, find.textContaining('Copié :'));
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    expect(copied!.text, matches(RegExp(r'^-?\d+\.\d{6}, -?\d+\.\d{6}$')));

    // Back to the list, then filter on service points only.
    // Escape closes the details on a desktop.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(container.read(selectionProvider), isNull);
    await tester.tap(find.text('Filtres'));
    await pumpUntil(tester, find.byType(Dialog));
    await tester.tap(find.text('Tout effacer'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.text('Services').first);
    await pumpUntil(tester, find.textContaining('Afficher'));
    final apply = find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton));
    await tester.tap(apply);
    await pumpFor(tester, const Duration(seconds: 1));
    final places = container.read(mapPlacesProvider).value!;
    expect(places, isNotEmpty);
    expect(places.every((p) => p.kind.family.name == 'services'), isTrue);

    // The saved place is in the favourites.
    await tester.tap(find.text('Favoris'));
    await pumpUntil(tester, find.text('Mes favoris'));
    expect(find.text(title), findsWidgets);

    // Switch the language.
    await tester.tap(find.text('Profil'));
    await pumpUntil(tester, find.text('Langue'));
    await tester.tap(find.text('English'));
    await pumpUntil(tester, find.text('Language'));
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('420 places on this device'), findsOneWidget);

    // Leave the app in French and unfiltered for the next run.
    await tester.tap(find.text('Français'));
    await pumpFor(tester, const Duration(milliseconds: 500));
  });
}
