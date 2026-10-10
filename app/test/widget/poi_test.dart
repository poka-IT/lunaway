import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_search.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/hours_text.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

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

/// Open from 05:00 to 21:00 UTC every day around [testNow] (08:30 UTC).
List<Map<String, String>> _openAllDay() => [
  for (var d = -1; d < 13; d++)
    {
      'start': DateTime.utc(2026, 10, 6 + d, 5).toIso8601String(),
      'end': DateTime.utc(2026, 10, 6 + d, 21).toIso8601String(),
    },
];

/// An address the geocoders find for "coiffeur".
const _coiffeurStreet = AddressMatch(
  kind: AddressKind.street,
  name: 'Rue du Coiffeur',
  postcode: '74000',
  city: 'Annecy',
  countryCode: 'FR',
  position: LatLng(45.9, 6.12),
  sourceId: 'ban',
  attribution: 'Base Adresse Nationale, IGN Géoplateforme',
);

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

    testWidgets('restaurants and sights read the tiles of every category, the others the default', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, map: map);
      String tiles() => map.lastProps!.pois!.tileJsonUrl;
      expect(tiles(), endsWith('/poi/tiles.json'), reason: 'no restaurant loaded by default');
      for (final (label, category) in [
        ('Restaurants et cafés', PoiCategory.food),
        ('À voir', PoiCategory.sights),
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await settleShort(tester);
        expect(map.lastProps!.pois!.category, category);
        expect(tiles(), endsWith('/poi/all/tiles.json'), reason: label);
      }
      await tester.ensureVisible(find.text('Santé'));
      await tester.tap(find.text('Santé'));
      await settleShort(tester);
      expect(tiles(), endsWith('/poi/tiles.json'), reason: 'back to the default tiles');
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

    testWidgets('an unnamed charging point says its kind once, and a paid one shows coins', (
      tester,
    ) async {
      final charging = poiJson(
        '00000000-0000-7000-8000-00000000b006',
        'EV_CHARGING',
        distanceM: 300,
        extra: {'fee': true},
      );
      final map = FakeMap();
      await pumpLunaway(
        tester,
        map: map,
        size: _tall,
        pois: FakePoiSource(pois: [charging, bakeryJson]),
      );
      map.lastProps!.onPoiTap!(_feature(charging));
      await settleShort(tester);
      expect(inPoi(find.text('Borne de recharge')), findsOneWidget, reason: 'not title and line');
      final paid = find.ancestor(of: inPoi(find.text(t.poi.fee)), matching: find.byType(Row));
      expect(find.descendant(of: paid.first, matching: find.byIcon(AppIcons.paid)), findsOneWidget);
      expect(inPoi(find.byIcon(AppIcons.priceServices)), findsNothing, reason: 'no water drop');
    });

    testWidgets('a restaurant says what it is under its name; a market titles its days', (
      tester,
    ) async {
      final restaurant = poiJson(
        '00000000-0000-7000-8000-00000000b010',
        'RESTAURANT',
        name: 'Le Garde Manger',
        distanceM: 400,
      );
      final market = poiJson(
        '00000000-0000-7000-8000-00000000b011',
        'MARKETPLACE',
        name: 'Marché de Sévrier',
        distanceM: 900,
        extra: {'openingHours': 'We,Sa 08:00-13:00'},
      );
      final map = FakeMap();
      await pumpLunaway(
        tester,
        map: map,
        size: _tall,
        pois: FakePoiSource(pois: [restaurant, market]),
      );
      map.lastProps!.onPoiTap!(_feature(restaurant));
      await settleShort(tester);
      expect(inPoi(find.text('Le Garde Manger')), findsOneWidget);
      expect(inPoi(find.textContaining('Restaurant')), findsOneWidget, reason: 'the kind, once');
      map.lastProps!.onPoiTap!(_feature(market));
      await settleShort(tester);
      expect(inPoi(find.text(t.poi.marketDays)), findsOneWidget);
      expect(inPoi(find.text(t.place.hours)), findsNothing);
      expect(inPoi(find.text(readableHours('We,Sa 08:00-13:00', t))), findsOneWidget);
    });

    testWidgets('a wash says the vehicles it takes, and nothing of what OSM does not say', (
      tester,
    ) async {
      final wash = poiJson(
        '00000000-0000-7000-8000-00000000b012',
        'CAR_WASH',
        name: 'Lavage poids lourds',
        distanceM: 1200,
        extra: {'hgv': true, 'motorhome': null, 'maxHeightM': 4.2},
      );
      final map = FakeMap();
      await pumpLunaway(
        tester,
        map: map,
        size: _tall,
        pois: FakePoiSource(pois: [wash]),
      );
      map.lastProps!.onPoiTap!(_feature(wash));
      await settleShort(tester);
      expect(inPoi(find.text(t.poi.vehicles.hgvYes)), findsOneWidget);
      expect(inPoi(find.text(t.poi.vehicles.maxHeight(height: t.metres(4.2)))), findsOneWidget);
      expect(inPoi(find.text(t.poi.vehicles.motorhomeYes)), findsNothing);
      expect(inPoi(find.text(t.poi.vehicles.motorhomeNo)), findsNothing, reason: 'unknown, not no');
    });

    testWidgets('a shop that takes credit and debit cards says "Carte" once', (tester) async {
      final shop = poiJson(
        '00000000-0000-7000-8000-00000000b007',
        'BAKERY',
        name: 'Boulangerie des Cartes',
        distanceM: 300,
        extra: {
          'payment': ['cash', 'credit_cards', 'debit_cards', 'cards', 'contactless'],
        },
      );
      final map = FakeMap();
      await pumpLunaway(
        tester,
        map: map,
        size: _tall,
        pois: FakePoiSource(pois: [shop]),
      );
      map.lastProps!.onPoiTap!(_feature(shop));
      await settleShort(tester);
      expect(inPoi(find.text(t.poi.paymentTitle)), findsOneWidget);
      expect(inPoi(find.text('Carte')), findsOneWidget);
      expect(inPoi(find.text('Espèces')), findsOneWidget);
      expect(inPoi(find.text('Sans contact')), findsOneWidget);
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
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
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
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
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
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(inPlace(find.text(t.poi.aroundOffline)), findsOneWidget);
    });
  });

  group('the search', () {
    /// The API, with the points it knows.
    FakeOnlinePlaces api({List<Map<String, Object?>> pois = const []}) =>
        FakeOnlinePlaces(samplePlaces)..pois.addAll([bakeryJson, ...pois]);

    double top(WidgetTester tester, Finder f) => tester.getTopLeft(f.first).dy;

    testWidgets('one request brings the shops with the addresses, in their own section', (
      tester,
    ) async {
      final online = api();
      await pumpLunaway(tester, online: online);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
      expect(find.text(t.poi.searchSection), findsOneWidget);
      // The API was asked once, for the places, the addresses and the
      // points together; the device's own places complete its answer.
      expect(online.requests.where((r) => !r.startsWith('page:')), ['searchAll:Boulangerie']);
      expect(online.poisAsked, [searchPoiCount]);
    });

    testWidgets('on the web the points come in the one request of the places', (tester) async {
      final online = api();
      await pumpLunaway(tester, places: const [], online: online);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
      expect(online.requests.where((r) => !r.startsWith('page:')), ['searchAll:Boulangerie']);
      expect(online.poisAsked, [searchPoiCount]);
    });

    testWidgets('two characters ask for no point', (tester) async {
      final online = api();
      await pumpLunaway(tester, places: const [], online: online);
      await tester.enterText(find.byType(TextField), 'Bo');
      await settleShort(tester);
      expect(online.poisAsked, [0]);
      expect(find.text(t.poi.searching), findsNothing);
    });

    testWidgets("ranks from the map's centre, never the user's position", (tester) async {
      final online = api();
      final app = await pumpLunaway(tester, online: online);
      const user = LatLng(45.9123, 6.1345);
      app.container(tester).read(userLocationProvider.notifier).update(user);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(online.nears, isNotEmpty);
      expect(online.nears, everyElement(app.map.viewport.center));
      // The distance shown is the device's own sum.
      expect(
        find.textContaining(t.distance(_feature(bakeryJson).position.distanceTo(user))),
        findsOneWidget,
      );
    });

    testWidgets('says when the shops need a network', (tester) async {
      await pumpLunaway(tester);
      await tester.enterText(find.byType(TextField), 'Boulangerie');
      await settleShort(tester);
      expect(find.text(t.poi.searchOffline), findsOneWidget);
    });

    testWidgets('a kind asked comes first under its own title, a row says what it needs', (
      tester,
    ) async {
      final hairdresser = poiJson(
        '00000000-0000-7000-8000-00000000c001',
        'HAIRDRESSER',
        name: 'Salon Mèche Rebelle',
        intervals: _openAllDay(),
      );
      final online = api()
        ..addresses.add(_coiffeurStreet)
        ..kindSearches['coiffeur'] = PoiResults(
          pois: [poiFromJson(hairdresser)!],
          match: PoiMatch.kind,
          kinds: const [PoiKind.hairdresser],
        );
      await pumpLunaway(tester, online: online);
      await tester.enterText(find.byType(TextField), 'coiffeur');
      await settleShort(tester);
      final title = find.text(t.poi.searchKindNear(what: 'Coiffeur'));
      expect(title, findsOneWidget);
      expect(find.text(t.poi.searchSection), findsNothing);
      expect(top(tester, title), lessThan(top(tester, find.text(t.search.addresses))));
      expect(find.text('Salon Mèche Rebelle'), findsOneWidget);
      expect(
        find.textContaining('${t.poiKind(PoiKind.hairdresser)} · '),
        findsOneWidget,
        reason: 'the kind on the line',
      );
      expect(
        find.textContaining(t.poiOpening(poiFromJson(hairdresser)!.hours, testNow)),
        findsOneWidget,
        reason: 'open now, until when',
      );
    });

    testWidgets('a kind in a town says the town, and a restaurant says what it cooks', (
      tester,
    ) async {
      final pizzeria = poiJson(
        '00000000-0000-7000-8000-00000000c002',
        'RESTAURANT',
        name: 'Da Gino',
        extra: {
          // A value the app has no word for is not the one the line shows.
          'cuisine': ['wood_fired_oven', 'pizza', 'italian'],
        },
      );
      final online = api()
        ..kindSearches['pizzeria annecy'] = PoiResults(
          pois: [poiFromJson(pizzeria)!],
          match: PoiMatch.kind,
          kinds: const [PoiKind.restaurant, PoiKind.fastFood],
          town: 'Annecy',
        );
      await pumpLunaway(tester, online: online);
      await tester.enterText(find.byType(TextField), 'pizzeria annecy');
      await settleShort(tester);
      expect(find.text(t.poi.searchKindIn(what: 'Pizzeria', town: 'Annecy')), findsOneWidget);
      expect(
        find.text('${t.poiKind(PoiKind.restaurant)} · ${t.poi.cuisine.pizza}'),
        findsOneWidget,
      );
      expect(find.textContaining(t.poi.hoursUnknown), findsNothing, reason: 'nothing unknown said');
    });

    testWidgets('a partial match comes after the towns and the addresses', (tester) async {
      final online = api()
        ..addresses.add(_coiffeurStreet)
        ..kindSearches['coiffeur'] = PoiResults(
          pois: [poiFromJson(bakeryJson)!],
          match: PoiMatch.partial,
        );
      await pumpLunaway(tester, online: online);
      await tester.enterText(find.byType(TextField), 'coiffeur');
      await settleShort(tester);
      expect(
        top(tester, find.text(t.poi.searchSection)),
        greaterThan(top(tester, find.text(t.search.addresses))),
      );
    });

    testWidgets('the places for motorhomes come before a point of the same name', (tester) async {
      final online = api(
        pois: [
          poiJson('00000000-0000-7000-8000-00000000c003', 'BAKERY', name: 'Fournil du Lac Bleu'),
        ],
      );
      await pumpLunaway(tester, online: online);
      await tester.enterText(find.byType(TextField), 'Lac Bleu');
      await settleShort(tester);
      expect(
        top(tester, find.text(t.search.places)),
        lessThan(top(tester, find.text('Fournil du Lac Bleu'))),
      );
    });

    testWidgets('a town named as typed comes before a point of that name', (tester) async {
      final online = api(
        pois: [poiJson('00000000-0000-7000-8000-00000000c004', 'BAR', name: 'Annecy Plage')],
      );
      await pumpLunaway(tester, online: online);
      await tester.enterText(find.byType(TextField), 'Annecy');
      await settleShort(tester);
      expect(
        top(tester, find.text(t.search.towns)),
        lessThan(top(tester, find.text('Annecy Plage'))),
      );
    });

    testWidgets('a point chosen opens its page and the map shows it with its pin', (tester) async {
      final hotel = poiJson(
        '00000000-0000-7000-8000-00000000c005',
        'HOTEL',
        name: 'Hôtel du Parc',
        extra: {'inTiles': false},
      );
      final online = api(pois: [hotel]);
      final map = FakeMap();
      await pumpLunaway(
        tester,
        map: map,
        size: _tall,
        online: online,
        pois: FakePoiSource(pois: [hotel]),
      );
      await tester.enterText(find.byType(TextField), 'Hôtel du Parc');
      await settleShort(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Hôtel du Parc'));
      await settleShort(tester);
      expect(inPoi(find.text('Hôtel du Parc')), findsOneWidget);
      expect(map.lastProps!.pois!.selected!.kind, PoiKind.hotel);
      expect(map.moves.last.center, _feature(hotel).position);
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
