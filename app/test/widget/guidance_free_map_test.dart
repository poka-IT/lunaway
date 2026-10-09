import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/style_expressions.dart';
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
    testWidgets("by default every place, from the main map's tiles, the best drawn large", (
      tester,
    ) async {
      const filter = PlaceFilter(families: {KindFamily.campsites});
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan, filter: filter);
      final places = map().places!;
      expect(places.placeTileJsonUrl, endsWith('/places/tiles.json'));
      expect(places.poiTileJsonUrl, endsWith('/poi/tiles.json'));
      expect(
        places.placeFilter,
        guidancePlaceFilter(const GuidancePlaces(), PlaceFilter.none),
        reason: "every place, not only the map's campsites",
      );
      expect(places.poiFilter, isNull, reason: 'no point by default');
      final rich = map().rich!;
      expect(rich.style.look, GuidanceLook.photos);
      expect(rich.tiles, isTrue);
      expect(rich.style.online, isTrue);
      expect(rich.style.credited, isTrue, reason: "the places' tiles credit the photos");
      expect(rich.limit, RichMarks.compactLimit);
      expect(rich.sizes, RichMarks.phone);
    });

    testWidgets('the places drawn large keep clear of the banner, the buttons and the bar', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await drive(tester, plan, toM: 100);
      final clear = map().rich!.clear;
      final banner = tester.getRect(find.byType(ManeuverIcon).first);
      expect(clear.top, greaterThanOrEqualTo(banner.bottom));
      expect(clear.bottom, greaterThan(map().padding.bottom), reason: 'the bar under the map');
      bool covered(Rect r) => map().rich!.obstacles.any(
        (o) => o.inflate(0.5).contains(r.topLeft) && o.inflate(0.5).contains(r.bottomRight),
      );
      for (final tip in ['Lieux sur la carte', 'Couper la voix', 'Tout le trajet']) {
        expect(covered(tester.getRect(find.byTooltip(tip))), isTrue, reason: tip);
      }
      expect(
        map().rich!.obstacles.every((o) => o.top > banner.bottom + 60),
        isTrue,
        reason: 'above the buttons the edge of the map stays open',
      );
      expect(map().rich!.vehicleAlongM, closeTo(100, 15));
      await gesture(tester);
      expect(
        covered(tester.getRect(find.text('Recentrer'))),
        isTrue,
        reason: '"Recentrer" over the bar',
      );
    });

    for (final (name, size) in [
      ('a phone on its side', const Size(860, 400)),
      ('a desktop', desktop),
    ]) {
      testWidgets('on $name, they keep clear of the panel, the buttons and "Recentrer"', (
        tester,
      ) async {
        final plan = routeFixture('limoges_drive');
        await guide(tester, plan, size: size);
        await drive(tester, plan, toM: 100);
        await gesture(tester);
        final rich = map().rich!;
        final panel = tester.getRect(find.byType(ManeuverIcon).first);
        expect(rich.clear.left, greaterThanOrEqualTo(panel.right), reason: 'the side panel');
        bool covered(Rect r) => rich.obstacles.any(
          (o) => o.inflate(0.5).contains(r.topLeft) && o.inflate(0.5).contains(r.bottomRight),
        );
        for (final tip in ['Lieux sur la carte', 'Tout le trajet']) {
          expect(covered(tester.getRect(find.byTooltip(tip))), isTrue, reason: tip);
        }
        final recenter = find.byWidgetPredicate(
          (w) => w.key == const ValueKey('recenter') || w.key == const ValueKey('recenter-icon'),
        );
        expect(covered(tester.getRect(recenter)), isTrue, reason: '"Recentrer" at the top');
        expect(
          rich.limit,
          size.shortestSide < 600 ? RichMarks.compactLimit : RichMarks.expandedLimit,
        );
      });
    }

    testWidgets('restaurants chosen in the sheet come from the tiles of every category', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      expect(map().places!.poiTileJsonUrl, endsWith('/poi/tiles.json'));
      await tester.tap(find.byTooltip('Lieux sur la carte'));
      await settleShort(tester);
      await tester.tap(find.text('Personnaliser'));
      await settleShort(tester);
      final food = find.widgetWithText(FilterChip, 'Restaurants et cafés');
      await tester.ensureVisible(food);
      await tester.tap(food);
      await settleShort(tester);
      final places = map().places!;
      expect(places.poiTileJsonUrl, endsWith('/poi/all/tiles.json'));
      expect(styleFilterKeeps(places.poiFilter!, {'kind': 'restaurant'}), isTrue);
    });

    testWidgets('"Pour manger" shows the restaurants; the garages stay on the default tiles', (
      tester,
    ) async {
      final plan = routeFixture('limoges_drive');
      await guide(tester, plan);
      await tester.tap(find.byTooltip('Lieux sur la carte'));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pour manger'));
      await settleShort(tester);
      var places = map().places!;
      expect(places.poiTileJsonUrl, endsWith('/poi/all/tiles.json'));
      for (final kind in ['restaurant', 'cafe', 'bakery', 'supermarket']) {
        expect(styleFilterKeeps(places.poiFilter!, {'kind': kind}), isTrue, reason: kind);
      }
      // Garages and equipment alone: the outdoor shops are in the default
      // tiles' layer `pois_more`, which the guidance map draws too.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rien'));
      await settleShort(tester);
      await tester.tap(find.text('Personnaliser'));
      await settleShort(tester);
      final garages = find.widgetWithText(FilterChip, 'Garages et équipement');
      await tester.ensureVisible(garages);
      await tester.tap(garages);
      await settleShort(tester);
      places = map().places!;
      expect(places.poiTileJsonUrl, endsWith('/poi/tiles.json'));
      expect(styleFilterKeeps(places.poiFilter!, {'kind': 'outdoor_shop'}), isTrue);
      final layers = RoutePlaceLayers.jsonLayers(places);
      final more = layers.singleWhere((l) => l['source-layer'] == 'pois_more');
      expect(more['filter'], places.poiFilter, reason: 'the same points as in `pois`');
      expect((more['layout']! as Map)['visibility'], 'visible');
    });

    testWidgets(
      'the sheet offers ready-made choices, the categories on demand and a display, kept',
      (tester) async {
        final plan = routeFixture('limoges_drive');
        await guide(tester, plan);
        await tester.tap(find.byTooltip('Lieux sur la carte'));
        await settleShort(tester);
        for (final label in ['Pour dormir', 'Pour le plein', 'Pour manger', 'Tout', 'Rien']) {
          expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
        }
        expect(find.text('Boulangeries'), findsNothing, reason: 'the categories folded');
        expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Tout')).selected, isTrue);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Pour le plein'));
        await settleShort(tester);
        final fill = GuidancePlaces(selection: GuidancePreset.fill.selection);
        expect(map().places!.placeFilter, guidancePlaceFilter(fill, PlaceFilter.none));
        expect(map().places!.poiFilter, guidancePoiFilter(fill));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Rien'));
        await settleShort(tester);
        expect(map().places!.placeFilter, isNull);
        expect(map().places!.poiFilter, isNull);
        expect(
          find.byTooltip('Lieux sur la carte : masqués'),
          findsOneWidget,
          reason: 'the button says the state to a screen reader',
        );
        // The categories of "On the way", then a minimum rating.
        await tester.tap(find.text('Personnaliser'));
        await settleShort(tester);
        for (final label in [
          'Tous les lieux',
          'Carburant',
          'Dormir',
          'Eau et vidange',
          'Courses',
          'Boulangeries',
          'Restaurants et cafés',
          'À voir',
          'Distributeurs alimentaires',
          'Toilettes, douches',
          'Santé',
          'Services',
          'Recharge',
          'Garages et équipement',
        ]) {
          expect(find.widgetWithText(FilterChip, label), findsOneWidget, reason: label);
        }
        await tester.ensureVisible(find.widgetWithText(FilterChip, 'Dormir'));
        await tester.tap(find.widgetWithText(FilterChip, 'Dormir'));
        await settleShort(tester);
        await tester.ensureVisible(find.text('4 et plus'));
        await tester.tap(find.text('4 et plus'));
        await settleShort(tester);
        final mine = settings.value.guidancePlaces;
        expect(mine.preset, isNull, reason: 'a choice of its own: no ready-made one lit');
        expect(
          mine.selection,
          const GuidanceSelection(categories: {OnTheWayCategory.sleep}, minRating: 4),
        );
        final filter = map().places!.placeFilter!;
        expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'r': 42}), isTrue);
        expect(
          styleFilterKeeps(filter, {'kind': 'parking', 'night': 'day_only', 'r': 42}),
          isFalse,
        );
        expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'r': 38}), isFalse);
        // The display.
        await tester.ensureVisible(find.text('Pictogrammes'));
        await tester.tap(find.text('Pictogrammes'));
        await settleShort(tester);
        expect(map().rich!.style.look, GuidanceLook.pictograms);
        expect(find.textContaining('avec leur prix, leur note ou la nuit'), findsOneWidget);
        // The next guidance starts with the same choice.
        final kept = settings;
        await tester.pumpWidget(const SizedBox());
        await guide(tester, plan, store: kept);
        expect(map().rich!.style.look, GuidanceLook.pictograms);
        expect(map().places!.placeFilter, filter);
        await tester.tap(find.byTooltip('Lieux sur la carte'));
        await settleShort(tester);
        expect(find.text('Boulangeries'), findsOneWidget, reason: 'a choice of its own: open');
        await tester.ensureVisible(find.text('Points discrets'));
        await tester.tap(find.text('Points discrets'));
        await settleShort(tester);
        expect(map().rich!.style.look, GuidanceLook.dots);
        expect(map().rich!.active, isFalse, reason: 'small pins only');
      },
    );

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
      expect(shown(), {'place:aire-limoges', 'place:parking-jour'}, reason: 'every place');
      expect(map().rich!.places, [
        _aire,
        dayOnly,
      ], reason: 'the places shown may stand out, from the device');
      expect(map().rich!.tiles, isFalse);
      expect(map().rich!.style.online, isFalse, reason: 'a pictogram rather than a photo');
      expect(map().rich!.style.photos, isFalse);
      await tester.tap(find.byTooltip('Lieux sur la carte'));
      await settleShort(tester);
      await tester.tap(find.text('Pour dormir'));
      await settleShort(tester);
      expect(shown(), {'place:aire-limoges'}, reason: 'the night only');
      expect(map().rich!.places, [_aire]);
      await tester.tap(find.text('Rien'));
      await settleShort(tester);
      expect(shown(), isEmpty);
      expect(map().rich!.places, isEmpty);
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
          'Sur le trajet',
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

    for (final (name, size, text) in [
      ('a phone', phone, 1.0),
      ('a small phone, large text', const Size(360, 640), 1.3),
      ('a phone on its side', const Size(860, 400), 1.0),
      ('a desktop', desktop, 1.0),
    ]) {
      testWidgets('on $name, the whole route keeps its ends clear of the map buttons', (
        tester,
      ) async {
        final plan = routeFixture('limoges_drive');
        await guide(tester, plan, size: size, textScale: text);
        await drive(tester, plan, toM: 100);
        await tester.tap(find.byTooltip('Tout le trajet'));
        await settleShort(tester);
        final props = map();
        final view = tester.getRect(find.byType(SchematicRouteMap));
        final project = schematicProjection(props, view.size)!;
        final ends = [
          for (final m in props.marks)
            if (m.id == 'destination') view.topLeft + project(m.position),
          view.topLeft + project(plan.routes.first.line.first),
        ];
        for (final tip in [
          'Couper la voix',
          'Lieux sur la carte',
          'Sur le trajet',
          'Signaler un problème sur la route',
          'Recentrer',
        ]) {
          if (find.byTooltip(tip).evaluate().isEmpty) continue;
          // The badge's disc around its point, as drawn.
          final button = tester.getRect(find.byTooltip(tip)).inflate(15.5);
          for (final end in ends) {
            expect(button.contains(end), isFalse, reason: '$end under "$tip"');
          }
        }
      });
    }

    // A small phone with large text: the column of buttons rises to the
    // banner, and a notice under it used to lose its right edge under them.
    for (final (name, size, text, beside) in [
      ('a small phone, large text', const Size(360, 640), 1.3, true),
      ('a phone', phone, 1.0, false),
    ]) {
      testWidgets('on $name, the banner and a notice under it stay clear of the map buttons', (
        tester,
      ) async {
        final plan = routeFixture('limoges_drive');
        final moved = routeFixture(
          'missed_turn',
          edit: (answer) => answer['movedStops'] = [
            {'stopIndex': 1, 'lat': 45.8458, 'lon': 1.2851, 'distanceM': 120.0},
          ],
        );
        final app = await guide(tester, plan, size: size, textScale: text, answers: [moved]);
        await drive(tester, plan, toM: 100);
        await app.container(tester).read(guidanceControllerProvider.notifier).goTo(utrillo);
        await settleShort(tester);
        Rect panel(Finder inside) =>
            tester.getRect(find.ancestor(of: inside, matching: find.byType(Material)).first);
        final banner = panel(find.byType(ManeuverIcon).first);
        final notice = panel(find.textContaining("Point d'arrivée déplacé"));
        expect(notice.top, greaterThanOrEqualTo(banner.bottom), reason: 'under the banner');
        final buttons = [
          for (final tip in [
            'Couper la voix',
            'Lieux sur la carte',
            'Sur le trajet',
            'Signaler un problème sur la route',
            'Tout le trajet',
          ])
            tester.getRect(find.byTooltip(tip)),
        ];
        for (final b in buttons) {
          expect(notice.overlaps(b), isFalse, reason: 'the notice under $b');
          expect(banner.overlaps(b), isFalse, reason: 'the banner under $b');
        }
        if (beside) {
          expect(
            notice.right,
            lessThanOrEqualTo(buttons.first.left - 8),
            reason: 'beside the column, with a gap',
          );
        } else {
          expect(notice.right, size.width - 8, reason: 'room enough: the whole width');
          expect(banner.right, size.width - 8);
        }
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
      for (final label in ['For the night', 'Fill up', 'Food', 'All', 'None', 'Customise']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final look in ['Photos', 'Icons', 'Small pins']) {
        expect(find.text(look), findsOneWidget, reason: look);
      }
      await tester.tap(find.text('Customise'));
      await settleShort(tester);
      expect(find.text('All places'), findsOneWidget);
      expect(find.text('Bakeries'), findsOneWidget);
    });
  });

  group('the preview', () {
    testWidgets("online, it credits the places' sources and may draw their photos", (tester) async {
      final app = await pumpLunaway(
        tester,
        online: FakeOnlinePlaces(const []),
        overrides: navigationOverrides(
          routes: FakeRouteService([routeFixture('utrillo_motorhome')]),
          placesNearRoute: const [_aire],
        ),
      );
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      final places = map().places!;
      expect(places.placeTileJsonUrl, endsWith('/places/tiles.json'), reason: 'their credit');
      expect(places.placeFilter, RouteMapPlaces.drawsNothing, reason: 'the preview draws its own');
      expect(places.poiFilter, isNull);
      final rich = map().rich!;
      expect(rich.places, [_aire]);
      expect(rich.style.credited, isTrue);
      expect(rich.style.photos, isTrue, reason: 'the default look, photos');
      // On the engines that credit only the sources a shown layer reads (GL
      // JS, the web and the desktop page), the places' layer is shown.
      final layers = RoutePlaceLayers.jsonLayers(places);
      final pins = layers.singleWhere((l) => l['id'] == RoutePlaceLayers.placePins);
      expect((pins['layout']! as Map)['visibility'], 'visible');
      expect(pins['filter'], RouteMapPlaces.drawsNothing);
      for (final (id, _) in RoutePlaceLayers.poiLayers) {
        final poi = layers.singleWhere((l) => l['id'] == id);
        expect((poi['layout']! as Map)['visibility'], 'none', reason: id);
      }
    });

    for (final (name, size, limit) in [
      ('a phone', phone, RichMarks.compactLimit),
      ('a desktop', desktop, RichMarks.expandedLimit),
    ]) {
      testWidgets('on $name, its places near the route may be drawn large, in the look chosen', (
        tester,
      ) async {
        final store = MemoryRouteSettings(
          const NavigationSettings(guidancePlaces: GuidancePlaces(look: GuidanceLook.pictograms)),
        );
        final app = await pumpLunaway(
          tester,
          size: size,
          overrides: navigationOverrides(
            routes: FakeRouteService([routeFixture('utrillo_motorhome')]),
            placesNearRoute: const [_aire],
            settings: store,
          ),
        );
        unawaited(
          app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
        );
        await settleShort(tester);
        final rich = map().rich!;
        expect(rich.places, [_aire]);
        expect(rich.tiles, isFalse, reason: 'its places are those near the route');
        expect(rich.style.credited, isFalse, reason: "offline, no places' tiles to credit a photo");
        expect(map().places, isNull);
        expect(rich.style.look, GuidanceLook.pictograms);
        expect(rich.limit, limit);
        expect(rich.vehicleAlongM, isNull, reason: 'no vehicle on a preview');
        expect(rich.clear.top, greaterThanOrEqualTo(map().padding.top + 56), reason: 'the legend');
      });
    }
  });
}
