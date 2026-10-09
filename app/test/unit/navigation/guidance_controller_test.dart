import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/country_locator.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
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
    List<RouteStop> stops = const [],
    NavigationSettings settings = const NavigationSettings(),
    CountryLocator? countries,
    EnforcementFeed? enforcement,
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
          settings: MemoryRouteSettings(settings),
          countries: countries,
          enforcement: enforcement,
        ),
        clockProvider.overrideWithValue(() => t0),
        // The driving aids' settings by default, kept in memory.
        drivingAidsStoreProvider.overrideWithValue(
          DrivingAidsStore(() async => null, (_) async {}),
        ),
      ],
    );
    // The settings the guidance starts with, loaded as the app has them.
    await container.read(routeSettingsControllerProvider.future);
    final controller = container.read(guidanceControllerProvider.notifier);
    final started = await controller.start(
      plan: p,
      routeIndex: p.routes.first.index,
      target: target,
      words: TranslatedWording(fr, DistanceUnits.metric),
      stops: stops,
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

  test('a recalculation keeps the cruising speed the route was timed at', () async {
    final a = routeFixture(
      'limoges_drive',
      edit: (answer) {
        final reroute = answer['reroute'] as Map<String, dynamic>;
        (reroute['vehicle'] as Map<String, dynamic>)['cruiseSpeedKph'] = 90;
        reroute['topSpeedKph'] = 90;
      },
    );
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
    expect(routes.requests.single.vehicle.cruiseSpeedKph, 90);
    expect(routes.requests.single.vehicle.toJson()['cruiseSpeedKph'], 90);
  });

  test('off the route, the new route keeps the stops not reached yet', () async {
    final a = routeFixture('limoges_drive');
    final detour = routeFixture('missed_turn');
    final stop = RouteStop(position: LineTrack(a.routes.single).at(2500), label: 'Boulangerie');
    await start(a, answers: [detour], more: [detour], stops: [stop]);
    final fixes = along(a.routes.single, toM: 600);
    await send(fixes);
    final away = LatLng(fixes.last.position.lat + 0.003, fixes.last.position.lon);
    await send([
      for (var i = 1; i <= 3; i++)
        Fix(
          position: away,
          accuracyM: 5,
          at: fixes.last.at.add(Duration(seconds: i)),
          speedMps: 9,
        ),
    ]);
    expect(routes.requests.single.stops, [stop.position]);
    expect(session().stops, [stop]);
  });

  test('another destination drops the stops, and the way back puts them back', () async {
    final a = routeFixture('limoges_drive');
    final detour = routeFixture('missed_turn');
    final stop = RouteStop(position: LineTrack(a.routes.single).at(2500), label: 'Boulangerie');
    final controller = await start(a, answers: [detour, a], more: [detour, a], stops: [stop]);
    await send(along(a.routes.single, toM: 300));
    const elsewhere = RouteTarget(destination: LatLng(45.84, 1.27), label: 'Ailleurs');
    expect(await controller.goTo(elsewhere), isTrue);
    expect(routes.requests.last.destination, elsewhere.destination);
    expect(routes.requests.last.stops, isEmpty);
    expect(session().target, elsewhere);
    expect(await controller.goTo(target, stops: [stop]), isTrue);
    expect(routes.requests.last.stops, [stop.position]);
    expect(session().stops, [stop]);
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

  test(
    'starting from a car park off the road is not a wrong turn, leaving the wrong way is',
    () async {
      final a = routeFixture('limoges_drive');
      await start(a);
      final start0 = LineTrack(a.routes.single).at(0);
      Fix at(LatLng p, int s) => Fix(
        position: p,
        accuracyM: 5,
        at: t0.add(Duration(seconds: s)),
        speedMps: 3,
      );
      // 80 m off the start, then a little further, moving: the way out of
      // an aire.
      final parkedAt = LatLng(start0.lat + 0.0007, start0.lon);
      await send([at(parkedAt, 1), at(LatLng(parkedAt.lat + 0.0003, parkedAt.lon), 3)]);
      expect(session().phase, GuidancePhase.navigating);
      expect(routes.requests, isEmpty);
      expect(voice.said, isNot(contains(fr.navigation.voice.rerouting)));
      // Driven 400 m away without ever meeting the route: a wrong way, and
      // a new route from there.
      final away = LatLng(parkedAt.lat + 0.0036, parkedAt.lon);
      await send([at(away, 40), at(LatLng(away.lat + 0.0002, away.lon), 42)]);
      expect(routes.requests, hasLength(1));
      expect(voice.said, contains(fr.navigation.voice.rerouting));
    },
  );

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

    /// Three fixes 330 m north of where the vehicle was: off the route.
    Future<void> leave(Fix last) => send([
      for (var i = 1; i <= 3; i++)
        Fix(
          position: LatLng(last.position.lat + 0.003, last.position.lon),
          accuracyM: 5,
          at: last.at.add(Duration(seconds: i)),
          courseDeg: 0,
          speedMps: 9,
        ),
    ]);

    test('a closure learnt during a recalculation is checked on the new route', () async {
      final a = routeFixture('limoges_drive');
      final detour = routeFixture('closure_detour');
      final nothing = RoadEventsDelta(cursor: 'c0', asOf: t0);
      final events = ScriptedRoadEvents([nothing, closureAt(a, 1700)]);
      // Off the route, the answer is the same road again; then the detour.
      await start(a, answers: [a, detour], events: events, more: [a, detour]);
      final fixes = along(a.routes.single, toM: 600);
      await send(fixes);
      routes.gate = Completer<void>();
      await leave(fixes.last);
      expect(session().phase, GuidancePhase.rerouting);
      await container.read(guidanceControllerProvider.notifier).refreshRoadEvents();
      await settle();
      expect(routes.requests, hasLength(1), reason: 'the old route is not worth a check');
      routes.gate!.complete();
      await settle();
      expect(routes.requests, hasLength(2), reason: 'the new route meets the closure');
      expect(session().plan, same(detour));
      expect((session().alert! as ReroutedAlert).reason, RerouteReason.roadEvent);
      // The closure is said, then the detour; never "new route" over the
      // closure's sentence before the detour is there.
      final closure = voice.said.lastIndexWhere((s) => s.startsWith('Route fermée'));
      expect(voice.said.sublist(closure + 1), [startsWith('Nouvel itinéraire')]);
    });

    group('and the stops a new route moves', () {
      /// [name] with the destination moved 120 m, as the server answers
      /// when the point asked has no road the vehicle can reach.
      RoutePlan moving(String name) => routeFixture(
        name,
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 1, 'lat': 45.8458, 'lon': 1.2851, 'distanceM': 120.0},
        ],
      );
      const told = "Point d'arrivée déplacé de 120 mètres vers la rue accessible la plus proche.";
      List<String> movedSaid() => voice.said.where((s) => s.contains('déplacé')).toList();

      for (final voiceOn in [true, false]) {
        test('a new route that still meets the closure shows them under "no other way" '
            '(voice ${voiceOn ? 'on' : 'off'})', () async {
          final a = routeFixture('limoges_drive');
          final moved = moving('limoges_drive');
          final events = ScriptedRoadEvents([
            RoadEventsDelta(cursor: 'c0', asOf: t0),
            closureAt(a, 1700),
          ]);
          final controller = await start(a, answers: [moved], events: events, more: [moved]);
          if (!voiceOn) await controller.setVoiceMode(VoiceMode.muted);
          await send(along(a.routes.single, toM: 700));
          await controller.refreshRoadEvents();
          await settle();
          final alert = session().alert! as NoDetourAlert;
          expect(alert.moved.single.distanceM, 120, reason: 'on screen, the voice on or off');
          if (voiceOn) {
            expect(voice.said.sublist(voice.said.length - 2), [
              contains("Il n'y a pas d'autre chemin."),
              told,
            ]);
          } else {
            expect(voice.said, isEmpty);
          }
          await send(along(a.routes.single, fromM: 720, toM: 1000));
          expect(movedSaid(), hasLength(voiceOn ? 1 : 0));
        });
      }

      test('a closure on the new route that asks for another leaves them to that one', () async {
        final a = routeFixture('limoges_drive');
        final again = moving('limoges_drive');
        final detour = moving('closure_detour');
        final events = ScriptedRoadEvents([
          RoadEventsDelta(cursor: 'c0', asOf: t0),
          closureAt(a, 1700),
        ]);
        await start(a, answers: [again, detour], events: events, more: [again, detour]);
        final fixes = along(a.routes.single, toM: 600);
        await send(fixes);
        routes.gate = Completer<void>();
        await leave(fixes.last);
        await container.read(guidanceControllerProvider.notifier).refreshRoadEvents();
        await settle();
        routes.gate!.complete();
        await settle();
        expect(routes.requests, hasLength(2), reason: 'the first new route meets the closure');
        expect(session().plan, same(detour));
        final alert = session().alert! as ReroutedAlert;
        expect(alert.moved.single.distanceM, 120, reason: 'under "new route"');
        final closure = voice.said.lastIndexWhere((s) => s.startsWith('Route fermée'));
        expect(voice.said.sublist(closure + 1), [startsWith('Nouvel itinéraire'), told]);
      });

      test(
        'a closure on the new route whose next one fails leaves them to the route kept',
        () async {
          final a = routeFixture('limoges_drive');
          final again = moving('limoges_drive');
          final events = ScriptedRoadEvents([
            RoadEventsDelta(cursor: 'c0', asOf: t0),
            closureAt(a, 1700),
          ]);
          await start(
            a,
            answers: [again, const RouteFailure(RouteFailureKind.offline)],
            events: events,
            more: [again],
          );
          final fixes = along(a.routes.single, toM: 600);
          await send(fixes);
          routes.gate = Completer<void>();
          await leave(fixes.last);
          await container.read(guidanceControllerProvider.notifier).refreshRoadEvents();
          await settle();
          routes.gate!.complete();
          await settle();
          expect(routes.requests, hasLength(2));
          expect(session().plan, same(again), reason: 'the route kept');
          expect((session().alert! as RerouteFailedAlert).moved.single.distanceM, 120);
          expect(movedSaid(), [told]);
        },
      );
    });

    test(
      'a closure recalculation without an answer is asked again later, shown meanwhile',
      () async {
        final a = routeFixture('limoges_drive');
        final detour = routeFixture('closure_detour');
        final nothing = RoadEventsDelta(cursor: 'c0', asOf: t0);
        final events = ScriptedRoadEvents([nothing, closureAt(a, 1700)]);
        await start(
          a,
          answers: [const RouteFailure(RouteFailureKind.offline), detour],
          events: events,
          more: [detour],
        );
        await send(along(a.routes.single, toM: 700));
        await container.read(guidanceControllerProvider.notifier).refreshRoadEvents();
        await settle();
        expect(routes.requests, hasLength(1));
        final failed = session().alert! as RerouteFailedAlert;
        expect(failed.cause?.event.id, 'naveix');
        expect(session().eventAlerts.map((e) => e.event.id), ['naveix'], reason: 'still on screen');
        expect(voice.said.last, isNot(contains("pas d'autre chemin")));
        // Within the doubled wait of 40 s, no new try.
        await send(along(a.routes.single, fromM: 720, toM: 1000));
        expect(routes.requests, hasLength(1));
        expect(session().eventAlerts.map((e) => e.event.id), ['naveix']);
        await send(along(a.routes.single, fromM: 1020, toM: 1200));
        expect(routes.requests, hasLength(2));
        expect(session().plan, same(detour));
      },
    );
  });

  group('a stop a new route moves', () {
    /// The detour, with the server's moves of the stops asked: (index in
    /// the route asked, where, how far).
    RoutePlan movedBy(List<(int, LatLng, double)> moves) => routeFixture(
      'missed_turn',
      edit: (answer) => answer['movedStops'] = [
        for (final (i, at, m) in moves)
          {'stopIndex': i, 'lat': at.lat, 'lon': at.lon, 'distanceM': m},
      ],
    );
    const end = LatLng(45.8458, 1.2851);
    const elsewhere = LatLng(45.8430, 1.2890);
    const destinationMoved =
        "Point d'arrivée déplacé de 120 mètres vers la rue accessible "
        'la plus proche.';

    List<String> movedSaid() => voice.said.where((s) => s.contains('déplacé')).toList();

    test('is said once, after "new route", and shown with it', () async {
      final a = routeFixture('limoges_drive');
      final moved = movedBy([(1, end, 120)]);
      final again = movedBy([(1, LatLng(end.lat + 0.0001, end.lon), 118)]);
      final farther = movedBy([(1, elsewhere, 180)]);
      final controller = await start(a, answers: [moved, again, farther], more: [moved]);
      await send(along(a.routes.single, toM: 300));
      expect(await controller.goTo(target), isTrue);
      await settle();
      final alert = session().alert! as ReroutedAlert;
      expect(alert.moved.single.distanceM, 120);
      expect(alert.lastStop, 1, reason: 'no stop: the destination is stop 1 of the route asked');
      expect(voice.said.sublist(voice.said.length - 2), ['Nouvel itinéraire.', destinationMoved]);
      expect(voice.mostAtOnce, 1, reason: 'after "new route", never over it');
      // The same move 11 m off, a recalculation later: already told.
      expect(await controller.goTo(target), isTrue);
      await settle();
      expect((session().alert! as ReroutedAlert).moved, isEmpty);
      expect(movedSaid(), [destinationMoved]);
      // Moved somewhere else: told again, with its new distance.
      expect(await controller.goTo(target), isTrue);
      await settle();
      expect((session().alert! as ReroutedAlert).moved.single.distanceM, 180);
      expect(movedSaid().last, contains('180 mètres'));
      expect(movedSaid(), hasLength(2));
    });

    test('a stop is told by its number among the stops ahead', () async {
      final a = routeFixture('limoges_drive');
      final stop = RouteStop(position: LineTrack(a.routes.single).at(2500), label: 'Fontaine');
      final moved = movedBy([(1, const LatLng(45.8352, 1.2655), 90), (2, end, 60)]);
      final controller = await start(a, answers: [moved], more: [moved], stops: [stop]);
      await send(along(a.routes.single, toM: 300));
      expect(await controller.goTo(target, stops: [stop]), isTrue);
      await settle();
      expect((session().alert! as ReroutedAlert).lastStop, 2);
      expect(movedSaid(), [
        'Étape 1 déplacée de 90 mètres vers la rue accessible la plus proche.',
        "Point d'arrivée déplacé de 60 mètres vers la rue accessible la plus proche.",
      ]);
    });

    test('a failed recalculation after a moved stop was passed tells no move', () async {
      final base = routeFixture('limoges_drive');
      final stop = RouteStop(position: LineTrack(base.routes.single).at(800), label: 'Fontaine');
      final shown = routeFixture(
        'limoges_drive',
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 1, 'lat': 45.8352, 'lon': 1.2655, 'distanceM': 90.0},
        ],
      );
      await start(shown, answers: [const RouteFailure(RouteFailureKind.offline)], stops: [stop]);
      final fixes = along(shown.routes.single, toM: 1200);
      await send(fixes);
      expect(session().stops, isEmpty, reason: 'the stop is behind');
      await send([
        for (var i = 1; i <= 3; i++)
          Fix(
            position: LatLng(fixes.last.position.lat + 0.003, fixes.last.position.lon),
            accuracyM: 5,
            at: fixes.last.at.add(Duration(seconds: i)),
            speedMps: 9,
          ),
      ]);
      expect(routes.requests, hasLength(1));
      final alert = session().alert! as RerouteFailedAlert;
      expect(
        alert.moved,
        isEmpty,
        reason: 'the stop moved was the one passed, not the destination',
      );
      expect(movedSaid(), isEmpty);
    });

    test('a move the preview showed is not told again', () async {
      final shown = routeFixture(
        'limoges_drive',
        edit: (answer) => answer['movedStops'] = [
          {'stopIndex': 1, 'lat': end.lat, 'lon': end.lon, 'distanceM': 120.0},
        ],
      );
      final moved = movedBy([(1, end, 120)]);
      final controller = await start(shown, answers: [moved], more: [moved]);
      await send(along(shown.routes.single, toM: 300));
      expect(await controller.goTo(target), isTrue);
      await settle();
      expect((session().alert! as ReroutedAlert).moved, isEmpty);
      expect(movedSaid(), isEmpty);
    });

    test('another destination is told of its own move', () async {
      final a = routeFixture('limoges_drive');
      final moved = movedBy([(1, end, 120)]);
      final controller = await start(a, answers: [moved], more: [moved]);
      await send(along(a.routes.single, toM: 300));
      expect(await controller.goTo(target), isTrue);
      await settle();
      // Another point picked beside the first, moved to the same street.
      const other = RouteTarget(destination: LatLng(45.8461, 1.2852), label: 'Ailleurs');
      expect(await controller.goTo(other), isTrue);
      await settle();
      expect(movedSaid(), [destinationMoved, destinationMoved]);
    });
  });

  test('a new route that comes after the arrival is dropped', () async {
    final a = routeFixture('limoges_drive');
    final detour = routeFixture('missed_turn');
    await start(a, answers: [detour], more: [detour]);
    final fixes = along(a.routes.single, toM: 600);
    await send(fixes);
    routes.gate = Completer<void>();
    await send([
      for (var i = 1; i <= 3; i++)
        Fix(
          position: LatLng(fixes.last.position.lat + 0.003, fixes.last.position.lon),
          accuracyM: 5,
          at: fixes.last.at.add(Duration(seconds: i)),
          speedMps: 9,
        ),
    ]);
    expect(routes.requests, hasLength(1));
    final rest = along(a.routes.single, fromM: 620, step: 40);
    await send([
      ...rest,
      Fix(
        position: a.routes.single.line.last,
        accuracyM: 5,
        at: rest.last.at.add(const Duration(seconds: 4)),
        speedMps: 5,
      ),
    ]);
    expect(session().phase, GuidancePhase.arrived);
    routes.gate!.complete();
    await settle();
    expect(session().phase, GuidancePhase.arrived);
    expect(session().plan, same(a));
  });

  test('the arrival stops the position and says so; the end releases the rest', () async {
    final a = routeFixture('limoges_drive');
    final controller = await start(a);
    await send(along(a.routes.single, step: 40));
    expect(session().phase, GuidancePhase.arrived);
    expect(feed.listening, isFalse, reason: 'the GPS stops at the arrival');
    expect(wake.on, isTrue, reason: 'the arrival card stays readable');
    expect(voice.said.last, 'Vous êtes à destination.');
    controller.stop();
    expect(container.read(guidanceControllerProvider), isNull);
    expect(wake.on, isFalse);
    expect(voice.stops, greaterThan(0));
    expect(engine.tracks.single.disposed, isTrue);
  });

  test('the voice off is silent and remembered', () async {
    final a = routeFixture('limoges_drive');
    final controller = await start(a);
    await controller.setVoiceMode(VoiceMode.muted);
    await send(along(a.routes.single, toM: 800));
    expect(voice.said, isEmpty);
    expect(container.read(routeSettingsControllerProvider).value?.voiceMode, VoiceMode.muted);
  });

  group('the voice modes', () {
    const rules = EnforcementRules(version: 1, countries: {'ES': EnforcementMode.exact});

    /// Three fixes 330 m north of [last]: off the route, moving.
    List<Fix> offRoute(Fix last) => [
      for (var i = 1; i <= 3; i++)
        Fix(
          position: LatLng(last.position.lat + 0.003, last.position.lon),
          accuracyM: 5,
          at: last.at.add(Duration(seconds: i)),
          courseDeg: 0,
          speedMps: 9,
        ),
    ];

    test('alerts only says a camera and a recalculation, each after the chime, and no '
        'instruction', () async {
      final a = routeFixture('limoges_drive');
      final detour = routeFixture('missed_turn');
      final route = a.routes.single;
      await start(
        a,
        answers: [detour],
        more: [detour],
        settings: const NavigationSettings(voiceMode: VoiceMode.alerts),
        countries: FakeCountries((_) => 'ES', rules: rules),
        enforcement: FixedEnforcement(
          rules: rules,
          items: [
            EnforcementItem(
              id: 'camera',
              kind: EnforcementKind.camera,
              category: 'FIXED',
              country: 'ES',
              position: LineTrack(route).at(1000),
              limitKmh: 50,
            ),
          ],
        ),
      );
      expect(session().voiceMode, VoiceMode.alerts);
      final fixes = along(route, toM: 1100);
      await send(fixes);
      await send(offRoute(fixes.last));
      await settle();
      expect(routes.requests, hasLength(1));
      final instructions = {
        for (final s in [...route.steps, ...detour.routes.single.steps]) s.instruction,
      };
      expect(voice.said.where(instructions.contains), isEmpty);
      expect(voice.said, [
        startsWith('Radar dans'),
        fr.navigation.voice.rerouting,
        startsWith('Nouvel itinéraire'),
      ]);
      expect(voice.calls.every((c) => c.chime), isTrue, reason: 'every one an alert');
    });

    test('the full voice says the instructions, without the chime', () async {
      final a = routeFixture('limoges_drive');
      await start(a);
      await send(along(a.routes.single, toM: 800));
      expect(voice.calls, isNotEmpty);
      expect(voice.calls.any((c) => c.chime), isFalse, reason: 'no alert on this stretch');
    });

    test('a lost position is said once, and a late one is not lost', () {
      fakeAsync((async) {
        final a = routeFixture('limoges_drive');
        final lost = fr.navigation.voice.positionLost;
        int saidLost() => voice.said.where((s) => s == lost).length;
        unawaited(start(a));
        async.elapse(const Duration(seconds: 1));
        final fixes = along(a.routes.single, toM: 200);
        for (final f in fixes) {
          feed.send(f);
          async.elapse(const Duration(milliseconds: 10));
        }
        // Two minutes without a position nor an error: a tunnel.
        async.elapse(const Duration(minutes: 2));
        expect(saidLost(), 0);
        // Location turned off: its errors go on while it stays off.
        feed.fail(Exception('location off'));
        async.elapse(positionLostAfter + const Duration(seconds: 1));
        expect(session().positionLost, isTrue);
        expect(saidLost(), 1);
        feed.fail(Exception('location off'));
        async.elapse(const Duration(minutes: 1));
        expect(saidLost(), 1, reason: 'said when it goes, not while it stays lost');
        // Back, then lost again: a new loss.
        feed.send(fixes.last);
        async.elapse(const Duration(seconds: 1));
        expect(session().positionLost, isFalse);
        feed.fail(Exception('location off'));
        async.elapse(positionLostAfter + const Duration(seconds: 1));
        expect(saidLost(), 2);
        container.read(guidanceControllerProvider.notifier).stop();
      });
    });

    test('works coming are said once, a size limit twice, works beside the road never', () async {
      final base = routeFixture('limoges_drive');
      final r = base.routes.single;
      final track = LineTrack(r);
      RouteRoadEvent onRoute(String id, RoadEventWeight weight, double at) => RouteRoadEvent(
        event: RoadEvent(
          id: id,
          eventClass: RoadEventClass.works,
          placement: RoadEventPlacement.point,
          source: 'dir',
          position: track.at(at),
        ),
        weight: weight,
        reason: RoadEventReason.works,
        distanceFromStartM: at,
        position: track.at(at),
      );
      final p = base.withRoutes([
        RouteOption(
          index: r.index,
          distanceM: r.distanceM,
          durationS: r.durationS,
          hasToll: r.hasToll,
          hasFerry: r.hasFerry,
          hasMotorway: r.hasMotorway,
          line: r.line,
          steps: r.steps,
          warnings: const [],
          roadEvents: [
            onRoute('works', RoadEventWeight.warning, 2500),
            onRoute('beside', RoadEventWeight.info, 1500),
          ],
        ),
      ]);
      // A size limit of 3.50 m the motorhome of 3.30 m passes, learnt
      // during the trip.
      final limit = RoadEventsDelta(
        cursor: 'c0',
        asOf: t0,
        upserts: [
          RoadEvent(
            id: 'limit',
            eventClass: RoadEventClass.vehicleLimit,
            placement: RoadEventPlacement.point,
            source: 'dir',
            mayBlock: true,
            maxHeightM: 3.5,
            position: track.at(2700),
          ),
        ],
        sources: [RoadEventSourceStatus(id: 'dir', fresh: true, lastReadAt: t0)],
      );
      await start(p, events: ScriptedRoadEvents([limit]));
      await send(along(r, toM: 2680));
      expect(session().eventAlerts.single.blocking, isFalse);
      expect(voice.said.where((s) => s.startsWith('Travaux')), ['Travaux dans 2 kilomètres.']);
      expect(voice.said.where((s) => s.contains('gabarit limité')), [
        'Attention, gabarit limité par des travaux dans 2 kilomètres.',
        'Attention, gabarit limité par des travaux dans 500 mètres.',
      ]);
      expect(
        voice.calls.where((c) => c.text.startsWith('Travaux') || c.text.contains('gabarit')),
        everyElement(predicate<({String text, bool chime})>((c) => c.chime)),
      );
    });

    test(
      'alerts only tells a lane closed that the next poll puts ahead, at its distance',
      () async {
        final a = routeFixture('limoges_drive');
        final events = ScriptedRoadEvents([
          RoadEventsDelta(cursor: 'c0', asOf: t0),
          RoadEventsDelta(
            cursor: 'c1',
            asOf: t0,
            upserts: [
              RoadEvent(
                id: 'lanes',
                eventClass: RoadEventClass.laneRestriction,
                placement: RoadEventPlacement.point,
                source: 'dir',
                position: LineTrack(a.routes.single).at(1200),
              ),
            ],
            sources: [RoadEventSourceStatus(id: 'dir', fresh: true, lastReadAt: t0)],
          ),
        ]);
        final controller = await start(
          a,
          events: events,
          settings: const NavigationSettings(voiceMode: VoiceMode.alerts),
        );
        await send(along(a.routes.single, toM: 700));
        expect(voice.said, isEmpty, reason: 'no instruction in alerts only');
        await controller.refreshRoadEvents();
        await settle();
        expect(voice.calls, [(text: 'Voie réduite dans 500 mètres.', chime: true)]);
        await send(along(a.routes.single, fromM: 720, toM: 1100));
        expect(voice.said, ['Voie réduite dans 500 mètres.'], reason: 'once');
      },
    );
  });
}
