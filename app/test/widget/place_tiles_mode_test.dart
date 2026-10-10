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
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/filters_sheet.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// What the tile under a pin says of [p]: id, kind, night, name, position.
PlaceSummary _fromTile(Place p, {double? rating, List<DayRange>? season}) => PlaceSummary(
  id: p.id,
  name: p.name,
  kind: p.kind,
  lat: p.lat,
  lon: p.lon,
  overnight: p.overnight,
  ratingForFilters: rating,
  openingSeason: season,
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

    testWidgets(
      "the list asks the API a page at a time, from the user's cell, never their position",
      (tester) async {
        final many = demoPlaces(count: 70, now: testNow);
        final online = FakeOnlinePlaces(many);
        final app = await pumpLunaway(tester, places: const [], online: online);
        final container = app.container(tester);
        final viewport = container.read(viewportProvider)!;
        expect(online.nears.toSet(), {
          searchAnchor(viewport.center),
        }, reason: 'not located yet: the map centre on a grid of 0.05 degree');
        online.nears.clear();
        const user = LatLng(45.8742, 6.1612);
        container.read(userLocationProvider.notifier).update(user);
        await settleShort(tester);
        expect(online.nears.toSet(), {
          searchAnchor(user),
        }, reason: 'the user in view: their position on the same grid');
        expect(online.nears, isNot(contains(user)));
        final page = container.read(nearbyPlacesPageProvider).value!;
        expect(page.places, hasLength(nearbyPageSize));
        expect(page.total, many.where((p) => viewport.bounds.contains(p.position)).length);
        expect(find.textContaining('${page.total} lieux ici'), findsOneWidget);
        await _settled(tester, container.read(nearbyPlacesPageProvider.notifier).loadMore());
        expect(online.requests, contains('page:$nearbyPageSize'));
        expect(online.nears.last, searchAnchor(user), reason: 'the next page from the same point');
        expect(
          container.read(nearbyPlacesPageProvider).value!.places,
          hasLength(2 * nearbyPageSize),
        );
      },
    );

    // The view of France the store captures show: the user at Annecy, the
    // map's centre in the Cher. A page ranked from the centre holds only
    // the places around it, which no sort on the device brings nearer.
    testWidgets('over France, the list starts with the place nearest the user, not the centre', (
      tester,
    ) async {
      final aroundCentre = [
        for (var i = 0; i < 2 * nearbyPageSize; i++)
          Place(
            id: 'centre-$i',
            name: 'Parking du Cher $i',
            kind: PlaceKind.parking,
            lat: 46.4 + (i % 8) * 0.05,
            lon: 2.3 + (i ~/ 8) * 0.05,
            overnight: OvernightStatus.allowed,
            updatedAt: DateTime.utc(2026, 9, 28),
          ),
      ];
      final online = FakeOnlinePlaces([...aroundCentre, lakeArea]);
      final app = await pumpLunaway(tester, places: const [], online: online, size: desktop);
      final container = app.container(tester);
      const user = LatLng(45.8742, 6.1612);
      container.read(userLocationProvider.notifier).update(user);
      await settleShort(tester);
      final page = container.read(nearbyPlacesPageProvider).value!;
      expect(page.places.first.id, lakeArea.id, reason: 'a few kilometres away, before the Cher');
      expect(page.total, aroundCentre.length + 1);
      final rows = find.descendant(of: find.byType(NearbyList), matching: find.byType(PlaceTile));
      expect(
        find.descendant(of: rows.first, matching: find.text(lakeArea.name!)),
        findsOneWidget,
        reason: 'the first row on screen',
      );
    });

    testWidgets("a user out of the view leaves the list ranked from the map's centre", (
      tester,
    ) async {
      final online = FakeOnlinePlaces(demoPlaces(count: 70, now: testNow));
      final app = await pumpLunaway(tester, places: const [], online: online);
      final container = app.container(tester);
      // Madrid, south of the view of France.
      container.read(userLocationProvider.notifier).update(const LatLng(40.4168, -3.7038));
      await settleShort(tester);
      expect(online.nears.toSet(), {searchAnchor(container.read(viewportProvider)!.center)});
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

    group('from the zoom of the names, the API answers at once when the tiles cannot', () {
      const view = MapViewport(
        bounds: GeoBounds(south: 45.86, west: 6.06, north: 45.94, east: 6.24),
        center: LatLng(45.9, 6.15),
        zoom: 13.2,
      );

      /// The list once the map rested on [view] and the test ran [then],
      /// short of the wait for a report: what the API was asked meanwhile.
      Future<(NearbyPage, List<String>)> listAfter(
        WidgetTester tester, {
        bool ready = true,
        void Function(FakeMap map)? then,
      }) async {
        final online = FakeOnlinePlaces(samplePlaces);
        final map = FakeMap()
          ..becomesReady = ready
          ..viewport = const MapViewport(
            bounds: GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.25),
            center: LatLng(45.9, 6.15),
            zoom: 13,
          );
        final app = await pumpLunaway(tester, places: const [], online: online, map: map);
        online.requests.clear();
        map.lastProps!.onViewportChanged(view);
        await settleShort(tester);
        then?.call(map);
        await settleShort(tester);
        final page = app.container(tester).read(nearbyPlacesPageProvider);
        expect(page.isLoading, isFalse, reason: 'answered well before $nearbyReportWait');
        return (page.value!, online.requests.where((r) => r.startsWith('page:')).toList());
      }

      /// The places of the sample data inside [view], as the tiles would
      /// have given them.
      final inView = [
        for (final p in samplePlaces)
          if (view.bounds.contains(p.position)) p.id,
      ];

      testWidgets('a tile that failed', (tester) async {
        final (page, asked) = await listAfter(
          tester,
          then: (map) =>
              map.lastProps!.onPlacesInView!([lakeArea.summary], view.bounds, failed: true),
        );
        expect(asked, isNotEmpty);
        expect(
          page.places.map((p) => p.id),
          unorderedEquals(inView),
          reason: "the API's page kept to the view, not the partial report",
        );
        expect(page.total, inView.length);
      });

      testWidgets('tiles that hold no place in the view', (tester) async {
        final (page, asked) = await listAfter(
          tester,
          then: (map) => map.lastProps!.onPlacesInView!(const [], view.bounds),
        );
        expect(asked, isNotEmpty);
        expect(page.places.map((p) => p.id), unorderedEquals(inView));
      });

      testWidgets('a map that never got ready', (tester) async {
        final (page, asked) = await listAfter(tester, ready: false);
        expect(asked, isNotEmpty);
        expect(page.places.map((p) => p.id), unorderedEquals(inView));
        // The screen gives up waiting for the map to locate the user.
        await settleShort(tester, const Duration(seconds: 11));
      });
    });

    testWidgets('the search asks the API when the device holds no place', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(tester, places: const [], online: online);
      final results = await _watched(tester, app, searchResultsProvider('Peupliers').future);
      expect(results.places.map((p) => p.id), [campsite.id]);
      expect(online.requests, contains('searchAll:Peupliers'));
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

    group('from the zoom of the names, the list and the filters count the same places', () {
      // Annecy at about zoom 14: the lake's area and a campsite in view; a
      // car park inside the API's box (the view widened to a grid of 0.05
      // degree) but outside the view.
      const view = MapViewport(
        bounds: GeoBounds(south: 45.89, west: 6.12, north: 45.91, east: 6.14),
        center: LatLng(45.9, 6.13),
        zoom: 14,
      );
      final lakeCampsite = Place(
        id: 'test-lake-campsite',
        name: 'Camping du Lac (démo)',
        kind: PlaceKind.campsite,
        lat: 45.905,
        lon: 6.135,
        overnight: OvernightStatus.allowed,
        address: const Address(city: 'Annecy'),
        updatedAt: DateTime.utc(2026, 9, 20),
        sources: [
          PlaceSource(source: osm, externalId: 'way/40', fetchedAt: DateTime.utc(2026, 10, 3)),
        ],
      );
      final boxParking = Place(
        id: 'test-box-parking',
        name: 'Parking du Semnoz (démo)',
        kind: PlaceKind.parking,
        lat: 45.93,
        lon: 6.145,
        overnight: OvernightStatus.tolerated,
        address: const Address(city: 'Annecy'),
        updatedAt: DateTime.utc(2026, 9, 20),
        sources: [
          PlaceSource(source: osm, externalId: 'way/41', fetchedAt: DateTime.utc(2026, 10, 3)),
        ],
      );

      Future<(TestApp, FakeOnlinePlaces)> atAnnecy(WidgetTester tester) async {
        final online = FakeOnlinePlaces([...samplePlaces, lakeCampsite, boxParking]);
        final map = FakeMap()..viewport = view;
        final app = await pumpLunaway(tester, places: const [], online: online, map: map);
        map.lastProps!.onViewportChanged(view);
        await settleShort(tester);
        // The tiles' report: every place of the view, the parking of the
        // wider box too since a tile reaches beyond the view.
        map.lastProps!.onPlacesInView!([
          for (final p in [lakeArea, lakeCampsite, boxParking]) _fromTile(p),
        ], view.bounds);
        await settleShort(tester);
        online.requests.clear();
        return (app, online);
      }

      testWidgets("the sheet's button tells the list's number", (tester) async {
        final (app, online) = await atAnnecy(tester);
        final page = app.container(tester).read(nearbyPlacesPageProvider).value!;
        expect(page.total, 2);
        final count = await _watched(
          tester,
          app,
          filterPreviewCountProvider(PlaceFilter.none).future,
        );
        expect(count, page.total, reason: 'one number for one view and one filter');
        expect(online.requests.where((r) => r.startsWith('page:')), isEmpty);
      });

      testWidgets('another filter is counted on the same places, on the device', (tester) async {
        final (app, online) = await atAnnecy(tester);
        final campsites = await _watched(
          tester,
          app,
          filterPreviewCountProvider(const PlaceFilter(families: {KindFamily.campsites})).future,
        );
        expect(campsites, 1);
        final nightOk = await _watched(
          tester,
          app,
          filterPreviewCountProvider(const PlaceFilter(overnight: nightPossible)).future,
        );
        expect(nightOk, 2);
        expect(online.requests.where((r) => r.startsWith('page:')), isEmpty);
        // Applied, the list says what the button said.
        await app
            .container(tester)
            .read(settingsProvider.notifier)
            .setFilter(const PlaceFilter(families: {KindFamily.campsites}));
        await settleShort(tester);
        expect(app.container(tester).read(nearbyPlacesPageProvider).value!.total, campsites);
      });

      // Two counts of one view once disagreed under a minimum rating: the
      // sheet offered to show 9 places, the list then held 7.
      testWidgets('a minimum rating is counted on the same places as the list', (tester) async {
        final (app, online) = await atAnnecy(tester);
        app.map.lastProps!.onPlacesInView!([
          _fromTile(lakeArea, rating: 4.5),
          _fromTile(lakeCampsite, rating: 3.5),
          _fromTile(boxParking, rating: 4.8),
        ], view.bounds);
        await settleShort(tester);
        const fourStars = PlaceFilter(minRating: 4);
        final count = await _watched(tester, app, filterPreviewCountProvider(fourStars).future);
        expect(
          count,
          1,
          reason: 'the lake area: the campsite is rated lower, the car park is out of view',
        );
        await app.container(tester).read(settingsProvider.notifier).setFilter(fourStars);
        await settleShort(tester);
        expect(app.container(tester).read(nearbyPlacesPageProvider).value!.total, count);
        expect(online.requests.where((r) => r.startsWith('page:')), isEmpty);
      });

      testWidgets('an opening filter is counted on the seasons the tiles carry', (tester) async {
        final (app, _) = await atAnnecy(tester);
        app.map.lastProps!.onPlacesInView!([
          _fromTile(lakeArea),
          _fromTile(lakeCampsite, season: const [DayRange(92, 305)]),
          _fromTile(boxParking, season: const [DayRange.wholeYear]),
        ], view.bounds);
        await settleShort(tester);
        const allYear = PlaceFilter(opening: AllYearOpening());
        expect(
          await _watched(tester, app, filterPreviewCountProvider(allYear).future),
          1,
          reason:
              'the lake area of unknown season; the campsite is seasonal, the car park out of view',
        );
        final october = PlaceFilter(
          opening: StayOpening(DateTime(2026, 10, 12), DateTime(2026, 10, 15)),
        );
        expect(await _watched(tester, app, filterPreviewCountProvider(october).future), 2);
      });
    });

    testWidgets('a dump station gives way to a place the map draws, not to one a filter hides', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        places: const [],
        online: FakeOnlinePlaces(samplePlaces),
      );
      final container = app.container(tester);
      // A motorhome area on the spot: the tiles' report holds it whatever
      // the filter.
      const area = PlaceSummary(
        id: 'area',
        kind: PlaceKind.motorhomeArea,
        lat: 45.9,
        lon: 6.16,
        overnight: OvernightStatus.allowed,
      );
      const station = PoiFeature(
        id: 'dump-here',
        kind: PoiKind.dumpStation,
        position: LatLng(45.9, 6.16028),
      );
      final sub = container.listen(poiLayerStateProvider, (_, _) {});
      addTearDown(sub.close);
      container.read(poisInViewProvider.notifier).report(const [station]);
      container.read(placesInViewProvider.notifier).report(const [
        area,
      ], const GeoBounds(south: 45.8, west: 6, north: 46, east: 6.3));
      await settleShort(tester);
      expect(sub.read().hidden, {'dump-here'}, reason: 'the area drawn stands for it');
      await container
          .read(settingsProvider.notifier)
          .setFilter(const PlaceFilter(families: {KindFamily.campsites}));
      await settleShort(tester);
      expect(sub.read().hidden, isEmpty, reason: 'the filter hides the area: the station shows');
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

    testWidgets('a minimum rating chosen in the sheet goes with the count asked of the API', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      await pumpLunaway(tester, places: const [], online: online);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final chip = find.text('4 et plus');
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find
            .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
            .first,
      );
      await tester.pump();
      await tester.tap(chip);
      await settleShort(tester);
      expect(online.filters.last.minRating, 4);
      expect(find.text('Afficher 2 lieux'), findsOneWidget);
    });

    testWidgets('all year chosen in the sheet goes with the count asked of the API', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      await pumpLunaway(tester, places: const [], online: online);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final chip = find.text("Toute l'année");
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find
            .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
            .first,
      );
      await tester.pump();
      await tester.tap(chip);
      await settleShort(tester);
      expect(online.filters.last.openDays, const [DayRange.wholeYear]);
      expect(find.text('Afficher 4 lieux'), findsOneWidget, reason: 'the seasonal campsite is out');
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

  testWidgets('offline, the filters count the places of the view, as the list does', (
    tester,
  ) async {
    final map = FakeMap()
      ..viewport = const MapViewport(
        bounds: GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.25),
        center: LatLng(45.9, 6.15),
        zoom: 12,
      );
    final app = await pumpLunaway(tester, places: samplePlaces, map: map);
    map.lastProps!.onViewportChanged(map.viewport);
    await settleShort(tester);
    final page = app.container(tester).read(nearbyPlacesPageProvider).value!;
    expect(page.total, 1, reason: "the lake's area, the one place of the view");
    final count = await _watched(tester, app, filterPreviewCountProvider(PlaceFilter.none).future);
    expect(count, page.total, reason: 'not every place of the device');
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

  group('one count, of the view shown', () {
    /// A view at street zoom beside the lake, without a place, whose box
    /// widened to the API's grid holds the lake's area.
    const empty = MapViewport(
      bounds: GeoBounds(south: 45.8950, west: 6.1350, north: 45.8970, east: 6.1380),
      center: LatLng(45.8960, 6.1365),
      zoom: 17,
    );

    testWidgets('a view without a place says none, not the count of the box around it', (
      tester,
    ) async {
      expect(empty.bounds.contains(lakeArea.position), isFalse);
      final online = FakeOnlinePlaces(samplePlaces);
      final map = FakeMap()..viewport = empty;
      final app = await pumpLunaway(tester, places: const [], online: online, map: map);
      map.lastProps!.onPlacesInView!(const [], empty.bounds);
      await settleShort(tester);
      final page = app.container(tester).read(nearbyPlacesPageProvider).value!;
      expect(page.places, isEmpty);
      expect(page.total, 0);
      expect(find.textContaining('lieux ici'), findsNothing);
      // The filters' sheet counts the same view.
      final count = await _watched(
        tester,
        app,
        filterPreviewCountProvider(app.container(tester).read(placeFilterProvider)).future,
      );
      expect(count, 0);
    });

    testWidgets("before the map reports its view, nothing is counted on France's box", (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final map = FakeMap()..reportsView = false;
      await pumpLunaway(tester, places: const [], online: online, map: map, settle: false);
      await settleShort(tester, const Duration(seconds: 2));
      expect(online.requests.where((r) => r.startsWith('page:')), isEmpty);
      expect(find.textContaining('lieux ici'), findsNothing);
      // The map reports its view: the list counts it, once.
      map.lastProps!.onViewportChanged(map.viewport);
      await settleShort(tester);
      expect(online.requests.where((r) => r.startsWith('page:')), hasLength(1));
      expect(find.textContaining('lieux ici'), findsOneWidget);
    });

    testWidgets('while the list reads another view, its title gives no count of the view before', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final map = FakeMap();
      await pumpLunaway(tester, places: const [], online: online, map: map);
      expect(find.textContaining('lieux ici'), findsOneWidget);
      online.holdFirstPages = Completer<void>();
      map.lastProps!.onViewportChanged(
        const MapViewport(
          bounds: GeoBounds(south: 45, west: 4, north: 46, east: 5),
          center: LatLng(45.5, 4.5),
          zoom: 8,
        ),
      );
      await settleShort(tester);
      expect(find.textContaining('lieux ici'), findsNothing, reason: 'the view before');
      online.holdFirstPages!.complete();
      await settleShort(tester);
      expect(find.textContaining(RegExp('lieux? ici')), findsOneWidget);
    });

    testWidgets('a map moved offline says there is no connection, not the list before', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final map = FakeMap();
      await pumpLunaway(tester, places: const [], online: online, map: map);
      expect(find.textContaining('lieux ici'), findsOneWidget);
      final shown = find.text('Camping des Peupliers (démo)');
      online.offline = true;
      map.lastProps!.onViewportChanged(
        const MapViewport(
          bounds: GeoBounds(south: 45, west: 4, north: 46, east: 5),
          center: LatLng(45.5, 4.5),
          zoom: 8,
        ),
      );
      await settleShort(tester);
      expect(find.textContaining('lieux ici'), findsNothing);
      expect(find.text('Pas de connexion'), findsOneWidget);
      expect(find.text('Pas de connexion : la liste a besoin du réseau.'), findsOneWidget);
      expect(shown, findsNothing, reason: 'no row of the view before');
    });
  });
}
