import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

import '../helpers/fake_api.dart';
import '../helpers/fakes.dart';
import '../helpers/fuel_feed_server.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

final Translations t = AppLocale.fr.buildSync();

/// A tall desktop window, where a page fits without scrolling.
const _tall = Size(1280, 3000);

Finder inPoi(Finder finder) => find.descendant(of: find.byType(PoiDetails), matching: finder);

Finder inPlace(Finder finder) =>
    find.descendant(of: find.byType(PlaceDetailsBody), matching: finder);

PoiFeature _feature(Map<String, Object?> json) => poiFromJson(json)!.feature;

void main() {
  group('the chips', () {
    testWidgets('one category at a time, turned off by a second tap', (tester) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map);
      expect(find.text('Courses'), findsOneWidget);
      expect(find.text('Santé'), findsOneWidget);
      expect(map.lastProps!.pois!.category, isNull, reason: 'none on by default');

      await tester.ensureVisible(find.text('Distributeurs alimentaires'));
      await tester.tap(find.text('Distributeurs alimentaires'));
      await settleShort(tester);
      await tester.tap(find.text(t.poi.vendingAll));
      await settleShort(tester);
      expect(map.lastProps!.pois!.category, PoiCategory.vending);
      await tester.ensureVisible(find.text('Santé'));
      await tester.tap(find.text('Santé'));
      await settleShort(tester);
      expect(map.lastProps!.pois!.category, PoiCategory.health, reason: 'it replaces the first');
      await tester.ensureVisible(find.text('Santé'));
      await tester.tap(find.text('Santé'));
      await settleShort(tester);
      expect(map.lastProps!.pois!.category, isNull);
    });

    testWidgets('the vending chip asks what the machines sell, and names the pizza once chosen', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map);
      await tester.ensureVisible(find.text('Distributeurs alimentaires'));
      await tester.tap(find.text('Distributeurs alimentaires'));
      await settleShort(tester);
      expect(map.lastProps!.pois!.category, isNull, reason: 'the menu first, nothing on yet');
      final listed = [
        for (final k in PoiKind.vendingChoices) t.poiVendingSells(k),
        t.poi.vendingAll,
      ];
      expect(listed.first, 'Pizza');
      for (final label in listed) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.text('Pizza')).dy,
        lessThan(tester.getTopLeft(find.text('Pain')).dy),
        reason: 'pizza first',
      );

      await tester.tap(find.text('Pizza'));
      await settleShort(tester);
      final pois = map.lastProps!.pois!;
      expect(pois.category, PoiCategory.vending);
      expect(pois.vending, PoiKind.vendingPizza);
      expect(find.text('Distributeurs de pizza'), findsOneWidget);
      expect(find.text('Distributeurs alimentaires'), findsNothing);

      // A second tap turns the machines off, as for any chip.
      await tester.tap(find.text('Distributeurs de pizza'));
      await settleShort(tester);
      expect(map.lastProps!.pois!.category, isNull);
      expect(find.text('Distributeurs alimentaires'), findsOneWidget);

      // Dismissed, the menu turns nothing on.
      await tester.ensureVisible(find.text('Distributeurs alimentaires'));
      await tester.tap(find.text('Distributeurs alimentaires'));
      await settleShort(tester);
      await tester.tapAt(const Offset(5, 5));
      await settleShort(tester);
      expect(map.lastProps!.pois!.category, isNull);
    });

    testWidgets('"Open now" shows beside the chosen category and keeps only the open points', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map);
      expect(find.text(t.poi.openNow), findsNothing);
      await tester.ensureVisible(find.text('Courses'));
      await tester.tap(find.text('Courses'));
      await settleShort(tester);
      await tester.ensureVisible(find.text(t.poi.openNow));
      await tester.tap(find.text(t.poi.openNow));
      await settleShort(tester);
      expect(map.lastProps!.pois!.openNowOnly, isTrue);
    });

    testWidgets(
      'the points the map reports are read open or closed, and a place hides its dump station',
      (tester) async {
        final map = FakeMap();
        await pumpLunaway(tester, map: map);
        final open = _feature(bakeryJson);
        final closed = _feature(pharmacyJson);
        // On the lake area's own spot.
        final dump = PoiFeature(
          id: 'dump',
          kind: PoiKind.dumpStation,
          position: LatLng(lakeArea.lat, lakeArea.lon + 0.0002),
        );
        map.lastProps!.onPoisInView!([open, closed, dump]);
        await settleShort(tester);
        final state = map.lastProps!.pois!.state;
        expect(state.open, {open.id});
        expect(state.closed, {closed.id});
        expect(state.hidden, {'dump'});
      },
    );
  });

  group('the page of a point', () {
    testWidgets('a tap on the map opens it: its name, its state until when, and the way there', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map, size: _tall);
      map.lastProps!.onPoiTap!(_feature(bakeryJson));
      await settleShort(tester);
      expect(inPoi(find.text('Boulangerie du Lac')), findsOneWidget);
      expect(inPoi(find.text('Boulangerie')), findsWidgets);
      expect(inPoi(find.text('Ouvert, ferme à 19:00')), findsOneWidget);
      expect(find.text(t.place.directions), findsWidgets);
      expect(map.moves.last.center, _feature(bakeryJson).position, reason: 'brought into view');
    });

    testWidgets('a station shows its prices, LPG first, with their freshness and the feed', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map, size: _tall);
      map.lastProps!.onPoiTap!(_feature(stationJson));
      await settleShort(tester);
      // The card's title, and the source of the same name.
      expect(inPoi(find.text(t.poi.fuelPrices)), findsNWidgets(2));
      final lpg = tester.getTopLeft(inPoi(find.text('GPL')));
      final diesel = tester.getTopLeft(inPoi(find.text('Gazole')));
      expect(lpg.dy, lessThan(diesel.dy));
      expect(inPoi(find.textContaining('1,029')), findsOneWidget);
      expect(inPoi(find.text('Prix mis à jour il y a 2 heures')), findsWidgets);
      expect(inPoi(find.text('Prix relevés il y a 10 minutes')), findsOneWidget);
      expect(inPoi(find.text('E85 · ${t.poi.shortageTemporary}')), findsOneWidget);
      expect(inPoi(find.text(t.poi.selfService24h)), findsOneWidget);
      expect(inPoi(find.text('Licence Ouverte 2.0')), findsOneWidget, reason: 'its source');
    });

    testWidgets('offline, a point opens from what the map knows, and says the details need it', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map, size: _tall, pois: FakePoiSource()..online = false);
      map.lastProps!.onPoiTap!(_feature(bakeryJson));
      await settleShort(tester);
      expect(inPoi(find.text('Boulangerie du Lac')), findsOneWidget);
      expect(inPoi(find.text('Ouvert, ferme à 19:00')), findsOneWidget);
      expect(inPoi(find.text(t.poi.loadError)), findsOneWidget);
    });

    testWidgets('a copy the server refused to read again says when it was read', (tester) async {
      final map = FakeMap();
      final pois = FakePoiSource()..refuse = true;
      final app = await pumpLunaway(tester, map: map, size: _tall, pois: pois);
      final readAt = testNow.subtract(const Duration(days: 2));
      await app.cache
          .into(app.cache.poiCache)
          .insert(
            PoiCacheCompanion.insert(
              cacheKey: 'poi:${bakeryJson['id']}',
              json: jsonEncode({'poi': bakeryJson, 'sources': <Object>[]}),
              fetchedAt: readAt.millisecondsSinceEpoch,
            ),
          );
      map.lastProps!.onPoiTap!(_feature(bakeryJson));
      await settleShort(tester);
      expect(inPoi(find.text('Boulangerie du Lac')), findsOneWidget);
      expect(inPoi(find.text(t.poi.readStale(when: t.agoFine(readAt, testNow)))), findsOneWidget);
    });

    testWidgets('"still there" sends the answer about the point and no position', (tester) async {
      final api = FakeApi();
      final map = FakeMap();
      await pumpLunaway(tester, map: map, size: _tall, api: api, signedIn: true);
      map.lastProps!.onPoiTap!(_feature(pizzaJson));
      await settleShort(tester);
      expect(inPoi(find.text(t.poi.alwaysOpen)), findsOneWidget);
      await tester.tap(inPoi(find.text(t.poi.gone)));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('ConfirmPoi'), {'poiId': pizzaJson['id'], 'stillThere': false});
      expect(find.text(t.poi.thanksGone), findsOneWidget);
    });
  });

  group('a link to a point', () {
    testWidgets('opens its page and brings it into view', (tester) async {
      final app = await pumpLunaway(tester, size: _tall);
      app.container(tester).read(routerProvider).go('/map?poi=${bakeryJson['id']}');
      await settleShort(tester, const Duration(seconds: 2));
      expect(inPoi(find.text('Boulangerie du Lac')), findsOneWidget);
      expect(app.map.moves.last.center, _feature(bakeryJson).position);
    });

    testWidgets('without network nor copy, says it could not open it', (tester) async {
      final app = await pumpLunaway(tester, size: _tall, pois: FakePoiSource()..online = false);
      app.container(tester).read(routerProvider).go('/map?poi=${bakeryJson['id']}');
      await settleShort(tester, const Duration(seconds: 2));
      expect(find.byType(PoiDetails), findsNothing);
      expect(find.text(t.poi.linkError), findsOneWidget);
    });
  });

  group('around a place', () {
    testWidgets('the best point of each category, with its distance and its state', (tester) async {
      final app = await pumpLunaway(tester, size: _tall);
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(inPlace(find.text(t.poi.around)), findsOneWidget);
      expect(inPlace(find.text('Boulangerie du Lac')), findsOneWidget);
      expect(inPlace(find.text('230 m')), findsOneWidget);
      expect(inPlace(find.text('Distributeur de pizzas')), findsOneWidget);
      expect(inPlace(find.text(t.poi.alwaysOpen)), findsOneWidget);
      expect(inPlace(find.text(t.poi.onSite)), findsOneWidget, reason: 'the dump station, 20 m');
      expect(inPlace(find.text('1,8 km')), findsOneWidget);
    });

    testWidgets('a point opened from a place leads back to it', (tester) async {
      final app = await pumpLunaway(tester, size: _tall);
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      await tester.tap(inPlace(find.text('Boulangerie du Lac')));
      await settleShort(tester);
      expect(inPoi(find.text('Boulangerie du Lac')), findsOneWidget);
      await tester.tap(inPoi(find.text(t.poi.backTo(name: lakeArea.name!))));
      await settleShort(tester);
      expect(inPlace(find.text(lakeArea.name!)), findsWidgets);
    });

    testWidgets('without network nor copy, the section says it could not be read', (tester) async {
      final app = await pumpLunaway(tester, size: _tall, pois: FakePoiSource()..online = false);
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(inPlace(find.text(t.poi.aroundOffline)), findsOneWidget);
    });
  });

  group('the search', () {
    testWidgets('lists shops and services in their own section', (tester) async {
      await pumpLunaway(tester);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(find.text(t.poi.searchSection), findsOneWidget);
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
    });

    testWidgets("ranks from the map's centre, never the user's position", (tester) async {
      final pois = FakePoiSource();
      final app = await pumpLunaway(tester, pois: pois);
      const user = LatLng(45.9123, 6.1345);
      app.container(tester).read(userLocationProvider.notifier).update(user);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(pois.searchedNear, isNotEmpty);
      expect(pois.searchedNear, everyElement(app.map.viewport.center));
      // The distance shown is the device's own sum.
      expect(
        find.textContaining(t.distance(_feature(bakeryJson).position.distanceTo(user))),
        findsOneWidget,
      );
    });

    testWidgets('says when the shops need a network', (tester) async {
      await pumpLunaway(tester, pois: FakePoiSource()..online = false);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(find.text(t.poi.searchOffline), findsOneWidget);
    });
  });

  group('a vending machine', () {
    testWidgets('below level 1, the level shows first and nothing is sent', (tester) async {
      final api = FakeApi();
      await pumpLunaway(tester, size: _tall, api: api);
      await tester.longPress(find.byKey(const ValueKey('fake-map')));
      await settleShort(tester);
      expect(find.text(t.poi.add.title), findsOneWidget);
      await tester.tap(find.text(t.poi.add.pizza));
      await settleShort(tester);
      expect(find.text(t.poi.add.gate), findsOneWidget);
      expect(api.operations, isNot(contains('AddVendingMachine')));
    });

    testWidgets('from level 1, a long press and a kind add it where it stands', (tester) async {
      final api = FakeApi(level: 1);
      final map = FakeMap();
      await pumpLunaway(tester, size: _tall, api: api, signedIn: true, map: map);
      await tester.longPress(find.byKey(const ValueKey('fake-map')));
      await settleShort(tester);
      await tester.tap(find.text(t.poi.add.pizza));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('AddVendingMachine'), {
        'input': {'lat': map.longPressAt.lat, 'lon': map.longPressAt.lon, 'kind': 'VENDING_PIZZA'},
      });
      expect(find.text(t.poi.add.sent), findsOneWidget);
    });

    testWidgets('one already there is asked about instead', (tester) async {
      const existing = '00000000-0000-7000-8000-00000000b002';
      final api = FakeApi(level: 1)..vendingDuplicateOf = existing;
      await pumpLunaway(tester, size: _tall, api: api, signedIn: true);
      await tester.longPress(find.byKey(const ValueKey('fake-map')));
      await settleShort(tester);
      await tester.tap(find.text(t.poi.add.bread));
      await settleShort(tester, const Duration(seconds: 2));
      expect(find.text(t.poi.add.duplicateTitle), findsOneWidget);
      await tester.tap(find.text(t.poi.add.duplicateThere));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('ConfirmPoi'), {'poiId': existing, 'stillThere': true});
    });
  });

  group('fuel prices', () {
    // Three stations of the lake's view: the cheapest of gazole is not the
    // cheapest of E10, and the third sells no E10.
    Map<String, Object?> station(String name, Map<String, double> prices, double lat) =>
        stationWith('fuel-$name', name, prices, lat: lat);
    final stations = [
      station('Station du Port', {'DIESEL': 1.699, 'E10': 1.849}, 45.903),
      station('Relais des Aravis', {'DIESEL': 1.749, 'E10': 1.759}, 45.91),
      station('Garage du Col', {'DIESEL': 1.829}, 45.92),
    ];
    const view = MapViewport(
      bounds: GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.2),
      center: LatLng(45.9, 6.12),
      zoom: 12,
    );

    Future<(TestApp, FakePoiSource)> fuelOn(
      WidgetTester tester, {
      Size size = _tall,
      MapViewport at = view,
      FuelFeedServer? feed,
    }) async {
      final pois = FakePoiSource(pois: stations);
      final map = FakeMap()..viewport = at;
      final app = await pumpLunaway(
        tester,
        size: size,
        map: map,
        pois: pois,
        httpClient: feed?.client,
      );
      await tester.ensureVisible(find.text(t.poi.category.fuel));
      await tester.tap(find.text(t.poi.category.fuel));
      await settleShort(tester);
      return (app, pois);
    }

    testWidgets('the chip prices the stations of the map and lists the cheapest, gazole first', (
      tester,
    ) async {
      final (app, _) = await fuelOn(tester);
      expect(find.text(t.poi.cheapest.title), findsOneWidget);
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Station du Port'), lessThan(y('Relais des Aravis')));
      expect(y('Relais des Aravis'), lessThan(y('Garage du Col')));
      expect(find.textContaining('1,699'), findsOneWidget);
      expect(app.map.lastProps!.pois!.fuelLabels.map((l) => l.text), ['1,699', '1,749', '1,829']);

      // Another fuel: its own order, and a station without it leaves.
      await tester.tap(find.widgetWithText(ChoiceChip, 'SP95-E10'));
      await settleShort(tester);
      expect(y('Relais des Aravis'), lessThan(y('Station du Port')));
      expect(find.text('Garage du Col'), findsNothing);
      expect(app.map.lastProps!.pois!.fuelLabels.map((l) => l.text), ['1,849', '1,759']);

      // The chip off, the places come back and the prices leave the map.
      await tester.ensureVisible(find.text(t.poi.category.fuel));
      await tester.tap(find.text(t.poi.category.fuel));
      await settleShort(tester);
      expect(find.text(t.poi.cheapest.title), findsNothing);
      expect(app.map.lastProps!.pois!.fuelLabels, isEmpty);
    });

    testWidgets('a row opens its station and brings it into view', (tester) async {
      final (app, _) = await fuelOn(tester);
      await tester.tap(find.text('Relais des Aravis'));
      await settleShort(tester);
      expect(inPoi(find.text('Relais des Aravis')), findsOneWidget);
      expect(app.map.moves.last.center, const LatLng(45.91, 6.12));
    });

    const farOut = MapViewport(
      bounds: GeoBounds(south: 44, west: 4, north: 48, east: 8),
      center: LatLng(46.012, 6.031),
      zoom: 8,
    );

    testWidgets('far out, the server ranks the stations around the view; no tile is read', (
      tester,
    ) async {
      final feed = FuelFeedServer(testDemoClient)
        ..nearby = [
          fuelStop(
            '74000001',
            'Relais du Lac',
            1.689,
            lat: 46.05,
            lon: 6.05,
            poiId: '0192f5a0-0000-7000-8000-0000000000f7',
          ),
          fuelStop('74000002', 'Garage des Cimes', 1.699, lat: 46.1, lon: 6),
          fuelStop('74000003', 'Station du Bourg', 1.659, lat: 46, lon: 6, shortage: 'TEMPORARY'),
        ];
      final (_, pois) = await fuelOn(tester, at: farOut, feed: feed);
      expect(find.text(t.poi.cheapest.zoomIn), findsNothing);
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Relais du Lac'), lessThan(y('Garage des Cimes')));
      expect(y('Garage des Cimes'), lessThan(y('Station du Bourg')), reason: 'out of it: last');
      expect(find.text(t.poi.shortageTemporary), findsOneWidget);
      expect(pois.fuelReads, 0);
      // The centre of the view leaves rounded to a twentieth of a degree.
      final (name, variables) = feed.requests.single;
      expect(name, 'FuelNearby');
      expect(variables['at'], {'lat': 46.0, 'lon': 6.05});
      expect(variables['fuel'], 'DIESEL');
      expect(feed.violations, isEmpty);
    });

    testWidgets('far out, against an API without that search, the list asks to come closer', (
      tester,
    ) async {
      final feed = FuelFeedServer(testDemoClient)..older = true;
      final (_, pois) = await fuelOn(tester, at: farOut, feed: feed);
      expect(find.text(t.poi.cheapest.zoomIn), findsOneWidget);
      expect(pois.fuelReads, 0);
    });

    testWidgets('without network the list says so, and Retry reads the prices again', (
      tester,
    ) async {
      final pois = FakePoiSource(pois: stations)..online = false;
      final map = FakeMap()..viewport = view;
      await pumpLunaway(tester, size: _tall, map: map, pois: pois);
      await tester.ensureVisible(find.text(t.poi.category.fuel));
      await tester.tap(find.text(t.poi.category.fuel));
      await settleShort(tester);
      expect(find.text(t.poi.cheapest.error), findsOneWidget);
      expect(find.text('Station du Port'), findsNothing);

      pois.online = true;
      await tester.tap(find.text(t.common.retry));
      await settleShort(tester);
      expect(find.text(t.poi.cheapest.error), findsNothing);
      expect(find.text('Station du Port'), findsOneWidget);
    });

    testWidgets('a failed read after a good one says so, and shows no old price', (tester) async {
      final (app, pois) = await fuelOn(tester);
      expect(find.text('Station du Port'), findsOneWidget);
      pois.online = false;
      // A wider area, still around the stations, which cannot be read.
      app
          .container(tester)
          .read(viewportProvider.notifier)
          .update(
            const MapViewport(
              bounds: GeoBounds(south: 45.7, west: 6.05, north: 45.95, east: 6.2),
              center: LatLng(45.825, 6.12),
              zoom: 12,
            ),
          );
      await settleShort(tester);
      expect(find.text(t.poi.cheapest.error), findsOneWidget);
      expect(find.text('Station du Port'), findsNothing);
      expect(app.map.lastProps!.pois!.fuelLabels, isEmpty);
    });

    testWidgets('on a phone the sheet lists them', (tester) async {
      await fuelOn(tester, size: phone);
      expect(find.text(t.poi.cheapest.title), findsOneWidget);
      // Raised, the sheet shows the rows under the fuels.
      await tester.drag(find.text(t.poi.cheapest.title), const Offset(0, -400));
      await settleShort(tester);
      expect(find.text('Station du Port').hitTestable(), findsOneWidget);
    });

    testWidgets('on a tablet the list button opens them', (tester) async {
      await fuelOn(tester, size: tablet);
      // The panel waits beside the window until asked for.
      expect(find.text(t.poi.cheapest.title).hitTestable(), findsNothing);
      await tester.tap(find.text(t.poi.cheapest.show));
      await settleShort(tester);
      expect(find.text(t.poi.cheapest.title).hitTestable(), findsOneWidget);
      expect(find.text('Station du Port').hitTestable(), findsOneWidget);
    });

    testWidgets("a station's page shows how its price moved, the days seen only", (tester) async {
      final id = stationJson['id']! as String;
      final feed = FuelFeedServer(testDemoClient)
        ..trends = {
          id: {
            'fuel': 'DIESEL',
            'days': [
              {'day': '2026-09-29', 'lowEur': 1.709, 'highEur': 1.719},
              {'day': '2026-10-02', 'lowEur': 1.699, 'highEur': 1.709},
              {'day': '2026-10-06', 'lowEur': 1.689, 'highEur': 1.699},
            ],
            'last7Days': {'lowEur': 1.689, 'highEur': 1.709, 'daysKnown': 2, 'changeEur': -0.01},
            'last30Days': {'lowEur': 1.689, 'highEur': 1.719, 'daysKnown': 3, 'changeEur': -0.02},
          },
        };
      final map = FakeMap();
      final app = await pumpLunaway(tester, map: map, size: _tall, httpClient: feed.client);
      await app
          .container(tester)
          .read(vehicleRepositoryProvider)
          .save(Vehicle.typical(VehicleType.van).copyWith(fuel: () => FuelType.diesel));
      await settleShort(tester);
      map.lastProps!.onPoiTap!(_feature(stationJson));
      await settleShort(tester);
      await tester.ensureVisible(inPoi(find.text(t.poi.trend.title(fuel: 'Gazole'))));
      await settleShort(tester);
      Finder line(String text) => inPoi(find.textContaining(text, findRichText: true));
      expect(
        line(
          '${t.poi.trend.week} de ${t.pricePerLitre(1.689)} à ${t.pricePerLitre(1.709)}, '
          'en baisse de ${t.pricePerLitre(0.01)}',
        ),
        findsOneWidget,
      );
      expect(line('${t.poi.trend.month} de ${t.pricePerLitre(1.689)}'), findsOneWidget);
      expect(line('en baisse de ${t.pricePerLitre(0.02)}'), findsOneWidget);
      expect(inPoi(find.textContaining('3 jours relevés depuis le 29 septembre')), findsOneWidget);
      expect(feed.requests.single.$2, {'id': id, 'fuel': 'DIESEL'});
      expect(feed.violations, isEmpty);
    });

    testWidgets("a station's page shows the vehicle's fuel first, then LPG for its heating", (
      tester,
    ) async {
      final map = FakeMap();
      final app = await pumpLunaway(tester, map: map, size: _tall);
      await app
          .container(tester)
          .read(vehicleRepositoryProvider)
          .save(
            Vehicle.typical(VehicleType.van).copyWith(fuel: () => FuelType.e10, lpgHeating: true),
          );
      await settleShort(tester);
      map.lastProps!.onPoiTap!(_feature(stationJson));
      await settleShort(tester);
      double y(String name) => tester.getTopLeft(inPoi(find.text(name))).dy;
      expect(y('SP95-E10'), lessThan(y('GPL')));
      expect(y('GPL'), lessThan(y('Gazole')));
    });
  });
}
