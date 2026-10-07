import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_entry.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/widgets/lanes_row.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fake_api.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

const utrillo = RouteTarget(
  destination: LatLng(45.84510, 1.28637),
  label: 'Aire de la rue Utrillo',
  placeId: 'utrillo',
);

/// A phone tall enough that the whole preview panel is built.
const tallPhone = Size(400, 2400);

/// The app with the navigation's fakes, on the preview of [target].
Future<(TestApp, FakeRouteService)> openPreview(
  WidgetTester tester, {
  List<Object>? answers,
  Size size = tallPhone,
  Vehicle? vehicle = motorhome,
  FakeLocationFeed? feed,
  GuidanceEngine? engine,
  MemoryRouteSettings? settings,
  RouteTarget target = utrillo,
  CountedNotificationAccess? notifications,
  FakeApi? api,
}) async {
  final routes = FakeRouteService(answers ?? [routeFixture('utrillo_motorhome')]);
  final app = await pumpLunaway(
    tester,
    size: size,
    api: api,
    overrides: navigationOverrides(
      routes: routes,
      vehicle: vehicle,
      feed: feed,
      engine: engine,
      settings: settings,
      notifications: notifications,
    ),
  );
  unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(target)));
  await settleShort(tester);
  return (app, routes);
}

void main() {
  setUp(() => SchematicRouteMap.last = null);

  group('the way into the guidance', () {
    testWidgets('"Itinéraire" offers the Lunaway guidance first, then the apps', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        overrides: navigationOverrides(routes: routes),
      );
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(dayParking.id));
      await settleShort(tester);
      await tester.tap(find.text('Itinéraire'));
      await settleShort(tester);
      expect(find.text('Guidage Lunaway'), findsOneWidget);
      expect(
        find.text(
          'Intégral · H\u00a03,30\u00a0m · l\u00a02,30\u00a0m · L\u00a07,4\u00a0m · 3,5\u00a0t',
        ),
        findsOneWidget,
      );
      expect(find.text('Autres applications'), findsOneWidget);
      final lunaway = tester.getTopLeft(find.text('Guidage Lunaway'));
      expect(lunaway.dy, lessThan(tester.getTopLeft(find.text('Waze')).dy));
      await tester.tap(find.text('Guidage Lunaway'));
      await settleShort(tester);
      expect(routes.requests.single.destination, dayParking.position);
      expect(routes.requests.single.vehicle.heightM, 3.3);
      expect(find.textContaining('Vers Parking des Tilleuls'), findsOneWidget);
      // Remembered: the next trip goes straight to the route.
      expect(app.settings.value.navigationApp, lunawayDirectionsId);
    });

    testWidgets('without a vehicle, the guidance says to describe it first', (tester) async {
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        overrides: navigationOverrides(
          routes: FakeRouteService([routeFixture('utrillo_motorhome')]),
          vehicle: null,
        ),
      );
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(dayParking.id));
      await settleShort(tester);
      await tester.tap(find.text('Itinéraire'));
      await settleShort(tester);
      expect(
        find.textContaining('Décrivez d’abord votre véhicule'.replaceAll('’', "'")),
        findsOneWidget,
      );
    });

    testWidgets('a long-pressed point can be guided to as well', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        settings: const AppSettings(navigationApp: lunawayDirectionsId),
        overrides: navigationOverrides(routes: routes),
      );
      const point = LatLng(45.7629, 4.831697);
      app.container(tester).read(selectionProvider.notifier).select(const PointSelection(point));
      await settleShort(tester);
      await tester.tap(find.text('Itinéraire').last);
      await settleShort(tester);
      expect(routes.requests.single.destination, point);
      expect(find.text('Vers ce point'), findsOneWidget);
    });
  });

  group('the preview', () {
    testWidgets('shows the routes with their time and length, and picks another', (tester) async {
      await openPreview(tester);
      expect(find.text('Vers Aire de la rue Utrillo'), findsOneWidget);
      expect(find.text('Recommandé'), findsOneWidget);
      expect(find.text('Variante 1'), findsOneWidget);
      expect(find.text('3 min'), findsOneWidget);
      expect(find.text('1,8 km'), findsOneWidget);
      expect(find.text('4,9 km'), findsOneWidget);
      expect(SchematicRouteMap.last!.lines.where((l) => l.selected).single.index, 0);
      // Both routes in view, the 4.9 km one too.
      final camera = SchematicRouteMap.last!.camera;
      final bounds = (camera as FitCamera).bounds;
      for (final line in SchematicRouteMap.last!.lines) {
        expect(line.points.every(bounds.contains), isTrue, reason: 'route ${line.index}');
      }
      await tester.tap(find.text('Variante 1'));
      await settleShort(tester);
      expect(SchematicRouteMap.last!.lines.where((l) => l.selected).single.index, 1);
      expect(SchematicRouteMap.last!.camera, camera, reason: 'the camera stays');
      expect(
        find.text('Aucune limite proche du gabarit de votre véhicule sur ce trajet.'),
        findsOneWidget,
      );
    });

    testWidgets('a 2.50 m van is told of the 2.70 m bridge, where and from which source', (
      tester,
    ) async {
      await openPreview(tester, answers: [routeFixture('utrillo_van')]);
      expect(find.text('1 limite à surveiller'), findsWidgets);
      expect(find.text('Pont bas 2,70 m'), findsOneWidget);
      expect(
        find.text('à 50 m du départ · votre véhicule : 2,50 m · Rue Maurice Utrillo'),
        findsOneWidget,
      );
      expect(
        find.text("OpenStreetMap · les sources divergent, la valeur la plus basse s'applique"),
        findsOneWidget,
      );
      expect(
        SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.warning),
        hasLength(1),
      );
    });

    testWidgets('the closures gone around and the works on the way, with their sources', (
      tester,
    ) async {
      await openPreview(tester, answers: [routeFixture('aix_marseille_closures')]);
      expect(find.text('Travaux et fermetures'), findsOneWidget);
      expect(
        find.text(
          'Itinéraire calculé autour de 2 fermetures : Tunnel de la Joliette, Tunnel du Vieux-Port',
        ),
        findsOneWidget,
      );
      expect(find.text('A51 · Voies réduites'), findsOneWidget);
      expect(
        find.text('A51 · Route fermée, position incertaine, peut-être sur le trajet'),
        findsOneWidget,
      );
      expect(find.textContaining('à 3,2 km du départ · DIR, Bison Futé'), findsOneWidget);
      expect(
        find.textContaining('Métropole Aix-Marseille-Provence (data.ampmetropole.fr), données'),
        findsOneWidget,
      );
      final marks = SchematicRouteMap.last!.marks;
      expect(marks.where((m) => m.kind == RouteMarkKind.blocker), hasLength(2));
      expect(marks.where((m) => m.kind == RouteMarkKind.event), hasLength(4));
    });

    testWidgets("a link naming a place held here routes to its own spot, not the link's point", (
      tester,
    ) async {
      final (app, routes) = await openPreview(tester);
      unawaited(
        app
            .container(tester)
            .read(routerProvider)
            .push('/route?lat=45.9&lon=6.1&name=Lac&place=${lakeArea.id}'),
      );
      await settleShort(tester);
      expect(routes.requests.last.destination, lakeArea.position);
    });

    testWidgets('a community report on the way shows its source and age, and asks nothing', (
      tester,
    ) async {
      await openPreview(
        tester,
        answers: [
          routeFixture(
            'aix_marseille_closures',
            edit: (route) {
              final first = ((route['routes'] as List).first as Map)['roadEvents'] as List;
              final event = (first.first as Map)['event'] as Map<String, dynamic>;
              event['source'] = 'community';
              event['sourceUpdatedAt'] = '2026-10-06T20:40:00Z';
            },
          ),
        ],
      );
      expect(find.text('A51 · Voies réduites'), findsOneWidget);
      // Nobody answers for a road not seen yet.
      expect(find.text('Toujours là'), findsNothing);
      expect(find.text("C'est fini"), findsNothing);
    });

    testWidgets('raised to the top, the sheet stops under the back button', (tester) async {
      // A status bar above the app, as on a device.
      tester.view.padding = const FakeViewPadding(top: 48);
      await openPreview(tester, size: phone);
      await tester.drag(find.text('Vers Aire de la rue Utrillo'), const Offset(0, -1500));
      await settleShort(tester);
      final title = tester.getRect(find.text('Vers Aire de la rue Utrillo'));
      final back = tester.getRect(find.byTooltip('Retour'));
      expect(title.top, greaterThanOrEqualTo(back.bottom));
    });

    Map<String, Object?> source({required bool fresh}) => {
      'id': 'dir',
      'name': 'DIR',
      'attribution': 'DIR, Bison Futé',
      'lastReadAt': '2026-10-06T08:00:00Z',
      'dataAt': '2026-10-06T08:00:00Z',
      'staleAfterSeconds': 7800,
      'fresh': fresh,
    };

    testWidgets('a route with no known works or closure says so', (tester) async {
      await openPreview(
        tester,
        answers: [
          routeFixture(
            'utrillo_motorhome',
            edit: (a) => a['roadEventSources'] = [source(fresh: true)],
          ),
        ],
      );
      expect(find.text('Pas de travaux ni de fermeture connus sur ce trajet.'), findsOneWidget);
    });

    testWidgets('with its sources gone stale, "none known" is not promised', (tester) async {
      await openPreview(
        tester,
        answers: [
          routeFixture(
            'utrillo_motorhome',
            edit: (a) => a['roadEventSources'] = [source(fresh: false)],
          ),
        ],
      );
      expect(find.text('Pas de travaux ni de fermeture connus sur ce trajet.'), findsNothing);
      expect(
        find.text("Travaux et fermetures : les sources n'ont pas été lues récemment."),
        findsOneWidget,
      );
    });

    testWidgets('a weight limit for goods vehicles says whom it binds', (tester) async {
      final plan = routeFixture(
        'utrillo_van',
        edit: (answer) {
          final route = (answer['routes'] as List<dynamic>).first as Map<String, dynamic>;
          ((route['warnings'] as List<dynamic>).first as Map<String, dynamic>)
            ..['kind'] = 'GOODS_VEHICLE_WEIGHT'
            ..['source'] = 'DIALOG'
            ..['certainty'] = 'KNOWN'
            ..['limit'] = 3.5
            ..['vehicleValue'] = 3.5;
        },
      );
      await openPreview(tester, answers: [plan]);
      expect(find.text('Poids limité pour les poids lourds 3,5 t'), findsOneWidget);
      expect(
        find.text(
          'Arrêté de circulation (DiaLog) · vise les poids lourds de marchandises, voyez les panneaux',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no safe route: what stopped it, the vehicle used, and what to do', (tester) async {
      await openPreview(tester, answers: [routeFixture('bregere_bar')]);
      expect(find.text('Aucun itinéraire sûr pour votre véhicule'), findsOneWidget);
      expect(find.text('Barre de hauteur 1,90 m'), findsOneWidget);
      expect(find.textContaining('votre véhicule : 3,30 m'), findsOneWidget);
      expect(find.text('Vérifiez les valeurs saisies : 3,30 m de haut, 3,5 t.'), findsOneWidget);
      expect(
        find.text("Choisissez une arrivée avant l'obstacle : appui long sur la carte."),
        findsOneWidget,
      );
      expect(
        SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.blocker),
        hasLength(1),
      );
    });

    testWidgets('no road there, with unpaved roads avoided, suggests allowing them', (
      tester,
    ) async {
      final plan = routeFixture('braille_tall');
      final avoided = RoutePlan(
        status: plan.status,
        routes: plan.routes,
        blockers: plan.blockers,
        recalculations: 0,
        applied: AppliedRequest(
          vehicle: plan.applied.vehicle,
          avoid: const AvoidOptions(unpaved: true),
          language: RouteLanguage.fr,
        ),
        graph: plan.graph,
        disclaimerKey: plan.disclaimerKey,
      );
      await openPreview(tester, answers: [avoided]);
      expect(find.text('Aucune route ne mène à ce point'), findsOneWidget);
      expect(find.textContaining("autorisez-les si l'arrivée est sur un chemin"), findsOneWidget);
    });

    testWidgets('avoiding tolls computes the route again, and is remembered', (tester) async {
      final settings = MemoryRouteSettings();
      final (_, routes) = await openPreview(tester, settings: settings);
      expect(routes.requests.single.avoid.tolls, isFalse);
      await tester.tap(find.text('Péages'));
      await settleShort(tester);
      expect(routes.requests, hasLength(2));
      expect(routes.requests.last.avoid.tolls, isTrue);
      expect(settings.value.avoid.tolls, isTrue);
    });

    testWidgets('without a vehicle, it asks for one and sends nothing', (tester) async {
      final (_, routes) = await openPreview(tester, vehicle: null);
      expect(find.text('Quel est votre véhicule ?'), findsOneWidget);
      expect(find.text('Décrire mon véhicule'), findsOneWidget);
      expect(routes.requests, isEmpty);
    });

    testWidgets('a vehicle without its height says what is missing', (tester) async {
      await openPreview(tester, vehicle: motorhome.copyWith(heightM: () => null));
      expect(find.text('Il manque : hauteur'), findsOneWidget);
    });

    testWidgets('without a position, it asks to locate', (tester) async {
      final (_, routes) = await openPreview(tester, feed: FakeLocationFeed());
      expect(find.text('Où êtes-vous ?'), findsOneWidget);
      expect(find.text('Me localiser'), findsOneWidget);
      expect(routes.requests, isEmpty);
    });

    testWidgets('offline, it says so and tries again on demand', (tester) async {
      final (_, routes) = await openPreview(
        tester,
        answers: [const RouteFailure(RouteFailureKind.offline), routeFixture('utrillo_motorhome')],
      );
      expect(find.text('Pas de connexion'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await settleShort(tester);
      expect(routes.requests, hasLength(2));
      expect(find.text('Recommandé'), findsOneWidget);
    });

    testWidgets('the data date, the sources and the disclaimer go with every route', (
      tester,
    ) async {
      await openPreview(tester);
      expect(find.text('Données routières du 4 octobre 2026'), findsOneWidget);
      expect(find.text("© les contributeurs d'OpenStreetMap"), findsOneWidget);
      expect(find.text('IGN, BD TOPO, édition du 15 juin 2026'), findsOneWidget);
      expect(
        find.textContaining('La signalisation et le code de la route priment'),
        findsOneWidget,
      );
    });

    testWidgets('a desktop shows the preview beside the map, without guidance', (tester) async {
      await openPreview(tester, size: const Size(1280, 900));
      expect(find.text('Démarrer'), findsNothing);
      expect(find.text('Le guidage pas à pas se lance depuis un téléphone.'), findsOneWidget);
      expect(find.text('Ouvrir dans une autre application'), findsOneWidget);
      final panel = tester.getTopLeft(find.text('Recommandé'));
      expect(panel.dx, lessThan(440), reason: 'the panel on the left');
    });

    testWidgets('on a phone, it starts after the disclaimer, read once', (tester) async {
      final plan = routeFixture('utrillo_motorhome');
      final settings = MemoryRouteSettings();
      final notifications = CountedNotificationAccess();
      final (app, _) = await openPreview(
        tester,
        size: phone,
        engine: LineEngine([plan]),
        settings: settings,
        notifications: notifications,
      );
      await tester.tap(find.text('Démarrer'));
      await settleShort(tester);
      expect(find.text('Avant de partir'), findsOneWidget);
      await tester.tap(find.text("J'ai compris"));
      await settleShort(tester);
      expect(settings.value.acceptedDisclaimer, 'routing.disclaimer.v1');
      final session = app.container(tester).read(guidanceControllerProvider);
      expect(session, isNotNull);
      expect(session!.target, utrillo);
      expect(find.byTooltip('Terminer'), findsOneWidget, reason: 'the guidance screen');
      expect(notifications.asked, 1, reason: "the service's notification, on Android 13");
    });

    testWidgets('while a route is computed again, the one on screen cannot be started', (
      tester,
    ) async {
      final plan = routeFixture('utrillo_motorhome');
      final (app, routes) = await openPreview(tester, engine: LineEngine([plan]));
      FilledButton start() => tester.widget<FilledButton>(
        find.ancestor(of: find.text('Démarrer'), matching: find.bySubtype<FilledButton>()),
      );
      expect(start().onPressed, isNotNull);
      routes.gate = Completer<void>();
      await tester.tap(find.text('Péages'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(start().onPressed, isNull, reason: 'the route of the old options');
      routes.gate!.complete();
      await settleShort(tester);
      expect(start().onPressed, isNotNull);
      expect(app.container(tester).read(guidanceControllerProvider), isNull);
    });

    testWidgets('after a failed recalculation, the old route cannot be started', (tester) async {
      final plan = routeFixture('utrillo_motorhome');
      final (_, routes) = await openPreview(
        tester,
        answers: [plan, const RouteFailure(RouteFailureKind.offline)],
        engine: LineEngine([plan]),
      );
      await tester.tap(find.text('Péages'));
      await settleShort(tester);
      expect(routes.requests, hasLength(2));
      final start = find.ancestor(
        of: find.text('Démarrer'),
        matching: find.bySubtype<FilledButton>(),
      );
      expect(tester.widget<FilledButton>(start).onPressed, isNull, reason: 'the toll route');
    });
  });

  group('the guidance', () {
    late FakeLocationFeed feed;
    late RecordingVoice voice;

    Future<TestApp> guide(
      WidgetTester tester,
      RoutePlan plan, {
      List<Object> answers = const [],
      Brightness brightness = Brightness.light,
      VoiceReadiness readiness = VoiceReadiness.ready,
      Size size = phone,
      List<RoutePlan> more = const [],
      RoadEventsSource? events,
      FakeApi? api,
    }) async {
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      voice = RecordingVoice(readiness: readiness);
      final app = await pumpLunaway(
        tester,
        size: size,
        api: api,
        brightness: brightness,
        overrides: navigationOverrides(
          routes: FakeRouteService(answers.isEmpty ? [plan] : answers),
          feed: feed,
          engine: LineEngine([plan, ...more]),
          voice: voice,
          events: events,
        ),
      );
      final container = app.container(tester);
      final t = await AppLocale.fr.build();
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: plan.routes.first.index,
            target: utrillo,
            words: TranslatedWording(t, DistanceUnits.metric),
          );
      unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      return app;
    }

    Future<void> drive(WidgetTester tester, RoutePlan plan, {double toM = double.infinity}) async {
      final route = plan.routes.first;
      final fixes = driveFixes(route, toM: toM);
      for (final f in fixes) {
        feed.send(f);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleShort(tester);
    }

    testWidgets('the next maneuver large, its road, the arrival time and the speed', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      expect(find.text('90 m'), findsOneWidget, reason: 'to the left turn at 192 m');
      expect(find.text('Boulevard Carnot'), findsOneWidget);
      expect(find.textContaining('Arrivée'), findsOneWidget);
      expect(find.text('36'), findsOneWidget, reason: '10 m/s');
      expect(find.text('50'), findsOneWidget, reason: 'the limit sign');
      final map = SchematicRouteMap.last!;
      expect(map.camera, isA<FollowCamera>());
      expect(map.vehicle, isNotNull);
    });

    testWidgets('a report while the vehicle moves waits for a passenger, then goes with its spot', (
      tester,
    ) async {
      final api = FakeApi();
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, api: api);
      await drive(tester, plan, toM: 100);
      await tester.tap(find.byTooltip('Signaler un problème sur la route'));
      await settleShort(tester);
      expect(find.text('Vous roulez'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(find.text('Que voyez-vous sur la route ?'), findsNothing);

      await tester.tap(find.byTooltip('Signaler un problème sur la route'));
      await settleShort(tester);
      await tester.tap(find.text('Je suis passager'));
      await settleShort(tester);
      expect(find.text('Que voyez-vous sur la route ?'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Signaler');
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'nothing chosen yet');
      await tester.tap(find.text('Hauteur limitée'));
      await settleShort(tester);
      await tester.tap(find.byTooltip('Plus haut de 10 cm'));
      await tester.pump();
      expect(find.text('Hauteur indiquée : 3,10 m'), findsOneWidget);
      await tester.tap(send);
      await settleShort(tester);
      final input = api.last('ReportRoadEvent')!['input']! as Map<String, dynamic>;
      expect(input['kind'], 'LOW_CLEARANCE');
      expect(input['valueM'], 3.1);
      expect(input['headingDeg'], isA<int>(), reason: 'the course of the vehicle');
      final at = LatLng(input['lat'] as double, input['lon'] as double);
      expect(at.distanceTo(plan.routes.first.line.first), lessThan(150));
      expect(find.text('Merci : les autres voyageurs sont prévenus.'), findsOneWidget);
    });

    testWidgets('a community report is asked about once passed, behind the passenger check', (
      tester,
    ) async {
      final api = FakeApi();
      final plan = routeFixture(
        'aix_marseille_closures',
        edit: (route) {
          final first = ((route['routes'] as List).first as Map)['roadEvents'] as List;
          ((first.first as Map)['event'] as Map<String, dynamic>)['source'] = 'community';
        },
      );
      await guide(tester, plan, api: api);
      await drive(tester, plan, toM: 1400);
      expect(find.textContaining('A51 · Voies réduites dans'), findsOneWidget);
      expect(find.text("C'est fini"), findsNothing, reason: 'not seen yet');
      await drive(tester, plan, toM: 5100);
      expect(
        find.text('Vous venez de passer : A51 · Voies réduites. Toujours là ?'),
        findsOneWidget,
      );
      await tester.tap(find.text("C'est fini"));
      await settleShort(tester);
      // The drive's fixes go at about 10 m/s: a passenger answers.
      await tester.tap(find.text('Je suis passager'));
      await settleShort(tester);
      expect(api.last('ClearRoadEvent')!['eventId'], isNotEmpty);
      await drive(tester, plan, toM: 5700);
      expect(find.textContaining('Vous venez de passer'), findsNothing, reason: 'long behind');
    });

    testWidgets(
      'on a small phone the question about a passed report stays clear of the map buttons',
      (tester) async {
        final plan = routeFixture(
          'aix_marseille_closures',
          edit: (route) {
            final first = ((route['routes'] as List).first as Map)['roadEvents'] as List;
            ((first.first as Map)['event'] as Map<String, dynamic>)['source'] = 'community';
          },
        );
        await guide(tester, plan, size: const Size(360, 640));
        await drive(tester, plan, toM: 5100);
        final answer = tester.getRect(find.text("C'est fini"));
        for (final tip in ['Signaler un problème sur la route', 'Tout le trajet']) {
          final button = tester.getRect(find.byTooltip(tip));
          expect(answer.overlaps(button), isFalse, reason: tip);
        }
      },
    );

    testWidgets('lanes show when the map has them', (tester) async {
      final plan = routeFixture('limoges_drive');
      final app = await guide(tester, plan);
      final session = app.container(tester).read(guidanceControllerProvider)!;
      final withLanes = session.route.steps.indexWhere((s) => s.lanes.isNotEmpty);
      var start = 0.0;
      for (var i = 0; i < withLanes; i++) {
        start += session.route.steps[i].distanceM;
      }
      await drive(tester, plan, toM: start + 20);
      // Place Jourdan: the left-turn lane is not the route's, the two
      // others are, and the route goes on straight from them.
      final lanes = tester.widget<LanesRow>(find.byType(LanesRow)).lanes;
      expect([for (final l in lanes) l.active], [false, true, true]);
      expect([for (final l in lanes) l.follows], [null, 'straight', 'straight']);
    });

    testWidgets('off the route, then a new route, said and shown', (tester) async {
      final plan = routeFixture('limoges_drive');
      final detour = routeFixture('missed_turn');
      await guide(tester, plan, answers: [detour], more: [detour]);
      await drive(tester, plan, toM: 400);
      final last = driveFixes(plan.routes.first, toM: 400).last;
      for (var i = 1; i <= 3; i++) {
        feed.send(
          Fix(
            position: LatLng(last.position.lat + 0.003, last.position.lon),
            accuracyM: 5,
            at: last.at.add(Duration(seconds: i)),
            speedMps: 9,
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (i == 2) {
          // Off the route (seen one fix late, as Ferrostar does), not yet
          // rerouting: the maneuver of the road left behind fades.
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Hors itinéraire'), findsOneWidget);
          final banner = find.ancestor(
            of: find.byType(ManeuverIcon).first,
            matching: find.byType(AnimatedOpacity),
          );
          expect(tester.widget<AnimatedOpacity>(banner).opacity, lessThan(1));
        }
      }
      await settleShort(tester);
      expect(find.text('Nouvel itinéraire'), findsOneWidget);
      expect(voice.said, contains("Recalcul de l'itinéraire."));
      final banner = find.ancestor(
        of: find.byType(ManeuverIcon).first,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(banner).opacity, 1);
    });

    testWidgets('roadworks ahead show with their source and the date of its data', (tester) async {
      final plan = routeFixture('limoges_drive');
      final events = ScriptedRoadEvents([
        RoadEventsDelta(
          cursor: 'c1',
          asOf: DateTime.utc(2026, 10, 6, 9),
          upserts: [
            RoadEvent(
              id: 'works',
              eventClass: RoadEventClass.laneRestriction,
              placement: RoadEventPlacement.point,
              source: 'dir',
              position: LineTrack(plan.routes.first).at(1500),
            ),
          ],
          sources: [
            RoadEventSourceStatus(
              id: 'dir',
              name: 'DIR Centre-Ouest',
              fresh: true,
              lastReadAt: DateTime.utc(2026, 10, 6, 8, 59),
              dataAt: DateTime.utc(2026, 10, 6, 8, 30),
            ),
          ],
        ),
      ]);
      await guide(tester, plan, events: events);
      await drive(tester, plan, toM: 700);
      expect(find.textContaining('Travaux dans 800 m'), findsOneWidget);
      final t = await AppLocale.fr.build();
      final dataAt = t.clockTime(DateTime.utc(2026, 10, 6, 8, 30).toLocal());
      expect(find.textContaining('DIR Centre-Ouest, données de $dataAt'), findsOneWidget);
    });

    testWidgets(
      'lanes closed ahead on the route show with their source; the closures gone round at the start',
      (tester) async {
        final plan = routeFixture('aix_marseille_closures');
        await guide(tester, plan);
        await drive(tester, plan, toM: 400);
        expect(
          find.textContaining(
            RegExp(
              r'^Itinéraire calculé autour de 2 fermetures\nMétropole Aix-Marseille-Provence '
              r'\(data\.ampmetropole\.fr\), données',
            ),
          ),
          findsOneWidget,
        );
        await drive(tester, plan, toM: 1400);
        expect(
          find.textContaining(
            RegExp(
              r'A51 · Voies réduites dans .*\nDIR, Bison Futé \(transport\.data\.gouv\.fr\), données',
            ),
          ),
          findsOneWidget,
        );
        await drive(tester, plan, toM: 2000);
        expect(find.textContaining('Itinéraire calculé autour de 2 fermetures'), findsNothing);
      },
    );

    testWidgets('the restriction coming up shows with its distance', (tester) async {
      final plan = routeFixture('utrillo_van');
      await guide(tester, plan);
      await drive(tester, plan, toM: 10);
      expect(find.text('Pont bas 2,70 m'), findsOneWidget);
      expect(find.textContaining('dans 40 m'), findsOneWidget);
    });

    testWidgets('without a voice for the language, the screen says so', (tester) async {
      await guide(tester, routeFixture('limoges_drive'), readiness: VoiceReadiness.none);
      expect(
        find.text("Aucune voix en français sur cet appareil : instructions à l'écran seulement."),
        findsOneWidget,
      );
    });

    testWidgets('a position that stops coming is said, and the next fix clears it', (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 200);
      const lost =
          'Position indisponible : vérifiez que la localisation de '
          "l'appareil est activée pour Lunaway.";
      expect(find.text(lost), findsNothing);
      feed.fail(StateError('location turned off'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(lost), findsOneWidget);
      // The failed stream has ended; the guidance asks for a new one.
      expect(feed.listening, isFalse);
      await tester.pump(const Duration(seconds: 11));
      expect(feed.listening, isTrue);
      feed.send(driveFixes(plan.routes.first, toM: 240).last);
      await settleShort(tester);
      expect(find.text(lost), findsNothing);
    });

    testWidgets('the voice button turns the voice off', (tester) async {
      final app = await guide(tester, routeFixture('limoges_drive'));
      await tester.tap(find.byTooltip('Couper la voix'));
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider)!.voiceOn, isFalse);
      expect(find.byTooltip('Activer la voix'), findsOneWidget);
    });

    testWidgets('the arrival card offers what a contribution flow registered', (tester) async {
      final plan = routeFixture('utrillo_van');
      final confirm = _Confirmation();
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      voice = RecordingVoice();
      final app = await pumpLunaway(
        tester,
        overrides: [
          ...navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: feed,
            engine: LineEngine([plan]),
            voice: voice,
          ),
          arrivalConfirmationProvider.overrideWithValue(confirm),
        ],
      );
      final container = app.container(tester);
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: 0,
            target: utrillo,
            words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          );
      unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      await drive(tester, plan);
      expect(find.text('Vous êtes à destination'), findsOneWidget);
      expect(find.text('Aire de la rue Utrillo'), findsOneWidget);
      await tester.tap(find.text('Toujours là ?'));
      await settleShort(tester);
      expect(confirm.confirmed, ['utrillo']);
      await tester.tap(find.text('Terminer'));
      await settleShort(tester);
      expect(container.read(guidanceControllerProvider), isNull);
    });

    testWidgets('back from the arrival card ends the guidance, the screen may sleep', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final app = await guide(tester, plan);
      await drive(tester, plan);
      final container = app.container(tester);
      expect(container.read(guidanceControllerProvider)?.phase, GuidancePhase.arrived);
      final wake = container.read(screenWakeProvider) as FakeScreenWake;
      expect(wake.on, isTrue);
      await tester.binding.handlePopRoute();
      await settleShort(tester);
      expect(container.read(guidanceControllerProvider), isNull);
      expect(wake.on, isFalse);
    });

    testWidgets('ending asks first, then leaves the guidance', (tester) async {
      final app = await guide(tester, routeFixture('limoges_drive'));
      await tester.tap(find.byTooltip('Terminer'));
      await settleShort(tester);
      expect(find.text('Terminer le guidage ?'), findsOneWidget);
      await tester.tap(find.text('Continuer'));
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
      await tester.tap(find.byTooltip('Terminer'));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider), isNull);
    });

    testWidgets('a tablet in landscape keeps the maneuver beside the map', (tester) async {
      await guide(tester, routeFixture('limoges_drive'), size: const Size(1100, 700));
      final map = tester.getTopLeft(find.byType(SchematicRouteMap));
      expect(map.dx, greaterThanOrEqualTo(380));
    });
  });

  testWidgets('the profile keeps the guidance settings', (tester) async {
    final settings = MemoryRouteSettings();
    await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      overrides: navigationOverrides(routes: FakeRouteService(const []), settings: settings),
    );
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    expect(find.text('Guidage'), findsOneWidget);
    await tester.tap(find.text('Autoroutes'));
    await settleShort(tester);
    expect(settings.value.avoid.motorways, isTrue);
    await tester.tap(find.text('Instructions vocales'));
    await settleShort(tester);
    expect(settings.value.voice, isFalse);
    await tester.tap(find.text('Miles'));
    await settleShort(tester);
    expect(settings.value.units, DistanceUnits.imperial);
  });
}

/// Fixes every 10 m along [route], up to [toM].
List<Fix> driveFixes(RouteOption route, {double toM = double.infinity}) {
  final track = LineTrack(route);
  final end = toM.isFinite ? toM : track.length;
  final fixes = <Fix>[];
  var at = DateTime.utc(2026, 10, 6, 9);
  for (var m = 0.0; m <= end; m += 10) {
    final p = track.at(m);
    fixes.add(
      Fix(position: p, accuracyM: 5, at: at, courseDeg: bearing(p, track.at(m + 5)), speedMps: 10),
    );
    at = at.add(const Duration(seconds: 1));
  }
  if (!toM.isFinite) {
    fixes.add(Fix(position: route.line.last, accuracyM: 5, at: at, speedMps: 0));
  }
  return fixes;
}

final class _Confirmation implements ArrivalConfirmation {
  final List<String> confirmed = [];

  @override
  String label(String languageCode) => languageCode == 'fr' ? 'Toujours là ?' : 'Still there?';

  @override
  Future<void> confirm(String placeId) async => confirmed.add(placeId);
}
