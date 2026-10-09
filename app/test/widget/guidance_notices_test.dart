import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'navigation_test.dart' show driveFixes, utrillo;

void main() {
  late FakeRouteService routes;
  late FakeLocationFeed feed;

  Future<TestApp> guide(
    WidgetTester tester,
    RoutePlan plan, {
    List<Object> answers = const [],
    List<RoutePlan> more = const [],
    Size size = phone,
    RoadEventsSource? events,
    VoiceReadiness readiness = VoiceReadiness.ready,
    DateTime Function()? clock,
    MinuteTicker? minuteTicker,
  }) async {
    routes = FakeRouteService(answers.isEmpty ? [plan] : answers);
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    final app = await pumpLunaway(
      tester,
      size: size,
      clock: clock,
      minuteTicker: minuteTicker,
      overrides: navigationOverrides(
        routes: routes,
        feed: feed,
        engine: LineEngine([plan, ...more]),
        voice: RecordingVoice(readiness: readiness),
        events: events,
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
    return app;
  }

  Future<void> drive(WidgetTester tester, RoutePlan plan, {required double toM}) async {
    for (final f in driveFixes(plan.routes.first, toM: toM)) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleShort(tester);
  }

  /// Three fixes 330 m north of the route's [toM]: off it, and a new route
  /// asked for.
  Future<void> leave(WidgetTester tester, RoutePlan plan, {required double toM}) async {
    final last = driveFixes(plan.routes.first, toM: toM).last;
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
    }
    await settleShort(tester);
  }

  /// The guidance with a new route said: off the route, the detour landed.
  Future<TestApp> rerouted(WidgetTester tester, {Size size = phone}) async {
    final plan = routeFixture('limoges_drive');
    final detour = routeFixture('missed_turn');
    final app = await guide(tester, plan, answers: [detour], more: [detour], size: size);
    await drive(tester, plan, toM: 400);
    await leave(tester, plan, toM: 400);
    expect(find.text('Nouvel itinéraire'), findsOneWidget);
    return app;
  }

  ScaffoldMessengerState messenger(WidgetTester tester) =>
      ScaffoldMessenger.of(tester.element(find.byType(GuidanceScreen)));

  /// The frame that starts a fade, the time it takes, then the frame that
  /// drops what faded.
  Future<void> faded(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  group('a passing notice', () {
    testWidgets('a new route is said for a few seconds, then goes, with no new position', (
      tester,
    ) async {
      await rerouted(tester);
      // The vehicle stands still: no fix moves the notice on.
      await tester.pump(const Duration(seconds: 4));
      await faded(tester);
      expect(find.text('Nouvel itinéraire'), findsNothing);
    });

    testWidgets('shows 4 s, then fades away', (tester) async {
      await rerouted(tester);
      showMessage(messenger(tester), 'Signalement envoyé');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3900));
      Finder fade() => find
          .ancestor(of: find.text('Signalement envoyé'), matching: find.byType(FadeTransition))
          .first;
      expect(tester.widget<FadeTransition>(fade()).opacity.value, 1);
      // Its time is up at 4 s: the fade starts with the next frame.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FadeTransition>(fade()).opacity.value, lessThan(1), reason: 'fading');
      await faded(tester);
      expect(find.text('Signalement envoyé'), findsNothing);
    });

    testWidgets('a tap closes it at once', (tester) async {
      await rerouted(tester);
      await tester.tap(find.text('Nouvel itinéraire'));
      await faded(tester);
      expect(find.text('Nouvel itinéraire'), findsNothing);
    });

    testWidgets('a swipe up closes it at once', (tester) async {
      await rerouted(tester);
      await tester.drag(find.text('Nouvel itinéraire'), const Offset(0, -60));
      await faded(tester);
      expect(find.text('Nouvel itinéraire'), findsNothing);
    });

    testWidgets('a swipe down leaves it', (tester) async {
      await rerouted(tester);
      await tester.drag(find.text('Nouvel itinéraire'), const Offset(0, 60));
      await faded(tester);
      expect(find.text('Nouvel itinéraire'), findsOneWidget);
    });

    testWidgets('a message of the app shows under the maneuver, never at the foot over the bar', (
      tester,
    ) async {
      await rerouted(tester);
      showMessage(messenger(tester), 'Signalement envoyé');
      await faded(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Signalement envoyé'), findsOneWidget);
      expect(find.text('Nouvel itinéraire'), findsNothing, reason: 'one at a time, the latest');
      final banner = tester.getRect(find.byType(ManeuverIcon).first);
      final notice = tester.getRect(find.text('Signalement envoyé'));
      final end = tester.getRect(find.byTooltip('Terminer'));
      expect(notice.top, greaterThan(banner.bottom));
      expect(notice.bottom, lessThan(end.top));
    });

    testWidgets('one with an undo stays 6 s, and its undo works', (tester) async {
      await rerouted(tester);
      var undone = 0;
      showMessage(
        messenger(tester),
        'Étape retirée',
        action: SnackBarAction(label: 'Annuler', onPressed: () => undone++),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Étape retirée'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await faded(tester);
      expect(undone, 1);
      expect(find.text('Étape retirée'), findsNothing, reason: 'the action closes it');
    });

    testWidgets('a closure with no other way is not replaced by a message, which comes after', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      final t0 = DateTime.utc(2026, 10, 6, 9);
      final events = ScriptedRoadEvents([
        RoadEventsDelta(cursor: 'c0', asOf: t0),
        RoadEventsDelta(
          cursor: 'c1',
          asOf: t0,
          upserts: [
            RoadEvent(
              id: 'naveix',
              eventClass: RoadEventClass.closure,
              placement: RoadEventPlacement.point,
              source: 'dir',
              mayBlock: true,
              position: LineTrack(plan.routes.single).at(1700),
            ),
          ],
          sources: [RoadEventSourceStatus(id: 'dir', fresh: true, lastReadAt: t0)],
        ),
      ]);
      final app = await guide(tester, plan, events: events);
      await drive(tester, plan, toM: 700);
      await app.container(tester).read(guidanceControllerProvider.notifier).refreshRoadEvents();
      await settleShort(tester);
      const noWay = 'Route fermée dans 1,0 km : aucun autre chemin';
      expect(find.text(noWay), findsOneWidget);
      // The closure's own standing notice waits under it, not twice.
      expect(find.textContaining('Route fermée dans 1,0 km\n'), findsNothing);
      showMessage(messenger(tester), 'Signalement envoyé');
      await faded(tester);
      expect(find.text(noWay), findsOneWidget);
      expect(find.text('Signalement envoyé'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await faded(tester);
      expect(find.text('Signalement envoyé'), findsOneWidget, reason: 'its turn');
      expect(find.text(noWay), findsNothing);
      expect(
        find.textContaining('Route fermée dans 1,0 km\n'),
        findsOneWidget,
        reason: 'the closure ahead stands as long as it is ahead',
      );
    });

    testWidgets('a screen reader is told of it once', (tester) async {
      final semantics = tester.ensureSemantics();
      await rerouted(tester);
      showMessage(messenger(tester), 'Signalement envoyé');
      await tester.pump();
      bool live() => tester
          .getSemantics(find.text('Signalement envoyé'))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion;
      expect(live(), isTrue, reason: 'its first frame');
      await tester.pump(const Duration(milliseconds: 100));
      expect(live(), isFalse, reason: 'told, not again');
      semantics.dispose();
    });
  });

  group('a standing notice', () {
    const voice = "Aucune voix en français sur cet appareil : instructions à l'écran seulement.";

    testWidgets('folds into a chip at a tap, and opens again from it', (tester) async {
      await guide(tester, routeFixture('limoges_drive'), readiness: VoiceReadiness.none);
      expect(find.text(voice), findsOneWidget);
      await tester.tap(find.text(voice));
      await settleShort(tester);
      expect(find.text(voice), findsNothing);
      expect(find.byTooltip(voice), findsOneWidget, reason: 'a chip, its words in its tooltip');
      final chip = tester.getRect(find.byTooltip(voice));
      expect(chip.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byTooltip(voice));
      await settleShort(tester);
      expect(find.text(voice), findsOneWidget);
    });

    testWidgets('folds at a swipe up', (tester) async {
      await guide(tester, routeFixture('limoges_drive'), readiness: VoiceReadiness.none);
      await tester.drag(find.text(voice), const Offset(0, -60));
      await settleShort(tester);
      expect(find.text(voice), findsNothing);
      expect(find.byTooltip(voice), findsOneWidget);
    });

    testWidgets('folded, opens again when its state worsens, and leaves with its state', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      var now = testNow;
      final minutes = StreamController<void>.broadcast();
      addTearDown(minutes.close);
      await guide(tester, plan, clock: () => now, minuteTicker: (_) => minutes.stream);
      await drive(tester, plan, toM: 100);
      const stale = "Dernière position reçue il y a 5 min : l'heure d'arrivée en dépend.";
      now = now.add(const Duration(minutes: 5));
      minutes.add(null);
      await settleShort(tester);
      expect(find.text(stale), findsOneWidget);
      await tester.tap(find.text(stale));
      await settleShort(tester);
      expect(find.text(stale), findsNothing, reason: 'folded');
      // A minute more: the same state, still folded.
      now = now.add(const Duration(minutes: 1));
      minutes.add(null);
      await settleShort(tester);
      expect(find.textContaining('Dernière position reçue'), findsNothing);
      // Then no position at all: worse, it opens again.
      feed.fail(StateError('location turned off'));
      await tester.pump(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('Position indisponible'), findsOneWidget);
      // A fix: the state is over, its notice and its chip go.
      feed.send(driveFixes(plan.routes.first, toM: 140).last);
      await settleShort(tester);
      expect(find.textContaining('Position indisponible'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains(RegExp('Position|Dernière')),
        ),
        findsNothing,
      );
    });

    testWidgets('a state that ends and comes back is told again to a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final plan = routeFixture('limoges_drive');
      var now = testNow;
      final minutes = StreamController<void>.broadcast();
      addTearDown(minutes.close);
      await guide(tester, plan, clock: () => now, minuteTicker: (_) => minutes.stream);
      await drive(tester, plan, toM: 100);
      now = now.add(const Duration(minutes: 5));
      minutes.add(null);
      await settleShort(tester);
      expect(find.textContaining('Dernière position reçue'), findsOneWidget);
      // A fix: the state is over.
      feed.send(driveFixes(plan.routes.first, toM: 120).last);
      await settleShort(tester);
      expect(find.textContaining('Dernière position reçue'), findsNothing);
      // Two minutes without one: the same state again.
      now = now.add(const Duration(minutes: 2));
      minutes.add(null);
      await tester.pump();
      await tester.pump();
      final node = tester.getSemantics(find.textContaining('Dernière position reçue'));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });

    testWidgets('a figure that changes in it is not told again to a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final plan = routeFixture('limoges_drive');
      var now = testNow;
      final minutes = StreamController<void>.broadcast();
      addTearDown(minutes.close);
      await guide(tester, plan, clock: () => now, minuteTicker: (_) => minutes.stream);
      await drive(tester, plan, toM: 100);
      now = now.add(const Duration(minutes: 5));
      minutes.add(null);
      await settleShort(tester);
      now = now.add(const Duration(minutes: 1));
      minutes.add(null);
      await tester.pump();
      await tester.pump();
      final node = tester.getSemantics(find.textContaining('il y a 6 min'));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
      semantics.dispose();
    });
  });

  for (final (name, size) in [
    ('a phone', phone),
    ('a phone on its side', const Size(860, 400)),
    ('a desktop', desktop),
  ]) {
    testWidgets('on $name, a notice covers neither the maneuver nor a button', (tester) async {
      await rerouted(tester, size: size);
      final notice = tester.getRect(
        find.ancestor(of: find.text('Nouvel itinéraire'), matching: find.byType(Material)).first,
      );
      final banner = tester.getRect(
        find.ancestor(of: find.byType(ManeuverIcon).first, matching: find.byType(Material)).first,
      );
      expect(notice.overlaps(banner), isFalse);
      for (final tip in [
        'Voix complète',
        'Lieux sur la carte',
        'Sur le trajet',
        'Signaler un problème sur la route',
        'Tout le trajet',
        'Terminer',
      ]) {
        expect(notice.overlaps(tester.getRect(find.byTooltip(tip))), isFalse, reason: tip);
      }
    });
  }

  // A message of the app's foot runs its time once it is in: frames as a
  // screen draws them, a tenth of a second apart.
  Future<void> frames(WidgetTester tester, Duration total) async {
    for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('once the guidance has ended, the messages show at the foot again', (tester) async {
    final app = await rerouted(tester);
    app.container(tester).read(guidanceControllerProvider.notifier).stop();
    await settleShort(tester);
    expect(find.byType(GuidanceScreen), findsNothing);
    final context = tester.element(find.byType(Scaffold).first);
    showMessage(ScaffoldMessenger.of(context), 'Position introuvable');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(SnackBar, 'Position introuvable'), findsOneWidget);
  });

  testWidgets('a message outside the guidance closes at a tap', (tester) async {
    await pumpLunaway(tester);
    final context = tester.element(find.byType(Scaffold).first);
    showMessage(ScaffoldMessenger.of(context), 'Position introuvable');
    await frames(tester, const Duration(milliseconds: 500));
    expect(find.text('Position introuvable'), findsOneWidget);
    await tester.tap(find.text('Position introuvable'));
    await frames(tester, const Duration(milliseconds: 600));
    expect(find.text('Position introuvable'), findsNothing);
  });

  testWidgets('a message outside the guidance leaves after 4 s', (tester) async {
    await pumpLunaway(tester);
    final context = tester.element(find.byType(Scaffold).first);
    showMessage(ScaffoldMessenger.of(context), 'Position introuvable');
    await frames(tester, const Duration(milliseconds: 3800));
    expect(find.text('Position introuvable'), findsOneWidget);
    await frames(tester, const Duration(milliseconds: 1000));
    expect(find.text('Position introuvable'), findsNothing);
  });

  testWidgets('a message with an undo outside the guidance leaves after 6 s', (tester) async {
    await pumpLunaway(tester);
    final context = tester.element(find.byType(Scaffold).first);
    showMessage(
      ScaffoldMessenger.of(context),
      'Étape retirée',
      action: SnackBarAction(label: 'Annuler', onPressed: () {}),
    );
    await frames(tester, const Duration(milliseconds: 5800));
    expect(find.text('Étape retirée'), findsOneWidget);
    await frames(tester, const Duration(milliseconds: 1000));
    expect(find.text('Étape retirée'), findsNothing);
  });
}
