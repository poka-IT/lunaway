import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_screen.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';

import '../helpers/fake_browser.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'map_screen_test.dart' show recordAppExits, systemBack;
import 'navigation_test.dart' show driveFixes;

// The report of 2026-10-08, on the web app: a route started, then ended,
// then the place closed. The close went back in the tab's history onto the
// guidance's entry ("Le guidage n'a pas pu démarrer sur cet appareil."),
// or onto the preview's, which the close reopened every time.

const _error = "Le guidage n'a pas pu démarrer sur cet appareil.";

/// Wide enough for the details in a panel of their own, right of the map.
const _wide = Size(1600, 1000);

/// A phone tall enough for the place's whole sheet.
const _tallPhone = Size(400, 1600);

/// The medium width class: the details in a side panel, beside the rail.
const _medium = Size(720, 1400);

MapSelection? _open(TestApp app, WidgetTester tester) =>
    app.container(tester).read(selectionProvider);

/// The pages a history entry shows over the map, as go_router writes them in
/// its state: none for the map itself.
List<String> _pagesOver(Object? state) => switch (state) {
  {'imperativeMatches': final List<Object?> pages} => [
    for (final page in pages)
      if (page case {'location': final String location}) location,
  ],
  _ => const [],
};

/// A voice whose preparation waits for [gate]: the guidance's start stays
/// pending until then.
final class _GatedVoice implements VoiceOutput {
  final gate = Completer<void>();

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    await gate.future;
    return VoiceReadiness.ready;
  }

  @override
  bool get chimes => false;

  @override
  Future<bool> say(String text, {bool chime = false}) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<bool> installVoices() async => true;
}

/// Neither the preview, nor the guidance, nor its error.
void _onlyTheMap() {
  expect(find.byType(RoutePreviewScreen), findsNothing);
  expect(find.byType(GuidanceScreen), findsNothing);
  expect(find.text(_error), findsNothing);
}

void main() {
  /// The app on the map with the guidance's fakes; in a browser when
  /// [web].
  Future<(TestApp, FakeBrowser?)> pumpApp(
    WidgetTester tester, {
    Size size = _wide,
    bool web = true,
    List<Object>? answers,
    VoiceOutput? voice,
    FakeLocationFeed? feed,
  }) async {
    final browser = web ? FakeBrowser(tester) : null;
    final plan = routeFixture('utrillo_motorhome');
    final app = await pumpLunaway(
      tester,
      size: size,
      overrides: [
        ...navigationOverrides(
          routes: FakeRouteService(answers ?? [for (var i = 0; i < 6; i++) plan]),
          engine: LineEngine([plan]),
          voice: voice,
          feed: feed,
          settings: MemoryRouteSettings(),
        ),
        if (browser != null) browserProvider.overrideWithValue(browser),
      ],
    );
    return (app, browser);
  }

  Future<void> tapPin(TestApp app, WidgetTester tester, String id) async {
    app.map.lastProps!.onPlaceTap(id);
    await settleShort(tester);
  }

  /// "Itinéraire" from what is open, the preview.
  Future<void> openRoute(WidgetTester tester, {String label = 'Itinéraire'}) async {
    await tester.tap(find.text(label).last);
    await settleShort(tester);
    expect(find.byType(RoutePreviewScreen), findsOneWidget);
  }

  /// "C'est parti !", then "Terminer", confirmed: back on the map.
  Future<void> guideAndEnd(TestApp app, WidgetTester tester) async {
    await tester.tap(find.text("C'est parti !"));
    await settleShort(tester);
    expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
    await tester.tap(find.byTooltip('Terminer'));
    await settleShort(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await settleShort(tester);
    expect(app.container(tester).read(guidanceControllerProvider), isNull);
    _onlyTheMap();
  }

  group('in a browser, after a guidance ended', () {
    for (final (name, size) in [
      ('a wide desktop', _wide),
      ('a medium window', _medium),
      ('a phone', _tallPhone),
    ]) {
      testWidgets('on $name the close shows the bare map, and no entry behind holds the route', (
        tester,
      ) async {
        final (app, browser) = await pumpApp(tester, size: size);
        await tapPin(app, tester, lakeArea.id);
        await openRoute(tester);
        await guideAndEnd(app, tester);
        expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the place it left');
        await tester.tap(find.byTooltip('Fermer'));
        await settleShort(tester);
        _onlyTheMap();
        expect(_open(app, tester), isNull);
        expect(browser!.location, '/map');
        final behind = browser.entries.sublist(0, browser.index + 1);
        expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
      });
    }

    testWidgets('Escape closes the place onto the bare map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser!.location, '/map');
    });

    testWidgets("the browser's back closes the place onto the bare map", (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await browser!.back();
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser.leftApp, isFalse);
    });

    testWidgets('after two guidances ended, the close shows the bare map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser!.location, '/map');
    });

    testWidgets('from a point of the map, the close shows the bare map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      app
          .container(tester)
          .read(mapFlowProvider.notifier)
          .select(const PointSelection(LatLng(45.7629, 4.831697)));
      await settleShort(tester);
      expect(browser!.location, '/map?point');
      await openRoute(tester, label: "Itinéraire jusqu'ici");
      await guideAndEnd(app, tester);
      expect(_open(app, tester), isA<PointSelection>());
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
    });

    testWidgets("forward to the ended guidance's page shows the map, not an error", (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      expect(browser!.moves, [-1], reason: '"Terminer" went back to the map');
      await browser.forward();
      await settleShort(tester);
      _onlyTheMap();
      expect(browser.moves, [-1, -1], reason: "the guidance's page, reached, left at once");
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      expect(browser.location, '/map?place=${lakeArea.id}');
    });

    testWidgets('a window crossing a width class while the guidance starts: the close shows the '
        'bare map', (tester) async {
      final voice = _GatedVoice();
      final (app, browser) = await pumpApp(tester, size: _tallPhone, voice: voice);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await tester.tap(find.text("C'est parti !"));
      await tester.pump();
      // The phone turned in its holder while the voice gets ready: the bar
      // of "C'est parti !" is built again elsewhere.
      tester.view.physicalSize = _wide;
      await tester.pump();
      voice.gate.complete();
      await settleShort(tester);
      expect(find.byType(GuidanceScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Terminer'));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
      await settleShort(tester);
      _onlyTheMap();
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      final behind = browser!.entries.sublist(0, browser.index + 1);
      expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
    });

    testWidgets('a card opened over the preview while the guidance starts: the close shows the '
        'bare map', (tester) async {
      final voice = _GatedVoice();
      final (app, browser) = await pumpApp(tester, voice: voice);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await tester.tap(find.text("C'est parti !"));
      await tester.pump();
      // The map of the preview still answers while the guidance starts.
      SchematicRouteMap.last!.onLongPress!(const LatLng(45.84, 1.27));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Point sur la carte'), findsWidgets);
      voice.gate.complete();
      await settleShort(tester);
      expect(find.byType(GuidanceScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Terminer'));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
      await settleShort(tester);
      _onlyTheMap();
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      final behind = browser!.entries.sublist(0, browser.index + 1);
      expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
    });

    testWidgets('the preview left while the guidance starts: its end comes back to the place', (
      tester,
    ) async {
      final voice = _GatedVoice();
      final (app, browser) = await pumpApp(tester, voice: voice);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await tester.tap(find.text("C'est parti !"));
      await tester.pump();
      await browser!.back();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RoutePreviewScreen), findsNothing);
      final map = tester.state(find.byType(MapScreen));
      voice.gate.complete();
      await settleShort(tester);
      expect(find.byType(GuidanceScreen), findsOneWidget);
      expect(
        tester.state(find.byType(MapScreen, skipOffstage: false)),
        same(map),
        reason: 'the map stays under the guidance, its view with it',
      );
      await tester.tap(find.byTooltip('Terminer'));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the map under it');
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      final behind = browser.entries.sublist(0, browser.index + 1);
      expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
    });

    testWidgets('after "Y aller directement" in the preview, the close shows the bare map', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      SchematicRouteMap.last!.onLongPress!(const LatLng(45.84, 1.27));
      await settleShort(tester);
      await tester.tap(find.text('Y aller directement'));
      await settleShort(tester);
      expect(find.text('Point sur la carte'), findsOneWidget, reason: 'the preview of the point');
      await guideAndEnd(app, tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      final behind = browser!.entries.sublist(0, browser.index + 1);
      expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
    });
  });

  group('in a browser, the preview left', () {
    testWidgets('by its own back: the close shows the bare map rather than the preview again', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await tester.tap(find.byTooltip('Retour'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser!.location, '/map');
    });

    testWidgets('by a pop asked of its page (an app bar): through the history all the same', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await Navigator.of(tester.element(find.byType(RoutePreviewScreen))).maybePop();
      await settleShort(tester);
      _onlyTheMap();
      expect(browser!.moves, [-1]);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
    });

    testWidgets('by two presses before the browser moved: one entry back, the place still open', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      final back = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip('Retour'), matching: find.byType(IconButton)),
      );
      back.onPressed!();
      back.onPressed!();
      await settleShort(tester);
      _onlyTheMap();
      expect(browser!.moves, [-1]);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
    });

    testWidgets('for the places around a destination out of reach: the back leaves no preview', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester, answers: [routeFixture('toulouse_no_route')]);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      final around = find.text('Voir les lieux autour de la destination');
      await tester.ensureVisible(around);
      await tester.tap(around);
      await settleShort(tester);
      _onlyTheMap();
      await browser!.back();
      await settleShort(tester);
      _onlyTheMap();
      expect(browser.leftApp, isFalse);
    });
  });

  group('in a browser, a page over the map', () {
    testWidgets('a selection changed under the preview writes no address and keeps the preview', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      final entries = browser!.entries.length;
      // As the surroundings of a place's card over the route do.
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(campsite.id));
      await settleShort(tester);
      expect(find.byType(RoutePreviewScreen), findsOneWidget);
      expect(browser.entries, hasLength(entries));
      expect(browser.location, '/map?place=${lakeArea.id}', reason: "the map's address under it");
    });
  });

  group('the guidance page without a guidance', () {
    testWidgets('in a browser, a link to it shows the map in its place', (tester) async {
      final (app, browser) = await pumpApp(tester);
      app.container(tester).read(routerProvider).go(NavigationRoutes.guidance);
      await settleShort(tester);
      _onlyTheMap();
      expect(browser!.location, '/map');
      // Its entry went to the map: the back does not come to it again.
      await browser.back();
      await settleShort(tester);
      _onlyTheMap();
    });

    testWidgets('in the apps, it goes back to the map', (tester) async {
      final (app, _) = await pumpApp(tester, size: phone, web: false);
      unawaited(app.container(tester).read(routerProvider).push<void>(NavigationRoutes.guidance));
      await settleShort(tester);
      _onlyTheMap();
    });
  });

  group('the system back of the apps, after a guidance ended', () {
    testWidgets('closes the place, then leaves the app, never the route', (tester) async {
      final exits = recordAppExits(tester);
      final (app, _) = await pumpApp(tester, size: _tallPhone, web: false);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      await systemBack(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(exits, isEmpty);
      await systemBack(tester);
      expect(exits, hasLength(1));
    });
  });

  group('a back during a guidance', () {
    const question = 'Arrêter le guidage ?';

    /// "C'est parti !" from the place's preview: the guidance runs.
    Future<void> start(TestApp app, WidgetTester tester) async {
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await tester.tap(find.text("C'est parti !"));
      await settleShort(tester);
      expect(find.byType(GuidanceScreen), findsOneWidget);
      expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
    }

    void stillGuiding(TestApp app, WidgetTester tester) {
      expect(find.text(question), findsNothing);
      expect(find.byType(GuidanceScreen), findsOneWidget);
      expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
    }

    /// "Arrêter": the voice and the guidance stop, the place is back on
    /// the map, and its close leaves the bare map with no entry behind it
    /// holding the route.
    Future<void> stop(TestApp app, WidgetTester tester, RecordingVoice voice) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Arrêter'));
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider), isNull);
      expect(voice.stops, greaterThan(0), reason: 'the voice says nothing more');
      _onlyTheMap();
      expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the place it left');
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
    }

    testWidgets('in a browser, its back asks first; Continuer keeps the guidance, Arrêter ends it '
        'onto the place', (tester) async {
      final voice = RecordingVoice();
      final (app, browser) = await pumpApp(tester, voice: voice);
      await start(app, tester);
      await browser!.back();
      await settleShort(tester);
      expect(find.text(question), findsOneWidget);
      expect(find.byType(GuidanceScreen), findsOneWidget, reason: 'the guidance stays behind it');
      await tester.tap(find.widgetWithText(TextButton, 'Continuer'));
      await settleShort(tester);
      stillGuiding(app, tester);
      expect(_pagesOver(browser.entries[browser.index].state), [
        NavigationRoutes.guidance,
      ], reason: "the entry shown is the guidance's again: the next back asks again");
      await browser.back();
      await settleShort(tester);
      expect(find.text(question), findsOneWidget);
      await stop(app, tester, voice);
      expect(browser.location, '/map');
      expect(browser.leftApp, isFalse);
      final behind = browser.entries.sublist(0, browser.index + 1);
      expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
    });

    testWidgets('in a browser, every back answered "Continuer" asks again', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await start(app, tester);
      for (var i = 0; i < 8; i++) {
        await browser!.back();
        await settleShort(tester);
        expect(find.text(question), findsOneWidget, reason: 'back number ${i + 1}');
        await tester.tap(find.widgetWithText(TextButton, 'Continuer'));
        await settleShort(tester);
        stillGuiding(app, tester);
      }
      expect(browser!.leftApp, isFalse);
    });

    testWidgets('in a browser, a back while the question is open keeps the guidance', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await start(app, tester);
      await browser!.back();
      await settleShort(tester);
      expect(find.text(question), findsOneWidget);
      await browser.back();
      await settleShort(tester);
      stillGuiding(app, tester);
      expect(browser.leftApp, isFalse);
    });

    testWidgets('in a browser, Escape asks first', (tester) async {
      final voice = RecordingVoice();
      final (app, browser) = await pumpApp(tester, voice: voice);
      await start(app, tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      expect(find.text(question), findsOneWidget);
      await stop(app, tester, voice);
      final behind = browser!.entries.sublist(0, browser.index + 1);
      expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
    });

    testWidgets('in a browser, the back from the arrival ends the guidance without asking', (
      tester,
    ) async {
      final plan = routeFixture('utrillo_motorhome');
      final feed = FakeLocationFeed(position: plan.routes.first.line.first);
      final (app, browser) = await pumpApp(tester, feed: feed);
      await start(app, tester);
      for (final fix in driveFixes(plan.routes.first)) {
        feed.send(fix);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider)?.phase, GuidancePhase.arrived);
      await browser!.back();
      await settleShort(tester);
      expect(find.text(question), findsNothing);
      expect(app.container(tester).read(guidanceControllerProvider), isNull);
      _onlyTheMap();
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
    });

    testWidgets('in a browser, the back from the arrival ends the guidance even from "Tout le '
        'trajet"', (tester) async {
      final plan = routeFixture('utrillo_motorhome');
      final feed = FakeLocationFeed(position: plan.routes.first.line.first);
      final (app, browser) = await pumpApp(tester, feed: feed);
      await start(app, tester);
      await tester.tap(find.byTooltip('Tout le trajet'));
      await settleShort(tester);
      for (final fix in driveFixes(plan.routes.first)) {
        feed.send(fix);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleShort(tester);
      expect(app.container(tester).read(guidanceControllerProvider)?.phase, GuidancePhase.arrived);
      expect(
        app.container(tester).read(guidanceCameraProvider).mode,
        GuidanceCameraMode.overview,
        reason: 'still the whole route: the countdown stops with the vehicle',
      );
      await browser!.back();
      await settleShort(tester);
      expect(find.text(question), findsNothing);
      expect(app.container(tester).read(guidanceControllerProvider), isNull);
      _onlyTheMap();
    });

    testWidgets("in the apps, the system's back asks first, then the place, then the app", (
      tester,
    ) async {
      final exits = recordAppExits(tester);
      final voice = RecordingVoice();
      final (app, _) = await pumpApp(tester, size: _tallPhone, web: false, voice: voice);
      await start(app, tester);
      await systemBack(tester);
      expect(find.text(question), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Continuer'));
      await settleShort(tester);
      stillGuiding(app, tester);
      await systemBack(tester);
      expect(find.text(question), findsOneWidget);
      await stop(app, tester, voice);
      expect(exits, isEmpty);
      await systemBack(tester);
      expect(exits, hasLength(1));
    });

    for (final web in [true, false]) {
      testWidgets('${web ? 'in a browser' : 'in the apps'}, a back from "Tout le trajet" goes back '
          'to the road without asking; the next back asks', (tester) async {
        final (app, browser) = await pumpApp(tester, size: _tallPhone, web: web);
        await start(app, tester);
        Future<void> back() async {
          if (browser != null) {
            await browser.back();
            await settleShort(tester);
          } else {
            await systemBack(tester);
          }
        }

        await tester.tap(find.byTooltip('Tout le trajet'));
        await settleShort(tester);
        expect(find.byTooltip('Tout le trajet'), findsNothing, reason: 'the whole route shown');
        await back();
        stillGuiding(app, tester);
        expect(find.byTooltip('Tout le trajet'), findsOneWidget, reason: 'the road again');
        await back();
        expect(find.text(question), findsOneWidget);
      });
    }

    testWidgets('in the apps, Escape from "Tout le trajet" goes back to the road', (tester) async {
      final (app, _) = await pumpApp(tester, web: false);
      await start(app, tester);
      await tester.tap(find.byTooltip('Tout le trajet'));
      await settleShort(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      stillGuiding(app, tester);
      expect(find.byTooltip('Tout le trajet'), findsOneWidget);
    });

    testWidgets('in the apps, Escape asks first', (tester) async {
      final (app, _) = await pumpApp(tester, web: false);
      await start(app, tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      expect(find.text(question), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Continuer'));
      await settleShort(tester);
      stillGuiding(app, tester);
    });
  });

  group('in a browser, an entry the map did not write', () {
    testWidgets('a link to the place open: the close stays on the map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      app.container(tester).read(routerProvider).go('/map?place=${lakeArea.id}');
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull, reason: 'a back would have landed on the place again');
      expect(browser!.location, '/map');
      expect(browser.moves, isEmpty);
    });
  });
}
