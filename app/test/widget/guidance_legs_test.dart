import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
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
    List<RoutePlan> more = const [],
    Size size = phone,
    double textScale = 1,
    FakeViewPadding? viewPadding,
    List<RouteStop>? withStops,
    VoiceOutput? voice,
  }) async {
    routes = FakeRouteService(answers ?? [plan]);
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    final app = await pumpLunaway(
      tester,
      size: size,
      textScale: textScale,
      viewPadding: viewPadding,
      overrides: navigationOverrides(
        routes: routes,
        feed: feed,
        engine: LineEngine([plan, ...more]),
        voice: voice,
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
          stops: withStops ?? [pause, fontaine],
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

  /// The cross of [name]'s chip, named with its stop.
  Finder cross(String name) => find.descendant(
    of: find.ancestor(of: chip(name), matching: find.byType(AnimatedContainer)).first,
    matching: find.byWidgetPredicate(
      (w) => w is IconButton && (w.tooltip ?? '').startsWith("Retirer l'étape "),
    ),
  );

  setUp(() => SchematicRouteMap.last = null);

  testWidgets('the same place added twice as a stop shows two chips, one taken out alone', (
    tester,
  ) async {
    await guide(tester, withStops: [pause, pause, fontaine]);
    await overview(tester);
    expect(tester.takeException(), isNull);
    expect(chip('Pause'), findsNWidgets(2), reason: 'one chip per stop, the same place or not');
    expect(cross('Fontaine'), findsOneWidget);
    routes.gate = Completer<void>();
    await touch(
      tester,
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == "Retirer l'étape 2, Pause"),
    );
    await tester.pump();
    expect(chip('Pause'), findsOneWidget, reason: 'the other one stays while the route is asked');
  });

  testWidgets('of two equal stops, the cross takes out its own and the undo puts it back', (
    tester,
  ) async {
    final app = await guide(tester, withStops: [pause, fontaine, pause]);
    await overview(tester);
    await touch(
      tester,
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == "Retirer l'étape 3, Pause"),
    );
    await settleShort(tester);
    expect(stops(app, tester), [pause, fontaine], reason: 'the third stop out, not the first');
    expect(routes.requests.last.stops, [pause.position, fontaine.position]);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(stops(app, tester), [pause, fontaine, pause], reason: 'back in its place');
    expect(routes.requests.last.stops, [pause.position, fontaine.position, pause.position]);
  });

  testWidgets('a chip taken out stays out while an equal stop before it is passed', (tester) async {
    final app = await guide(tester, withStops: [pause, fontaine, pause]);
    await overview(tester);
    routes.gate = Completer<void>();
    await touch(
      tester,
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == "Retirer l'étape 3, Pause"),
    );
    await tester.pump();
    expect(chip('Pause'), findsOneWidget);
    // On past the first Pause while the new route is on its way, after the
    // fixes guide() sent: one every 10 m from 0 to 300 m.
    final sent = driveFixes(plan.routes.first, toM: 300).length;
    for (final f in driveFixes(plan.routes.first, toM: 900).skip(sent)) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(stops(app, tester), [fontaine, pause], reason: 'the first one passed');
    expect(chip('Pause'), findsNothing, reason: 'the one taken out still waits for its route');
    routes.gate!.complete();
    routes.gate = null;
    await settleShort(tester);
  });

  testWidgets('the undo puts back the first of two equal stops in its place', (tester) async {
    final app = await guide(tester, withStops: [pause, fontaine, pause]);
    await overview(tester);
    await touch(
      tester,
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == "Retirer l'étape 1, Pause"),
    );
    await settleShort(tester);
    expect(stops(app, tester), [fontaine, pause]);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(stops(app, tester), [pause, fontaine, pause]);
  });

  testWidgets('the whole route is framed below the banner and the notices under it', (
    tester,
  ) async {
    // No voice for French on the device: a standing notice under the
    // banner, as a zone's would be.
    await guide(tester, voice: RecordingVoice(readiness: VoiceReadiness.none));
    await overview(tester);
    final notice = tester.getRect(find.textContaining('Aucune voix'));
    final top = tester.getRect(find.byType(SchematicRouteMap)).top;
    final camera = map().camera as FitCamera;
    expect(
      map().padding.top + camera.room.top,
      greaterThanOrEqualTo(notice.bottom - top),
      reason: 'the route framed under the notice, not behind it',
    );
  });

  testWidgets('the whole route framed below a passing notice stays there once it goes', (
    tester,
  ) async {
    await guide(tester);
    await overview(tester);
    await touch(tester, cross('Pause'));
    await settleShort(tester);
    expect(find.text('Étape retirée'), findsOneWidget);
    final under = (map().camera as FitCamera).room.top;
    final notice = tester.getRect(find.text('Étape retirée'));
    final top = tester.getRect(find.byType(SchematicRouteMap)).top;
    expect(map().padding.top + under, greaterThanOrEqualTo(notice.bottom - top));
    // The message gone, the route does not move back up: a frame that
    // followed each message would jump twice for each.
    await tester.pump(const Duration(seconds: 8));
    await settleShort(tester);
    expect(find.text('Étape retirée'), findsNothing);
    expect((map().camera as FitCamera).room.top, under);
  });

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

  group('the overview stays its whole time back to the road', () {
    const almost = Duration(seconds: 2);

    Future<void> leavesAfter(WidgetTester tester, String why) async {
      await tester.pump(FreeMap.idleReturn - almost);
      expect(map().camera, isA<FitCamera>(), reason: why);
      expect(find.text('Tout'), findsOneWidget);
      await tester.pump(almost * 2);
      await settleShort(tester);
      expect(map().camera, isA<FollowCamera>(), reason: 'then back to the road');
    }

    testWidgets('after a cross, as after a chip', (tester) async {
      await guide(tester);
      await overview(tester);
      await tester.pump(FreeMap.idleReturn - almost);
      await touch(tester, cross('Pause'));
      await settleShort(tester);
      expect(chip('Fontaine'), findsOneWidget);
      await leavesAfter(tester, 'counted from the cross');
    });

    // Each answer a route of its own, as the server's are.
    List<Object> fresh() => [routeFixture('limoges_drive'), routeFixture('limoges_drive')];

    testWidgets('after a new route that took its time', (tester) async {
      await guide(tester, answers: fresh());
      await overview(tester);
      routes.gate = Completer<void>();
      await touch(tester, cross('Pause'));
      await tester.pump();
      await tester.pump(FreeMap.idleReturn - almost);
      routes.gate!.complete();
      routes.gate = null;
      await settleShort(tester);
      await leavesAfter(tester, 'counted from the new route');
    });

    testWidgets('after the undo put the stop back', (tester) async {
      final app = await guide(tester, answers: fresh());
      await overview(tester);
      await touch(tester, cross('Pause'));
      await settleShort(tester);
      await tester.pump(const Duration(seconds: 4));
      routes.gate = Completer<void>();
      await tester.tap(find.text('Annuler'));
      await tester.pump();
      await tester.pump(FreeMap.idleReturn - almost);
      routes.gate!.complete();
      routes.gate = null;
      await settleShort(tester);
      expect(stops(app, tester), [pause, fontaine]);
      await leavesAfter(tester, 'counted from the route the undo brought');
    });

    testWidgets('while the chips are scrolled', (tester) async {
      await guide(tester);
      await overview(tester);
      await tester.pump(FreeMap.idleReturn - almost);
      await tester.drag(
        find.ancestor(of: find.text('Tout'), matching: find.byType(SingleChildScrollView)),
        const Offset(-120, 0),
      );
      await settleShort(tester);
      await leavesAfter(tester, 'counted from the scroll');
    });
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

  testWidgets('a cross says which stop it takes out', (tester) async {
    await guide(tester);
    await overview(tester);
    expect(find.byTooltip("Retirer l'étape 1, Pause"), findsOneWidget);
    expect(find.byTooltip("Retirer l'étape 2, Fontaine"), findsOneWidget);
  });

  testWidgets('a stop put back after the overview was left shows again in the strip', (
    tester,
  ) async {
    final app = await guide(tester);
    await overview(tester);
    routes.gate = Completer<void>();
    await touch(tester, cross('Pause'));
    await tester.pump();
    // Back to the road while the new route is on its way.
    await tester.tap(find.byTooltip('Recentrer'));
    await tester.pump();
    routes.gate!.complete();
    routes.gate = null;
    await settleShort(tester);
    expect(stops(app, tester), [fontaine]);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(stops(app, tester), [pause, fontaine]);
    await overview(tester);
    expect(chip('Pause'), findsOneWidget);
  });

  testWidgets('a stop taken out whose new route moves the destination says both, its undo '
      'kept', (tester) async {
    final moved = routeFixture(
      'limoges_drive',
      edit: (answer) => answer['movedStops'] = [
        {'stopIndex': 2, 'lat': 45.8458, 'lon': 1.2851, 'distanceM': 120.0},
      ],
    );
    await guide(tester, answers: [moved], more: [moved]);
    await overview(tester);
    await touch(tester, cross('Pause'));
    await settleShort(tester);
    expect(
      find.text(
        "Étape retirée\nPoint d'arrivée déplacé de 120 m vers la rue accessible la plus proche",
      ),
      findsOneWidget,
    );
    expect(find.text('Annuler'), findsOneWidget);
  });

  testWidgets('a stop added right after one taken out keeps the moves its route told', (
    tester,
  ) async {
    final moved = routeFixture(
      'closure_detour',
      edit: (answer) => answer['movedStops'] = [
        {'stopIndex': 1, 'lat': 45.8352, 'lon': 1.2655, 'distanceM': 90.0},
      ],
    );
    await guide(tester, answers: [plan, moved], more: [moved]);
    await overview(tester);
    await touch(tester, cross('Pause'));
    await settleShort(tester);
    expect(find.text('Étape retirée'), findsOneWidget);
    // At once, a point of the map added as a stop: its route moves it.
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

  testWidgets('on the web, a screen reader finds the chips where they are drawn once the '
      'strip scrolled: every name in it is an attribute, no text laid out to overflow it', (
    tester,
  ) async {
    // Flutter web (3.47) writes a sideways scroll's offset to its element's
    // scrollTop, which the browser grants as far as the content overflows
    // downwards; a leaf's name is laid out as text in its own box, and the
    // cross's wrapped into a column taller than the strip (the nodes 54 to
    // 82 px over the chips in Chromium). A node with children is named by
    // an attribute.
    final semantics = tester.ensureSemantics();
    await guide(tester);
    await overview(tester);
    final rows = find.semantics.scrollable(axis: Axis.horizontal).evaluate().where((node) {
      var holds = false;
      node.visitChildren((child) {
        holds = holds || _labels(child).contains('Tout le trajet');
        return !holds;
      });
      return holds;
    }).toList();
    expect(rows, hasLength(1), reason: 'the strip scrolls sideways');
    final named = <SemanticsNode>[];
    void collect(SemanticsNode node) {
      if (node.label.isNotEmpty || node.tooltip.isNotEmpty) named.add(node);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    rows.single.visitChildren((child) {
      collect(child);
      return true;
    });
    final names = [for (final n in named) _labels(n)];
    expect(names, contains("Retirer l'étape 1, Pause"));
    expect(names, contains(startsWith('Étape 1 : Pause')));
    expect(names, contains(startsWith('Arrivée')));
    for (final node in named) {
      expect(node.hasChildren, isTrue, reason: '"${_labels(node)}" laid out as text');
    }
    semantics.dispose();
  });

  testWidgets('the chip that takes the place of a stop taken out shows whole, or its start, the '
      'row scrolled', (tester) async {
    await guide(tester);
    await overview(tester);
    final row = find.ancestor(of: find.text('Tout'), matching: find.byType(SingleChildScrollView));
    // Fontaine's end at the strip's end, the arrival past it.
    await Scrollable.ensureVisible(
      tester.element(
        find.ancestor(of: chip('Fontaine'), matching: find.byType(AnimatedContainer)).first,
      ),
      alignment: 1,
    );
    await settleShort(tester);
    final strip = tester.getRect(row);
    expect(tester.getRect(chip('Arrivée')).left, greaterThanOrEqualTo(strip.right - 0.5));
    await tester.tap(cross('Fontaine'));
    await settleShort(tester);
    final arrival = tester.getRect(
      find.ancestor(of: chip('Arrivée'), matching: find.byType(AnimatedContainer)).first,
    );
    // Clear of the fade a row scrolled away from its start draws there.
    expect(arrival.left, greaterThanOrEqualTo(strip.left + 48 - 0.5), reason: 'its start');
    // Its end too, when it fits; wider (the test's type), its start.
    if (arrival.width <= strip.width - 48) {
      expect(arrival.right, lessThanOrEqualTo(strip.right + 0.5), reason: 'its end');
    } else {
      expect(arrival.left, lessThanOrEqualTo(strip.left + 48 + 0.5), reason: 'no further');
    }
  });

  testWidgets('the row the user moved during the new route stays where the user left it', (
    tester,
  ) async {
    await guide(tester);
    await overview(tester);
    final row = find.ancestor(of: find.text('Tout'), matching: find.byType(SingleChildScrollView));
    await Scrollable.ensureVisible(
      tester.element(
        find.ancestor(of: chip('Fontaine'), matching: find.byType(AnimatedContainer)).first,
      ),
      alignment: 1,
    );
    await settleShort(tester);
    final slow = routes.gate = Completer<void>();
    await tester.tap(cross('Fontaine'));
    await settleShort(tester);
    // Back to the start by a finger while the new route is computed.
    await tester.drag(row, const Offset(600, 0));
    await settleShort(tester);
    final left = tester.getRect(find.text('Tout'));
    slow.complete();
    routes.gate = null;
    await settleShort(tester);
    expect(tester.getRect(find.text('Tout')), left, reason: 'not scrolled back by the new route');
  });

  testWidgets('the row turned back by a mouse wheel during the new route stays there', (
    tester,
  ) async {
    await guide(tester);
    await overview(tester);
    final row = find.ancestor(of: find.text('Tout'), matching: find.byType(SingleChildScrollView));
    await Scrollable.ensureVisible(
      tester.element(
        find.ancestor(of: chip('Fontaine'), matching: find.byType(AnimatedContainer)).first,
      ),
      alignment: 1,
    );
    await settleShort(tester);
    final slow = routes.gate = Completer<void>();
    await tester.tap(cross('Fontaine'));
    await settleShort(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    tester.binding.handlePointerEvent(mouse.hover(tester.getCenter(row)));
    tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -600)));
    await settleShort(tester);
    final left = tester.getRect(find.text('Tout'));
    slow.complete();
    routes.gate = null;
    await settleShort(tester);
    expect(tester.getRect(find.text('Tout')), left, reason: 'not scrolled back by the new route');
  });

  testWidgets('a chip whole already stays where it is when the stop before it is taken out', (
    tester,
  ) async {
    await guide(tester, size: tablet);
    await overview(tester);
    final before = tester.getRect(find.text('Tout'));
    await tester.tap(cross('Pause'));
    await settleShort(tester);
    expect(tester.getRect(find.text('Tout')), before, reason: 'no scroll');
  });

  for (final (name, padding) in [
    ('', null),
    (' with a notch', const FakeViewPadding(left: 44, right: 44, bottom: 21)),
  ]) {
    testWidgets("on a phone on its side$name, the strip runs over the bar from the panel's edge "
        'to the buttons, the maneuver and its notices above it', (tester) async {
      const size = Size(860, 560);
      await guide(tester, size: size, viewPadding: padding);
      await overview(tester);
      final strip = tester.getRect(
        find.ancestor(of: find.text('Tout'), matching: find.byType(SingleChildScrollView)),
      );
      final left = padding?.left ?? 0;
      final right = padding?.right ?? 0;
      // 400 dp beside the panel: "Tout" and the first chip.
      expect(strip.left, closeTo(left + 8, 0.5), reason: "from the panel's edge");
      expect(strip.right, closeTo(size.width - right - 72, 0.5), reason: 'to the buttons');
      expect(tester.getRect(chip('Fontaine')).left, lessThan(strip.right), reason: 'a third chip');
      // A stop taken out: its notice and undo under the maneuver, above the
      // strip.
      await tester.tap(cross('Pause'));
      await settleShort(tester);
      final undo = tester.getRect(find.text('Annuler'));
      expect(undo.bottom, lessThanOrEqualTo(strip.top), reason: 'above the strip');
      // More notices scroll under the maneuver rather than slide under the
      // strip: the panel's room ends above it.
      final panel = find
          .ancestor(of: find.text('Annuler'), matching: find.byType(SingleChildScrollView))
          .first;
      final room = tester.renderObject<RenderBox>(panel).constraints.maxHeight;
      expect(tester.getRect(panel).top + room, lessThanOrEqualTo(strip.top + 0.5));
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(chip('Pause'), findsOneWidget, reason: 'the undo reached');
    });
  }

  // Where the strip goes: over the bar (a phone upright, or on its side when
  // its panel keeps the maneuver above the strip), or beside the panel.
  const overBar = true;
  const besidePanel = false;
  for (final (name, size, text, padding, over) in [
    ('a phone', phone, 1.0, null, overBar),
    ('a small phone, large text', const Size(360, 640), 1.3, null, overBar),
    // The test's type is taller than the app's: at 400 dp the maneuver and
    // the bar leave no room for the strip in the panel, which 844 x 390
    // leaves in the app's own type (measured in Chromium).
    ('a phone on its side', const Size(860, 400), 1.0, null, besidePanel),
    // A camera cut-out on the left, a home bar at the foot: the strip and
    // its room on the map move with the safe area.
    (
      'a phone on its side with a notch',
      const Size(860, 400),
      1.0,
      const FakeViewPadding(left: 44, bottom: 21),
      besidePanel,
    ),
    ('a taller phone on its side', const Size(860, 560), 1.0, null, overBar),
    (
      'a taller phone on its side with a notch',
      const Size(860, 560),
      1.0,
      const FakeViewPadding(left: 44, right: 44, bottom: 21),
      overBar,
    ),
    ('a phone with a home bar', phone, 1.0, const FakeViewPadding(top: 47, bottom: 34), overBar),
    ('a tablet', tablet, 1.0, null, overBar),
    ('a desktop', desktop, 1.0, null, besidePanel),
  ]) {
    testWidgets('on $name, the strip is one line over the map, clear of the maneuver, the bar '
        'and the buttons, and the route clear of it', (tester) async {
      await guide(tester, size: size, textScale: text, viewPadding: padding);
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
        'Voix complète',
        'Lieux sur la carte',
        'Sur le trajet',
        'Signaler un problème sur la route',
        'Recentrer',
        'Arrêter le guidage',
      ]) {
        expect(strip.overlaps(tester.getRect(find.byTooltip(tip))), isFalse, reason: tip);
      }
      if (over) {
        expect(strip.bottom, lessThanOrEqualTo(bar.top), reason: 'over the bar');
        expect(strip.top, greaterThanOrEqualTo(banner.bottom), reason: 'under the maneuver');
      } else {
        expect(strip.left, greaterThanOrEqualTo(banner.right), reason: 'beside the panel');
      }
      final camera = map().camera as FitCamera;
      expect(
        map().padding.bottom + camera.room.bottom,
        greaterThanOrEqualTo(size.height - strip.top - 0.5),
        reason: 'the route above it',
      );
      // No place drawn large under it either, and its room is given back
      // with the overview.
      bool covered(Rect r) => map().rich!.obstacles.any(
        (o) => o.inflate(0.5).contains(r.topLeft) && o.inflate(0.5).contains(r.bottomRight),
      );
      expect(covered(strip), isTrue, reason: 'a place drawn large under the strip');
      await tester.tap(find.byTooltip('Recentrer'));
      await settleShort(tester);
      expect(map().rich!.obstacles.any((o) => o.overlaps(strip)), isFalse);
    });
  }
}

/// The words a node says: its label, else its tooltip.
String _labels(SemanticsNode node) => node.label.isEmpty ? node.tooltip : node.label;
