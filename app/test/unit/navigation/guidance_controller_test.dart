import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../../helpers/navigation.dart';

const target = RouteTarget(destination: LatLng(45.84510, 1.28637), label: 'Aire du Naveix');
final t0 = DateTime.utc(2026, 10, 6, 9);

/// The Limoges drive with a low bridge 2.5 km from its start.
RoutePlan withBridge(RoutePlan plan) {
  final r = plan.routes.single;
  final bridgeAt = LineTrack(r).at(2500);
  return plan.withRoutes([
    RouteOption(
      index: r.index,
      distanceM: r.distanceM,
      durationS: r.durationS,
      hasToll: r.hasToll,
      hasFerry: r.hasFerry,
      hasMotorway: r.hasMotorway,
      line: r.line,
      steps: r.steps,
      warnings: [
        RouteWarning(
          kind: RouteWarningKind.lowClearance,
          severity: WarningSeverity.warning,
          limit: 3.5,
          vehicleValue: 3.3,
          distanceFromStartM: 2500,
          geometryIndex: 0,
          position: bridgeAt,
          source: RestrictionSource.ign,
          certainty: RestrictionCertainty.known,
          place: RestrictionPlace.underpass,
          externalId: 'ign/TRONROUT1',
        ),
      ],
    ),
  ]);
}

/// Fixes every [step] metres along [route] from [fromM] to [toM].
List<Fix> along(RouteOption route, {double fromM = 0, double? toM, double step = 20}) {
  final track = LineTrack(route);
  final end = toM ?? track.length;
  final fixes = <Fix>[];
  var at = t0.add(Duration(seconds: (fromM / 10).round()));
  for (var m = fromM; m <= end; m += step) {
    final p = track.at(m);
    final ahead = track.at(m + 5);
    fixes.add(Fix(position: p, accuracyM: 5, at: at, courseDeg: bearing(p, ahead), speedMps: 10));
    at = at.add(Duration(seconds: (step / 10).round()));
  }
  return fixes;
}

/// Lets the controller's awaits finish.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Translations fr;
  setUpAll(() async => fr = await AppLocale.fr.build());

  late FakeRouteService routes;
  late FakeLocationFeed feed;
  late RecordingVoice voice;
  late FakeScreenWake wake;
  late LineEngine engine;
  late ProviderContainer container;

  Future<GuidanceController> start(
    RoutePlan p, {
    List<Object> answers = const [],
    RoadEventsSource? events,
    List<RoutePlan> more = const [],
  }) async {
    routes = FakeRouteService(answers.isEmpty ? [p] : answers);
    feed = FakeLocationFeed();
    voice = RecordingVoice();
    wake = FakeScreenWake();
    engine = LineEngine([p, ...more]);
    container = ProviderContainer.test(
      overrides: [
        ...navigationOverrides(
          routes: routes,
          feed: feed,
          engine: engine,
          voice: voice,
          wake: wake,
          events: events,
        ),
        clockProvider.overrideWithValue(() => t0),
      ],
    );
    final controller = container.read(guidanceControllerProvider.notifier);
    final started = await controller.start(
      plan: p,
      routeIndex: p.routes.first.index,
      target: target,
      words: TranslatedWording(fr, DistanceUnits.metric),
    );
    expect(started, isTrue);
    await settle();
    return controller;
  }

  GuidanceSession session() => container.read(guidanceControllerProvider)!;

  Future<void> send(Iterable<Fix> fixes) async {
    for (final f in fixes) {
      feed.send(f);
      await settle();
    }
  }

  test('starts with the screen on and the position asked in the background', () async {
    await start(routeFixture('limoges_drive'));
    expect(wake.on, isTrue);
    expect(feed.listening, isTrue);
    expect(feed.notices.single.title, 'Lunaway vous guide');
  });

  test('each instruction is said once, a restriction at 2 km and at 500 m', () async {
    final p = withBridge(routeFixture('limoges_drive'));
    await start(p);
    await send(along(p.routes.single, toM: 2600));
    expect(voice.said.toSet(), hasLength(voice.said.length), reason: 'nothing said twice');
    final bridge = voice.said.where((s) => s.contains('passage bas de 3 mètres 50')).toList();
    expect(bridge, hasLength(2));
    expect(bridge.first, contains('dans 2 kilomètres'));
    expect(bridge.last, contains('dans 500 mètres'));
    expect(session().ahead, isEmpty, reason: 'the bridge is behind at 2 600 m');
  });

  test('the restriction ahead shows with its distance until it is passed', () async {
    final p = withBridge(routeFixture('limoges_drive'));
    await start(p);
    await send(along(p.routes.single, toM: 1000));
    expect(session().ahead.single.aheadM, closeTo(1500, 25));
  });

  test('off the route while moving: a new route from where the vehicle is, its way', () async {
    final a = routeFixture('limoges_drive');
    final detour = routeFixture('missed_turn');
    await start(a, answers: [detour], more: [detour]);
    final fixes = along(a.routes.single, toM: 600);
    await send(fixes);
    final last = fixes.last;
    final away = LatLng(last.position.lat + 0.003, last.position.lon);
    await send([
      for (var i = 1; i <= 3; i++)
        Fix(
          position: away,
          accuracyM: 5,
          at: last.at.add(Duration(seconds: i)),
          courseDeg: 270,
          speedMps: 9,
        ),
    ]);
    expect(routes.requests, hasLength(1));
    final request = routes.requests.single;
    expect(request.origin, away);
    expect(request.headingDeg, 270);
    expect(request.destination, target.destination);
    expect(request.vehicle, a.applied.vehicle);
    expect(session().reroutes, 1);
    expect(session().plan, same(detour));
    expect(session().alert, isA<ReroutedAlert>());
    expect(engine.tracks.first.disposed, isTrue);
    expect(voice.said, contains('Recalcul de l’itinéraire.'.replaceAll('’', "'")));
  });

  test('parked off the route is not a wrong turn', () async {
    final a = routeFixture('limoges_drive');
    await start(a);
    final fixes = along(a.routes.single, toM: 300);
    await send(fixes);
    final away = LatLng(fixes.last.position.lat + 0.003, fixes.last.position.lon);
    await send([
      for (var i = 1; i <= 5; i++)
        Fix(
          position: away,
          accuracyM: 5,
          at: fixes.last.at.add(Duration(seconds: i)),
          speedMps: 0,
        ),
    ]);
    expect(routes.requests, isEmpty);
    expect(session().phase, GuidancePhase.offRoute);
  });

  test('a failed recalculation keeps the route and waits longer before the next', () async {
    final a = routeFixture('limoges_drive');
    await start(a, answers: [const RouteFailure(RouteFailureKind.offline)]);
    final fixes = along(a.routes.single, toM: 300);
    await send(fixes);
    final away = LatLng(fixes.last.position.lat + 0.003, fixes.last.position.lon);
    Fix off(int s) => Fix(
      position: away,
      accuracyM: 5,
      at: fixes.last.at.add(Duration(seconds: s)),
      speedMps: 9,
    );
    await send([off(1), off(2), off(3)]);
    expect(routes.requests, hasLength(1));
    final alert = session().alert;
    expect(alert, isA<RerouteFailedAlert>());
    expect((alert! as RerouteFailedAlert).failure?.kind, RouteFailureKind.offline);
    expect(session().plan, same(a));
    // 25 s later: under the doubled wait of 40 s.
    await send([off(27)]);
    expect(routes.requests, hasLength(1));
    await send([off(45)]);
    expect(routes.requests, hasLength(2));
  });

  group('road events', () {
    RoadEventsDelta closureAt(RoutePlan p, double metres) => RoadEventsDelta(
      cursor: 'c1',
      asOf: t0,
      upserts: [
        RoadEvent(
          id: 'naveix',
          eventClass: RoadEventClass.closure,
          placement: RoadEventPlacement.point,
          source: 'dir',
          mayBlock: true,
          position: LineTrack(p.routes.single).at(metres),
        ),
      ],
      sources: [RoadEventSourceStatus(id: 'dir', fresh: true, lastReadAt: t0)],
    );

    test('are asked without any position, and a closure ahead brings a new route', () async {
      final a = routeFixture('limoges_drive');
      final detour = routeFixture('closure_detour');
      final nothing = RoadEventsDelta(cursor: 'c0', asOf: t0);
      final events = ScriptedRoadEvents([nothing, closureAt(a, 1700)]);
      await start(a, answers: [detour], events: events, more: [detour]);
      expect(events.cursors, [null]);
      // The detour leaves from Avenue des Bénédictins, 700 m along: the
      // closure is published as the vehicle gets there.
      await send(along(a.routes.single, toM: 700));
      expect(routes.requests, isEmpty);
      await container.read(guidanceControllerProvider.notifier).refreshRoadEvents();
      await settle();
      expect(events.cursors, [null, 'c0']);
      expect(routes.requests, hasLength(1));
      expect(routes.requests.single.headingDeg, isNotNull);
      expect(session().plan, same(detour));
      final alert = session().alert;
      expect(alert, isA<ReroutedAlert>());
      expect((alert! as ReroutedAlert).reason, RerouteReason.roadEvent);
      expect(voice.said, contains(startsWith('Route fermée dans')));
      expect(voice.said.last, startsWith('Nouvel itinéraire'));
    });

    test('when the new route still meets the closure, there is no other way', () async {
      final a = routeFixture('limoges_drive');
      final nothing = RoadEventsDelta(cursor: 'c0', asOf: t0);
      final events = ScriptedRoadEvents([nothing, closureAt(a, 1700)]);
      await start(a, events: events);
      await send(along(a.routes.single, toM: 700));
      await container.read(guidanceControllerProvider.notifier).refreshRoadEvents();
      await settle();
      expect(routes.requests, hasLength(1), reason: 'one try, no loop');
      expect(session().alert, isA<NoDetourAlert>());
      expect(voice.said.last, contains("Il n'y a pas d'autre chemin."));
      await send(along(a.routes.single, fromM: 720, toM: 1000));
      expect(routes.requests, hasLength(1));
    });
  });

  test('the arrival stops the position and says so; the end releases the rest', () async {
    final a = routeFixture('limoges_drive');
    final controller = await start(a);
    await send(along(a.routes.single, step: 40));
    expect(session().phase, GuidancePhase.arrived);
    expect(feed.listening, isFalse, reason: 'the GPS stops at the arrival');
    expect(wake.on, isTrue, reason: 'the arrival card stays readable');
    expect(voice.said.last, 'Vous êtes arrivé.');
    controller.stop();
    expect(container.read(guidanceControllerProvider), isNull);
    expect(wake.on, isFalse);
    expect(voice.stops, greaterThan(0));
    expect(engine.tracks.single.disposed, isTrue);
  });

  test('the voice off is silent and remembered', () async {
    final a = routeFixture('limoges_drive');
    final controller = await start(a);
    await controller.setVoice(on: false);
    await send(along(a.routes.single, toM: 800));
    expect(voice.said, isEmpty);
    expect(container.read(routeSettingsControllerProvider).value?.voice, isFalse);
  });
}
