import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/on_the_way_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart' hide FuelOffer;
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'navigation_test.dart' show driveFixes, tallPhone, utrillo;

PoiOnTheWay toilet(String name, {required double alongM, double detourS = 0, double offM = 40}) =>
    PoiOnTheWay(
      id: 'poi-$name',
      position: LatLng(45.846 + alongM / 1e7, 1.283),
      alongM: alongM,
      offM: offM,
      detourM: detourS * 10,
      detourS: detourS,
      kind: PoiKind.toilets,
      name: name,
    );

PlaceOnTheWay aire({
  required String name,
  required double alongM,
  Photo? photo,
  String? licence,
  double? price,
}) => PlaceOnTheWay(
  id: 'place-$name',
  position: LatLng(45.846 + alongM / 1e7, 1.283),
  alongM: alongM,
  offM: 300,
  detourM: 1400,
  detourS: 190,
  place: PlaceSummary(
    id: 'place-$name',
    kind: PlaceKind.motorhomeArea,
    lat: 45.846,
    lon: 1.283,
    overnight: OvernightStatus.allowed,
    name: name,
    services: const {Service.drinkingWater, Service.blackWater, Service.wifi},
    priceParkingEur: price,
    ratingAverage: 4.5,
    ratingCount: 12,
  ),
  photo: photo,
  photoLicence: licence,
);

const commonsPhoto = Photo(
  id: 'ph-1',
  sourceId: 'wikimedia-commons',
  thumbUrl: 'https://api.example.org/media/a/thumb.webp',
  largeUrl: 'https://api.example.org/media/a/full.webp',
  authorName: 'Jeanne',
);

FuelOffer station(String id) => FuelOffer(
  id: id,
  name: 'Station $id',
  position: const LatLng(45.8455, 1.2817),
  priceEur: 1.789,
  priceUpdatedAt: testNow.subtract(const Duration(hours: 3)),
  detourM: 0,
  detourS: 0,
  alongM: 1500,
  fuel: FuelType.diesel,
  open: StationOpen.open,
);

bool chosen(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

/// Taps the chip [label], scrolled into sight first: a row of chips runs
/// past the edge of a phone.
Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('the preview', () {
    late FakeRouteService routes;

    Future<TestApp> preview(
      WidgetTester tester, {
      FakeFuelStations? fuel,
      FakeOnTheWay? along,
      Vehicle vehicle = motorhome,
      Size size = tallPhone,
    }) async {
      routes = FakeRouteService([routeFixture('utrillo_motorhome'), routeFixture('limoges_drive')]);
      final app = await pumpLunaway(
        tester,
        size: size,
        overrides: navigationOverrides(
          routes: routes,
          fuel: fuel,
          onTheWay: along,
          vehicle: vehicle,
        ),
      );
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      return app;
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'Sur le trajet'));
      await settleShort(tester);
    }

    testWidgets("a vehicle's fuel reads in one line, another one a tap away", (tester) async {
      final fuel = FakeFuelStations(const []);
      await preview(
        tester,
        fuel: fuel,
        vehicle: motorhome.copyWith(fuel: () => FuelType.diesel),
      );
      await open(tester);
      expect(chosen(tester, 'Carburant'), isTrue, reason: 'fuel first');
      expect(find.text("Gazole, d'après votre véhicule"), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'SP98'), findsNothing, reason: 'no other fuel shown');
      expect(fuel.queries.single.fuel, FuelType.diesel);
      await tester.tap(find.text('Autre carburant'));
      await settleShort(tester);
      expect(chosen(tester, 'Gazole'), isTrue);
      await tapChip(tester, 'GPL');
      await settleShort(tester);
      expect(fuel.queries.last.fuel, FuelType.lpg);
    });

    testWidgets("without a fuel in the vehicle, the fuels show and one is kept as the vehicle's", (
      tester,
    ) async {
      final app = await preview(tester, fuel: FakeFuelStations(const []));
      await open(tester);
      expect(chosen(tester, 'Gazole'), isTrue);
      expect(find.textContaining("d'après votre véhicule"), findsNothing);
      await tapChip(tester, 'SP98');
      await settleShort(tester);
      await tester.tap(find.text('Retenir comme mon carburant'));
      await settleShort(tester);
      final saved = await tester.runAsync(
        () => app.container(tester).read(vehicleRepositoryProvider).watch().first,
      );
      expect(saved!.fuel, FuelType.sp98);
      expect(find.text('SP98 retenu pour votre véhicule.'), findsOneWidget);
    });

    testWidgets('another kind of stop lists what lies near by its minutes, the far ones folded', (
      tester,
    ) async {
      final along = FakeOnTheWay(
        pages: {
          'toilets': [
            OnTheWayPage(
              lineStartM: 2000,
              items: [
                toilet('Halle', alongM: 6000),
                toilet('Gare', alongM: 9000, detourS: 240, offM: 900),
                toilet('Loin', alongM: 90000),
              ],
            ),
          ],
        },
      );
      final app = await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Toilettes, douches');
      await settleShort(tester);
      expect(along.queries.single.search, OnTheWayCategory.toilets.search());
      expect(along.queries.single.fromM, 0);
      expect(find.text('Halle'), findsOneWidget);
      expect(find.text('Gare'), findsOneWidget);
      expect(find.text('Ajouter · sans détour'), findsOneWidget);
      expect(find.text('Ajouter · +4 min'), findsOneWidget);
      expect(find.textContaining('à 900 m de la route'), findsOneWidget);
      expect(find.text('Plus loin (1)'), findsOneWidget);
      expect(find.text('Loin'), findsNothing, reason: 'folded');
      await tester.tap(find.text('Plus loin (1)'));
      await settleShort(tester);
      expect(find.text('Loin'), findsOneWidget);
      await tester.tap(find.text('Ajouter · +4 min'));
      await settleShort(tester);
      expect(
        app.container(tester).read(routeStopsControllerProvider(utrillo)).single.poiId,
        'poi-Gare',
      );
      expect(routes.requests.last.stops, hasLength(1));
    });

    testWidgets('the chip chosen holds for the trip; the next trip starts from fuel', (
      tester,
    ) async {
      final app = await preview(tester, along: FakeOnTheWay());
      await open(tester);
      await tapChip(tester, 'Dormir');
      await settleShort(tester);
      await tester.tapAt(const Offset(10, 10));
      await settleShort(tester);
      await open(tester);
      expect(chosen(tester, 'Dormir'), isTrue);
      final choices = app.container(tester).read(onTheWayChoicesProvider.notifier);
      expect(
        choices.of(const RouteTarget(destination: LatLng(45.2, 1.5))).category,
        OnTheWayCategory.fuel,
      );
    });

    testWidgets('a chip kept from earlier is in sight when the list opens again', (tester) async {
      await preview(tester, along: FakeOnTheWay());
      await open(tester);
      await tapChip(tester, 'Garages et équipement');
      await settleShort(tester);
      await tester.tapAt(const Offset(10, 10));
      await settleShort(tester);
      await open(tester);
      final chip = tester.getRect(find.widgetWithText(ChoiceChip, 'Garages et équipement'));
      expect(chip.left, greaterThanOrEqualTo(0));
      expect(chip.right, lessThanOrEqualTo(400), reason: 'past the edge of the row otherwise');
    });

    testWidgets('a chip pressed from the keyboard keeps the focus', (tester) async {
      await preview(tester, along: FakeOnTheWay());
      await open(tester);
      final garages = find.widgetWithText(ChoiceChip, 'Garages et équipement');
      await tester.ensureVisible(garages);
      await tester.pump();
      Focus.of(tester.element(find.text('Garages et équipement'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleShort(tester);
      expect(tester.widget<ChoiceChip>(garages).selected, isTrue);
      expect(
        Focus.of(tester.element(find.text('Garages et équipement'))).hasPrimaryFocus,
        isTrue,
        reason: 'the chip just pressed, not one rebuilt in its place',
      );
    });

    testWidgets('nothing on the route says so; a failure says so and tries again', (tester) async {
      final along = FakeOnTheWay(pages: {'bakery': const []}, error: Exception('down'));
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Boulangeries');
      await settleShort(tester);
      expect(find.text("La liste n'a pas pu être chargée."), findsOneWidget);
      along.error = null;
      await tester.tap(find.text('Réessayer'));
      await settleShort(tester);
      expect(find.text('Pas de résultat sur ce trajet'), findsOneWidget);
      along.error = GraphQLNetworkException('offline', null);
      await tapChip(tester, 'Santé');
      await settleShort(tester);
      expect(find.text('Pas de réseau : la liste reviendra avec la connexion.'), findsOneWidget);
    });

    testWidgets('a shop says whether it is open when the vehicle gets there', (tester) async {
      final route = routeFixture('utrillo_motorhome').routes.first;
      final open = PoiOnTheWay(
        id: 'poi-open',
        position: route.line[route.line.length ~/ 2],
        alongM: 1500,
        offM: 120,
        detourM: 3000,
        detourS: 600,
        kind: PoiKind.bakery,
        name: 'Fournil',
      );
      // Closed now, open from a minute before the vehicle gets there.
      final at = passageAt(route, 0, open, testNow)!;
      expect(at.difference(testNow).inMinutes, greaterThanOrEqualTo(5));
      final hours = PoiHours(
        intervals: [
          OpeningInterval(
            at.subtract(const Duration(minutes: 1)),
            at.add(const Duration(hours: 2)),
          ),
        ],
        validUntil: testNow.add(const Duration(days: 10)),
      );
      final along = FakeOnTheWay(
        pages: {
          'bakery': [
            OnTheWayPage(
              items: [
                PoiOnTheWay(
                  id: open.id,
                  position: open.position,
                  alongM: open.alongM,
                  offM: open.offM,
                  detourM: open.detourM,
                  detourS: open.detourS,
                  kind: open.kind,
                  name: open.name,
                  hours: hours,
                ),
                PoiOnTheWay(
                  id: 'poi-shut',
                  position: open.position,
                  alongM: open.alongM,
                  offM: open.offM,
                  detourM: open.detourM,
                  detourS: open.detourS,
                  kind: PoiKind.bakery,
                  name: 'Mie',
                  hours: PoiHours(
                    intervals: const [],
                    validUntil: testNow.add(const Duration(days: 1)),
                  ),
                ),
              ],
            ),
          ],
        },
      );
      await preview(tester, along: along);
      expect(
        PoiHours(intervals: hours.intervals, validUntil: hours.validUntil).opennessAt(testNow),
        PoiOpenness.closed,
        reason: 'closed now: what the row says is the passage',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Sur le trajet'));
      await settleShort(tester);
      await tapChip(tester, 'Boulangeries');
      await settleShort(tester);
      expect(find.textContaining('Ouvert à votre passage, vers'), findsOneWidget);
      expect(find.textContaining('Fermé à votre passage, vers'), findsOneWidget);
    });

    testWidgets('restaurants and sights have their chips; hours unknown said where hours exist', (
      tester,
    ) async {
      final route = routeFixture('utrillo_motorhome').routes.first;
      PoiOnTheWay stop(String id, PoiKind kind, String name) => PoiOnTheWay(
        id: id,
        position: route.line[route.line.length ~/ 2],
        alongM: 1500,
        offM: 120,
        detourM: 3000,
        detourS: 600,
        kind: kind,
        name: name,
      );
      final along = FakeOnTheWay(
        pages: {
          PoiCategory.food.kinds.first.code: [
            OnTheWayPage(items: [stop('r', PoiKind.restaurant, 'Le Garde Manger')]),
          ],
          PoiCategory.sights.kinds.first.code: [
            OnTheWayPage(
              items: [
                stop('v', PoiKind.viewpoint, "Vue sur la plaine de l'Ain"),
                stop('m', PoiKind.museum, 'Musée du Cheminot'),
              ],
            ),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Restaurants et cafés');
      await settleShort(tester);
      expect(along.queries.last.search.poiKinds, PoiCategory.food.kinds);
      expect(find.text('Le Garde Manger'), findsOneWidget);
      expect(find.textContaining('Horaires inconnus'), findsOneWidget, reason: 'a restaurant has');
      await tapChip(tester, 'À voir');
      await settleShort(tester);
      expect(along.queries.last.search.poiKinds, PoiCategory.sights.kinds);
      expect(find.text('Musée du Cheminot'), findsOneWidget);
      expect(
        find.textContaining('Horaires inconnus'),
        findsOneWidget,
        reason: 'the museum has hours to know, the viewpoint none',
      );
    });

    testWidgets('a place to sleep shows its night, price, services and its photo with its credit', (
      tester,
    ) async {
      final along = FakeOnTheWay(
        pages: {
          'places': [
            OnTheWayPage(
              items: [
                aire(
                  name: 'Aire du lac',
                  alongM: 12000,
                  photo: commonsPhoto,
                  licence: 'CC BY-SA 4.0',
                  price: 12,
                ),
              ],
            ),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Dormir');
      await settleShort(tester);
      expect(along.queries.single.search.places!.overnight, {
        OvernightStatus.allowed,
        OvernightStatus.tolerated,
      });
      expect(find.text('Aire du lac'), findsOneWidget);
      expect(find.textContaining('autorisée'), findsWidgets);
      // The euros as the locale writes them, with its narrow space.
      expect(find.textContaining(RegExp(r'^12\s€ la nuit$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Services : Eau potable')), findsOneWidget);
      expect(
        find.text('Photo : Wikimedia Commons · Jeanne, CC BY-SA 4.0'),
        findsOneWidget,
        reason: 'the credit the photo is shown under, beside it',
      );
    });

    testWidgets("the external source's photo is credited without the agreement's reference", (
      tester,
    ) async {
      final along = FakeOnTheWay(
        pages: {
          'places': [
            OnTheWayPage(
              items: [
                aire(
                  name: 'Aire du lac',
                  alongM: 12000,
                  photo: const Photo(
                    id: 'ph-x',
                    sourceId: extcomSourceId,
                    thumbUrl: 'https://api.example.org/external-photos/x/thumb.webp',
                    largeUrl: 'https://api.example.org/external-photos/x/full.webp',
                  ),
                  licence: 'EXTCOM-2026-10-07',
                ),
              ],
            ),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Dormir');
      await settleShort(tester);
      expect(find.text('Photo : Source communautaire externe'), findsOneWidget);
      expect(find.textContaining('EXTCOM'), findsNothing);
    });

    testWidgets('the place the trip goes to is not offered as a stop on the way', (tester) async {
      PlaceOnTheWay at(String id, LatLng position, double alongM) => PlaceOnTheWay(
        id: id,
        position: position,
        alongM: alongM,
        offM: 20,
        detourM: 100,
        detourS: 30,
        place: PlaceSummary(
          id: id,
          kind: PlaceKind.motorhomeArea,
          lat: position.lat,
          lon: position.lon,
          overnight: OvernightStatus.allowed,
          name: 'Aire $id',
        ),
      );
      final along = FakeOnTheWay(
        pages: {
          'places': [
            OnTheWayPage(
              items: [
                at('halte', const LatLng(45.846, 1.283), 3000),
                // The destination itself, and its copy from another source.
                at('utrillo', utrillo.destination, 7000),
                at('copie', const LatLng(45.84520, 1.28640), 7000),
              ],
            ),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Dormir');
      await settleShort(tester);
      expect(find.text('Aire halte'), findsOneWidget);
      expect(find.text('Aire utrillo'), findsNothing);
      expect(find.text('Aire copie'), findsNothing);
    });

    testWidgets('no station with a price says the prices are known in France only', (tester) async {
      await preview(tester, fuel: FakeFuelStations(const []));
      await open(tester);
      expect(
        find.text('Aucune station avec un prix de ce carburant près du trajet.'),
        findsOneWidget,
      );
      expect(
        find.text(
          "Les prix viennent du relevé du ministère de l'Économie : ils ne sont connus qu'en France.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('with a mouse the chips scroll by the wheel and by an arrow, fading at the edge', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await preview(tester, along: FakeOnTheWay(), size: const Size(1024, 900));
        await open(tester);
        final fuel = find.widgetWithText(ChoiceChip, 'Carburant');
        final before = tester.getTopLeft(fuel).dx;
        expect(find.byTooltip('Voir les filtres suivants'), findsOneWidget);
        // A wheel turns vertically: the row moves sideways.
        final scroll = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(scroll.hover(tester.getCenter(fuel)));
        await tester.sendEventToBinding(scroll.scroll(const Offset(0, 200)));
        await settleShort(tester);
        expect(tester.getTopLeft(fuel).dx, lessThan(before));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a stop added once the window widened is added all the same', (tester) async {
      final app = await preview(tester, fuel: FakeFuelStations([station('route')]));
      await open(tester);
      // From the phone's sheet to the side panel: the panel that opened
      // the list is gone.
      tester.view.physicalSize = const Size(1280, 900);
      await settleShort(tester);
      await tester.tap(find.text('Ajouter'));
      await settleShort(tester);
      expect(
        app.container(tester).read(routeStopsControllerProvider(utrillo)).single.label,
        'Station route',
      );
      expect(find.text('Étape ajoutée'), findsOneWidget);
    });

    testWidgets('the next pages come on demand, each item once, and a failed one is tried again', (
      tester,
    ) async {
      final along = FakeOnTheWay(
        pages: {
          'toilets': [
            OnTheWayPage(items: [toilet('Halle', alongM: 6000)]),
            OnTheWayPage(items: [toilet('Halle', alongM: 6000), toilet('Gare', alongM: 9000)]),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Toilettes, douches');
      await settleShort(tester);
      expect(find.text('Gare'), findsNothing);
      along.error = GraphQLNetworkException('offline', null);
      await tester.tap(find.text('Voir plus'));
      await settleShort(tester);
      expect(find.text("La suite n'a pas pu être chargée."), findsOneWidget);
      along.error = null;
      await tester.tap(find.text('Réessayer'));
      await settleShort(tester);
      expect(find.text('Gare'), findsOneWidget);
      expect(find.text('Halle'), findsOneWidget, reason: 'once, though both pages hold it');
      expect(find.text('Voir plus'), findsNothing, reason: 'the last page');
      expect(along.queries.last.after, '1');
    });

    testWidgets('a first page the engine emptied reads on rather than say nothing is there', (
      tester,
    ) async {
      final along = FakeOnTheWay(
        pages: {
          'toilets': [
            OnTheWayPage.empty,
            OnTheWayPage(items: [toilet('Halle', alongM: 6000)]),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Toilettes, douches');
      await settleShort(tester);
      expect(find.text('Halle'), findsOneWidget);
      expect(find.text('Pas de résultat sur ce trajet'), findsNothing);
    });

    testWidgets('a point without a name says its kind once', (tester) async {
      final along = FakeOnTheWay(
        pages: {
          'toilets': [
            const OnTheWayPage(
              items: [
                PoiOnTheWay(
                  id: 'poi-bare',
                  position: LatLng(45.846, 1.283),
                  alongM: 6000,
                  offM: 40,
                  detourM: 0,
                  detourS: 0,
                  kind: PoiKind.toilets,
                ),
                PoiOnTheWay(
                  id: 'poi-blank',
                  position: LatLng(45.85, 1.29),
                  alongM: 7000,
                  offM: 40,
                  detourM: 0,
                  detourS: 0,
                  kind: PoiKind.shower,
                  name: ' ',
                ),
              ],
            ),
          ],
        },
      );
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Toilettes, douches');
      await settleShort(tester);
      expect(find.text('Toilettes'), findsOneWidget, reason: 'its title, not again under it');
      expect(find.text('Douches'), findsOneWidget, reason: 'a blank name is no name');
    });

    testWidgets('a server that asks to wait says so', (tester) async {
      final along = FakeOnTheWay(error: GraphQLRateLimitedException(const Duration(minutes: 2)));
      await preview(tester, along: along);
      await open(tester);
      await tapChip(tester, 'Courses');
      await settleShort(tester);
      expect(
        find.text("Beaucoup de recherches d'affilée : réessayez dans quelques minutes."),
        findsOneWidget,
      );
    });
  });

  group('the guidance', () {
    Future<TestApp> guide(
      WidgetTester tester, {
      FakeFuelStations? fuel,
      Size size = const Size(400, 860),
    }) async {
      final plan = routeFixture('limoges_drive');
      // A stop's quote and the route through it.
      final detour = routeFixture('closure_detour');
      final routes = FakeRouteService([detour, plan]);
      final feed = FakeLocationFeed(position: plan.routes.first.line.first);
      final app = await pumpLunaway(
        tester,
        size: size,
        overrides: navigationOverrides(
          routes: routes,
          feed: feed,
          engine: LineEngine([plan, detour, plan]),
          fuel: fuel,
        ),
      );
      await app
          .container(tester)
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: plan.routes.first.index,
            target: utrillo,
            words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          );
      unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      for (final f in driveFixes(plan.routes.first, toM: 500)) {
        feed.send(f);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleShort(tester);
      return app;
    }

    testWidgets('while driving, the list opens at once at half height', (tester) async {
      final fuel = FakeFuelStations(const []);
      final app = await guide(tester, fuel: fuel);
      final speed = app.container(tester).read(guidanceControllerProvider)!.lastFix!.speedMps!;
      expect(speed * 3.6, greaterThan(10), reason: 'driving, not standing still');
      await tester.tap(find.byTooltip('Sur le trajet'));
      await settleShort(tester);
      expect(find.byType(AlertDialog), findsNothing, reason: 'no question before the list');
      expect(fuel.queries, hasLength(1));
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(sheet.height / screen.height, closeTo(0.5, 0.06), reason: 'half the screen');
      final maneuver = tester.getRect(find.byType(ManeuverIcon).first);
      expect(maneuver.bottom, lessThan(sheet.top), reason: 'the maneuver stays in sight');
    });

    testWidgets('a stop added once the phone turned is added all the same', (tester) async {
      final app = await guide(tester, fuel: FakeFuelStations([station('route')]));
      await tester.tap(find.byTooltip('Sur le trajet'));
      await settleShort(tester);
      // The screen under the sheet is rebuilt for the landscape layout.
      tester.view.physicalSize = const Size(900, 400);
      await settleShort(tester);
      await tester.ensureVisible(find.text('Ajouter'));
      await settleShort(tester);
      await tester.tap(find.text('Ajouter'));
      await settleShort(tester);
      expect(
        app.container(tester).read(guidanceControllerProvider)!.stops.single.label,
        'Station route',
      );
      expect(find.text('Étape ajoutée'), findsOneWidget);
    });

    testWidgets('on a phone on its side, the list opens tall enough to show a result', (
      tester,
    ) async {
      await guide(tester, fuel: FakeFuelStations([station('route')]), size: const Size(900, 400));
      await tester.tap(find.byTooltip('Sur le trajet'));
      await settleShort(tester);
      final add = tester.getRect(find.text('Ajouter'));
      expect(
        add.bottom,
        lessThanOrEqualTo(400),
        reason: 'the first station in sight, not only the chips',
      );
    });
  });
}
