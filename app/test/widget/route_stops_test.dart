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
      fuel: VehicleFuel.e10,
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
      MemoryRouteSettings? settings,
      bool cached = false,
    }) async {
      routes = FakeRouteService(answers ?? [routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: tallPhone,
        overrides: navigationOverrides(
          routes: routes,
          placesNearRoute: places,
          fuel: fuel,
          settings: settings,
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
      expect(find.text('Ajouter une étape · +2 min'), findsOneWidget);
      expect(routes.requests.last.stops, [const LatLng(45.8462, 1.2828)]);
      await tester.tap(find.text('Ajouter une étape · +2 min'));
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
      await tester.tap(find.text('Ajouter une étape · +2 min'));
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

    testWidgets('a stop on the map is taken out from its card', (tester) async {
      final app = await preview(tester);
      const a = RouteStop(position: LatLng(45.846, 1.283), label: 'Étape A');
      app.container(tester).read(routeStopsControllerProvider(utrillo).notifier).set([a]);
      await settleShort(tester);
      final mark = SchematicRouteMap.last!.marks.singleWhere((m) => m.kind == RouteMarkKind.stop);
      SchematicRouteMap.last!.onMarkTap!(mark.id!);
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
      expect(find.text('Point de la carte'), findsOneWidget);
      expect(find.text('Voir la fiche'), findsNothing, reason: 'a bare point has no card');
      await tester.tap(find.text('Y aller directement'));
      await settleShort(tester);
      expect(routes.requests.last.destination, const LatLng(45.84, 1.27));
      expect(find.text('Vers ce point'), findsOneWidget, reason: 'the preview of the point');
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
        settings: MemoryRouteSettings(const NavigationSettings(fuel: VehicleFuel.e10)),
      );
      await tester.tap(find.text('Carburant'));
      await settleShort(tester);
      expect(find.text('Carburant sur le trajet'), findsOneWidget);
      expect(fuel.queries.single.fuel, VehicleFuel.e10, reason: "the vehicle's fuel first");
      final names = tester
          .widgetList<Text>(find.textContaining('Station '))
          .map((t) => t.data)
          .toList();
      expect(names, ['Station pres', 'Station route', 'Station loin']);
      expect(find.textContaining('1,739 €/L · il y a 3 h'), findsOneWidget);
      expect(find.textContaining('+1,5 km · +2 min · Ouvert'), findsOneWidget);
      expect(
        SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.station),
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
      OneDangerZone? zone,
    }) async {
      routes = FakeRouteService(answers.isEmpty ? [plan] : answers);
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      final app = await pumpLunaway(
        tester,
        overrides: navigationOverrides(
          routes: routes,
          feed: feed,
          engine: LineEngine([plan, ...more]),
          fuel: fuel,
          zones: zone,
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
      await tester.tap(find.byTooltip('Carburant le moins cher devant'));
      await settleShort(tester);
      await tester.tap(find.text('Ajouter'));
      await settleShort(tester);
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

    testWidgets('a danger zone ahead shows in its banner, where the law allows one', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, zone: const OneDangerZone(startM: 1500));
      await drive(tester, plan, toM: 1000);
      expect(find.text('Zone de danger dans 500 m'), findsOneWidget);
    });
  });

  testWidgets('the profile keeps the fuel and the consumption', (tester) async {
    final settings = MemoryRouteSettings();
    await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      overrides: navigationOverrides(routes: FakeRouteService(const []), settings: settings),
    );
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    await tester.tap(find.text('Gazole'));
    await settleShort(tester);
    await tester.tap(find.text('GPL').last);
    await settleShort(tester);
    expect(settings.value.fuel, VehicleFuel.lpg);
    await tester.enterText(find.widgetWithText(TextField, '11'), '13,5');
    await settleShort(tester);
    expect(settings.value.consumptionL100, 13.5);
  });
}
