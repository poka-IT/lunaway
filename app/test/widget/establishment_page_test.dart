import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fake_api.dart';
import '../helpers/fakes.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

final Translations t = AppLocale.fr.buildSync();

/// A tall desktop window, where a page fits without scrolling.
const _tall = Size(1280, 3000);

Finder inPoi(Finder finder) => find.descendant(of: find.byType(PoiDetails), matching: finder);

/// An establishment of [kind], as the page of the API sends it.
Map<String, Object?> _establishment(
  String id,
  String kind, {
  String? name,
  Map<String, Object?> extra = const {},
}) => poiJson(
  '00000000-0000-7000-8000-00000000d$id',
  kind,
  name: name,
  extra: {'inTiles': false, ...extra},
);

/// Opens the page of [json] from the map, on a tall window.
Future<TestApp> _open(
  WidgetTester tester,
  Map<String, Object?> json, {
  FakePoiSource? pois,
  FakeApi? api,
  bool signedIn = false,
  Size size = _tall,
}) async {
  final map = FakeMap();
  final app = await pumpLunaway(
    tester,
    map: map,
    size: size,
    api: api,
    signedIn: signedIn,
    pois: pois ?? FakePoiSource(pois: [json]),
  );
  map.lastProps!.onPoiTap!(poiFromJson(json)!.feature);
  await settleShort(tester);
  return app;
}

void main() {
  group('the page of an establishment says what its kind needs', () {
    testWidgets('a restaurant: its cuisine, its diets, what one finds there; nothing unsaid', (
      tester,
    ) async {
      final restaurant = _establishment(
        '001',
        'RESTAURANT',
        name: 'Da Gino',
        extra: {
          'cuisine': ['pizza', 'italian', 'hot_pot'],
          'diets': ['vegetarian', 'gluten_free'],
          'takeaway': true,
          'outdoorSeating': false,
          'delivery': null,
          'reservation': 'RECOMMENDED',
          'internetAccess': true,
          'wheelchair': 'limited',
          'stars': 4,
          'vehicleServices': ['tyres'],
          'emergency': true,
        },
      );
      await _open(tester, restaurant);
      expect(inPoi(find.text(t.poi.details.cuisineTitle)), findsOneWidget);
      for (final word in [t.poi.cuisine.pizza, t.poi.cuisine.italian, 'Hot pot']) {
        expect(inPoi(find.text(word)), findsOneWidget, reason: word);
      }
      expect(inPoi(find.text(t.poi.diet.vegetarian)), findsOneWidget);
      expect(inPoi(find.text(t.poi.diet.glutenFree)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.takeaway)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.noOutdoorSeating)), findsOneWidget, reason: 'a no');
      expect(inPoi(find.text(t.poi.details.delivery)), findsNothing, reason: 'nothing said');
      expect(inPoi(find.text(t.poi.details.noDelivery)), findsNothing);
      expect(inPoi(find.text(t.poi.reservation.recommended)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.wifi)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.wheelchairLimited)), findsOneWidget);
      // What a restaurant has no use for, whatever the source says.
      expect(inPoi(find.textContaining(t.poi.details.stars(n: 4))), findsNothing);
      expect(inPoi(find.text(t.poi.details.vehicleServicesTitle)), findsNothing);
      expect(inPoi(find.text(t.poi.details.emergency)), findsNothing);
    });

    testWidgets('a hairdresser: its payments and its access, no cuisine nor terrace', (
      tester,
    ) async {
      final hairdresser = _establishment(
        '002',
        'HAIRDRESSER',
        name: 'Salon Mèche Rebelle',
        extra: {
          'payment': ['cash', 'cards'],
          'wheelchair': 'yes',
          'cuisine': ['pizza'],
          'takeaway': true,
          'phone': '+33 4 50 00 00 00',
        },
      );
      await _open(tester, hairdresser);
      expect(inPoi(find.text(t.poiKind(PoiKind.hairdresser))), findsWidgets);
      expect(inPoi(find.text(t.poi.paymentTitle)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.wheelchairYes)), findsOneWidget);
      expect(inPoi(find.text(t.place.call)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.cuisineTitle)), findsNothing);
      expect(inPoi(find.text(t.poi.details.takeaway)), findsNothing);
    });

    testWidgets('a health centre: whether it takes emergencies, not its Wi-Fi', (tester) async {
      final clinic = _establishment(
        '003',
        'CLINIC',
        name: 'Centre de santé du Lac',
        extra: {'emergency': true, 'internetAccess': true},
      );
      await _open(tester, clinic);
      expect(inPoi(find.text(t.poi.details.emergency)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.wifi)), findsNothing);
    });

    testWidgets('a hotel: its stars under its name, its booking and its Wi-Fi', (tester) async {
      final hotel = _establishment(
        '004',
        'HOTEL',
        name: 'Hôtel du Parc',
        extra: {
          'stars': 3,
          'reservation': 'REQUIRED',
          'internetAccess': false,
          'takeaway': true,
          'cuisine': ['french'],
        },
      );
      await _open(tester, hotel);
      expect(inPoi(find.textContaining(t.poi.details.stars(n: 3))), findsOneWidget);
      expect(inPoi(find.text(t.poi.reservation.required)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.noWifi)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.cuisineTitle)), findsNothing);
      expect(inPoi(find.text(t.poi.details.takeaway)), findsNothing);
    });

    testWidgets('a tyre fitter: what it works on and the vehicles it takes', (tester) async {
      final tyres = _establishment(
        '005',
        'TYRES',
        name: 'Pneus Alpes',
        extra: {
          'vehicleServices': ['tyres', 'brakes', 'oil_change', 'wheel_balancing'],
          'motorhome': true,
          'wheelchair': 'yes',
        },
      );
      await _open(tester, tyres);
      expect(inPoi(find.text(t.poi.details.vehicleServicesTitle)), findsOneWidget);
      // The kind says "Pneus" too, under the name.
      expect(inPoi(find.text(t.poi.vehicleService.tyres)), findsNWidgets(2));
      for (final word in [
        t.poi.vehicleService.brakes,
        t.poi.vehicleService.oilChange,
        'Wheel balancing',
      ]) {
        expect(inPoi(find.text(word)), findsOneWidget, reason: word);
      }
      expect(inPoi(find.text(t.poi.vehicles.motorhomeYes)), findsOneWidget);
      expect(inPoi(find.text(t.poi.details.wheelchairYes)), findsNothing);
    });

    testWidgets('a photo of an open source shows with its author, its licence and its page', (
      tester,
    ) async {
      final museum = _establishment(
        '006',
        'GALLERY',
        name: 'Galerie du Pâquier',
        extra: {
          'externalPhotos': [
            {
              'id': '00000000-0000-7000-8000-00000000e001',
              'sourceId': 'wikimedia-commons',
              'kind': 'PLACE',
              'authorName': 'Jean Dupont',
              'publisher': null,
              'sourceUpdatedOn': null,
              'licence': 'CC BY-SA 4.0',
              'licenceUrl': 'https://creativecommons.org/licenses/by-sa/4.0/',
              'pageUrl': 'https://commons.wikimedia.org/wiki/File:Galerie.jpg',
              'takenAt': null,
              'thumbUrl': '$testApiBase/media/w/thumb',
              'largeUrl': '$testApiBase/media/w/large',
              'width': 1600,
              'height': 1200,
              'thumbhash': null,
            },
          ],
        },
      );
      final app = await _open(tester, museum);
      expect(inPoi(find.textContaining('Jean Dupont')), findsOneWidget);
      expect(inPoi(find.textContaining('CC BY-SA 4.0')), findsOneWidget);
      expect(inPoi(find.textContaining('Wikimedia Commons')), findsOneWidget);
      await tester.tap(inPoi(find.text(t.place.viewSource)).first);
      await settleShort(tester);
      expect(
        app.external.opened.last,
        Uri.parse('https://commons.wikimedia.org/wiki/File:Galerie.jpg'),
      );
    });
  });

  group('the reviews of an establishment', () {
    testWidgets('the ratings of each source, then the reviews, the newest first', (tester) async {
      final cafe = _establishment(
        '010',
        'CAFE',
        name: 'Café des Arts',
        extra: {
          'ratings': [
            {'sourceId': 'community-cc-by', 'average': 4.5, 'count': 2},
          ],
          'externalRatings': [
            {'sourceId': 'mangrove', 'average': 3.0, 'count': 7},
          ],
        },
      );
      final pois = FakePoiSource(pois: [cafe])
        ..reviewsOf[cafe['id']! as String] = (
          mine: null,
          ours: ReviewPage(
            nodes: [
              Review(
                id: '00000000-0000-7000-8000-00000000f001',
                sourceId: 'community-cc-by',
                rating: 5,
                text: 'Un café calme, une terrasse au soleil.',
                authorName: 'Marmotte',
                createdAt: DateTime.utc(2026, 10, 2),
              ),
            ],
            hasNextPage: false,
            totalCount: 1,
          ),
          external: ReviewPage(
            nodes: [
              Review(
                id: '00000000-0000-7000-8000-00000000f002',
                sourceId: 'mangrove',
                rating: 3,
                text: 'Service lent mais accueil sympathique.',
                createdAt: DateTime.utc(2026, 10, 4),
              ),
            ],
            hasNextPage: false,
            totalCount: 1,
          ),
        );
      await _open(tester, cafe, pois: pois);
      expect(inPoi(find.text('Mangrove Reviews')), findsWidgets, reason: 'each source its badge');
      final newer = tester.getTopLeft(inPoi(find.text('Service lent mais accueil sympathique.')));
      final older = tester.getTopLeft(inPoi(find.text('Un café calme, une terrasse au soleil.')));
      expect(newer.dy, lessThan(older.dy));
      expect(inPoi(find.text(t.place.noReviews)), findsNothing);
    });

    testWidgets('without any review it says so; offline, it offers to try again', (tester) async {
      final bar = _establishment('011', 'BAR', name: 'Le Tonneau');
      final pois = FakePoiSource(pois: [bar])..reviewsOffline = true;
      await _open(tester, bar, pois: pois);
      expect(inPoi(find.text(t.poi.details.reviewsError)), findsOneWidget);
      pois.reviewsOffline = false;
      await tester.tap(inPoi(find.text(t.common.retry)));
      await settleShort(tester);
      expect(inPoi(find.text(t.place.noReviews)), findsOneWidget);
    });

    testWidgets('a star rates the point; a review is written under the rules of a place', (
      tester,
    ) async {
      final bakery = _establishment('012', 'PASTRY', name: 'Pâtisserie du Lac');
      final api = FakeApi(level: 1);
      final pois = FakePoiSource(pois: [bakery]);
      await _open(tester, bakery, pois: pois, api: api, signedIn: true);
      final reads = pois.reviewReads;
      await tester.tap(inPoi(find.byTooltip(t.contribute.rateStar(n: 4))));
      await settleShort(tester, const Duration(seconds: 4));
      expect(api.last('RatePoi'), {'poiId': bakery['id'], 'stars': 4});
      expect(pois.reviewReads, greaterThan(reads), reason: 'the reviews read again');

      await tester.tap(inPoi(find.text(t.contribute.writeReview)));
      await settleShort(tester);
      expect(find.text(t.reviewSheet.licence), findsOneWidget, reason: 'CC BY, as for a place');
      expect(find.text(t.reviewSheet.vehicle), findsNothing, reason: 'a point names no vehicle');
      await tester.tap(find.byTooltip(t.contribute.rateStar(n: 5)).last);
      await tester.enterText(find.byType(TextField).last, 'Des tartes aux myrtilles parfaites.');
      await tester.tap(find.text(t.reviewSheet.publish));
      await settleShort(tester, const Duration(seconds: 4));
      final sent = api.last('ReviewPoi')!;
      expect(sent['poiId'], bakery['id']);
      expect(sent['stars'], 5);
      expect(sent['text'], 'Des tartes aux myrtilles parfaites.');
      expect(sent.containsKey('vehicle'), isFalse);
    });

    testWidgets('below level 1 writing a review says which level opens it', (tester) async {
      final bakery = _establishment('013', 'PASTRY', name: 'Pâtisserie du Port');
      await _open(tester, bakery, api: FakeApi(), signedIn: true);
      await tester.tap(inPoi(find.text(t.contribute.writeReview)));
      await settleShort(tester);
      expect(find.text(t.account.nextLevel(level: '1')), findsOneWidget);
      expect(find.text(t.reviewSheet.publish), findsNothing);
    });

    testWidgets('the link to Google Maps opens the search of its name where it stands', (
      tester,
    ) async {
      final pizzeria = _establishment('014', 'RESTAURANT', name: "Pizz'à Gino");
      final app = await _open(tester, pizzeria);
      expect(inPoi(find.text(t.poi.details.googleMapsHint)), findsOneWidget);
      await tester.tap(inPoi(find.text(t.poi.details.googleMaps)));
      await settleShort(tester);
      expect(
        app.external.opened.single,
        Uri.parse("https://www.google.com/maps/search/Pizz'%C3%A0%20Gino/@45.900200,6.130000,17z"),
      );
    });

    testWidgets('an unnamed point has no link to Google Maps: nothing to search', (tester) async {
      final toilets = _establishment('015', 'TOILETS');
      await _open(tester, toilets);
      expect(inPoi(find.text(t.poi.details.googleMaps)), findsNothing);
    });
  });

  group('the page of an establishment in the three layouts', () {
    for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
      testWidgets('on a $name, its sections, its reviews and the way there', (tester) async {
        final restaurant = _establishment(
          '020',
          'RESTAURANT',
          name: 'Le Garde Manger',
          extra: {
            'cuisine': ['regional'],
          },
        );
        await _open(tester, restaurant, size: size);
        expect(inPoi(find.text('Le Garde Manger')), findsOneWidget);
        expect(find.text(t.place.directions), findsWidgets, reason: 'the action bar');
        final scrollable = find
            .descendant(of: find.byType(PoiDetails), matching: find.byType(Scrollable))
            .first;
        for (final text in [
          t.poi.cuisine.regional,
          t.contribute.writeReview,
          t.poi.details.googleMaps,
        ]) {
          await tester.scrollUntilVisible(inPoi(find.text(text)), 200, scrollable: scrollable);
          await settleShort(tester);
          expect(inPoi(find.text(text)).hitTestable(), findsOneWidget, reason: text);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
