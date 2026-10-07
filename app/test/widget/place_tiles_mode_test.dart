import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// What the tile under a pin says of [p]: id, kind, night, name, position.
PlaceSummary _fromTile(Place p) => PlaceSummary(
  id: p.id,
  name: p.name,
  kind: p.kind,
  lat: p.lat,
  lon: p.lon,
  overnight: p.overnight,
);

/// [future] once the fake clock has moved on: what it waits for (a pause
/// in typing, a query of the in-memory database) runs on the test's timers.
Future<T> _settled<T>(WidgetTester tester, Future<T> future) async {
  await settleShort(tester);
  return await future;
}

/// What [provider] gives while something listens to it, as a screen
/// would: read alone, an automatically disposed provider goes before its
/// answer.
Future<T> _watched<T>(
  WidgetTester tester,
  TestApp app,
  ProviderListenable<Future<T>> provider,
) async {
  final sub = app.container(tester).listen(provider, (_, _) {});
  addTearDown(sub.close);
  return await _settled(tester, sub.read());
}

/// Every state the sync of [app] goes through from now on.
List<SyncStatus> _syncStates(TestApp app, WidgetTester tester) {
  final states = <SyncStatus>[];
  app.container(tester).listen(syncControllerProvider, (_, s) => states.add(s));
  return states;
}

void main() {
  group('online, the places come from the tiles', () {
    testWidgets('the map draws the tiles and none of the device, and no download card covers it', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        online: FakeOnlinePlaces(samplePlaces),
      );
      final props = app.map.lastProps!;
      expect(props.placeTiles, isNotNull);
      expect(props.placeTiles!.tileJsonUrl, endsWith('/places/tiles.json'));
      expect(props.places, isEmpty, reason: 'nothing read from the device for the map');
      expect(find.text("Aucun lieu sur cet appareil pour l'instant"), findsNothing);
    });

    testWidgets("a quick filter becomes the tiles' filter at once", (tester) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        online: FakeOnlinePlaces(samplePlaces),
      );
      await tester.ensureVisible(find.text('Gratuit'));
      await tester.tap(find.text('Gratuit'));
      await settleShort(tester);
      expect(app.map.lastProps!.placeTiles!.filter.freeOnly, isTrue);
    });

    testWidgets('a tapped pin opens with what its tile said, then the place itself', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces)..hold = Completer<void>();
      final app = await pumpLunaway(tester, places: const [], online: online);
      app.map.lastProps!.onPlaceTap(lakeArea.id, hint: _fromTile(lakeArea));
      await settleShort(tester);
      expect(find.text('Aire du Lac Bleu (démo)'), findsWidgets, reason: 'the name from the tile');
      expect(find.text('Nuit autorisée'), findsNothing, reason: 'the rest is still on its way');
      expect(app.map.lastProps!.selectedPlace?.id, lakeArea.id, reason: 'the pin is drawn at once');
      expect(online.requests, contains('place:${lakeArea.id}'));
      online.hold!.complete();
      await settleShort(tester);
      expect(find.text('Nuit autorisée'), findsWidgets, reason: 'the place itself, from the API');
    });

    testWidgets('a place opened once shows again offline from its copy', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final reader = app.container(tester).read(placeReaderProvider);
      expect((await _settled(tester, reader.read(campsite.id)))?.name, campsite.name);
      online.offline = true;
      expect(
        (await _settled(tester, reader.read(campsite.id)))?.name,
        campsite.name,
        reason: 'the copy',
      );
      expect(
        online.requests.where((r) => r == 'place:${campsite.id}'),
        hasLength(1),
        reason: 'a fresh copy is not asked again',
      );
    });

    testWidgets("the list asks the API a page at a time, from the map's centre, never the user", (
      tester,
    ) async {
      final many = demoPlaces(count: 70, now: testNow);
      final online = FakeOnlinePlaces(many);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final container = app.container(tester);
      container.read(userLocationProvider.notifier).update(many.first.position);
      await settleShort(tester);
      final viewport = container.read(viewportProvider)!;
      expect(online.nears, isNotEmpty);
      expect(online.nears.toSet(), {viewport.center}, reason: 'the position is never sent');
      final page = container.read(nearbyPlacesPageProvider).value!;
      expect(page.places, hasLength(nearbyPageSize));
      expect(page.total, many.where((p) => viewport.bounds.contains(p.position)).length);
      expect(find.textContaining('${page.total} lieux ici'), findsOneWidget);
      await _settled(tester, container.read(nearbyPlacesPageProvider.notifier).loadMore());
      expect(online.requests, contains('page:$nearbyPageSize'));
      expect(container.read(nearbyPlacesPageProvider).value!.places, hasLength(2 * nearbyPageSize));
    });

    testWidgets('the list says when the next page failed, and asks again on a tap', (tester) async {
      final many = demoPlaces(count: 70, now: testNow);
      final online = FakeOnlinePlaces(many);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final container = app.container(tester);
      online.offline = true;
      await _settled(tester, container.read(nearbyPlacesPageProvider.notifier).loadMore());
      expect(container.read(nearbyPlacesPageProvider).value!.moreFailed, isTrue);
      expect(
        container.read(nearbyPlacesPageProvider).value!.places,
        hasLength(nearbyPageSize),
        reason: 'the rows shown stay',
      );
    });

    testWidgets('the search asks the API when the device holds no place', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final results = await _watched(tester, app, searchResultsProvider('Peupliers').future);
      expect(results.places.map((p) => p.id), [campsite.id]);
      expect(online.requests, contains('search:Peupliers'));
    });

    testWidgets('the search reads the device when it holds places, without a request', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(tester, online: online);
      final results = await _watched(tester, app, searchResultsProvider('Peupliers').future);
      expect(results.places.map((p) => p.id), [campsite.id]);
      expect(online.requests.where((r) => r.startsWith('search:')), isEmpty);
    });

    testWidgets('the filters count what the view holds, as the API counts it', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final count = await _watched(
        tester,
        app,
        filterPreviewCountProvider(const PlaceFilter(families: {KindFamily.campsites})).future,
      );
      expect(count, 1);
    });
  });

  group('a device that keeps no places (the web)', () {
    testWidgets('never syncs, and its profile says nothing of a download', (tester) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        online: FakeOnlinePlaces(samplePlaces),
        neverSynced: true,
        overrides: [keepsPlacesProvider.overrideWithValue(false)],
        settle: false,
      );
      final states = _syncStates(app, tester);
      await settleShort(tester, const Duration(seconds: 2));
      expect(states.whereType<SyncRunning>(), isEmpty);
      await _settled(tester, app.container(tester).read(syncControllerProvider.notifier).sync());
      expect(states.whereType<SyncRunning>(), isEmpty, reason: 'not even when asked');
      await tester.tap(find.text('Profil'));
      await settleShort(tester);
      expect(find.text('Données hors ligne'), findsNothing);
    });
  });

  group('a phone online', () {
    testWidgets('downloads its regions behind the map, after its first view', (tester) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        online: FakeOnlinePlaces(samplePlaces),
        neverSynced: true,
        syncStartDelays: (
          afterMap: const Duration(seconds: 3),
          atLatest: const Duration(seconds: 15),
        ),
        settle: false,
      );
      final states = _syncStates(app, tester);
      await settleShort(tester, const Duration(seconds: 2));
      expect(states.whereType<SyncRunning>(), isEmpty, reason: 'the map first');
      await settleShort(tester, const Duration(seconds: 2));
      expect(states.whereType<SyncRunning>(), isNotEmpty);
    });
  });

  test('the props of a place from the tiles carry its id', () {
    const props = PlaceSummary(
      id: 'x',
      kind: PlaceKind.parking,
      lat: 1,
      lon: 2,
      overnight: OvernightStatus.unknown,
    );
    expect(
      LunaMapProps(
        style: '{}',
        dark: false,
        initialCenter: const LatLng(0, 0),
        initialZoom: 1,
        places: const [],
        selectedPlace: props,
        onPlaceTap: (_, {hint}) {},
        onLongPress: (_) {},
        onViewportChanged: (_) {},
        onMapReady: (_) {},
      ).selectedId,
      'x',
    );
  });
}
