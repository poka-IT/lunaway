import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';

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
      expect(online.nears.toSet(), {
        searchAnchor(viewport.center),
      }, reason: 'the map centre on a grid of 0.05 degree, never the position');
      expect(online.nears, isNot(contains(many.first.position)));
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
      final app = await pumpLunaway(tester, places: const [], online: online, size: desktop);
      final container = app.container(tester);
      online.offline = true;
      await _settled(tester, container.read(nearbyPlacesPageProvider.notifier).loadMore());
      expect(container.read(nearbyPlacesPageProvider).value!.moreFailed, isTrue);
      expect(
        container.read(nearbyPlacesPageProvider).value!.places,
        hasLength(nearbyPageSize),
        reason: 'the rows shown stay',
      );
      online.offline = false;
      final retry = find.text("La suite de la liste n'a pas pu s'afficher. Réessayer");
      await tester.scrollUntilVisible(
        retry,
        400,
        scrollable: find.descendant(of: find.byType(NearbyList), matching: find.byType(Scrollable)),
      );
      await tester.tap(retry);
      await settleShort(tester);
      expect(
        container.read(nearbyPlacesPageProvider).value!.places.length,
        greaterThan(nearbyPageSize),
      );
    });

    testWidgets('a page asked before the map moved never lands on the list of the new view', (
      tester,
    ) async {
      final many = demoPlaces(count: 70, now: testNow);
      final online = FakeOnlinePlaces(many);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final container = app.container(tester);
      final before = container.read(nearbyPlacesPageProvider).value!;
      online.holdPages = Completer<void>();
      final more = container.read(nearbyPlacesPageProvider.notifier).loadMore();
      await tester.pump();
      // The map moves to another view while the next page is on its way.
      container
          .read(viewportProvider.notifier)
          .update(
            const MapViewport(
              bounds: GeoBounds(south: 45, west: 5, north: 46.5, east: 7),
              center: LatLng(45.75, 6),
              zoom: 8,
            ),
          );
      await tester.pump();
      online.holdPages!.complete();
      await _settled(tester, more);
      final after = container.read(nearbyPlacesPageProvider).value!;
      expect(after.query!.bounds, const GeoBounds(south: 45, west: 5, north: 46.5, east: 7));
      expect(
        after.places.length,
        lessThanOrEqualTo(nearbyPageSize),
        reason: 'the first page of the new view only, not the old list and its next page',
      );
      expect(before.query!.bounds, isNot(after.query!.bounds));
    });

    testWidgets('from the zoom of the names the list reads the tiles in view, without a request', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final map = FakeMap()
        ..viewport = const MapViewport(
          bounds: GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.25),
          center: LatLng(45.9, 6.15),
          zoom: 13,
        );
      final app = await pumpLunaway(tester, places: const [], online: online, map: map);
      // Before the map reports its first camera, the list covers France from
      // the API; from then on, nothing.
      online.requests.clear();
      const view = MapViewport(
        bounds: GeoBounds(south: 45.86, west: 6.06, north: 45.94, east: 6.24),
        center: LatLng(45.9, 6.15),
        zoom: 13.2,
      );
      map.lastProps!.onViewportChanged(view);
      await settleShort(tester);
      // The map reports the places of its tiles once they are in.
      map.lastProps!.onPlacesInView!([lakeArea.summary, campsite.summary], view.bounds);
      await settleShort(tester);
      final page = app.container(tester).read(nearbyPlacesPageProvider).value!;
      expect(page.places.map((p) => p.id), containsAll([lakeArea.id]));
      expect(
        page.places.every((p) => view.bounds.contains(p.position)),
        isTrue,
        reason: 'only the places inside the view',
      );
      expect(
        online.requests.where((r) => r.startsWith('page:')),
        isEmpty,
        reason: 'nothing of the view leaves the device beyond the tiles',
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

  testWidgets(
    'a report of another view keeps the list waiting, and a silent map leaves it to the API',
    (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final map = FakeMap()
        ..viewport = const MapViewport(
          bounds: GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.25),
          center: LatLng(45.9, 6.15),
          zoom: 13,
        );
      final app = await pumpLunaway(tester, places: const [], online: online, map: map);
      final container = app.container(tester);
      // A resize: the same centre and zoom, another view, and the report of
      // the previous one.
      map.lastProps!.onPlacesInView!([lakeArea.summary], map.viewport.bounds);
      await settleShort(tester);
      online.requests.clear();
      map.lastProps!.onViewportChanged(
        const MapViewport(
          bounds: GeoBounds(south: 45.8, west: 6.05, north: 46, east: 6.25),
          center: LatLng(45.9, 6.15),
          zoom: 13,
        ),
      );
      await settleShort(tester);
      expect(
        container.read(nearbyPlacesPageProvider).isLoading,
        isTrue,
        reason: 'waits for the map',
      );
      expect(online.requests, isEmpty);
      await settleShort(tester, nearbyReportWait);
      expect(online.requests.where((r) => r.startsWith('page:')), isNotEmpty);
      expect(container.read(nearbyPlacesPageProvider).isLoading, isFalse);
    },
  );

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
    testWidgets('a map that keeps moving does not put the download off', (tester) async {
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
      final container = app.container(tester);
      for (var i = 0; i < 5; i++) {
        container
            .read(viewportProvider.notifier)
            .update(
              MapViewport(
                bounds: GeoBounds(south: 45, west: 5 + i * 0.1, north: 46, east: 6 + i * 0.1),
                center: LatLng(45.5, 5.5 + i * 0.1),
                zoom: 9,
              ),
            );
        await settleShort(tester, const Duration(seconds: 1));
      }
      expect(states.whereType<SyncRunning>(), isNotEmpty, reason: '3 s after the first view');
    });

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
}
