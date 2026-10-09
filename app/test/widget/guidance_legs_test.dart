import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show driveFixes, utrillo;

void main() {
  late FakeRouteService routes;
  late FakeLocationFeed feed;
  final plan = routeFixture('limoges_drive');
  final track = LineTrack(plan.routes.first);
  final pause = RouteStop(position: track.at(800), label: 'Pause');
  final fontaine = RouteStop(position: track.at(2000), label: 'Fontaine');

  RouteMapProps map() => SchematicRouteMap.last!;

  Future<TestApp> guide(
    WidgetTester tester, {
    List<Object>? answers,
    Size size = phone,
    double textScale = 1,
  }) async {
    routes = FakeRouteService(answers ?? [plan]);
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    final app = await pumpLunaway(
      tester,
      size: size,
      textScale: textScale,
      overrides: navigationOverrides(routes: routes, feed: feed, engine: LineEngine([plan])),
    );
    await app
        .container(tester)
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: plan.routes.first.index,
          target: utrillo,
          words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          stops: [pause, fontaine],
        );
    unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.guidance));
    await settleShort(tester);
    for (final f in driveFixes(plan.routes.first, toM: 300)) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleShort(tester);
    return app;
  }

  Future<void> overview(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Tout le trajet'));
    await settleShort(tester);
  }

  List<RouteStop> stops(TestApp app, WidgetTester tester) =>
      app.container(tester).read(guidanceControllerProvider)!.stops;

  GeoBounds framed() => (map().camera as FitCamera).bounds;

  Finder chip(String name) => find.textContaining('$name ·');

  /// Touches [target] in the strip, scrolled into view first as a finger
  /// would.
  Future<void> touch(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
  }

  Finder cross(String name) => find.descendant(
    of: find.ancestor(of: chip(name), matching: find.byType(AnimatedContainer)).first,
    matching: find.byTooltip("Retirer l'étape"),
  );

  setUp(() => SchematicRouteMap.last = null);

  testWidgets('the overview lists the stops ahead, then the arrival, "Tout" first', (tester) async {
    await guide(tester);
    expect(find.text('Tout'), findsNothing, reason: 'not while following the road');
    await overview(tester);
    expect(find.text('Tout'), findsOneWidget);
    // "Pause · 9:01 · 500 m": its name, its arrival time, its distance.
    expect(chip('Pause'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Pause · \d+:\d\d · 500 m$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Fontaine · \d+:\d\d · 1,7 km$')), findsOneWidget);
    // The arrival at the time the bar says.
    final bar = tester.widget<Text>(find.textContaining(RegExp(r'^Arrivée \d'))).data ?? '';
    final time = bar.substring('Arrivée '.length);
    expect(find.text('Arrivée · Aire de la rue Utrillo · $time'), findsOneWidget);
    // Numbered as their marks on the map.
    final strip = find.ancestor(
      of: find.text('Tout'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(find.descendant(of: strip, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('2')), findsOneWidget);
    expect(map().marks.singleWhere((m) => m.id == 'stop:0').label, '1');
    expect(map().marks.singleWhere((m) => m.id == 'stop:1').label, '2');
    expect(framed(), plan.routes.first.bounds, reason: '"Tout": the whole route');
  });

  testWidgets('a screen reader hears each leg in words', (tester) async {
    final semantics = tester.ensureSemantics();
    await guide(tester);
    await overview(tester);
    final label = tester.getSemantics(chip('Pause')).label;
    expect(label, matches(RegExp(r'^Étape 1 : Pause, vers \d+:\d\d, à 500 m$')));
    semantics.dispose();
  });

  testWidgets('a chip frames its leg, "Tout" the whole route, and no choice outlives the '
      'overview', (tester) async {
    await guide(tester);
    await overview(tester);
    await touch(tester, chip('Pause'));
    await settleShort(tester);
    expect(framed().contains(pause.position), isTrue);
    expect(framed().contains(track.at(500)), isTrue, reason: 'from the vehicle on');
    expect(framed().contains(fontaine.position), isFalse);
    await touch(tester, chip('Fontaine'));
    await settleShort(tester);
    expect(framed().contains(fontaine.position), isTrue);
    expect(framed().contains(track.at(1400)), isTrue);
    expect(framed().contains(track.at(400)), isFalse, reason: 'from the stop before');
    expect(framed().contains(plan.routes.first.line.last), isFalse);
    await touch(tester, chip('Arrivée'));
    await settleShort(tester);
    expect(framed().contains(plan.routes.first.line.last), isTrue);
    expect(framed().contains(pause.position), isFalse);
    await touch(tester, find.text('Tout'));
    await settleShort(tester);
    expect(framed(), plan.routes.first.bounds);
    await touch(tester, chip('Fontaine'));
    await settleShort(tester);
    // Back to the road, then the overview again: the whole route.
    await tester.tap(find.byTooltip('Recentrer'));
    await settleShort(tester);
    expect(map().camera, isA<FollowCamera>());
    await overview(tester);
    expect(framed(), plan.routes.first.bounds);
  });

  testWidgets('the cross takes a stop out at once, asks nothing, and the notice undoes it', (
    tester,
  ) async {
    final app = await guide(tester);
    await overview(tester);
    routes.gate = Completer<void>();
    await touch(tester, cross('Pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(chip('Pause'), findsNothing, reason: 'gone at once');
    expect(chip('Fontaine'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Étape retirée'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(routes.requests.last.stops, [fontaine.position], reason: 'a new route asked at once');
    routes.gate!.complete();
    routes.gate = null;
    await settleShort(tester);
    expect(stops(app, tester), [fontaine]);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(routes.requests.last.stops, [pause.position, fontaine.position]);
    expect(stops(app, tester), [pause, fontaine]);
    expect(chip('Pause'), findsOneWidget);
  });

  testWidgets('an undo asked while the new route is on its way waits for it', (tester) async {
    final app = await guide(tester);
    await overview(tester);
    routes.gate = Completer<void>();
    await touch(tester, cross('Pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The column of notices grows after it.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Annuler'));
    await tester.pump();
    expect(routes.requests, hasLength(1), reason: 'the undo waits for the removal');
    routes.gate!.complete();
    routes.gate = null;
    await settleShort(tester);
    expect(stops(app, tester), [pause, fontaine]);
    expect(find.text("L'itinéraire n'a pas pu être changé."), findsNothing);
  });

  testWidgets('a swipe up on a chip takes its stop out', (tester) async {
    final app = await guide(tester);
    await overview(tester);
    await tester.ensureVisible(chip('Fontaine'));
    await tester.pump();
    await tester.drag(chip('Fontaine'), const Offset(0, -60));
    await settleShort(tester);
    expect(stops(app, tester), [pause]);
    expect(chip('Fontaine'), findsNothing);
    expect(find.text('Étape retirée'), findsOneWidget);
  });

  testWidgets('a stop that could not be taken out comes back, and the notice says why', (
    tester,
  ) async {
    final app = await guide(tester, answers: [const RouteFailure(RouteFailureKind.offline)]);
    await overview(tester);
    await touch(tester, cross('Pause'));
    await settleShort(tester);
    expect(stops(app, tester), [pause, fontaine]);
    expect(chip('Pause'), findsOneWidget);
    expect(find.text("L'itinéraire n'a pas pu être changé."), findsOneWidget);
  });

  testWidgets('the framed stop taken out leaves the whole route framed', (tester) async {
    await guide(tester);
    await overview(tester);
    await touch(tester, chip('Pause'));
    await settleShort(tester);
    await touch(tester, cross('Pause'));
    await settleShort(tester);
    expect(find.text('Tout'), findsOneWidget);
    expect(framed().contains(plan.routes.first.line.last), isTrue);
  });

  for (final (name, size, text) in [
    ('a phone', phone, 1.0),
    ('a small phone, large text', const Size(360, 640), 1.3),
    ('a phone on its side', const Size(860, 400), 1.0),
    ('a tablet', tablet, 1.0),
    ('a desktop', desktop, 1.0),
  ]) {
    testWidgets('on $name, the strip is one line over the map, clear of the maneuver, the bar '
        'and the buttons, and the route clear of it', (tester) async {
      await guide(tester, size: size, textScale: text);
      await overview(tester);
      final chips = [tester.getRect(find.text('Tout')), tester.getRect(chip('Pause'))];
      expect(chips[1].center.dy, closeTo(chips[0].center.dy, 1), reason: 'one line');
      final strip = tester.getRect(
        find.ancestor(of: find.text('Tout'), matching: find.byType(SingleChildScrollView)),
      );
      expect(strip.height, lessThanOrEqualTo(48 + 2 * 8 + 0.5));
      final banner = tester.getRect(
        find.ancestor(of: find.byType(ManeuverIcon).first, matching: find.byType(Material)).first,
      );
      final bar = tester.getRect(
        find
            .ancestor(
              of: find.textContaining(RegExp(r'^Arrivée \d')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(strip.overlaps(banner), isFalse, reason: 'the maneuver');
      expect(strip.overlaps(bar), isFalse, reason: 'the bar');
      for (final tip in [
        'Couper la voix',
        'Lieux sur la carte',
        'Sur le trajet',
        'Signaler un problème sur la route',
        'Recentrer',
        'Terminer',
      ]) {
        expect(strip.overlaps(tester.getRect(find.byTooltip(tip))), isFalse, reason: tip);
      }
      if (size.width < size.height) {
        expect(strip.bottom, lessThanOrEqualTo(bar.top), reason: 'over the bar');
      } else {
        expect(strip.left, greaterThanOrEqualTo(banner.right), reason: 'beside the panel');
      }
      final camera = map().camera as FitCamera;
      expect(camera.room.bottom, greaterThanOrEqualTo(strip.height), reason: 'the route above it');
    });
  }
}
