import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/data/last_view.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

import '../helpers/fakes.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// Sends the system back, as Android's gesture or key does.
Future<void> systemBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await settleShort(tester);
}

/// The times the app asked the system to close it.
List<String> recordAppExits(WidgetTester tester, {List<bool>? handlesBack}) {
  final exits = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
    call,
  ) async {
    if (call.method == 'SystemNavigator.pop') exits.add(call.method);
    if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
      handlesBack?.add(call.arguments as bool);
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return exits;
}

void main() {
  group('basemap', () {
    // Read outside the tests' fake clock, which an asset read would wait on.
    late BasemapTemplates templates;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      templates = await BasemapTemplates.load();
    });
    Map<String, Object?> style(TestApp app) =>
        jsonDecode(app.map.lastProps!.style) as Map<String, Object?>;
    const config = AppConfig(
      apiBaseUrl: testApiBase,
      demo: false,
      basemapUrl: 'https://tiles.example.org/',
    );

    testWidgets('the map gets Aube from the configured tile host, labelled in the app language', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, basemap: templates, config: config);
      final aube = style(app);
      expect(aube['name'], 'Lunaway Aube');
      expect(
        (aube['sources']! as Map<String, Object?>)['protomaps'],
        containsPair('url', 'https://tiles.example.org/planet.json'),
      );
      expect(aube['glyphs'], startsWith('https://tiles.example.org/fonts/'));
      expect(app.map.lastProps!.style, contains('name:fr'));
      expect(app.map.lastProps!.dark, isFalse);
    });

    testWidgets('a dark theme switches to Minuit, a new language relabels the map', (tester) async {
      final app = await pumpLunaway(tester, basemap: templates, config: config);
      final settings = app.container(tester).read(settingsProvider.notifier);
      await settings.setTheme(ThemePreference.dark);
      await settleShort(tester);
      expect(style(app)['name'], 'Lunaway Minuit');
      expect(app.map.lastProps!.dark, isTrue);

      await settings.setLocale(AppLocale.en);
      await settleShort(tester);
      expect(style(app)['name'], 'Lunaway Minuit');
      expect(app.map.lastProps!.style, isNot(contains('name:fr')));
      expect(app.map.lastProps!.style, contains('name:en'));
    });
  });

  group('phone', () {
    testWidgets('the list rests at the bottom with the places of the area', (tester) async {
      await pumpLunaway(tester);
      expect(find.text('5 lieux ici'), findsOneWidget);
      expect(find.text('Démo : lieux inventés'), findsNothing, reason: 'not a demo build');
    });

    testWidgets('a crowded view lists the places nearest its centre and says so', (tester) async {
      await pumpLunaway(tester, places: demoPlaces(count: 260, now: testNow));
      expect(find.text('200 lieux les plus proches du centre'), findsOneWidget);
    });

    testWidgets('located in view, the crowded list is the one nearest the user', (tester) async {
      final app = await pumpLunaway(tester, places: demoPlaces(count: 260, now: testNow));
      app.container(tester).read(userLocationProvider.notifier).update(const LatLng(46.6, 2.5));
      await settleShort(tester);
      expect(find.text('200 lieux les plus proches de vous'), findsOneWidget);
    });

    testWidgets('tapping a pin opens its details in a sheet, and closing returns to the list', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.byKey(ValueKey('pin-${lakeArea.id}')));
      await settleShort(tester);
      expect(find.text('Aire du Lac Bleu (démo)'), findsWidgets);
      expect(find.text('Nuit autorisée'), findsWidgets);
      expect(app.map.lastProps!.selectedId, lakeArea.id);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(find.text('5 lieux ici'), findsOneWidget);
      expect(app.map.lastProps!.selectedId, isNull);
    });

    testWidgets('the system back closes the open place first, and leaves the app only then', (
      tester,
    ) async {
      final exits = recordAppExits(tester);
      final app = await pumpLunaway(tester);
      await tester.tap(find.byKey(ValueKey('pin-${lakeArea.id}')));
      await settleShort(tester);
      expect(app.map.lastProps!.selectedId, lakeArea.id);
      await systemBack(tester);
      expect(app.map.lastProps!.selectedId, isNull);
      expect(find.text('5 lieux ici'), findsOneWidget);
      expect(exits, isEmpty, reason: 'the first back closes the place, the app stays');
      await systemBack(tester);
      expect(exits, hasLength(1));
    });

    testWidgets('with the position already allowed, the map opens on the user', (tester) async {
      final map = FakeMap()..userPosition = dayParking.position;
      final app = await pumpLunaway(tester, map: map);
      expect(map.moves, [(center: dayParking.position, zoom: 11.0)]);
      expect(app.container(tester).read(userLocationProvider), dayParking.position);
      expect(app.location.requests, 0);
    });

    testWidgets('a map moved by hand before the position comes keeps its camera', (tester) async {
      final map = _SlowFix()..userPosition = dayParking.position;
      final app = await pumpLunaway(tester, map: map);
      map.viewport = const MapViewport(
        bounds: GeoBounds(south: 44, west: 4, north: 46, east: 7),
        center: LatLng(45, 5.5),
        zoom: 9,
      );
      app.map.lastProps!.onViewportChanged(map.viewport);
      map.fix.complete(dayParking.position);
      await settleShort(tester);
      expect(map.moves, isEmpty);
    });

    testWidgets('the position is never asked for at launch', (tester) async {
      final map = FakeMap()..userPosition = dayParking.position;
      final app = await pumpLunaway(tester, map: map, locationAccess: LocationAccess.notGranted);
      expect(app.location.requests, 0);
      expect(map.moves, isEmpty);
      expect(find.text('Afficher votre position ?'), findsNothing);
    });

    testWidgets('the map opens where the previous run left it, without fitting France', (
      tester,
    ) async {
      const left = LatLng(45.9, 6.13);
      final app = await pumpLunaway(
        tester,
        locationAccess: LocationAccess.notGranted,
        overrides: [initialViewProvider.overrideWithValue((center: left, zoom: 10.5))],
      );
      expect(app.map.firstProps!.initialCenter, left);
      expect(app.map.firstProps!.initialZoom, 10.5);
      expect(app.map.firstProps!.fitInitial, isFalse);
    });

    testWidgets('the view the map rests on is kept for the next launch, coarsely', (tester) async {
      final map = FakeMap()
        ..viewport = const MapViewport(
          bounds: GeoBounds(south: 45.8, west: 6, north: 46, east: 6.3),
          center: LatLng(45.90061, 6.12913),
          zoom: 11.3,
        );
      final app = await pumpLunaway(tester, map: map, locationAccess: LocationAccess.notGranted);
      final kept = await tester.runAsync(() => DriftLastViewStore(app.cache).load());
      expect(kept?.center, const LatLng(45.9, 6.1), reason: 'a tenth of a degree, as the position');
      expect(kept?.zoom, 10, reason: 'no closer than the area a coarse centre stands for');
    });

    testWidgets("a map at rest checks that the basemap's host still answers", (tester) async {
      final app = await pumpLunaway(tester);
      final host =
          app.container(tester).read(basemapReachabilityProvider.notifier) as FixedReachability;
      expect(host.restChecks, isNotEmpty);
    });

    testWidgets('adding a place from afar brings the map down to the street first', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.byTooltip('Ajouter un lieu'));
      await settleShort(tester);
      expect(find.text('Point choisi'), findsOneWidget);
      expect(app.map.moves.last, (center: app.map.viewport.center, zoom: 15.0));
    });

    testWidgets('with a place open, Android is told the app handles back', (tester) async {
      final handlesBack = <bool>[];
      recordAppExits(tester, handlesBack: handlesBack);
      // The app tells the engine only once it runs in the foreground.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpLunaway(tester);
      await tester.tap(find.byKey(ValueKey('pin-${lakeArea.id}')));
      await settleShort(tester);
      expect(handlesBack.last, isTrue);
      await systemBack(tester);
      expect(handlesBack.last, isFalse, reason: 'on the bare map, back may leave the app');
    });

    testWidgets('the system back clears a search before anything else', (tester) async {
      final exits = recordAppExits(tester);
      await pumpLunaway(tester);
      await tester.enterText(find.byType(TextField), 'ann');
      await settleShort(tester);
      expect(find.text('Communes'), findsOneWidget);
      await systemBack(tester);
      expect(find.text('Communes'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(exits, isEmpty);
    });

    testWidgets('a screen reader opens the map credit and the filters with a filter on', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpLunaway(
        tester,
        settings: const AppSettings(
          theme: ThemePreference.light,
          filter: PlaceFilter(amenities: {Amenity.water}),
        ),
      );
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Crédits de la carte')));
      await settleShort(tester);
      expect(app.external.opened, contains(osmCopyright));
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Filtres, ')));
      await settleShort(tester);
      expect(find.text('Tout effacer'), findsOneWidget, reason: 'the filters sheet is open');
      semantics.dispose();
    });

    testWidgets('a long press on the map gives the coordinates of the point, marked on the map', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.longPress(find.byKey(const ValueKey('fake-map')));
      await settleShort(tester);
      expect(find.text('Point choisi'), findsOneWidget);
      expect(find.text('45.762900, 4.831697'), findsOneWidget);
      expect(app.map.lastProps!.markedPoint, dayParking.position);
      expect(app.map.moves.last.center, dayParking.position, reason: 'the point stays in view');
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(app.map.lastProps!.markedPoint, isNull);
    });

    testWidgets('the position button moves the map to the user, or says why not', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      expect(find.textContaining('Position introuvable pour'), findsOneWidget);
      // The message covers the button for a few seconds, then goes.
      await tester.pump(const Duration(seconds: 6));
      await settleShort(tester);
      app.map.userPosition = dayParking.position;
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      expect(app.map.moves.last.center, dayParking.position);
      expect(app.map.moves.last.zoom, 12);
    });

    testWidgets('moving the map keeps the list in place while the next one loads', (tester) async {
      final app = await pumpLunaway(tester);
      expect(find.text('Aire du Lac Bleu (démo)'), findsWidgets);
      app.map.lastProps!.onViewportChanged(
        const MapViewport(
          bounds: GeoBounds(south: 40, west: -6, north: 52, east: 11),
          center: LatLng(46, 2.4),
          zoom: 5.8,
        ),
      );
      // The frame right after the move: the new query has not answered yet.
      await tester.pump();
      expect(find.byType(SkeletonTile), findsNothing, reason: 'no flash of placeholders');
      expect(find.text('Aire du Lac Bleu (démo)'), findsWidgets);
      await settleShort(tester);
      expect(find.text('5 lieux ici'), findsOneWidget);
    });

    testWidgets('the position is asked for after an explanation, never straight away', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      app.location
        ..current = LocationAccess.notGranted
        ..afterRequest = LocationAccess.granted;
      app.map.userPosition = dayParking.position;
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      expect(find.text('Afficher votre position ?'), findsOneWidget);
      expect(app.location.requests, 0, reason: 'the system prompt waits for the explanation');
      await tester.tap(find.text('Continuer'));
      await settleShort(tester);
      expect(app.location.requests, 1);
      expect(app.map.moves.last.center, dayParking.position);
    });

    testWidgets('"not now" leaves the system prompt unasked', (tester) async {
      final app = await pumpLunaway(tester);
      app.location.current = LocationAccess.notGranted;
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      await tester.tap(find.text('Pas maintenant'));
      await settleShort(tester);
      expect(app.location.requests, 0);
      expect(app.map.moves, isEmpty);
    });

    testWidgets('after a refusal for good, the way leads to the settings', (tester) async {
      final app = await pumpLunaway(tester);
      app.location.current = LocationAccess.deniedForever;
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      expect(find.text('Position désactivée pour Lunaway'), findsOneWidget);
      await tester.tap(find.text('Ouvrir les réglages'));
      await settleShort(tester);
      expect(app.location.settingsOpened, 1);
      expect(app.location.requests, 0);
    });

    testWidgets('with location off on the device, the user is told to switch it on', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      app.location.current = LocationAccess.serviceOff;
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      expect(find.text('Localisation désactivée'), findsOneWidget);
      expect(app.location.requests, 0);
    });

    testWidgets('the map credits OpenStreetMap and opens its copyright page', (tester) async {
      final app = await pumpLunaway(tester);
      expect(find.text('© OpenStreetMap · Protomaps'), findsOneWidget);
      await tester.tap(find.text('© OpenStreetMap · Protomaps'));
      await settleShort(tester);
      expect(app.external.opened.single.toString(), 'https://www.openstreetmap.org/copyright');
      expect(
        tester.getSize(find.byType(MapCredit)).height,
        greaterThanOrEqualTo(48),
        reason: 'a finger-sized target',
      );
    });

    testWidgets('a quick filter applies at once and is remembered', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.ensureVisible(find.text('Gratuit'));
      await tester.tap(find.text('Gratuit'));
      await settleShort(tester);
      expect(find.text('1 lieu ici'), findsOneWidget);
      expect(app.settings.value.filter.freeOnly, isTrue);
      expect(app.map.lastProps!.places.map((p) => p.id), [dayParking.id]);
    });

    testWidgets('the place filters and the shops and services share one row under the search', (
      tester,
    ) async {
      await pumpLunaway(tester);
      final filters = tester.getCenter(find.text('Filtres'));
      final groceries = tester.getCenter(find.text('Courses'));
      expect(groceries.dy, filters.dy, reason: 'one row, the map keeps the room');
      expect(find.text('Eau'), findsNothing, reason: 'no second "water" beside "Eau et vidange"');
    });

    testWidgets('a new user sees every place, service points and day-only car parks included', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, settings: const AppSettings());
      expect(find.text('5 lieux ici'), findsOneWidget);
      expect(
        app.map.lastProps!.places.map((p) => p.id),
        containsAll([dayParking.id, serviceArea.id]),
      );
    });

    testWidgets('search finds places and towns, and a result selects the place', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.enterText(find.byType(TextField), 'ann');
      await settleShort(tester);
      expect(find.text('Communes'), findsOneWidget);
      expect(find.text('Annecy'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'lac');
      await settleShort(tester);
      await tester.tap(find.text('Aire du Lac Bleu (démo)').last);
      await settleShort(tester);
      expect(app.map.lastProps!.selectedId, lakeArea.id);
      expect(app.map.moves.last.center, lakeArea.position);
    });

    testWidgets('search results sit above the map controls, and the locate button gives way', (
      tester,
    ) async {
      await pumpLunaway(tester);
      await tester.enterText(find.byType(TextField), 'ann');
      await settleShort(tester);
      expect(find.text('Annecy').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Afficher ma position'), findsNothing);
      expect(find.text('Gratuit'), findsNothing, reason: 'the chips give way too');
      await tester.tap(find.byTooltip('Effacer la recherche'));
      await settleShort(tester);
      expect(find.byTooltip('Afficher ma position'), findsOneWidget);
      expect(find.text('Gratuit'), findsOneWidget);
    });

    testWidgets('a new selection opens its sheet at the usual height, whatever the last one was', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.byKey(ValueKey('pin-${lakeArea.id}')));
      await settleShort(tester);
      await tester.drag(find.byType(PlaceDetailsBody), const Offset(0, -700));
      await settleShort(tester);
      expect(find.byType(TextField).hitTestable(), findsNothing);
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(campsite.id));
      await settleShort(tester);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(app.map.lastProps!.padding.bottom, closeTo(phone.height * 0.6, 1));
    });

    testWidgets('the search fades away under a sheet dragged to the top', (tester) async {
      await pumpLunaway(tester);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      await tester.drag(find.text('5 lieux ici'), const Offset(0, -900));
      await settleShort(tester);
      expect(find.byType(TextField).hitTestable(), findsNothing);
    });

    testWidgets('a search without match says so', (tester) async {
      await pumpLunaway(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await settleShort(tester);
      expect(find.text('Aucun lieu ni aucune commune ne correspond à « zzz ».'), findsOneWidget);
    });
  });

  group('links', () {
    testWidgets('a link to a place opens it and moves the map there', (tester) async {
      final app = await pumpLunaway(tester);
      app.container(tester).read(routerProvider).go('/map?place=${campsite.id}');
      await settleShort(tester, const Duration(seconds: 2));
      expect(app.container(tester).read(selectionProvider), PlaceSelection(campsite.id));
      expect(app.map.moves.last.center, campsite.position);
      expect(find.text('Camping des Peupliers (démo)'), findsWidgets);
    });
  });

  group('empty device', () {
    testWidgets('an empty list still says so when the count of stored places fails', (
      tester,
    ) async {
      await pumpLunaway(
        tester,
        places: const [],
        overrides: [
          placeCountProvider.overrideWith((ref) => Stream<int>.error(StateError('disk'))),
        ],
      );
      expect(find.text('Aucun lieu par ici avec ces filtres'), findsOneWidget);
    });

    testWidgets('during the first download the list says the places are coming', (tester) async {
      await pumpLunaway(
        tester,
        places: const [],
        neverSynced: true,
        syncService: SyncService(source: _PendingSource(), store: MemorySyncStore()),
      );
      expect(find.text('Les lieux arrivent'), findsOneWidget);
      expect(find.text('Aucun lieu par ici avec ces filtres'), findsNothing);
      expect(find.text('0 lieu ici'), findsNothing);
      // The download's own card stays clear of the map's buttons.
      final card = tester.getRect(find.text('Téléchargement des lieux de France'));
      final locate = tester.getRect(find.byTooltip('Afficher ma position'));
      expect(card.right, lessThanOrEqualTo(locate.left));
    });

    testWidgets('reports a failed first download, and a retry asks the server again', (
      tester,
    ) async {
      final source = FakeChangesSource(const [], failing: true);
      await pumpLunaway(
        tester,
        places: const [],
        neverSynced: true,
        syncService: SyncService(source: source, store: MemorySyncStore()),
      );
      // The first sync starts with the map and fails: the banner says why.
      expect(find.text("Le téléchargement s'est interrompu"), findsOneWidget);
      expect(find.text("Pas de connexion pour l'instant."), findsOneWidget);
      expect(source.requests, 1);
      source.failing = false;
      await tester.tap(find.text('Réessayer'));
      await settleShort(tester);
      expect(source.requests, 2);
      expect(find.text("Le téléchargement s'est interrompu"), findsNothing);
    });
  });

  group('tablet', () {
    testWidgets('the list opens in a side panel on demand', (tester) async {
      await pumpLunaway(tester, size: tablet);
      expect(find.text('5 lieux ici').hitTestable(), findsNothing);
      await tester.tap(find.text('Liste (5)'));
      await settleShort(tester);
      expect(find.text('5 lieux ici').hitTestable(), findsOneWidget);
      expect(find.text('Liste (5)'), findsNothing);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(find.text('Liste (5)'), findsOneWidget);
    });

    testWidgets('typing a search at 600 dp lays out without overflow', (tester) async {
      await pumpLunaway(tester, size: const Size(600, 900));
      await tester.enterText(find.byType(TextField), 'ann');
      await settleShort(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Annecy'), findsOneWidget);
    });

    testWidgets('a pin shows its details in the side panel', (tester) async {
      await pumpLunaway(tester, size: tablet);
      await tester.tap(find.byKey(ValueKey('pin-${campsite.id}')));
      await settleShort(tester);
      expect(find.text('Camping des Peupliers (démo)').hitTestable(), findsOneWidget);
      expect(find.text('Itinéraire').hitTestable(), findsOneWidget);
    });
  });

  group('desktop', () {
    testWidgets('the list sits beside the map; a row opens the place in its place', (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      expect(find.text('5 lieux ici'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-map')), findsOneWidget);
      await tester.tap(find.text('Camping des Peupliers (démo)'));
      await settleShort(tester);
      expect(app.map.lastProps!.selectedId, campsite.id);
      expect(app.map.moves.last.center, campsite.position);
      expect(find.text('Itinéraire'), findsOneWidget);
      expect(
        find.text('5 lieux ici'),
        findsNothing,
        reason: 'below 1500 px the details take the list place',
      );
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(find.text('5 lieux ici'), findsOneWidget);
    });

    testWidgets('on a wide screen list, map and details sit side by side, in step', (tester) async {
      final app = await pumpLunaway(tester, size: const Size(1600, 900));
      await tester.tap(find.text('Camping des Peupliers (démo)'));
      await settleShort(tester);
      expect(app.map.lastProps!.selectedId, campsite.id);
      expect(find.text('Itinéraire'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      final row = find.ancestor(
        of: find.text('Camping des Peupliers (démo)').first,
        matching: find.byType(PlaceTile),
      );
      expect(
        tester.getSemantics(row),
        isSemantics(isSelected: true),
        reason: 'the list row stays and is marked as selected',
      );
      semantics.dispose();
    });

    testWidgets('Escape closes the details', (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(find.text('Itinéraire'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      expect(find.text('Itinéraire'), findsNothing);
    });
  });

  group('a place selected on a phone', () {
    FakeMap mapOver(double north, double south) => FakeMap()
      ..viewport = MapViewport(
        bounds: GeoBounds(south: south, west: 6, north: north, east: 6.3),
        center: LatLng((north + south) / 2, 6.15),
        zoom: 11,
      );

    Future<FakeMap> select(WidgetTester tester, FakeMap map, {bool reachable = true}) async {
      await pumpLunaway(tester, map: map, reachable: reachable);
      map.moves.clear();
      // A tap on its pin, which leaves the camera where it is.
      map.lastProps!.onPlaceTap(lakeArea.id);
      await settleShort(tester);
      return map;
    }

    testWidgets('under the sheet that opens comes up into the map left free', (tester) async {
      final map = await select(tester, mapOver(46, 45.8));
      expect(map.moves.map((m) => m.center), [lakeArea.position]);
    });

    testWidgets('already clear of the sheet and the search stays where it is', (tester) async {
      final map = await select(tester, mapOver(45.95, 45.65));
      expect(map.moves, isEmpty);
    });

    testWidgets('from the list moves the map once, with the zoom the list asks for', (
      tester,
    ) async {
      final map = FakeMap()
        ..viewport = const MapViewport(
          bounds: GeoBounds(south: 45.5, west: 5.7, north: 46.3, east: 6.6),
          center: LatLng(45.9, 6.15),
          zoom: 9,
        );
      await pumpLunaway(tester, map: map);
      map.moves.clear();
      await tester.tap(find.text(lakeArea.name!).first);
      await settleShort(tester);
      expect(map.moves, [(center: lakeArea.position, zoom: 12.0)]);
    });

    testWidgets('under the offline notice comes down below it', (tester) async {
      final map = await select(tester, mapOver(45.95, 45.65), reachable: false);
      expect(find.textContaining('Hors ligne'), findsOneWidget);
      expect(map.moves.map((m) => m.center), [lakeArea.position]);
    });
  });
}

/// A server that never answers: the first download stays running.
final class _PendingSource implements ChangesSource {
  final _never = Completer<ChangeSet>();

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) =>
      _never.future;
}

/// A map whose position comes only when the test says so.
final class _SlowFix extends FakeMap {
  final fix = Completer<LatLng?>();

  @override
  Future<LatLng?> locateUser() => fix.future;
}
