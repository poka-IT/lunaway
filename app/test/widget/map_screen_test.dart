import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

void main() {
  group('phone', () {
    testWidgets('the list rests at the bottom with the places of the area', (tester) async {
      await pumpLunaway(tester);
      expect(find.text('5 lieux ici'), findsOneWidget);
      expect(find.text('Démo : lieux inventés'), findsNothing, reason: 'not a demo build');
    });

    testWidgets('a crowded view lists the places nearest its centre and says so', (tester) async {
      await pumpLunaway(tester, places: demoPlaces(count: 260, now: testNow));
      expect(find.text('Les 200 lieux les plus proches'), findsOneWidget);
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
      expect(find.textContaining("Votre position n'est pas disponible"), findsOneWidget);
      // The message covers the button for a few seconds, then goes.
      await tester.pump(const Duration(seconds: 6));
      await settleShort(tester);
      app.map.userPosition = dayParking.position;
      await tester.tap(find.byTooltip('Afficher ma position'));
      await settleShort(tester);
      expect(app.map.moves.last.center, dayParking.position);
      expect(app.map.moves.last.zoom, 12);
    });

    testWidgets('a quick filter applies at once and is remembered', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Vidange'));
      await tester.tap(find.widgetWithText(FilterChip, 'Vidange'));
      await settleShort(tester);
      expect(find.text('2 lieux ici'), findsOneWidget);
      expect(app.settings.value.filter.amenities, {Amenity.dumpStation});
      expect(
        app.map.lastProps!.places.map((p) => p.id),
        unorderedEquals([lakeArea.id, serviceArea.id]),
      );
    });

    testWidgets('the night filter a new user starts with hides day-only places', (tester) async {
      final app = await pumpLunaway(tester, settings: const AppSettings());
      expect(find.text('3 lieux ici'), findsOneWidget);
      expect(app.map.lastProps!.places.map((p) => p.id), isNot(contains(dayParking.id)));
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
      expect(
        find.widgetWithText(FilterChip, 'Eau'),
        findsNothing,
        reason: 'the chips give way too',
      );
      await tester.tap(find.byTooltip('Effacer la recherche'));
      await settleShort(tester);
      expect(find.byTooltip('Afficher ma position'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Eau'), findsOneWidget);
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
      expect(app.map.lastProps!.padding.bottom, closeTo(phone.height * 0.46, 1));
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
    testWidgets('invites to download the places, then reports a failed download', (tester) async {
      final source = FakeChangesSource(const [], failing: true);
      final app = await pumpLunaway(
        tester,
        places: const [],
        neverSynced: true,
        sync: SyncService(source: source, store: _MemoryStore()),
      );
      // The first sync starts with the map and fails: the banner says so.
      expect(find.textContaining('Le téléchargement a échoué'), findsOneWidget);
      source.failing = false;
      await tester.tap(find.text('Réessayer'));
      await settleShort(tester);
      expect(find.textContaining('Le téléchargement a échoué'), findsNothing);
      expect(
        app.places.all,
        isEmpty,
        reason: 'the fake store is separate; the banner reacts to the sync state',
      );
    });
  });

  group('tablet', () {
    testWidgets('the list opens in a side panel on demand', (tester) async {
      await pumpLunaway(tester, size: tablet);
      expect(find.text('5 lieux ici').hitTestable(), findsNothing);
      await tester.tap(find.text('Afficher la liste'));
      await settleShort(tester);
      expect(find.text('5 lieux ici').hitTestable(), findsOneWidget);
      expect(find.text('Afficher la carte'), findsOneWidget);
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
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Camping des Peupliers (démo)').first,
      );
      expect(tile.selected, isTrue, reason: 'the list row stays and is marked as selected');
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
}

final class _MemoryStore implements SyncStore {
  String? cursor;

  @override
  Future<void> applyPage(String region, ChangeSet page, DateTime syncedAt) async =>
      cursor = page.cursor;

  @override
  Future<String?> cursorFor(String region) async => cursor;

  @override
  Future<void> reset(String region) async => cursor = null;

  @override
  Future<DateTime?> fullSyncStart(String region) async => null;

  @override
  Future<void> beginFullSync(String region, DateTime at) async {}

  @override
  Future<int> finishFullSync(String region, GeoBounds bounds) async => 0;
}
