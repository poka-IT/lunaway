import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/places/application/places_providers.dart';

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

  testWidgets('a list the network fails says there is no connection', (tester) async {
    final online = FakeOnlinePlaces(samplePlaces)..offline = true;
    await pumpLunaway(tester, places: const [], online: online);
    // Past the retries of the list's own provider.
    await settleShort(tester, const Duration(seconds: 40));
    expect(find.text('Pas de connexion : la liste a besoin du réseau.'), findsOneWidget);
    expect(find.text("La liste n'a pas pu s'afficher."), findsNothing);
  });
}
