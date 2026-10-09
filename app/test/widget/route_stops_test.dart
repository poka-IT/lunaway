import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show driveFixes, tallPhone, utrillo;

/// An aire by the Utrillo route, 30 m off the road.
const aire = PlaceSummary(
  id: 'aire-naveix',
  kind: PlaceKind.motorhomeArea,
  lat: 45.8462,
  lon: 1.2828,
  overnight: OvernightStatus.allowed,
  name: 'Aire du Naveix',
);

FuelOffer station(String id, {required double price, double detourM = 0, double at = 900}) =>
    FuelOffer(
      id: id,
      name: 'Station $id',
      position: LatLng(45.8455 + at / 1e6, 1.2817),
      priceEur: price,
      priceUpdatedAt: testNowMinus(const Duration(hours: 3)),
      detourM: detourM,
      detourS: detourM / 14,
      alongM: at,
      fuel: FuelType.e10,
      open: StationOpen.open,
      detourEstimated: true,
    );

DateTime testNowMinus(Duration d) => DateTime.utc(2026, 10, 6, 8, 30).subtract(d);

void main() {
  group('the preview', () {
    late FakeRouteService routes;

    Future<TestApp> preview(
      WidgetTester tester, {
      List<Object>? answers,
      List<PlaceSummary> places = const [],
      FakeFuelStations? fuel,
      Vehicle vehicle = motorhome,
      bool cached = false,
      Size size = tallPhone,
    }) async {
      routes = FakeRouteService(answers ?? [routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: size,
        overrides: navigationOverrides(
          routes: routes,
          placesNearRoute: places,
          fuel: fuel,
          vehicle: vehicle,
          service: cached ? CachingRouteService(routes) : null,
        ),
      );
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      return app;
    }

    testWidgets('a place by the route becomes a stop from its card, its detour shown first', (
      tester,
    ) async {
      final withStop = routeFixture('limoges_drive');
      await preview(tester, answers: [routeFixture('utrillo_motorhome'), withStop], places: [aire]);
      final map = SchematicRouteMap.last!;
      expect(map.marks.where((m) => m.id == 'place:aire-naveix'), hasLength(1));
      map.onMarkTap!('place:aire-naveix');
      await settleShort(tester);
      expect(find.text('Aire du Naveix'), findsOneWidget);
      // 309 s instead of 191 s: two minutes more.
      expect(find.text('Ajouter comme étape · +2 min'), findsOneWidget);
      expect(routes.requests.last.stops, [const LatLng(45.8462, 1.2828)]);
      await tester.tap(find.text('Ajouter comme étape · +2 min'));
      await settleShort(tester);
      expect(find.text('Étapes'), findsOneWidget);
      expect(find.byTooltip("Retirer l'étape"), findsOneWidget);
      expect(routes.requests.last.stops, [const LatLng(45.8462, 1.2828)]);
      expect(routes.requests.last.alternatives, 0, reason: 'the API takes none with stops');
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(find.text('Étapes'), findsNothing);
      expect(routes.requests.last.stops, isEmpty);
    });

    testWidgets('the detour computed for the card is the route taken: asked once', (tester) async {
      await preview(
        tester,
        answers: [routeFixture('utrillo_motorhome'), routeFixture('limoges_drive')],
        places: [aire],
        cached: true,
      );
      SchematicRouteMap.last!.onMarkTap!('place:aire-naveix');
      await settleShort(tester);
      await tester.tap(find.text('Ajouter comme étape · +2 min'));
      await settleShort(tester);
      expect(find.text('Étapes'), findsOneWidget);
      expect(routes.requests, hasLength(2), reason: 'the preview, then the detour; no third');
    });

    testWidgets('without network, the card says so rather than blame the vehicle', (tester) async {
      await preview(
        tester,
        answers: [routeFixture('utrillo_motorhome'), const RouteFailure(RouteFailureKind.offline)],
        places: [aire],
      );
      SchematicRouteMap.last!.onMarkTap!('place:aire-naveix');
      await settleShort(tester);
      expect(find.text('Pas de réseau pour calculer le détour.'), findsOneWidget);
      expect(find.text("Pas d'itinéraire par ce point pour votre véhicule."), findsNothing);
    });

    testWidgets("a place's card opens over the route, the route kept", (tester) async {
      // The sample lake's id: its full card is in the test database.
      const lake = PlaceSummary(
        id: 'test-lake',
        kind: PlaceKind.motorhomeArea,
        lat: 45.8462,
        lon: 1.2828,
        overnight: OvernightStatus.allowed,
        name: 'Aire du Lac Bleu (démo)',
      );
      await preview(tester, places: [lake]);
      SchematicRouteMap.last!.onMarkTap!('place:test-lake');
      await settleShort(tester);
      await tester.tap(find.text('Voir la fiche'));
      await settleShort(tester);
      expect(find.byType(PlaceDetails), findsOneWidget);
      expect(find.text('Aire du Lac Bleu (démo)'), findsWidgets);
      expect(find.text('Vers Aire de la rue Utrillo'), findsWidgets, reason: 'the preview stays');
    });

    testWidgets('the card scrolls on a phone on its side, its last action in reach', (
      tester,
    ) async {
      const lake = PlaceSummary(
        id: 'test-lake',
        kind: PlaceKind.motorhomeArea,
        lat: 45.8462,
        lon: 1.2828,
        overnight: OvernightStatus.allowed,
        name: 'Aire du Lac Bleu (démo)',
      );
      await preview(tester, places: [lake], size: const Size(800, 360));
      SchematicRouteMap.last!.onMarkTap!('place:test-lake');
      await settleShort(tester);
      await tester.ensureVisible(find.text('Voir la fiche'));
      await settleShort(tester);
      await tester.tap(find.text('Voir la fiche'));
      await settleShort(tester);
      expect(find.byType(PlaceDetails), findsOneWidget);
    });

    testWidgets('a stop on the map is taken out from its card', (tester) async {
      final app = await preview(tester);
      const a = RouteStop(position: LatLng(45.846, 1.283), label: 'Étape A');
      app.container(tester).read(routeStopsControllerProvider(utrillo).notifier).set([a]);
      await settleShort(tester);
      final mark = SchematicRouteMap.last!.marks.singleWhere((m) => m.kind == RouteMarkKind.stop);
      SchematicRouteMap.last!.onMarkTap!(mark.id);
      await settleShort(tester);
      await tester.tap(find.text("Retirer l'étape").last);
      await settleShort(tester);
      expect(app.container(tester).read(routeStopsControllerProvider(utrillo)), isEmpty);
      expect(routes.requests.last.stops, isEmpty);
    });

    testWidgets('a held point can be gone to directly', (tester) async {
      await preview(tester);
      SchematicRouteMap.last!.onLongPress!(const LatLng(45.84, 1.27));
      await settleShort(tester);
      expect(find.text('Point sur la carte'), findsOneWidget);
      expect(find.text('Voir la fiche'), findsNothing, reason: 'a bare point has no card');
      await tester.tap(find.text('Y aller directement'));
      await settleShort(tester);
      expect(routes.requests.last.destination, const LatLng(45.84, 1.27));
      expect(find.text('Point sur la carte'), findsOneWidget, reason: 'the preview of the point');
      expect(find.text('Vers Aire de la rue Utrillo'), findsNothing);
    });

    testWidgets('a stop is removed by its cross, and comes back with undo', (tester) async {
      final app = await preview(tester);
      const a = RouteStop(position: LatLng(45.846, 1.283), label: 'Étape A');
      const b = RouteStop(position: LatLng(45.845, 1.285), label: 'Étape B');
      app.container(tester).read(routeStopsControllerProvider(utrillo).notifier).set([a, b]);
      await settleShort(tester);
      expect(find.text('Étape A'), findsOneWidget);
      expect(routes.requests.last.stops, [a.position, b.position]);
      await tester.tap(find.byTooltip("Retirer l'étape").first);
      await settleShort(tester);
      expect(find.text('Étape A'), findsNothing);
      expect(routes.requests.last.stops, [b.position]);
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(find.text('Étape A'), findsOneWidget);
      expect(routes.requests.last.stops, [a.position, b.position]);
    });

    testWidgets('the window widened while a card is open: its choice still counts', (tester) async {
      final app = await preview(tester);
      const a = RouteStop(position: LatLng(45.846, 1.283), label: 'Étape A');
      app.container(tester).read(routeStopsControllerProvider(utrillo).notifier).set([a]);
      await settleShort(tester);
      final mark = SchematicRouteMap.last!.marks.singleWhere((m) => m.kind == RouteMarkKind.stop);
      SchematicRouteMap.last!.onMarkTap!(mark.id);
      await settleShort(tester);
      // From the phone's sheet to the side panel: another map under the card.
      tester.view.physicalSize = const Size(1280, 900);
      await settleShort(tester);
      await tester.tap(find.text("Retirer l'étape").last);
      await settleShort(tester);
      expect(app.container(tester).read(routeStopsControllerProvider(utrillo)), isEmpty);
      expect(find.text('Étape retirée'), findsOneWidget);
    });

    testWidgets('a stop dragged below the next one changes their order, undoable', (tester) async {
      final app = await preview(tester);
      const a = RouteStop(position: LatLng(45.846, 1.283), label: 'Étape A');
      const b = RouteStop(position: LatLng(45.845, 1.285), label: 'Étape B');
      app.container(tester).read(routeStopsControllerProvider(utrillo).notifier).set([a, b]);
      await settleShort(tester);
      final handle = find.byTooltip("Glisser pour changer l'ordre").first;
      final drag = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await drag.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await settleShort(tester);
      expect(app.container(tester).read(routeStopsControllerProvider(utrillo)), [b, a]);
      expect(routes.requests.last.stops, [b.position, a.position]);
      expect(find.text('Ordre des étapes changé'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(routes.requests.last.stops, [a.position, b.position]);
    });

    testWidgets('the fuel list puts the detour in the price, and one tap makes a stop', (
      tester,
    ) async {
      final fuel = FakeFuelStations([
        station('loin', price: 1.700, detourM: 30000),
        station('route', price: 1.789),
        station('pres', price: 1.739, detourM: 1500),
      ]);
      await preview(
        tester,
        answers: [routeFixture('utrillo_motorhome'), routeFixture('limoges_drive')],
        fuel: fuel,
        vehicle: motorhome.copyWith(fuel: () => FuelType.e10),
      );
      await tester.tap(find.text('Sur le trajet'));
      await settleShort(tester);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Carburant')).selected,
        isTrue,
        reason: 'fuel first',
      );
      expect(fuel.queries.single.fuel, FuelType.e10, reason: "the vehicle's fuel first");
      final names = tester
          .widgetList<Text>(find.textContaining('Station '))
          .map((t) => t.data)
          .toList();
      expect(names, ['Station pres', 'Station route', 'Station loin']);
      expect(find.textContaining('1,739 €/L · il y a 3 h'), findsOneWidget);
      expect(find.textContaining('+1,5 km · +2 min · Ouvert'), findsOneWidget);
      expect(
        SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.fuel),
        hasLength(3),
      );
      await tester.tap(find.text('Ajouter').first);
      await settleShort(tester);
      expect(find.text('Étapes'), findsOneWidget);
      expect(find.text('Station pres'), findsOneWidget);
      expect(routes.requests.last.stops, hasLength(1));
    });
  });

  group('the guidance', () {
    late FakeRouteService routes;
    late FakeLocationFeed feed;

    Future<TestApp> guide(
      WidgetTester tester,
      RoutePlan plan, {
      List<Object> answers = const [],
      List<RoutePlan> more = const [],
      FakeFuelStations? fuel,
      List<RouteStop> stops = const [],
      List<PlaceSummary> places = const [],
    }) async {
      routes = FakeRouteService(answers.isEmpty ? [plan] : answers);
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      final app = await pumpLunaway(
        tester,
        size: tallPhone,
        overrides: navigationOverrides(
          routes: routes,
          feed: feed,
          engine: LineEngine([plan, ...more]),
          fuel: fuel,
          placesNearRoute: places,
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
            stops: stops,
          );
      unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      return app;
    }

    Future<void> drive(WidgetTester tester, RoutePlan plan, {required double toM}) async {
      for (final f in driveFixes(plan.routes.first, toM: toM)) {
        feed.send(f);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleShort(tester);
    }

    testWidgets('a station of the fuel list becomes a stop from where the vehicle is, undoable', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final detour = routeFixture('closure_detour');
      final app = await guide(
        tester,
        plan,
        answers: [detour, plan],
        more: [detour, plan],
        fuel: FakeFuelStations([station('route', price: 1.789, at: 1500)]),
      );
      await drive(tester, plan, toM: 500);
      final speed = app.container(tester).read(guidanceControllerProvider)!.lastFix!.speedMps!;
      expect(speed * 3.6, greaterThan(10), reason: 'driving, not standing still');
      await tester.tap(find.byTooltip('Sur le trajet'));
      await settleShort(tester);
      await tester.tap(find.text('Ajouter'));
      await settleShort(tester);
      expect(find.byType(AlertDialog), findsNothing, reason: 'no question on the way');
      final session = app.container(tester).read(guidanceControllerProvider)!;
      expect(session.stops.single.label, 'Station route');
      expect(session.plan, same(detour));
      final request = routes.requests.first;
      expect(request.stops, [session.stops.single.position]);
      expect(request.origin.distanceTo(LineTrack(plan.routes.first).at(500)), lessThan(15));
      expect(find.text('Étape ajoutée'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, isEmpty);
      expect(routes.requests.last.stops, isEmpty);
    });

    testWidgets('without network, the fuel list says why the station is not added', (tester) async {
      final plan = routeFixture('limoges_drive');
      final app = await guide(
        tester,
        plan,
        answers: [const RouteFailure(RouteFailureKind.offline)],
        fuel: FakeFuelStations([station('route', price: 1.789, at: 1500)]),
      );
      await drive(tester, plan, toM: 500);
      await tester.tap(find.byTooltip('Sur le trajet'));
      await settleShort(tester);
      await tester.tap(find.text('Ajouter'));
      await settleShort(tester);
      expect(find.text('Pas de réseau pour calculer le détour.'), findsOneWidget);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, isEmpty);
    });

    testWidgets('a stop added that the server moves says both, its undo kept', (tester) async {
      final plan = routeFixture('limoges_drive');
      final track = LineTrack(plan.routes.first);
      final moved = routeFixture(
        'closure_detour',
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 1, 'lat': 45.8352, 'lon': 1.2655, 'distanceM': 90.0},
        ],
      );
      await guide(tester, plan, answers: [moved], more: [moved]);
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onLongPress!(track.at(2500));
      await settleShort(tester);
      await tester.tap(find.textContaining('Ajouter comme étape'));
      await settleShort(tester);
      expect(
        find.text('Étape ajoutée\nÉtape 1 déplacée de 90 m vers la rue accessible la plus proche'),
        findsOneWidget,
      );
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('a detour priced from too far behind is priced again from where the vehicle is', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final detour = routeFixture('closure_detour');
      final track = LineTrack(plan.routes.first);
      final app = await guide(tester, plan, answers: [detour], more: [detour, detour]);
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onLongPress!(track.at(2500));
      await settleShort(tester);
      expect(routes.requests, hasLength(1), reason: 'the card prices the stop');
      // The card stays open while the vehicle drives on 500 m.
      await drive(tester, plan, toM: 800);
      await tester.tap(find.textContaining('Ajouter comme étape'));
      await settleShort(tester);
      expect(routes.requests, hasLength(2), reason: 'priced again, then that route taken');
      expect(routes.requests.last.origin.distanceTo(track.at(800)), lessThan(15));
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, hasLength(1));
    });

    testWidgets("a stop passed while the next one's card is open: only that one goes", (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final track = LineTrack(plan.routes.first);
      final a = RouteStop(position: track.at(800), label: 'Pause');
      final b = RouteStop(position: track.at(2000), label: 'Fontaine');
      final app = await guide(tester, plan, answers: [plan], more: [plan, plan], stops: [a, b]);
      List<RouteStop> stops() => app.container(tester).read(guidanceControllerProvider)!.stops;
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onMarkTap!('stop:1');
      await settleShort(tester);
      await drive(tester, plan, toM: 900);
      expect(stops(), [b], reason: 'the first stop is behind');
      await tester.tap(find.text("Retirer l'étape").last);
      await settleShort(tester);
      expect(stops(), isEmpty);
      expect(routes.requests.last.stops, isEmpty, reason: 'no way back to the first stop');
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(stops(), [b]);
      expect(routes.requests.last.stops, [b.position]);
    });

    testWidgets(
      'of two equal stops, the card takes out the one tapped, and the undo puts it back',
      (tester) async {
        final plan = routeFixture('limoges_drive');
        final track = LineTrack(plan.routes.first);
        final a = RouteStop(position: track.at(800), label: 'Pause');
        final b = RouteStop(position: track.at(2000), label: 'Fontaine');
        final app = await guide(
          tester,
          plan,
          answers: [plan, plan],
          more: [plan, plan],
          stops: [a, b, a],
        );
        List<RouteStop> stops() => app.container(tester).read(guidanceControllerProvider)!.stops;
        await drive(tester, plan, toM: 300);
        SchematicRouteMap.last!.onMarkTap!('stop:0');
        await settleShort(tester);
        await tester.tap(find.text("Retirer l'étape").last);
        await settleShort(tester);
        expect(stops(), [b, a], reason: 'the first stop out, not the last');
        expect(routes.requests.last.stops, [b.position, a.position]);
        await tester.tap(find.text('Annuler'));
        await settleShort(tester);
        expect(stops(), [a, b, a]);
      },
    );

    testWidgets('of two equal stops, the one tapped then passed is not taken for the other', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final track = LineTrack(plan.routes.first);
      final a = RouteStop(position: track.at(800), label: 'Pause');
      final b = RouteStop(position: track.at(2000), label: 'Fontaine');
      final app = await guide(tester, plan, answers: [plan], more: [plan], stops: [a, b, a]);
      List<RouteStop> stops() => app.container(tester).read(guidanceControllerProvider)!.stops;
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onMarkTap!('stop:0');
      await settleShort(tester);
      await drive(tester, plan, toM: 900);
      expect(stops(), [b, a], reason: 'the stop tapped is behind');
      await tester.tap(find.text("Retirer l'étape").last);
      await settleShort(tester);
      expect(stops(), [b, a], reason: 'the other copy stays on the route');
    });

    testWidgets('the phone turned while a card is open: its choice still counts', (tester) async {
      final plan = routeFixture('limoges_drive');
      final at = LineTrack(plan.routes.first).at(2000);
      final app = await guide(
        tester,
        plan,
        answers: [plan],
        more: [plan],
        stops: [RouteStop(position: at, label: 'Pause')],
      );
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onMarkTap!('stop:0');
      await settleShort(tester);
      // The map under the card is rebuilt for the landscape layout.
      tester.view.physicalSize = const Size(900, 400);
      await settleShort(tester);
      await tester.tap(find.text("Retirer l'étape").last);
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, isEmpty);
      expect(find.text('Étape retirée'), findsOneWidget);
    });

    testWidgets("the phone turned while a place's card is open: the place still opens", (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final road = LineTrack(plan.routes.first).at(2000);
      // The sample lake's id, by the road: its full card is in the test
      // database.
      final lake = PlaceSummary(
        id: 'test-lake',
        kind: PlaceKind.motorhomeArea,
        lat: road.lat,
        lon: road.lon,
        overnight: OvernightStatus.allowed,
        name: 'Aire du Lac Bleu (démo)',
      );
      await guide(tester, plan, places: [lake]);
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onMarkTap!('place:test-lake');
      await settleShort(tester);
      tester.view.physicalSize = const Size(900, 400);
      await settleShort(tester);
      await tester.ensureVisible(find.text('Voir la fiche'));
      await tester.tap(find.text('Voir la fiche'));
      await settleShort(tester);
      expect(find.byType(PlaceDetails), findsOneWidget);
    });

    testWidgets('a stop passed while its detour is priced again is not brought back', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final detour = routeFixture('closure_detour');
      final track = LineTrack(plan.routes.first);
      final pause = RouteStop(position: track.at(800), label: 'Pause');
      final app = await guide(
        tester,
        plan,
        answers: [detour],
        more: [detour, detour],
        stops: [pause],
      );
      List<RouteStop> stops() => app.container(tester).read(guidanceControllerProvider)!.stops;
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onLongPress!(track.at(2500));
      await settleShort(tester);
      // 400 m on: the detour is priced again when the stop is added, and
      // the answer waits while the vehicle passes the pause.
      await drive(tester, plan, toM: 700);
      routes.gate = Completer<void>();
      await tester.tap(find.textContaining('Ajouter comme étape'));
      await tester.pump();
      await drive(tester, plan, toM: 900);
      expect(stops(), isEmpty, reason: 'the pause is behind');
      routes.gate!.complete();
      await settleShort(tester);
      expect(stops(), isEmpty, reason: 'no way back to the pause');
      expect(routes.requests, hasLength(2), reason: 'the card, then the new price; no route taken');
      expect(find.text("L'itinéraire n'a pas pu être changé."), findsOneWidget);
    });

    testWidgets('a stop is left behind once the vehicle has been there', (tester) async {
      final plan = routeFixture('limoges_drive');
      final at = LineTrack(plan.routes.first).at(800);
      final app = await guide(
        tester,
        plan,
        stops: [RouteStop(position: at, label: 'Pause')],
      );
      expect(
        SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.stop),
        hasLength(1),
      );
      await drive(tester, plan, toM: 900);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, isEmpty);
    });

    testWidgets('a stop is taken out from its card on the guidance map', (tester) async {
      final plan = routeFixture('limoges_drive');
      final at = LineTrack(plan.routes.first).at(2000);
      final app = await guide(
        tester,
        plan,
        answers: [plan],
        more: [plan],
        stops: [RouteStop(position: at, label: 'Pause')],
      );
      await drive(tester, plan, toM: 300);
      SchematicRouteMap.last!.onMarkTap!('stop:0');
      await settleShort(tester);
      await tester.tap(find.text("Retirer l'étape").last);
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, isEmpty);
      expect(routes.requests.last.stops, isEmpty);
      expect(find.text('Étape retirée'), findsOneWidget);
    });

    testWidgets('a stop off the road is behind once the route has passed it', (tester) async {
      final plan = routeFixture('limoges_drive');
      final road = LineTrack(plan.routes.first).at(800);
      // 200 m north of the road: the router reaches it from the road.
      final off = LatLng(road.lat + 0.0018, road.lon);
      final app = await guide(
        tester,
        plan,
        stops: [RouteStop(position: off, label: 'Fontaine')],
      );
      await drive(tester, plan, toM: 700);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, hasLength(1));
      await drive(tester, plan, toM: 1000);
      expect(app.container(tester).read(guidanceControllerProvider)!.stops, isEmpty);
    });

    testWidgets('a stop and a destination the server moved keep their places once a stop is '
        'passed', (tester) async {
      final base = routeFixture('limoges_drive');
      final road = LineTrack(base.routes.first).at(800);
      final stopAt = LatLng(road.lat + 0.0018, road.lon);
      const movedStop = LatLng(45.8352, 1.2655);
      const movedEnd = LatLng(45.8101, 1.2302);
      final plan = routeFixture(
        'limoges_drive',
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 1, 'lat': movedStop.lat, 'lon': movedStop.lon, 'distanceM': 90.0},
          {'stopIndex': 2, 'lat': movedEnd.lat, 'lon': movedEnd.lon, 'distanceM': 60.0},
        ],
      );
      await guide(
        tester,
        plan,
        stops: [RouteStop(position: stopAt, label: 'Fontaine')],
      );
      LatLng markAt(String id) =>
          SchematicRouteMap.last!.marks.singleWhere((m) => m.id == id).position;
      await drive(tester, plan, toM: 700);
      expect(markAt('stop:0'), movedStop, reason: 'the stop where the route passes');
      expect(markAt('destination'), movedEnd);
      await drive(tester, plan, toM: 1000);
      expect(SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.stop), isEmpty);
      expect(
        markAt('destination'),
        movedEnd,
        reason: 'the stop passed and dropped, the destination stays where the route ends',
      );
    });
  });

  testWidgets("the detour to a station is weighed with the vehicle's own consumption", (
    tester,
  ) async {
    // 3 km of detour for 4 cents a litre: worth it at 11 L/100 km, not at 40.
    final fuel = FakeFuelStations([
      station('detour', price: 1.700, detourM: 3000),
      station('bord', price: 1.740),
    ]);
    final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
    final app = await pumpLunaway(
      tester,
      size: tallPhone,
      overrides: navigationOverrides(
        routes: routes,
        fuel: fuel,
        vehicle: motorhome.copyWith(fuel: () => FuelType.e10, consumptionL100: () => 40),
      ),
    );
    unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)));
    await settleShort(tester);
    await tester.tap(find.text('Sur le trajet'));
    await settleShort(tester);
    final names = tester
        .widgetList<Text>(find.textContaining('Station '))
        .map((t) => t.data)
        .toList();
    expect(names, ['Station bord', 'Station detour']);
  });
}
