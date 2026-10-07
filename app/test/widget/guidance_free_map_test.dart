import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show driveFixes, utrillo;

/// An aire beside the Limoges route.
const _aire = PlaceSummary(
  id: 'aire-limoges',
  kind: PlaceKind.motorhomeArea,
  lat: 45.8462,
  lon: 1.2828,
  overnight: OvernightStatus.allowed,
  name: 'Aire du Naveix',
);

const _water = PoiFeature(
  id: 'poi-water',
  kind: PoiKind.drinkingWater,
  position: LatLng(45.8458, 1.2831),
  name: 'Fontaine du Champ de Juillet',
);

void main() {
  late FakeLocationFeed feed;
  late RecordingVoice voice;
  late MemoryRouteSettings settings;

  RouteMapProps map() => SchematicRouteMap.last!;

  Future<TestApp> guide(
    WidgetTester tester,
    RoutePlan plan, {
    Size size = phone,
    AppLocale locale = AppLocale.fr,
    List<Object> answers = const [],
    MemoryRouteSettings? store,
    PlaceFilter filter = PlaceFilter.none,
    // Online, the places come from the main map's tiles; offline, the
    // device's places along the route.
    bool online = true,
    List<PlaceSummary> nearRoute = const [],
    double textScale = 1,
  }) async {
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    voice = RecordingVoice();
    settings = store ?? MemoryRouteSettings();
    final app = await pumpLunaway(
      tester,
      size: size,
      locale: locale,
      textScale: textScale,
      settings: AppSettings(filter: filter),
      online: online ? FakeOnlinePlaces(const []) : null,
      overrides: navigationOverrides(
        routes: FakeRouteService(answers.isEmpty ? [plan] : answers),
        feed: feed,
        engine: LineEngine([plan, for (final a in answers) ?(a is RoutePlan ? a : null)]),
        voice: voice,
        settings: settings,
        placesNearRoute: nearRoute,
      ),
    );
    final container = app.container(tester);
    final t = await locale.build();
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

  Future<void> drive(
    WidgetTester tester,
    RoutePlan plan, {
    required double toM,
    double fromM = 0,
  }) async {
    for (final f in driveFixes(plan.routes.first, toM: toM).skip((fromM / 10).round())) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleShort(tester);
  }

  /// The user moves the map: the engine says so.
  Future<void> gesture(WidgetTester tester) async {
    map().onGesture!();
    await settleShort(tester);
  }

  setUp(() => SchematicRouteMap.last = null);

  group('the free map', () {
    testWidgets('a gesture frees the map at once, and "Recentrer" brings it back', (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      expect(map().camera, isA<FollowCamera>());
      expect(map().guiding, isTrue, reason: 'pan, zoom, turn and tilt while following');
      expect(find.text('Recentrer'), findsNothing);
      await gesture(tester);
      expect(map().camera, isA<FreeCamera>());
      expect(find.text('Recentrer'), findsOneWidget);
      // The overview stays on its own button.
      expect(find.byTooltip('Tout le trajet'), findsOneWidget);
      await tester.tap(find.text('Recentrer'));
      await settleShort(tester);
      final camera = map().camera;
      expect(camera, isA<FollowCamera>());
      expect((camera as FollowCamera).ease, FreeMap.recenterEase);
      expect(find.text('Recentrer'), findsNothing);
    });

    testWidgets('the magnet snaps a view brought back near the vehicle, not one left away', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      final course = map().vehicle!.course!;
      await gesture(tester);
      final anchor = followAnchor(phone, map().padding);
      FreeView rest(Offset vehicle, {double? zoom}) => FreeView(
        size: phone,
        vehicle: vehicle,
        zoom: zoom ?? followZoom(10),
        bearing: course,
        tilt: followTiltDeg,
      );
      final far = rest(anchor + const Offset(0, -200));
      map().onRest!(far);
      await settleShort(tester);
      expect(map().camera, isA<FreeCamera>(), reason: 'the vehicle far from its place');
      expect(
        (map().camera as FreeCamera).view,
        far,
        reason: 'a map made anew (the phone turned) opens where the user left it',
      );
      map().onRest!(rest(anchor + const Offset(20, 25), zoom: followZoom(10) + 2));
      await settleShort(tester);
      expect(map().camera, isA<FreeCamera>(), reason: 'two levels closer');
      map().onRest!(rest(anchor + const Offset(20, 25)));
      await settleShort(tester);
      final camera = map().camera;
      expect(camera, isA<FollowCamera>());
      expect((camera as FollowCamera).ease, FreeMap.snapEase);
    });

    testWidgets('a nudge the magnet answers in the same frame is a new request to follow', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      final before = (map().camera as FollowCamera).request;
      final course = map().vehicle!.course!;
      // The gesture and the rest before any frame: the screen never builds
      // the free map, the engine must still hear a new request.
      map().onGesture!();
      map().onRest!(
        FreeView(
          size: phone,
          vehicle: followAnchor(phone, map().padding) + const Offset(3, 3),
          zoom: followZoom(10),
          bearing: course,
          tilt: followTiltDeg,
        ),
      );
      await settleShort(tester);
      final after = map().camera;
      expect(after, isA<FollowCamera>());
      expect((after as FollowCamera).request, greaterThan(before));
      expect(after.ease, FreeMap.snapEase);
    });

    testWidgets('after 12 s without a touch while driving the map follows again', (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      // A finger on the map: no return however long it stays.
      map().onTouch!(true);
      await gesture(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(map().camera, isA<FreeCamera>());
      map().onTouch!(false);
      await tester.pump(const Duration(seconds: 11));
      expect(map().camera, isA<FreeCamera>());
      await tester.pump(const Duration(seconds: 2));
      expect(map().camera, isA<FollowCamera>());
    });

    testWidgets('the guidance goes on while the map is free: instructions and voice', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      expect(find.text('90 m'), findsOneWidget, reason: 'to the left turn at 192 m');
      await gesture(tester);
      final said = voice.said.length;
      await drive(tester, plan, toM: 400, fromM: 110);
      expect(map().camera, isA<FreeCamera>());
      expect(find.text('90 m'), findsNothing, reason: 'the banner moved on');
      expect(voice.said.length, greaterThan(said), reason: 'the voice spoke on');
    });
  });

  group('the places on the map', () {
    testWidgets("by default the map's own filters, drawn from the main map's tiles", (
      tester,
    ) async {
      const filter = PlaceFilter(families: {KindFamily.campsites});
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, filter: filter);
      final places = map().places!;
      expect(places.placeTileJsonUrl, endsWith('/places/tiles.json'));
      expect(places.poiTileJsonUrl, endsWith('/poi/tiles.json'));
      expect(places.placeFilter, placeTileFilter(filter));
      expect(places.poiFilter, isNull, reason: 'no chip on, no point');
    });

    testWidgets('the sheet hides them or picks a group, and the choice is kept', (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await tester.tap(find.byTooltip('Lieux sur la carte'));
      await settleShort(tester);
      expect(find.text('Comme sur la carte'), findsOneWidget);
      await tester.tap(find.text('Carburant'));
      await settleShort(tester);
      expect(map().places!.placeFilter, isNull, reason: 'fuel is points only');
      expect(
        map().places!.poiFilter,
        guidancePoiFilter(const GuidancePlaces(groups: {GuidancePlaceGroup.fuel}), category: null),
      );
      await tester.tap(find.text('Eau et vidange'));
      await settleShort(tester);
      expect(map().places!.placeFilter, isNotNull, reason: 'service points and bornes');
      expect(settings.value.guidancePlaces.groups, {
        GuidancePlaceGroup.fuel,
        GuidancePlaceGroup.water,
      });
      await tester.tap(find.text('Montrer les lieux et services'));
      await settleShort(tester);
      expect(map().places!.placeFilter, isNull);
      expect(map().places!.poiFilter, isNull);
      expect(settings.value.guidancePlaces.shown, isFalse);
      expect(
        find.byTooltip('Lieux sur la carte : masqués'),
        findsOneWidget,
        reason: 'the button says the state to a screen reader',
      );
      // The next guidance starts with the same choice.
      final kept = settings;
      await tester.pumpWidget(const SizedBox());
      await guide(tester, plan, store: kept);
      expect(map().places!.placeFilter, isNull);
      await tester.tap(find.byTooltip('Lieux sur la carte : masqués'));
      await settleShort(tester);
      await tester.tap(find.text('Montrer les lieux et services'));
      await settleShort(tester);
      expect(map().places!.poiFilter, isNotNull, reason: 'fuel and water again');
    });

    testWidgets('offline, the places the device holds along the route, by the same choice', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      const dayOnly = PlaceSummary(
        id: 'parking-jour',
        kind: PlaceKind.parking,
        lat: 45.8459,
        lon: 1.2825,
        overnight: OvernightStatus.dayOnly,
      );
      await guide(tester, plan, online: false, nearRoute: [_aire, dayOnly]);
      Set<String> shown() => {
        for (final m in map().marks)
          if (m.kind == RouteMarkKind.place) m.id,
      };
      expect(map().places, isNull, reason: 'no tiles offline');
      expect(shown(), {'place:aire-limoges', 'place:parking-jour'});
      await tester.tap(find.byTooltip('Lieux sur la carte'));
      await settleShort(tester);
      await tester.tap(find.text('Nuit possible'));
      await settleShort(tester);
      expect(shown(), {'place:aire-limoges'});
      await tester.tap(find.text('Montrer les lieux et services'));
      await settleShort(tester);
      expect(shown(), isEmpty);
    });

    testWidgets('a place opens a compact card: go there instead', (tester) async {
      final plan = routeFixture('limoges_drive');
      final app = await guide(tester, plan, answers: [plan, plan]);
      await drive(tester, plan, toM: 100);
      map().onPlaceTap!(_aire);
      await settleShort(tester);
      expect(find.text('Aire du Naveix'), findsOneWidget);
      expect(find.textContaining('Ajouter comme étape'), findsOneWidget);
      expect(find.text('Voir la fiche'), findsOneWidget);
      await tester.tap(find.text('Y aller directement'));
      await settleShort(tester);
      final session = app.container(tester).read(guidanceControllerProvider)!;
      expect(session.target.destination, _aire.position);
      expect(session.target.placeId, _aire.id);
      expect(find.text('Nouvelle destination'), findsOneWidget);
    });

    testWidgets("the place's own card holds the map too", (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, answers: [plan, plan]);
      await drive(tester, plan, toM: 100);
      await gesture(tester);
      map().onPlaceTap!(_aire);
      await settleShort(tester);
      await tester.tap(find.text('Voir la fiche'));
      await settleShort(tester);
      await tester.pump(const Duration(seconds: 20));
      expect(map().camera, isA<FreeCamera>(), reason: 'the details are read');
      await tester.tapAt(const Offset(200, 20));
      await settleShort(tester);
      await tester.pump(const Duration(seconds: 13));
      expect(map().camera, isA<FollowCamera>());
    });

    testWidgets('a point opens the same card, with its source: add it as a stop', (tester) async {
      final plan = routeFixture('limoges_drive');
      final app = await guide(tester, plan, answers: [plan, plan]);
      await drive(tester, plan, toM: 100);
      map().onPoiTap!(_water);
      await settleShort(tester);
      expect(find.text('Fontaine du Champ de Juillet'), findsOneWidget);
      expect(find.text("© les contributeurs d'OpenStreetMap"), findsOneWidget);
      expect(find.text('Voir la fiche'), findsNothing, reason: 'a point has no place card');
      await tester.tap(find.textContaining('Ajouter comme étape'));
      await settleShort(tester);
      final session = app.container(tester).read(guidanceControllerProvider)!;
      expect(session.stops.single.poiId, 'poi-water');
      expect(find.text('Étape ajoutée'), findsOneWidget);
    });

    testWidgets('an open card holds the map: no return to following while it is read', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, answers: [plan, plan]);
      await drive(tester, plan, toM: 100);
      await gesture(tester);
      map().onPlaceTap!(_aire);
      await settleShort(tester);
      await tester.pump(const Duration(seconds: 20));
      expect(map().camera, isA<FreeCamera>());
      await tester.tapAt(const Offset(200, 40));
      await settleShort(tester);
      await tester.pump(const Duration(seconds: 13));
      expect(map().camera, isA<FollowCamera>());
    });
  });

  group('every layout', () {
    for (final (name, size, text) in [
      ('a phone', phone, 1.0),
      ('a small phone, large text', const Size(360, 640), 1.3),
      ('a phone on its side', const Size(860, 400), 1.0),
      ('a small phone on its side, large text', const Size(640, 360), 1.3),
      ('a tablet', tablet, 1.0),
      ('a desktop', desktop, 1.0),
    ]) {
      testWidgets('on $name, "Recentrer" and the places button stand clear of the others', (
        tester,
      ) async {
        final plan = routeFixture('limoges_drive');
        await guide(tester, plan, size: size, textScale: text);
        await drive(tester, plan, toM: 100);
        await gesture(tester);
        // The word and the icon, or the icon alone on a narrow map.
        final button = find.byWidgetPredicate(
          (w) => w.key == const ValueKey('recenter') || w.key == const ValueKey('recenter-icon'),
        );
        expect(button, findsOneWidget);
        expect(
          find.text('Recentrer').evaluate().length + find.byTooltip('Recentrer').evaluate().length,
          1,
          reason: 'its word, on it or in its tooltip',
        );
        final recenter = tester.getRect(button);
        final places = tester.getRect(find.byTooltip('Lieux sur la carte'));
        for (final tip in [
          'Activer la voix',
          'Couper la voix',
          'Carburant le moins cher sur la route',
          'Tout le trajet',
          'Signaler un problème sur la route',
          'Terminer',
        ]) {
          if (find.byTooltip(tip).evaluate().isEmpty) continue;
          final other = tester.getRect(find.byTooltip(tip));
          expect(recenter.overlaps(other), isFalse, reason: tip);
          expect(places.overlaps(other), isFalse, reason: tip);
        }
        expect(recenter.overlaps(places), isFalse);
        expect(recenter.height, greaterThanOrEqualTo(48));
        expect(recenter.width, greaterThanOrEqualTo(48));
        await tester.tap(button);
        await settleShort(tester);
        expect(map().camera, isA<FollowCamera>());
      });
    }

    testWidgets('in English', (tester) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, locale: AppLocale.en);
      await drive(tester, plan, toM: 100);
      await gesture(tester);
      expect(find.text('Recenter'), findsOneWidget);
      await tester.tap(find.byTooltip('Places on the map'));
      await settleShort(tester);
      expect(find.text('Show places and services'), findsOneWidget);
      expect(find.text('As on the map'), findsOneWidget);
      expect(find.text('Overnight spots'), findsOneWidget);
      expect(find.text('Water and dump'), findsOneWidget);
    });
  });
}
