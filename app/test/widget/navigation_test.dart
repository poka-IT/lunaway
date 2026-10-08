import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/application/route_mark_focus.dart';
import 'package:lunaway/features/navigation/data/country_locator.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/features/navigation/presentation/widgets/departure_sheet.dart';
import 'package:lunaway/features/navigation/presentation/widgets/lanes_row.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_marks_overlay.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/features/navigation/presentation/widgets/warning_tile.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

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
  CountryLocator? countries,
  EnforcementFeed? enforcement,
  RoutingInfo? routing,
  AppLocale locale = AppLocale.fr,
}) async {
  final routes = FakeRouteService(
    answers ?? [routeFixture('utrillo_motorhome')],
    routingInfo: routing,
  );
  final app = await pumpLunaway(
    tester,
    size: size,
    api: api,
    locale: locale,
    overrides: navigationOverrides(
      routes: routes,
      vehicle: vehicle,
      feed: feed,
      engine: engine,
      settings: settings,
      notifications: notifications,
      countries: countries,
      enforcement: enforcement,
    ),
  );
  unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(target)));
  await settleShort(tester);
  return (app, routes);
}

/// Speed camera data held back until [gate] completes: the zones come
/// after the route's first fit, as on a first poll over the network.
final class _GatedEnforcement implements EnforcementFeed {
  new(this.zone);

  final EnforcementItem zone;
  final gate = Completer<void>();

  static const _rules = EnforcementRules(version: 1, countries: {'FR': EnforcementMode.zones});

  @override
  Future<EnforcementData> refresh(Set<String> countries, DateTime now) async {
    await gate.future;
    return (
      rules: _rules,
      items: [zone],
      sources: const <EnforcementSource>[],
      pollInterval: const Duration(hours: 6),
      polledAt: now,
    );
  }
}

void main() {
  setUp(() => SchematicRouteMap.last = null);

  group('the way into the guidance', () {
    testWidgets('"Itinéraire" opens the route for the vehicle, even with an app remembered', (
      tester,
    ) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        settings: AppSettings(navigationApp: NavigationApp.waze.id),
        overrides: navigationOverrides(routes: routes),
      );
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(dayParking.id));
      await settleShort(tester);
      await tester.tap(find.text('Itinéraire'));
      await settleShort(tester);
      expect(routes.requests.single.destination, dayParking.position);
      expect(routes.requests.single.vehicle.heightM, 3.3);
      expect(find.textContaining('Vers Parking des Tilleuls'), findsOneWidget);
      expect(app.external.routes, isEmpty, reason: 'the apps are a step aside, never the button');
    });

    testWidgets('the preview hands the route to the remembered app, a step aside', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        settings: AppSettings(navigationApp: NavigationApp.waze.id),
        overrides: navigationOverrides(routes: routes),
      );
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(dayParking.id));
      await settleShort(tester);
      await tester.tap(find.text('Itinéraire'));
      await settleShort(tester);
      await tester.tap(find.text('Ouvrir dans…'));
      await settleShort(tester);
      expect(app.external.routes.single.app, NavigationApp.waze);
      expect(app.external.routes.single.to, dayParking.position);
    });

    testWidgets('without a vehicle, the preview asks to describe it first', (tester) async {
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
      expect(find.text('Quel est votre véhicule ?'), findsOneWidget);
      expect(find.text('Décrire mon véhicule'), findsOneWidget);
    });

    testWidgets('a long-pressed point can be guided to as well', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        overrides: navigationOverrides(routes: routes),
      );
      const point = LatLng(45.7629, 4.831697);
      app.container(tester).read(selectionProvider.notifier).select(const PointSelection(point));
      await settleShort(tester);
      await tester.tap(find.text("Itinéraire jusqu'ici").last);
      await settleShort(tester);
      expect(routes.requests.single.destination, point);
      expect(find.text('Point sur la carte'), findsOneWidget);
      expect(find.text('45.762900, 4.831697'), findsOneWidget, reason: 'which point it is');
    });
  });

  group('the preview', () {
    /// Picks [name] among the starts the departure's search finds for
    /// [query].
    Future<void> chooseStart(WidgetTester tester, String query, String name) async {
      final sheet = find.byType(DepartureSearch);
      await tester.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), query);
      await tester.pump(const Duration(milliseconds: 600));
      await settleShort(tester);
      await tester.tap(
        find.descendant(of: sheet, matching: find.widgetWithText(ListTile, name)).first,
      );
      await settleShort(tester);
    }

    // The town of Lyon, as the device's places in it place it.
    const lyon = LatLng(45.7629, 4.831697);

    for (final (name, size) in [('a phone', tallPhone), ('a desktop', desktop)]) {
      testWidgets('on $name, the start can be a town the search finds, and back to my position', (
        tester,
      ) async {
        const here = LatLng(45.84719, 1.28476);
        final plan = routeFixture('utrillo_motorhome');
        final (_, routes) = await openPreview(
          tester,
          answers: [plan],
          size: size,
          engine: LineEngine([plan]),
          feed: FakeLocationFeed(position: here),
        );
        expect(find.text('Départ : ma position'), findsOneWidget);
        expect(routes.requests.last.origin, here);
        await tester.tap(find.widgetWithText(TextButton, 'Changer'));
        await settleShort(tester);
        await chooseStart(tester, 'Lyon', 'Lyon');
        expect(find.text('Départ : Lyon'), findsOneWidget);
        expect(routes.requests.last.origin.distanceTo(lyon), lessThan(1000));
        expect(
          routes.requests.last.fromVehicle,
          isFalse,
          reason: 'a point chosen, not the vehicle',
        );
        // A trip prepared: the guidance leaves from where the vehicle is.
        expect(find.text("C'est parti !"), findsNothing);
        await tester.tap(find.text('Partir de ma position'));
        await settleShort(tester);
        expect(find.text('Départ : ma position'), findsOneWidget);
        expect(routes.requests.last.origin, here);
        expect(find.text("C'est parti !"), findsOneWidget);
      });
    }

    testWidgets('without a position, the start can be chosen instead', (tester) async {
      final plan = routeFixture('utrillo_motorhome');
      final (_, routes) = await openPreview(
        tester,
        answers: [plan],
        size: desktop,
        feed: FakeLocationFeed(),
      );
      expect(find.text('Où êtes-vous ?'), findsOneWidget);
      expect(find.text('Départ : ma position'), findsNothing, reason: 'no position to name');
      expect(routes.requests, isEmpty);
      await tester.tap(find.text('Choisir un départ'));
      await settleShort(tester);
      await chooseStart(tester, 'Lyon', 'Lyon');
      expect(find.text('Où êtes-vous ?'), findsNothing);
      expect(routes.requests.single.origin.distanceTo(lyon), lessThan(1000));
    });

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
      final bridge = SchematicRouteMap.last!.marks.singleWhere((m) => m.id.startsWith('warning:'));
      expect(bridge.kind, RouteMarkKind.clearance);
      expect(bridge.badge, RouteBadge.sign(SignGlyph.height), reason: 'the height sign');
      expect(bridge.side, '2,70 m', reason: 'its figure beside it');
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
      final avoided = marks.where((m) => m.id.startsWith('avoided:'));
      expect(avoided.map((m) => m.kind), [RouteMarkKind.closure, RouteMarkKind.closure]);
      final met = marks.where((m) => m.id.startsWith('event:')).toList();
      expect(met, hasLength(4));
      expect(
        met.where((m) => m.kind == RouteMarkKind.lanes).map((m) => m.minor),
        everyElement(isTrue),
        reason: 'lanes closed are drawn small, from a closer zoom',
      );
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
      final bar = SchematicRouteMap.last!.marks.singleWhere((m) => m.id.startsWith('blocker:'));
      expect(bar.badge, RouteBadge.sign(SignGlyph.height, blocking: true));
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

    testWidgets('a desktop shows the preview beside the map and starts the guidance', (
      tester,
    ) async {
      final plan = routeFixture('utrillo_motorhome');
      await openPreview(tester, size: const Size(1280, 900), engine: LineEngine([plan]));
      final start = find.ancestor(
        of: find.text("C'est parti !"),
        matching: find.bySubtype<FilledButton>(),
      );
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      expect(find.text('Ouvrir dans…'), findsOneWidget);
      final panel = tester.getTopLeft(find.text('Recommandé'));
      expect(panel.dx, lessThan(440), reason: 'the panel on the left');
    });

    testWidgets('where the guidance library did not load, the preview says so', (tester) async {
      await openPreview(tester, size: const Size(1280, 900));
      expect(find.text("C'est parti !"), findsNothing);
      expect(find.text("Le guidage n'a pas pu démarrer sur cet appareil."), findsOneWidget);
      expect(find.text('Ouvrir dans…'), findsOneWidget);
    });

    testWidgets('on a phone, it starts after the disclaimer, read once', (tester) async {
      final plan = routeFixture('utrillo_motorhome');
      final settings = MemoryRouteSettings();
      final notifications = CountedNotificationAccess(wouldAskValue: true);
      final (app, _) = await openPreview(
        tester,
        size: phone,
        engine: LineEngine([plan]),
        settings: settings,
        notifications: notifications,
      );
      await tester.tap(find.text("C'est parti !"));
      await settleShort(tester);
      expect(find.text('Avant de partir'), findsOneWidget);
      await tester.tap(find.text("J'ai compris"));
      await settleShort(tester);
      expect(settings.value.acceptedDisclaimer, 'routing.disclaimer.v1');
      // Android 13 asks whether the app may notify: the app says why first.
      expect(find.text('Notification du guidage'), findsOneWidget);
      expect(notifications.asked, 0, reason: 'not before the reason is read');
      await tester.tap(find.text('Continuer'));
      await settleShort(tester);
      final session = app.container(tester).read(guidanceControllerProvider);
      expect(session, isNotNull);
      expect(session!.target, utrillo);
      expect(find.byTooltip('Terminer'), findsOneWidget, reason: 'the guidance screen');
      expect(notifications.asked, 1, reason: "the service's notification, on Android 13");
    });

    testWidgets('the reason of the notification is said once, then Android asks alone', (
      tester,
    ) async {
      final plan = routeFixture('utrillo_motorhome');
      final settings = MemoryRouteSettings();
      final notifications = CountedNotificationAccess(wouldAskValue: true);
      final (app, _) = await openPreview(
        tester,
        size: phone,
        engine: LineEngine([plan]),
        settings: settings,
        notifications: notifications,
      );
      await tester.tap(find.text("C'est parti !"));
      await settleShort(tester);
      await tester.tap(find.text("J'ai compris"));
      await settleShort(tester);
      await tester.tap(find.text('Pas maintenant'));
      await settleShort(tester);
      expect(settings.value.notificationExplained, isTrue, reason: 'kept on the device');
      // Another guidance, later.
      app.container(tester).read(guidanceControllerProvider.notifier).stop();
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      await tester.tap(find.text("C'est parti !"));
      await settleShort(tester);
      expect(find.text('Notification du guidage'), findsNothing, reason: 'said once');
      expect(notifications.asked, 1, reason: 'Android asks, or not, by itself');
      expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
    });

    testWidgets('"not now" to the notification starts the guidance without asking', (tester) async {
      final plan = routeFixture('utrillo_motorhome');
      final notifications = CountedNotificationAccess(wouldAskValue: true);
      final (app, _) = await openPreview(
        tester,
        size: phone,
        engine: LineEngine([plan]),
        settings: MemoryRouteSettings(),
        notifications: notifications,
      );
      await tester.tap(find.text("C'est parti !"));
      await settleShort(tester);
      await tester.tap(find.text("J'ai compris"));
      await settleShort(tester);
      await tester.tap(find.text('Pas maintenant'));
      await settleShort(tester);
      expect(notifications.asked, 0);
      expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
    });

    testWidgets('while a route is computed again, the one on screen cannot be started', (
      tester,
    ) async {
      final plan = routeFixture('utrillo_motorhome');
      final (app, routes) = await openPreview(tester, engine: LineEngine([plan]));
      FilledButton start() => tester.widget<FilledButton>(
        find.ancestor(of: find.text("C'est parti !"), matching: find.bySubtype<FilledButton>()),
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
        of: find.text("C'est parti !"),
        matching: find.bySubtype<FilledButton>(),
      );
      expect(tester.widget<FilledButton>(start).onPressed, isNull, reason: 'the toll route');
    });

    RoutePlan timedAt(int kmh) => routeFixture(
      'utrillo_motorhome',
      edit: (answer) {
        final reroute = answer['reroute'] as Map<String, dynamic>;
        (reroute['vehicle'] as Map<String, dynamic>)['cruiseSpeedKph'] = kmh;
        reroute['topSpeedKph'] = kmh;
      },
    );

    testWidgets('the cruising speed is told in miles per hour to a driver in miles', (
      tester,
    ) async {
      await openPreview(
        tester,
        answers: [timedAt(100)],
        vehicle: motorhome.copyWith(cruiseSpeedKph: () => 100),
        settings: MemoryRouteSettings(const NavigationSettings(units: DistanceUnits.imperial)),
      );
      expect(find.text('Calculé à 62 mph max'), findsOneWidget);
    });

    testWidgets("the route is asked and told at the driver's cruising speed", (tester) async {
      final timed = routeFixture(
        'utrillo_motorhome',
        edit: (answer) {
          final reroute = answer['reroute'] as Map<String, dynamic>;
          (reroute['vehicle'] as Map<String, dynamic>)['cruiseSpeedKph'] = 100;
          reroute['topSpeedKph'] = 100;
        },
      );
      final (_, routes) = await openPreview(
        tester,
        answers: [timed],
        vehicle: motorhome.copyWith(cruiseSpeedKph: () => 100),
      );
      expect(routes.requests.single.vehicle.cruiseSpeedKph, 100);
      expect(find.text('Calculé à 100 km/h max'), findsOneWidget);
    });

    testWidgets('without a cruising speed, no speed is told with the times', (tester) async {
      final (_, routes) = await openPreview(tester);
      expect(routes.requests.single.vehicle.cruiseSpeedKph, isNull);
      expect(find.textContaining('km/h max'), findsNothing);
      expect(find.text('Recommandé'), findsOneWidget);
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
      CountryLocator? countries,
      FakeRouteService? routes,
    }) async {
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      voice = RecordingVoice(readiness: readiness);
      final app = await pumpLunaway(
        tester,
        size: size,
        api: api,
        brightness: brightness,
        overrides: navigationOverrides(
          routes: routes ?? FakeRouteService(answers.isEmpty ? [plan] : answers),
          feed: feed,
          engine: LineEngine([plan, ...more]),
          voice: voice,
          events: events,
          countries: countries,
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

    testWidgets('the debug demonstration drives the route by itself, and says so', (tester) async {
      final plan = routeFixture('limoges_drive');
      final device = FakeLocationFeed(position: plan.routes.first.line.first);
      final app = await pumpLunaway(
        tester,
        overrides: [
          ...navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: device,
            engine: LineEngine([plan]),
          ),
          demoDriveProvider.overrideWithValue(true),
        ],
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
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Trajet simulé : démonstration sans GPS'), findsOneWidget);
      expect(device.listening, isFalse, reason: 'the device position is not used');
      final along = container.read(guidanceControllerProvider)!.snapshot!.distanceAlongM;
      expect(along, greaterThan(20), reason: 'about 14 m a second along the route');
      container.read(guidanceControllerProvider.notifier).stop();
      await tester.pump(const Duration(seconds: 2));
    });

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

    testWidgets('outside the countries that take reports, the button says where they are taken', (
      tester,
    ) async {
      final api = FakeApi();
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, api: api, countries: FakeCountries((_) => 'IT'));
      await drive(tester, plan, toM: 100);
      await tester.tap(find.byTooltip('Signaler un problème sur la route'));
      await settleShort(tester);
      expect(find.text('Vous roulez'), findsNothing);
      expect(find.text('Que voyez-vous sur la route ?'), findsNothing);
      expect(find.text('Pas de signalement ici'), findsOneWidget);
      expect(
        find.text(
          'Lunaway accepte les signalements là où un flux officiel les recoupe : '
          'Espagne, France, Pays-Bas.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Compris'));
      await settleShort(tester);
      expect(find.text('Pas de signalement ici'), findsNothing);
      expect(api.calls.map((c) => c.operation), isNot(contains('ReportRoadEvent')));
    });

    testWidgets('a report while the vehicle moves waits for a passenger, then goes with its spot', (
      tester,
    ) async {
      final api = FakeApi();
      final plan = routeFixture('limoges_drive');
      final routes = FakeRouteService([plan]);
      await guide(tester, plan, api: api, routes: routes);
      await drive(tester, plan, toM: 100);
      // Tapped twice while the network is slow to say where reports are
      // taken: one question.
      final slow = routes.infoGate = Completer<void>();
      await tester.tap(find.byTooltip('Signaler un problème sur la route'));
      await tester.pump();
      await tester.tap(find.byTooltip('Signaler un problème sur la route'));
      await tester.pump();
      slow.complete();
      routes.infoGate = null;
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
      expect(
        find.textContaining('déplacé'),
        findsNothing,
        reason: 'a new route that moves nothing says nothing of it',
      );
      final banner = find.ancestor(
        of: find.byType(ManeuverIcon).first,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(banner).opacity, 1);
    });

    testWidgets('a new route that moves the destination says so under the banner and aloud', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final detour = routeFixture(
        'missed_turn',
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 1, 'lat': 45.8458, 'lon': 1.2851, 'distanceM': 120.0},
        ],
      );
      final app = await guide(tester, plan, answers: [detour], more: [detour]);
      await drive(tester, plan, toM: 400);
      final controller = app.container(tester).read(guidanceControllerProvider.notifier);
      await controller.goTo(utrillo);
      await settleShort(tester);
      expect(
        find.text(
          "Nouvel itinéraire\nPoint d'arrivée déplacé de 120 m vers la rue accessible la plus "
          'proche',
        ),
        findsOneWidget,
      );
      expect(
        voice.said.last,
        "Point d'arrivée déplacé de 120 mètres vers la rue accessible la plus proche.",
      );
      expect(
        SchematicRouteMap.last!.marks.singleWhere((m) => m.id == 'destination').position,
        const LatLng(45.8458, 1.2851),
        reason: 'the mark stands where the route ends',
      );
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

    testWidgets('a street for local access coming up says so, with the sign figure', (
      tester,
    ) async {
      final plan = _desserte();
      await guide(tester, plan);
      await drive(tester, plan, toM: 10);
      expect(
        find.text(
          'Accès riverains (desserte) : interdit aux plus de 3,5 t sauf pour rejoindre votre '
          'destination',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('dans 40 m'), findsOneWidget);
      expect(
        SchematicRouteMap.last!.marks.singleWhere((m) => m.id == 'destination').position,
        const LatLng(45.8452, 1.2862),
        reason: 'the route ends where the server moved the destination',
      );
    });

    testWidgets('without a voice for the language, the screen says so, until it is closed', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, readiness: VoiceReadiness.none);
      const notice = "Aucune voix en français sur cet appareil : instructions à l'écran seulement.";
      expect(find.text(notice), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.ancestor(of: find.text(notice), matching: find.byType(Material)).first,
          matching: find.byTooltip('Fermer'),
        ),
      );
      await settleShort(tester);
      expect(find.text(notice), findsNothing);
      await drive(tester, plan, toM: 200);
      expect(find.text(notice), findsNothing, reason: 'closed for the trip');
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
      expect(find.text(lost), findsNothing, reason: 'an error alone is not yet a lost position');
      // The failed stream has ended; the guidance asks for a new one.
      expect(feed.listening, isFalse);
      await tester.pump(const Duration(seconds: 11));
      expect(feed.listening, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(lost), findsOneWidget, reason: '15 s without a position');
      feed.send(driveFixes(plan.routes.first, toM: 240).last);
      await settleShort(tester);
      expect(find.text(lost), findsNothing);
    });

    testWidgets('errors between fixes that keep coming are no lost position (Firefox)', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      final fixes = driveFixes(plan.routes.first, toM: 300);
      for (final f in fixes) {
        feed.send(f);
        if (fixes.indexOf(f).isEven) feed.error(StateError('POSITION_UNAVAILABLE'));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.textContaining('Position indisponible'), findsNothing);
    });

    testWidgets('a position that stops coming leaves the arrival time with the clock, and says '
        'how old it is, until the arrival', (tester) async {
      final plan = routeFixture('limoges_drive');
      var now = testNow;
      final minutes = StreamController<void>.broadcast();
      addTearDown(minutes.close);
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      voice = RecordingVoice();
      final app = await pumpLunaway(
        tester,
        clock: () => now,
        minuteTicker: (_) => minutes.stream,
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: feed,
          engine: LineEngine([plan]),
          voice: voice,
        ),
      );
      final container = app.container(tester);
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: plan.routes.first.index,
            target: utrillo,
            words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          );
      unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      await drive(tester, plan, toM: 100);
      const stale = "Dernière position reçue il y a 5 min : l'heure d'arrivée en dépend.";
      expect(find.text(stale), findsNothing);
      // Five minutes without a position, by the app's clock.
      now = now.add(const Duration(minutes: 5));
      minutes.add(null);
      await settleShort(tester);
      expect(find.text(stale), findsOneWidget);
      final left = container.read(guidanceControllerProvider)!.snapshot!.durationRemainingS;
      final t = await AppLocale.fr.build();
      final eta = now.add(Duration(seconds: left.round())).toLocal();
      expect(find.text('Arrivée ${t.clockTime(eta)}'), findsOneWidget, reason: 'never in the past');
      // Arrived: the position is no longer asked for, its age says nothing.
      await drive(tester, plan);
      expect(container.read(guidanceControllerProvider)!.phase, GuidancePhase.arrived);
      now = now.add(const Duration(minutes: 3));
      minutes.add(null);
      await settleShort(tester);
      expect(find.textContaining('Dernière position reçue'), findsNothing);
    });

    testWidgets('a phone on its side with a notch keeps the bar clear of it, once', (tester) async {
      final plan = routeFixture('limoges_drive');
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      voice = RecordingVoice();
      final app = await pumpLunaway(
        tester,
        size: const Size(860, 400),
        viewPadding: const FakeViewPadding(left: 44, bottom: 21),
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: feed,
          engine: LineEngine([plan]),
          voice: voice,
        ),
      );
      final container = app.container(tester);
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: plan.routes.first.index,
            target: utrillo,
            words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          );
      unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      await drive(tester, plan, toM: 100);
      final bar = tester.getRect(
        find.ancestor(of: find.byType(SpeedAndLimit), matching: find.byType(Material)).first,
      );
      expect(bar.left, 44 + Space.s, reason: 'beside the notch');
      expect(bar.bottom, 400 - 21 - Space.s, reason: 'above the home bar');
      expect(
        tester.getRect(find.byType(SpeedAndLimit)).left - bar.left,
        Space.l,
        reason: "the bar's own margin, not the notch again",
      );
    });

    testWidgets('a phone on its side with the notch on the right keeps the buttons clear of it', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      feed = FakeLocationFeed(position: plan.routes.first.line.first);
      voice = RecordingVoice();
      final app = await pumpLunaway(
        tester,
        size: const Size(860, 400),
        viewPadding: const FakeViewPadding(right: 44),
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: feed,
          engine: LineEngine([plan]),
          voice: voice,
        ),
      );
      final container = app.container(tester);
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: plan.routes.first.index,
            target: utrillo,
            words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          );
      unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
      await drive(tester, plan, toM: 100);
      for (final tip in ['Couper la voix', 'Tout le trajet']) {
        expect(tester.getRect(find.byTooltip(tip)).right, 860 - 44 - Space.s, reason: tip);
      }
    });

    testWidgets('a speed the position does not give shows no unit alone', (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      for (final f in driveFixes(plan.routes.first, toM: 100)) {
        feed.send(Fix(position: f.position, accuracyM: 5, at: f.at, courseDeg: f.courseDeg));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleShort(tester);
      // Not drawn: nothing of it can be seen or touched.
      expect(find.text('km/h').hitTestable(), findsNothing);
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

    testWidgets('a tablet in landscape keeps the maneuver beside the route, the map under no '
        'empty panel', (tester) async {
      await guide(tester, routeFixture('limoges_drive'), size: const Size(1100, 700));
      final banner = tester.getRect(
        find.ancestor(of: find.byType(ManeuverIcon).first, matching: find.byType(Material)).first,
      );
      expect(banner.right, lessThanOrEqualTo(380), reason: 'the maneuver on the left');
      expect(
        SchematicRouteMap.last!.padding.left,
        greaterThanOrEqualTo(380),
        reason: 'the vehicle and the route right of the panel',
      );
      final bar = tester.getRect(
        find.ancestor(of: find.byTooltip('Terminer'), matching: find.byType(Material)).first,
      );
      // Between the maneuver and the bar: the map, which takes the touch.
      final between = Offset(190, (banner.bottom + bar.top) / 2);
      expect(bar.top - banner.bottom, greaterThan(100));
      final hit = tester.hitTestOnBinding(between);
      expect(
        hit.path.any((e) => e.target == tester.renderObject(find.byType(SchematicRouteMap))),
        isTrue,
        reason: 'no panel left empty between them',
      );
    });
  });

  group('a trip without a route', () {
    for (final (name, size) in [
      ('phone', tallPhone),
      ('tablet', const Size(700, 1600)),
      ('desktop', const Size(1280, 1600)),
    ]) {
      testWidgets('on a $name, the destination out of reach names what keeps the vehicle out', (
        tester,
      ) async {
        await openPreview(tester, answers: [routeFixture('toulouse_no_route')], size: size);
        expect(
          find.text('Destination inaccessible avec votre véhicule : hauteur limitée à 3,20 m'),
          findsOneWidget,
        );
        expect(find.text('Votre véhicule : 3,30 m'), findsOneWidget);
        expect(find.text('Chemin de Gabardie · IGN BD TOPO'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Modifier le véhicule'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Voir les lieux autour de la destination'),
          findsOneWidget,
        );
        expect(find.textContaining('appui long sur la carte'), findsOneWidget);
        expect(find.text("C'est parti !"), findsNothing);
        expect(find.text('Ouvrir dans…'), findsNothing);
        final blocker = SchematicRouteMap.last!.marks.singleWhere((m) => m.id.startsWith('limit:'));
        expect(blocker.position, const LatLng(43.636884, 1.482296));
      });
    }

    testWidgets('in English, a weight limit with the vehicle weight and the source', (
      tester,
    ) async {
      await openPreview(tester, answers: [routeFixture('warsaw_no_route')], locale: AppLocale.en);
      expect(
        find.text('Destination out of reach for your vehicle: weight limit 1.5 t'),
        findsOneWidget,
      );
      expect(find.text('Your vehicle: 3.5 t'), findsOneWidget);
      expect(find.text('Wrzesińska · OpenStreetMap'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Edit the vehicle'), findsOneWidget);
    });

    testWidgets('an island without a car ferry, and a point at sea, each say so', (tester) async {
      await openPreview(
        tester,
        answers: [routeFixture('porquerolles_no_route'), routeFixture('sea_off_network')],
      );
      expect(find.text('Aucune route ne mène à la destination'), findsOneWidget);
      expect(find.textContaining('une île sans ferry pour les véhicules'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Modifier le véhicule'),
        findsNothing,
        reason: 'the vehicle is not the cause',
      );
      expect(
        find.widgetWithText(FilledButton, 'Voir les lieux autour de la destination'),
        findsOneWidget,
      );
      await tester.tap(find.text('Péages'));
      await settleShort(tester);
      expect(find.text("Destination trop loin d'une route"), findsOneWidget);
      expect(find.textContaining('à moins de 5 km de ce point'), findsOneWidget);
    });

    testWidgets('a stop out of reach is taken out in one tap, and the route asked again', (
      tester,
    ) async {
      final waypoint = routeFixture(
        'toulouse_no_route',
        edit: (answer) {
          final reason = (answer['noRouteReasons'] as List<dynamic>).single as Map<String, dynamic>;
          reason['kind'] = 'WAYPOINT_UNREACHABLE';
        },
      );
      final (app, routes) = await openPreview(
        tester,
        answers: [routeFixture('utrillo_motorhome'), waypoint, routeFixture('utrillo_motorhome')],
      );
      app.container(tester).read(routeStopsControllerProvider(utrillo).notifier).set([
        const RouteStop(position: LatLng(45.8335, 1.2610), label: 'Dépôt'),
      ]);
      await settleShort(tester);
      expect(
        find.text('Étape 1 inaccessible avec votre véhicule : hauteur limitée à 3,20 m'),
        findsOneWidget,
      );
      expect(find.text('Dépôt'), findsWidgets);
      await tester.ensureVisible(find.text("Retirer l'étape « Dépôt »"));
      await tester.tap(find.text("Retirer l'étape « Dépôt »"));
      await settleShort(tester);
      expect(routes.requests, hasLength(3));
      expect(routes.requests.last.stops, isEmpty);
      expect(find.text('Recommandé'), findsOneWidget);
    });

    testWidgets('unpaved roads avoided and a stop off them: one tap allows them', (tester) async {
      final settings = MemoryRouteSettings(
        const NavigationSettings(avoid: AvoidOptions(unpaved: true)),
      );
      final unpaved = routeFixture(
        'toulouse_no_route',
        edit: (answer) {
          final reason = (answer['noRouteReasons'] as List<dynamic>).single as Map<String, dynamic>;
          reason['limits'] = [
            {'kind': 'UNPAVED', 'limit': null, 'vehicleValue': null, 'restriction': null},
          ];
          (answer['reroute'] as Map<String, dynamic>)['options'] = {
            'avoidTolls': false,
            'avoidMotorways': false,
            'avoidFerries': false,
            'avoidUnpaved': true,
          };
        },
      );
      final (_, routes) = await openPreview(
        tester,
        answers: [unpaved, routeFixture('utrillo_motorhome')],
        settings: settings,
      );
      expect(
        find.text('Destination inaccessible avec votre véhicule : route non revêtue'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Autoriser les routes non revêtues'));
      await settleShort(tester);
      expect(settings.value.avoid.unpaved, isFalse);
      expect(routes.requests.last.avoid.unpaved, isFalse);
    });

    testWidgets('a destination outside the covered countries is told without asking', (
      tester,
    ) async {
      const sarajevo = RouteTarget(destination: LatLng(43.86, 18.41), label: 'Sarajevo');
      final (_, routes) = await openPreview(
        tester,
        target: sarajevo,
        countries: FakeCountries((p) => p.lon > 15 ? 'BA' : 'FR'),
      );
      expect(routes.requests, isEmpty);
      expect(find.text('Destination hors de la zone des itinéraires'), findsOneWidget);
      expect(
        find.textContaining('Lunaway calcule les itinéraires dans ces pays : Allemagne, Andorre'),
        findsOneWidget,
      );
      expect(find.textContaining('Maroc'), findsOneWidget);
      expect(find.text('Choisissez une destination dans un de ces pays.'), findsOneWidget);
      expect(find.text("C'est parti !"), findsNothing);
      expect(
        find.text('Ouvrir dans…'),
        findsOneWidget,
        reason: 'where Lunaway computes nothing, the other apps are the way left',
      );
    });

    testWidgets('a trip longer than the server takes is told without asking', (tester) async {
      const nordkapp = RouteTarget(destination: LatLng(71.17, 25.78), label: 'Cap Nord');
      final (_, routes) = await openPreview(
        tester,
        target: nordkapp,
        routing: RoutingInfo(
          available: true,
          disclaimerKey: europeRouting.disclaimerKey,
          coveredArea: europeRouting.coveredArea,
          maxAlternatives: 2,
          bounds: europeRouting.bounds,
          coveredCountries: europeRouting.coveredCountries,
          maxTripKm: 2000,
        ),
      );
      expect(routes.requests, isEmpty);
      expect(find.text('Trajet trop long'), findsOneWidget);
      expect(find.textContaining('km au plus'), findsOneWidget);
      expect(find.textContaining('faites le trajet en plusieurs fois'), findsOneWidget);
    });

    testWidgets('a request the server refuses no longer speaks of France alone', (tester) async {
      await openPreview(tester, answers: [const RouteFailure(RouteFailureKind.refused)]);
      expect(find.text("Pas d'itinéraire ici"), findsOneWidget);
      expect(find.textContaining('la longueur du trajet'), findsOneWidget);
      expect(find.textContaining('France'), findsNothing);
    });

    testWidgets('an API that names no country leaves the trip to the server', (tester) async {
      const sarajevo = RouteTarget(destination: LatLng(43.86, 18.41), label: 'Sarajevo');
      final (_, routes) = await openPreview(
        tester,
        target: sarajevo,
        routing: olderRouting,
        countries: FakeCountries((p) => p.lon > 15 ? 'BA' : 'FR'),
      );
      expect(routes.requests, hasLength(1));
    });
  });

  group('a stop moved and a street for local access', () {
    for (final (name, size) in [
      ('phone', tallPhone),
      ('tablet', const Size(700, 1600)),
      ('desktop', const Size(1280, 1600)),
    ]) {
      testWidgets('on a $name, the preview tells the move and the street, the map shows them', (
        tester,
      ) async {
        await openPreview(tester, answers: [_desserte()], size: size);
        expect(
          find.text("Point d'arrivée déplacé de 120 m vers la rue accessible la plus proche"),
          findsOneWidget,
        );
        expect(
          find.text(
            'Accès riverains (desserte) : interdit aux plus de 3,5 t sauf pour rejoindre votre '
            'destination',
          ),
          findsOneWidget,
        );
        final destination = SchematicRouteMap.last!.marks.singleWhere((m) => m.id == 'destination');
        expect(destination.position, const LatLng(45.8452, 1.2862));
      });
    }

    testWidgets('in English, the start moved', (tester) async {
      final plan = routeFixture(
        'utrillo_van',
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 0, 'lat': 45.8478, 'lon': 1.2843, 'distanceM': 80.0},
        ],
      );
      await openPreview(tester, answers: [plan], locale: AppLocale.en);
      expect(
        find.text('Start moved 80 m to the nearest street your vehicle can reach'),
        findsOneWidget,
      );
      expect(
        SchematicRouteMap.last!.marks.singleWhere((m) => m.id == 'origin').position,
        const LatLng(45.8478, 1.2843),
      );
    });
  });

  group('a route with a ferry', () {
    const elba = RouteTarget(destination: LatLng(42.8137, 10.3149), label: 'Portoferraio');

    testWidgets('on a phone, each crossing shows its line, ports and country', (tester) async {
      await openPreview(
        tester,
        answers: [routeFixture('elba_ferry')],
        target: elba,
        feed: FakeLocationFeed(position: const LatLng(42.9256, 10.5267)),
      );
      expect(find.text('Traversée en ferry'), findsOneWidget);
      expect(find.text('Ferry Piombino - Portoferraio'), findsOneWidget);
      expect(find.text('Ports : Piombino, Portoferraio'), findsOneWidget);
      expect(find.text('Pays : Italie'), findsOneWidget);
      expect(find.textContaining('27 km en mer'), findsOneWidget);
      expect(
        find.text(
          "La destination ne peut pas être atteinte sans ferry : l'itinéraire en prend un, "
          'même si vous évitez les ferries.',
        ),
        findsOneWidget,
        reason: 'the route was asked without ferries',
      );
    });

    testWidgets('on a desktop, the roadbook shows the crossing among the steps, where it begins', (
      tester,
    ) async {
      await openPreview(
        tester,
        answers: [routeFixture('elba_ferry')],
        target: elba,
        size: const Size(1280, 3200),
      );
      await tester.ensureVisible(find.text('Voir les instructions'));
      await tester.tap(find.text('Voir les instructions'));
      await settleShort(tester);
      final tiles = find.text('Ferry Piombino - Portoferraio');
      expect(tiles, findsNWidgets(2));
      final boarding = find.text('Prenez Piombino - Portoferraio Ferry.');
      expect(
        tester.getTopLeft(tiles.last).dy,
        greaterThan(tester.getTopLeft(boarding).dy),
        reason: 'under the step that boards it',
      );
      expect(
        tester.getTopLeft(tiles.last).dy,
        lessThan(tester.getTopLeft(find.text('Conduisez vers le nord-ouest.')).dy),
        reason: 'before the step that lands',
      );
      expect(
        tester.getTopLeft(tiles.last).dy,
        greaterThan(
          tester.getTopLeft(find.text('Conduisez vers le sud sur Via Alessandro Volta.')).dy,
        ),
      );
    });

    testWidgets('on a tablet in English, without ferries avoided, nothing more is said', (
      tester,
    ) async {
      final plan = routeFixture(
        'elba_ferry',
        edit: (answer) =>
            ((answer['reroute'] as Map<String, dynamic>)['options']
                    as Map<String, dynamic>)['avoidFerries'] =
                false,
      );
      await openPreview(
        tester,
        answers: [plan],
        target: elba,
        size: const Size(700, 1600),
        locale: AppLocale.en,
      );
      expect(find.text('Ferry crossing'), findsOneWidget);
      expect(find.text('Country: Italy'), findsOneWidget);
      expect(find.textContaining('cannot be reached without a ferry'), findsNothing);
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

  group('the marks of the route map', () {
    const bridge = 'warning:0:0';
    const desktop = Size(1280, 1600);
    // The legend, open on a first preview, would repeat the kinds.
    MemoryRouteSettings legendSeen() =>
        MemoryRouteSettings(const NavigationSettings(legendSeen: true));
    Finder inTip(String text) =>
        find.descendant(of: find.byType(MarkTip), matching: find.text(text));
    Color? rowTint(WidgetTester tester) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(MarkLinkedRow), matching: find.byType(AnimatedContainer)),
      );
      return (box.decoration as BoxDecoration?)?.color;
    }

    Color lit(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(MarkLinkedRow))).colorScheme.secondaryContainer;

    testWidgets('the pointer on a mark says what it is and lights its row', (tester) async {
      await openPreview(
        tester,
        answers: [routeFixture('utrillo_van')],
        size: desktop,
        settings: legendSeen(),
      );
      expect(find.byType(MarkTip), findsNothing);
      SchematicRouteMap.last!.onMarkHover!(const RouteMapHover(at: Offset(600, 400), mark: bridge));
      await tester.pump();
      expect(inTip('Hauteur limitée'), findsOneWidget);
      expect(inTip('Pont bas 2,70 m'), findsOneWidget);
      expect(inTip('à 50 m du départ'), findsOneWidget);
      expect(inTip('OpenStreetMap'), findsOneWidget);
      expect(
        SchematicRouteMap.last!.highlighted,
        isEmpty,
        reason: 'the map draws its own hover ring on the mark; a lit ring would be a second',
      );
      await tester.pump(Motion.short);
      expect(rowTint(tester), lit(tester));
      SchematicRouteMap.last!.onMarkHover!(null);
      await tester.pump(Motion.short);
      expect(find.byType(MarkTip), findsNothing);
      expect(SchematicRouteMap.last!.highlighted, isEmpty);
      expect(rowTint(tester), isNot(lit(tester)));
    });

    testWidgets('a group under the pointer counts its marks by kind', (tester) async {
      await openPreview(
        tester,
        answers: [routeFixture('utrillo_van')],
        size: desktop,
        settings: legendSeen(),
      );
      SchematicRouteMap.last!.onMarkHover!(
        const RouteMapHover(
          at: Offset(600, 400),
          group: {RouteMarkKind.closure: 1, RouteMarkKind.works: 2},
        ),
      );
      await tester.pump();
      expect(inTip('3 repères'), findsOneWidget);
      expect(inTip('Route fermée : 1 · Travaux : 2'), findsOneWidget);
      expect(inTip('Rapprochez-vous pour les voir un par un'), findsOneWidget);
    });

    testWidgets('the pointer on a row lights its mark; a click on the row flies the map there', (
      tester,
    ) async {
      await openPreview(
        tester,
        answers: [routeFixture('utrillo_van')],
        size: desktop,
        settings: legendSeen(),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(WarningTile)));
      await tester.pump();
      expect(SchematicRouteMap.last!.highlighted, {bridge});
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(SchematicRouteMap.last!.highlighted, isEmpty);
      expect(SchematicRouteMap.last!.focus, isNull);
      await tester.tap(find.byType(WarningTile));
      await tester.pump();
      final focus = SchematicRouteMap.last!.focus!;
      expect(focus.marks, [bridge]);
      expect(focus.position, routeFixture('utrillo_van').routes.first.warnings.single.position);
      await tester.tap(find.byType(WarningTile));
      await tester.pump();
      expect(SchematicRouteMap.last!.focus!.serial, greaterThan(focus.serial), reason: 'again');
    });

    testWidgets('a click on a mark the pointer is on shows its row, without a callout', (
      tester,
    ) async {
      await openPreview(
        tester,
        answers: [routeFixture('utrillo_van')],
        size: desktop,
        settings: legendSeen(),
      );
      final map = SchematicRouteMap.last!;
      map.onMarkHover!(const RouteMapHover(at: Offset(600, 400), mark: bridge));
      await tester.pump();
      map.onMarkTap!(bridge, at: const Offset(600, 400));
      map.onMarkHover!(null);
      await tester.pump(Motion.medium);
      expect(find.byType(MarkTip), findsNothing);
      expect(SchematicRouteMap.last!.highlighted, {bridge}, reason: 'chosen, it stays lit');
      expect(rowTint(tester), lit(tester));
    });

    for (final (name, size) in [
      ('a phone', tallPhone),
      ('a tablet', const Size(700, 2000)),
      ('a desktop', desktop),
    ]) {
      testWidgets('on $name a tap opens a callout that leads to the row and closes', (
        tester,
      ) async {
        await openPreview(
          tester,
          answers: [routeFixture('utrillo_van')],
          size: size,
          settings: legendSeen(),
        );
        SchematicRouteMap.last!.onMarkTap!(bridge, at: const Offset(200, 120));
        await tester.pump();
        expect(inTip('Pont bas 2,70 m'), findsOneWidget);
        await tester.tap(find.text('Voir dans la liste'));
        await tester.pump(Motion.medium);
        expect(find.byType(MarkTip), findsNothing);
        expect(rowTint(tester), lit(tester), reason: 'the row is the one chosen');
        expect(tester.getRect(find.byType(WarningTile)).top, lessThan(size.height));
        SchematicRouteMap.last!.onMarkTap!(bridge, at: const Offset(200, 120));
        await tester.pump();
        expect(find.byType(MarkTip), findsOneWidget);
        SchematicRouteMap.last!.onEmptyTap!(const LatLng(45.84, 1.27), 16);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(MarkTip), findsNothing, reason: 'a tap elsewhere closes it');
        expect(find.text('Point de la carte'), findsNothing, reason: 'and opens nothing else');
        SchematicRouteMap.last!.onMarkTap!('destination', at: const Offset(200, 120));
        await tester.pump();
        expect(inTip('Arrivée'), findsOneWidget);
        expect(find.text('Voir dans la liste'), findsNothing, reason: 'no row for the end');
        SchematicRouteMap.last!.onCameraMove!();
        await tester.pump();
        expect(find.byType(MarkTip), findsNothing, reason: 'a moved map closes it');
      });

      testWidgets('on $name the legend opens the first time, folded afterwards', (tester) async {
        final settings = MemoryRouteSettings();
        await openPreview(
          tester,
          answers: [routeFixture('utrillo_van')],
          size: size,
          settings: settings,
        );
        final legend = find.byType(MarkLegend);
        Finder inLegend(String text) => find.descendant(of: legend, matching: find.text(text));
        expect(inLegend('Départ'), findsOneWidget);
        expect(inLegend('Arrivée'), findsOneWidget);
        expect(inLegend('Hauteur limitée'), findsOneWidget);
        expect(inLegend('Route fermée'), findsNothing, reason: 'none on this route');
        expect(inLegend('Travaux'), findsNothing);
        await settleShort(tester);
        expect(settings.value.legendSeen, isTrue);
        await tester.tap(find.byTooltip('Replier la légende'));
        await settleShort(tester);
        expect(inLegend('Hauteur limitée'), findsNothing);
        await tester.tap(inLegend('Légende'));
        await settleShort(tester);
        expect(inLegend('Hauteur limitée'), findsOneWidget);
      });
    }

    testWidgets('what keeps the vehicle out of the destination leads to its reason', (
      tester,
    ) async {
      await openPreview(
        tester,
        answers: [routeFixture('toulouse_no_route')],
        settings: legendSeen(),
      );
      const id = 'limit:ign/TRONROUT0000000073480284';
      SchematicRouteMap.last!.onMarkTap!(id, at: const Offset(200, 120));
      await tester.pump();
      expect(inTip('Bloque chaque itinéraire'), findsNothing, reason: 'not a road event');
      expect(inTip('Chemin de Gabardie'), findsOneWidget);
      await tester.tap(find.text('Voir dans la liste'));
      await tester.pump(Motion.medium);
      expect(rowTint(tester), lit(tester), reason: 'the reason it stands for');
    });

    /// [plan]'s first route with [n] road events met, copies of its first.
    RoutePlan manyEvents(int n) => routeFixture(
      'aix_marseille_closures',
      edit: (answer) {
        final route = (answer['routes'] as List<Object?>).first! as Map<String, dynamic>;
        final first = (route['roadEvents'] as List<Object?>).first! as Map<String, dynamic>;
        route['roadEvents'] = [
          for (var i = 0; i < n; i++)
            {
              ...first,
              'distanceFromStartM': 1000.0 * (i + 1),
              'event': {
                ...first['event']! as Map<String, dynamic>,
                'id': 'ev$i',
                'roadNumber': 'D$i',
              },
            },
        ];
      },
    );

    testWidgets('a mark beyond the first rows opens the list and shows its row', (tester) async {
      await openPreview(tester, answers: [manyEvents(8)], settings: legendSeen());
      expect(find.text('D6 · Voies réduites'), findsNothing, reason: 'five rows at first');
      expect(find.text('Tout afficher'), findsOneWidget);
      SchematicRouteMap.last!.onMarkTap!(eventMarkId(0, 'ev6'), at: const Offset(200, 120));
      await tester.pump();
      await tester.tap(find.text('Voir dans la liste'));
      await settleShort(tester);
      final row = find.text('D6 · Voies réduites');
      expect(row, findsOneWidget);
      expect(tester.getRect(row).top, inInclusiveRange(0, tallPhone.height));
      expect(find.text('Tout afficher'), findsNothing);
      // A later mark among the first rows leaves the list open.
      SchematicRouteMap.last!.onMarkTap!(eventMarkId(0, 'ev0'), at: const Offset(200, 120));
      await tester.pump();
      await tester.tap(find.text('Voir dans la liste'));
      await settleShort(tester);
      expect(find.text('D6 · Voies réduites'), findsOneWidget);
    });

    testWidgets('"Tout afficher" shows the rows past the first five', (tester) async {
      await openPreview(tester, answers: [manyEvents(8)], settings: legendSeen());
      expect(find.text('D7 · Voies réduites'), findsNothing);
      await tester.ensureVisible(find.text('Tout afficher'));
      await tester.pump();
      await tester.tap(find.text('Tout afficher'));
      await tester.pump();
      expect(find.text('D7 · Voies réduites'), findsOneWidget);
      expect(find.text('Tout afficher'), findsNothing);
    });

    testWidgets('choosing another route puts out what was lit and closes the callout', (
      tester,
    ) async {
      await openPreview(tester, size: desktop, settings: legendSeen());
      SchematicRouteMap.last!.onMarkTap!('destination', at: const Offset(600, 300));
      await tester.pump();
      expect(find.byType(MarkTip), findsOneWidget);
      expect(SchematicRouteMap.last!.highlighted, {'destination'});
      await tester.tap(find.text('Variante 1'));
      await settleShort(tester);
      expect(find.byType(MarkTip), findsNothing);
      expect(SchematicRouteMap.last!.highlighted, isEmpty);
    });

    for (final (name, size) in [('a small phone', const Size(360, 700)), ('a desktop', desktop)]) {
      testWidgets('on $name the legend open by itself covers neither end of the route, and closing '
          'it moves no camera', (tester) async {
        await openPreview(
          tester,
          answers: [routeFixture('utrillo_van')],
          size: size,
          settings: MemoryRouteSettings(),
        );
        final props = SchematicRouteMap.last!;
        final camera = props.camera as FitCamera;
        expect(camera.room, isNot(EdgeInsets.zero), reason: 'the fit keeps room for the legend');
        final map = tester.getRect(find.byType(SchematicRouteMap));
        final legend = tester.getRect(
          find.descendant(of: find.byType(MarkLegend), matching: find.byType(Material)).first,
        );
        final project = schematicProjection(props, map.size)!;
        for (final end in props.marks.where((m) => m.kind.anchor && m.kind != RouteMarkKind.stop)) {
          final at = map.topLeft + project(end.position);
          // The badge's disc around its point, as drawn.
          expect(legend.inflate(15.5).contains(at), isFalse, reason: '${end.kind.name} at $at');
        }
        final line = props.lines.firstWhere((l) => l.selected).points;
        expect(
          line.where((p) => legend.contains(map.topLeft + project(p))),
          isEmpty,
          reason: 'no point of the route under the legend',
        );
        await tester.tap(find.byTooltip('Replier la légende'));
        await settleShort(tester);
        expect(SchematicRouteMap.last!.camera, camera, reason: 'the camera stays where it is');
      });
    }

    /// The preview of a route with two variants, the zone on the first,
    /// its data held back until the test lets it come.
    Future<(RoutePlan, _GatedEnforcement, TestApp)> previewWithLateZones(
      WidgetTester tester,
    ) async {
      final plan = routeFixture('utrillo_motorhome');
      expect(plan.routes, hasLength(2));
      final track = LineTrack(plan.routes.first);
      final step = track.length / 20;
      final zones = _GatedEnforcement(
        EnforcementItem(
          id: 'zone',
          kind: EnforcementKind.zone,
          category: 'FIXED',
          country: 'FR',
          line: [for (var i = 4; i <= 12; i++) track.at(i * step)],
        ),
      );
      final (app, _) = await openPreview(
        tester,
        answers: [plan],
        size: const Size(360, 700),
        settings: MemoryRouteSettings(),
        countries: FakeCountries((_) => 'FR'),
        enforcement: zones,
      );
      return (plan, zones, app);
    }

    Finder legendRow(String text) =>
        find.descendant(of: find.byType(MarkLegend), matching: find.text(text));

    testWidgets('zones known a moment after the route: the fit makes room for the row they add', (
      tester,
    ) async {
      final (_, zones, _) = await previewWithLateZones(tester);
      final fitted = SchematicRouteMap.last!.camera as FitCamera;
      expect(fitted.room, isNot(EdgeInsets.zero));
      expect(legendRow('Zone de danger'), findsNothing, reason: 'not known yet');
      zones.gate.complete();
      await settleShort(tester);
      expect(legendRow('Zone de danger'), findsOneWidget, reason: 'the legend grew a row');
      final legend = tester.getRect(
        find.descendant(of: find.byType(MarkLegend), matching: find.byType(Material)).first,
      );
      final camera = SchematicRouteMap.last!.camera as FitCamera;
      expect(camera.room.top + camera.room.right, greaterThan(fitted.room.top + fitted.room.right));
      expect(
        camera.room == EdgeInsets.only(top: legend.height + Space.s) ||
            camera.room == EdgeInsets.only(right: legend.width + Space.s),
        isTrue,
        reason: 'the room of the legend as it is now: ${camera.room}, $legend',
      );
    });

    testWidgets('zones known long after the route, on a slow network, still get room', (
      tester,
    ) async {
      final (_, zones, _) = await previewWithLateZones(tester);
      await tester.pump(const Duration(seconds: 30));
      final fitted = SchematicRouteMap.last!.camera as FitCamera;
      zones.gate.complete();
      await settleShort(tester);
      expect(legendRow('Zone de danger'), findsOneWidget, reason: 'the legend grew a row');
      final camera = SchematicRouteMap.last!.camera as FitCamera;
      expect(
        camera.room.top + camera.room.right,
        greaterThan(fitted.room.top + fitted.room.right),
        reason: 'the route framed clear of the row, however late it came',
      );
    });

    for (final (how, take) in <(String, void Function(ProviderContainer app, RoutePlan plan))>[
      ('a gesture', (_, _) => SchematicRouteMap.last!.onGesture!()),
      ('a tap on bare map', (_, _) => SchematicRouteMap.last!.onEmptyTap!(utrillo.destination, 12)),
      (
        'a tap on the route',
        (_, plan) => SchematicRouteMap.last!.onLineTap!(plan.routes.first.index),
      ),
      (
        'a tap on a mark',
        (_, _) => SchematicRouteMap.last!.onMarkTap!('destination', at: const Offset(120, 200)),
      ),
      (
        'a row of the list that flies the map',
        (app, _) => app.read(routeMarkFocusProvider(utrillo).notifier).fly(['destination']),
      ),
    ]) {
      testWidgets('once the user took the map ($how), zones known later leave the camera where '
          'it is', (tester) async {
        final (plan, zones, app) = await previewWithLateZones(tester);
        take(app.container(tester), plan);
        await settleShort(tester);
        final fitted = SchematicRouteMap.last!.camera as FitCamera;
        expect(fitted.room, isNot(EdgeInsets.zero));
        zones.gate.complete();
        await settleShort(tester);
        expect(legendRow('Zone de danger'), findsOneWidget, reason: 'the legend grew a row');
        expect(SchematicRouteMap.last!.camera, fitted, reason: "the camera is the user's");
      });
    }

    testWidgets('on a small phone, a route that comes after the legend opened is framed clear of '
        'the legend its marks make', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_van')])..gate = Completer<void>();
      final app = await pumpLunaway(
        tester,
        size: const Size(360, 700),
        overrides: navigationOverrides(routes: routes, settings: MemoryRouteSettings()),
      );
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      final card = find.descendant(of: find.byType(MarkLegend), matching: find.byType(Material));
      final before = tester.getSize(card.first);
      routes.gate!.complete();
      await settleShort(tester);
      final legend = tester.getRect(card.first);
      expect(legend.height, greaterThan(before.height), reason: 'the route brought its rows');
      final props = SchematicRouteMap.last!;
      final map = tester.getRect(find.byType(SchematicRouteMap));
      final project = schematicProjection(props, map.size)!;
      final line = props.lines.firstWhere((l) => l.selected).points;
      final fit = props.camera as FitCamera;
      expect(line.every(fit.bounds.contains), isTrue, reason: 'the camera framed the route');
      expect(
        line.where((p) => legend.contains(map.topLeft + project(p))),
        isEmpty,
        reason: 'no point of the route under the legend',
      );
      for (final end in props.marks.where((m) => m.kind.anchor && m.kind != RouteMarkKind.stop)) {
        final at = map.topLeft + project(end.position);
        expect(legend.inflate(15.5).contains(at), isFalse, reason: '${end.kind.name} at $at');
      }
    });

    for (final (name, size) in [('a phone', const Size(360, 700)), ('a desktop', desktop)]) {
      testWidgets('on $name the legend open by itself stays open when a mark shows its words', (
        tester,
      ) async {
        await openPreview(
          tester,
          answers: [routeFixture('utrillo_van')],
          size: size,
          settings: MemoryRouteSettings(),
        );
        final legend = find.byType(MarkLegend);
        Finder inLegend(String text) => find.descendant(of: legend, matching: find.text(text));
        expect(inLegend('Hauteur limitée'), findsOneWidget);
        SchematicRouteMap.last!.onMarkHover!(
          const RouteMapHover(at: Offset(120, 300), mark: bridge),
        );
        await tester.pump();
        expect(find.byType(MarkTip), findsOneWidget);
        expect(inLegend('Hauteur limitée'), findsOneWidget, reason: 'still open under the tip');
        SchematicRouteMap.last!.onMarkHover!(null);
        await tester.pump();
        expect(inLegend('Hauteur limitée'), findsOneWidget, reason: 'and once the tip has gone');
      });
    }

    for (final (name, size) in [('a small phone', const Size(360, 700)), ('a desktop', desktop)]) {
      testWidgets('on $name a legend seen before keeps the route clear of its chip', (
        tester,
      ) async {
        await openPreview(
          tester,
          answers: [routeFixture('utrillo_van')],
          size: size,
          settings: legendSeen(),
        );
        final props = SchematicRouteMap.last!;
        final camera = props.camera as FitCamera;
        final chip = tester.getRect(
          find.descendant(of: find.byType(MarkLegend), matching: find.byType(ActionChip)),
        );
        final map = tester.getRect(find.byType(SchematicRouteMap));
        expect(
          camera.room == EdgeInsets.only(top: chip.height + Space.s) ||
              camera.room == EdgeInsets.only(right: chip.width + Space.s),
          isTrue,
          reason: 'room for the chip: ${camera.room}, $chip',
        );
        final project = schematicProjection(props, map.size)!;
        for (final end in props.marks.where((m) => m.kind.anchor && m.kind != RouteMarkKind.stop)) {
          final at = map.topLeft + project(end.position);
          expect(chip.inflate(15.5).contains(at), isFalse, reason: '${end.kind.name} at $at');
        }
      });
    }

    test('the room goes beside the legend or below it, whichever frames the route larger', () {
      const map = Size(1000, 800);
      const legend = Size(280, 300);
      const wide = GeoBounds(south: 45, west: 0, north: 45.5, east: 5);
      const tall = GeoBounds(south: 42, west: 2, north: 48, east: 2.5);
      expect(
        legendRoom(bounds: wide, map: map, padding: EdgeInsets.zero, legend: legend),
        const EdgeInsets.only(top: 300 + Space.s),
      );
      expect(
        legendRoom(bounds: tall, map: map, padding: EdgeInsets.zero, legend: legend),
        const EdgeInsets.only(right: 280 + Space.s),
      );
    });

    test('the room follows the legend as it grows, holds when it shrinks, closes or once the user '
        'took the map; new bounds follow anew', () {
      const map = Size(360, 700);
      const padding = EdgeInsets.only(bottom: 336);
      const bounds = GeoBounds(south: 45.80, west: 1.20, north: 45.90, east: 1.35);
      final fit = LegendFit();
      const camera = FitCamera(bounds);
      final first = fit.fit(camera, map: map, padding: padding, legend: null);
      expect(first.room, EdgeInsets.zero, reason: 'the legend not laid out yet');
      final roomed = fit.fit(camera, map: map, padding: padding, legend: const Size(220, 120));
      expect(roomed.room, isNot(EdgeInsets.zero), reason: 'its first size frames the route again');
      expect(
        fit.fit(camera, map: map, padding: padding, legend: const Size(220, 120)),
        same(roomed),
        reason: 'the same size: the same fit',
      );
      final grown = fit.fit(camera, map: map, padding: padding, legend: const Size(220, 160));
      expect(grown.room, isNot(roomed.room), reason: 'rows came: the room follows');
      for (final legend in [const Size(220, 90), const Size(200, 160), null]) {
        expect(
          fit.fit(camera, map: map, padding: padding, legend: legend),
          same(grown),
          reason: 'legend $legend: smaller or closed, the camera stays',
        );
      }
      final later = fit.fit(camera, map: map, padding: padding, legend: const Size(220, 200));
      expect(later.room, isNot(grown.room), reason: 'rows that come late still move it');
      fit.hold();
      for (final legend in [const Size(220, 260), const Size(220, 90), null]) {
        expect(
          fit.fit(camera, map: map, padding: padding, legend: legend),
          same(later),
          reason: 'legend $legend: the user has the map, the camera stays',
        );
      }
      const other = GeoBounds(south: 45.70, west: 1.10, north: 45.95, east: 1.50);
      final next = fit.fit(
        const FitCamera(other),
        map: map,
        padding: padding,
        legend: const Size(220, 160),
      );
      expect(next.bounds, other);
      expect(next.room, isNot(EdgeInsets.zero), reason: 'new bounds, the legend as it is now');
      final followed = fit.fit(
        const FitCamera(other),
        map: map,
        padding: padding,
        legend: const Size(220, 200),
      );
      expect(followed.room, isNot(next.room), reason: 'new bounds follow the legend again');
    });

    testWidgets('a legend seen before opens folded, a chip above the map', (tester) async {
      await openPreview(tester, answers: [routeFixture('utrillo_van')], settings: legendSeen());
      final legend = find.byType(MarkLegend);
      expect(find.descendant(of: legend, matching: find.text('Légende')), findsOneWidget);
      expect(find.descendant(of: legend, matching: find.text('Hauteur limitée')), findsNothing);
    });

    testWidgets('in English, the tooltip and the legend', (tester) async {
      await openPreview(
        tester,
        answers: [routeFixture('utrillo_van')],
        size: desktop,
        locale: AppLocale.en,
      );
      expect(
        find.descendant(of: find.byType(MarkLegend), matching: find.text('Height limit')),
        findsOneWidget,
      );
      SchematicRouteMap.last!.onMarkHover!(const RouteMapHover(at: Offset(600, 400), mark: bridge));
      await tester.pump();
      expect(inTip('Height limit'), findsOneWidget);
      expect(inTip('50 m from the start'), findsOneWidget);
    });
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

/// The van's route under the Utrillo bridge, with its first restriction a
/// 3.5 t street for local access and its destination moved 120 m, as the
/// API answers since 2026-10-08.
RoutePlan _desserte() => routeFixture(
  'utrillo_van',
  edit: (answer) {
    answer['movedStops'] = [
      {'stopIndex': 1, 'lat': 45.8452, 'lon': 1.2862, 'distanceM': 120.0},
    ];
    final route = (answer['routes'] as List<dynamic>).first as Map<String, dynamic>;
    ((route['warnings'] as List<dynamic>).first as Map<String, dynamic>)
      ..['kind'] = 'TOO_HEAVY'
      ..['limit'] = 3.5
      ..['vehicleValue'] = 4.5
      ..['place'] = 'ROAD'
      ..['certainty'] = 'KNOWN'
      ..['exceptDestination'] = true;
  },
);
