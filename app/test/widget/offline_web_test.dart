import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';

import '../helpers/fake_browser.dart';
import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The app that reads its places from the API, as the web always does,
/// with nothing on the device.
Future<FakeOnlinePlaces> _pumpOnline(
  WidgetTester tester, {
  bool? reachable = true,
  FakeBrowser? browser,
}) async {
  final online = FakeOnlinePlaces(samplePlaces);
  await pumpLunaway(
    tester,
    places: const [],
    online: online,
    reachable: reachable,
    overrides: [if (browser != null) browserProvider.overrideWithValue(browser)],
  );
  return online;
}

const _searchOffline = 'Pas de connexion : la recherche a besoin du réseau.';

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await settleShort(tester);
}

void main() {
  testWidgets('a search the network fails says there is no connection at once', (tester) async {
    final online = await _pumpOnline(tester);
    online.offline = true;
    await _search(tester, 'Peupliers');
    expect(find.text(_searchOffline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'no wait on retries');
  });

  testWidgets('a search the network does not carry is given up after a few seconds', (
    tester,
  ) async {
    final online = await _pumpOnline(tester);
    online.holdSearches = Completer<void>();
    await _search(tester, 'Peupliers');
    expect(find.text(_searchOffline), findsNothing, reason: 'still on its way');
    await settleShort(tester, searchWait);
    expect(find.text(_searchOffline), findsOneWidget);
    expect(online.aborted, contains('Peupliers'));
  });

  testWidgets('a browser offline: the search asks nothing and says so', (tester) async {
    final online = await _pumpOnline(
      tester,
      reachable: false,
      browser: FakeBrowser(tester, online: false),
    );
    await _search(tester, 'Peupliers');
    expect(find.text(_searchOffline), findsOneWidget);
    expect(online.requests.where((r) => r.startsWith('searchAll')), isEmpty);
  });

  testWidgets('the basemap host down while the browser is online: the search still asks', (
    tester,
  ) async {
    final online = await _pumpOnline(tester, reachable: false, browser: FakeBrowser(tester));
    await _search(tester, 'Peupliers');
    expect(find.text(_searchOffline), findsNothing);
    expect(online.requests, contains('searchAll:Peupliers'));
    expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
  });

  testWidgets('a failed search is asked again on a tap, once the network is back', (tester) async {
    final online = await _pumpOnline(tester);
    online.offline = true;
    await _search(tester, 'Peupliers');
    expect(find.text(_searchOffline), findsOneWidget);
    online.offline = false;
    await tester.tap(find.text('Réessayer'));
    await settleShort(tester);
    expect(find.text(_searchOffline), findsNothing);
    expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
  });

  testWidgets('a list the network fails says at once there is no connection, asking once', (
    tester,
  ) async {
    final online = FakeOnlinePlaces(samplePlaces)..offline = true;
    await pumpLunaway(tester, places: const [], online: online, settle: false);
    // Under two seconds from the start of the app, retries included.
    await settleShort(tester, const Duration(milliseconds: 1500));
    expect(find.text('Pas de connexion : la liste a besoin du réseau.'), findsOneWidget);
    expect(find.text("La liste n'a pas pu s'afficher."), findsNothing);
    final asked = online.requests.length;
    await settleShort(tester, const Duration(seconds: 10));
    expect(online.requests, hasLength(asked), reason: "no retry behind the user's back");
  });

  testWidgets('a list offline asks again by itself when the browser is back', (tester) async {
    final online = FakeOnlinePlaces(samplePlaces)..offline = true;
    final app = await pumpLunaway(tester, places: const [], online: online, reachable: false);
    expect(find.text('Pas de connexion : la liste a besoin du réseau.'), findsOneWidget);
    online.offline = false;
    final asked = online.requests.length;
    app.container(tester).read(basemapReachabilityProvider.notifier).assume(reachable: true);
    await settleShort(tester, const Duration(seconds: 2));
    expect(online.requests.length, greaterThan(asked));
    expect(find.text('Pas de connexion : la liste a besoin du réseau.'), findsNothing);
    expect(find.byType(PlaceTile), findsWidgets);
  });

  testWidgets('a place never opened shows offline what its pin said, and that the rest needs '
      'the network, in under two seconds', (tester) async {
    const rest = "Pas de connexion : le reste de la fiche s'affichera au retour du réseau.";
    final online = FakeOnlinePlaces(samplePlaces)..offline = true;
    final app = await pumpLunaway(
      tester,
      size: const Size(1280, 900),
      places: const [],
      online: online,
      reachable: false,
    );
    // A tap on the pin: the tile said its name, kind and night.
    app
        .container(tester)
        .read(mapFlowProvider.notifier)
        .select(PlaceSelection(campsite.id, hint: campsite.summary));
    await tester.pump(const Duration(milliseconds: 1500));
    final page = find.byType(PlaceDetails);
    expect(find.descendant(of: page, matching: find.text(rest)), findsOneWidget);
    expect(
      find.descendant(of: page, matching: find.text('Camping des Peupliers (démo)')),
      findsOneWidget,
    );
    expect(find.descendant(of: page, matching: find.text('Nuit autorisée')), findsOneWidget);

    // The network back: the page fills by itself.
    online.offline = false;
    app.container(tester).read(basemapReachabilityProvider.notifier).assume(reachable: true);
    await settleShort(tester, const Duration(seconds: 2));
    expect(find.text(rest), findsNothing);
    expect(find.byType(PlaceDetailsBody), findsOneWidget);
  });

  for (final (street, title, line) in [
    (null, 'Parking · Saint-Malo', null),
    ('4 Rue de la Gare', 'Parking · Rue de la Gare', 'Saint-Malo'),
  ]) {
    testWidgets('offline, an unnamed place titled "$title" says its kind and town once', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces)..offline = true;
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 900),
        places: const [],
        online: online,
        reachable: false,
      );
      final hint = PlaceSummary(
        id: unnamedParking.id,
        kind: unnamedParking.kind,
        lat: unnamedParking.lat,
        lon: unnamedParking.lon,
        overnight: unnamedParking.overnight,
        city: 'Saint-Malo',
        street: street,
      );
      app
          .container(tester)
          .read(mapFlowProvider.notifier)
          .select(PlaceSelection(hint.id, hint: hint));
      await tester.pump(const Duration(milliseconds: 1500));
      final page = find.byType(PlaceDetails);
      expect(find.descendant(of: page, matching: find.text(title)), findsOneWidget);
      expect(
        find.descendant(of: page, matching: find.text('Saint-Malo')),
        line == null ? findsNothing : findsOneWidget,
        reason: 'the line under the title says what the title does not, as the read card does',
      );
    });
  }
}
