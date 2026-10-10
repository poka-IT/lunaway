import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/community/presentation/place_placement.dart';
import 'package:lunaway/features/favorites/presentation/favorites_screen.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/widgets/floating.dart';

import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'desktop_web_test.dart' show onDesktopSystem;
import 'navigation_test.dart' show driveFixes, openPreview, utrillo;
import 'shell_test.dart' show messageRect;

/// Every element meant to be centred over the screen or the map, measured
/// against it to the pixel at 360, 390, 820 and 1440 px of width: centred
/// on the whole width, or on the map beside a fixed panel, and pushed aside
/// only by a column of buttons, a panel or a camera cut-out it would cover
/// (`centredSpan`).
void main() {
  late FakeLocationFeed feed;

  /// The guidance of the Limoges drive, 100 m in.
  Future<TestApp> guide(WidgetTester tester, Size size, {double textScale = 1}) async {
    final plan = routeFixture('limoges_drive');
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    final app = await pumpLunaway(
      tester,
      size: size,
      textScale: textScale,
      online: FakeOnlinePlaces(const []),
      overrides: navigationOverrides(
        routes: FakeRouteService([plan]),
        feed: feed,
        engine: LineEngine([plan]),
        voice: RecordingVoice(),
        settings: MemoryRouteSettings(),
      ),
    );
    final container = app.container(tester);
    final t = await AppLocale.fr.build();
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
    for (final f in driveFixes(plan.routes.first, toM: 100)) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleShort(tester);
    return app;
  }

  /// Shows a message from [inside] and returns where it stands.
  Future<Rect> message(WidgetTester tester, Finder inside) async {
    showMessage(ScaffoldMessenger.of(tester.element(inside.first)), 'Étape ajoutée');
    await settleShort(tester);
    return messageRect(tester);
  }

  group('"Recentrer", the guidance held upright', () {
    final recenter = find.byWidgetPredicate(
      (w) => w.key == const ValueKey('recenter') || w.key == const ValueKey('recenter-icon'),
    );

    // Taller than wide: the guidance's portrait layout at every width.
    for (final size in const [Size(360, 640), Size(390, 844), Size(820, 1180), Size(1440, 2400)]) {
      testWidgets('at ${size.width.round()} px it stands in the middle of the screen', (
        tester,
      ) async {
        await guide(tester, size);
        SchematicRouteMap.last!.onGesture!();
        await settleShort(tester);
        final button = tester.getRect(recenter);
        expect(button.center.dx, closeTo(size.width / 2, 1));
        final column = tester.getRect(find.byTooltip('Tout le trajet'));
        expect(button.right, lessThanOrEqualTo(column.left - 8), reason: 'clear of the column');
        expect(button.bottom, column.bottom, reason: 'level with its foot');
      });
    }

    testWidgets('a word too long for the middle moves aside by what it would cover, no more', (
      tester,
    ) async {
      // Larger text on a small phone: centred, the word would run under the
      // column.
      await guide(tester, const Size(360, 640), textScale: 1.3);
      SchematicRouteMap.last!.onGesture!();
      await settleShort(tester);
      final button = tester.getRect(find.byKey(const ValueKey('recenter')));
      final column = tester.getRect(find.byTooltip('Tout le trajet'));
      expect(button.center.dx, lessThan(180), reason: 'off the middle, toward the free side');
      expect(button.right, closeTo(column.left - 8, 1), reason: 'stopped beside the column');
    });
  });

  group('a message in the guidance', () {
    // The guidance shows the app's messages with its own notices, under the
    // maneuver and as wide as it: never at the foot over the driver's bar,
    // never under the buttons (`shared/notices.dart`).
    for (final size in const [
      Size(360, 640),
      Size(390, 844),
      Size(820, 1180),
      Size(1440, 2400),
      Size(1440, 900),
      Size(820, 500),
      Size(640, 360),
      Size(520, 400),
    ]) {
      testWidgets('at ${size.width.round()} x ${size.height.round()}, under the maneuver, as wide '
          'as it', (tester) async {
        await guide(tester, size);
        showMessage(
          ScaffoldMessenger.of(tester.element(find.byType(GuidanceScreen).first)),
          'Étape ajoutée',
        );
        await settleShort(tester);
        expect(find.byType(SnackBar), findsNothing);
        Rect panel(Finder inside) =>
            tester.getRect(find.ancestor(of: inside, matching: find.byType(Material)).first);
        final notice = panel(find.text('Étape ajoutée'));
        final banner = panel(find.byType(ManeuverIcon).first);
        expect(notice.top, greaterThanOrEqualTo(banner.bottom), reason: 'under the maneuver');
        expect(notice.left, closeTo(banner.left, 1), reason: 'in line with it');
        expect(notice.right, lessThanOrEqualTo(banner.right + 1));
        for (final tip in ['Voix complète', 'Tout le trajet', 'Arrêter le guidage']) {
          expect(notice.overlaps(tester.getRect(find.byTooltip(tip))), isFalse, reason: tip);
        }
      });
    }
  });

  group('a message on the route preview', () {
    for (final size in const [Size(360, 2400), Size(390, 2400)]) {
      testWidgets('at ${size.width.round()} px, across the middle of the screen', (tester) async {
        await openPreview(tester, size: size);
        final rect = await message(tester, find.byType(RoutePreviewScreen));
        expect(rect.center.dx, closeTo(size.width / 2, 1));
      });
    }

    for (final (size, panel) in const [(Size(820, 1000), 380.0), (Size(1440, 900), 440.0)]) {
      testWidgets('at ${size.width.round()} px, in the middle of the map beside the panel', (
        tester,
      ) async {
        await openPreview(tester, size: size);
        final rect = await message(tester, find.byType(RoutePreviewScreen));
        expect(rect.center.dx, closeTo((panel + size.width) / 2, 1));
        expect(rect.left, greaterThanOrEqualTo(panel + 16), reason: "off the panel's foot");
      });
    }
  });

  group('a message on the map', () {
    Rect mapRect(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('fake-map')));

    for (final size in const [Size(360, 800), Size(390, 844)]) {
      testWidgets('on a phone at ${size.width.round()} px, across the middle of the screen', (
        tester,
      ) async {
        await pumpLunaway(tester, size: size);
        final rect = await message(tester, find.text('Carte'));
        expect(rect.center.dx, closeTo(size.width / 2, 1));
      });
    }

    testWidgets('at 820 px, in the middle of the map beside the rail', (tester) async {
      await pumpLunaway(tester, size: const Size(820, 1180));
      final rect = await message(tester, find.text('Carte'));
      expect(rect.center.dx, closeTo(mapRect(tester).center.dx, 1));
      expect(rect.width, 440);
    });

    testWidgets('at 820 px with a place open, in the middle of the map the panel leaves', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: const Size(820, 1180));
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(campsite.id));
      await settleShort(tester);
      final rect = await message(tester, find.text('Carte'));
      final map = mapRect(tester);
      final free = map.right - app.map.lastProps!.padding.right;
      expect(rect.center.dx, closeTo((map.left + free) / 2, 1));
      expect(rect.right, lessThanOrEqualTo(free - 16), reason: 'clear of the panel');
    });

    testWidgets('at 640 px with a mouse, moved aside from the position button by the overlap', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        await pumpLunaway(tester, size: const Size(640, 900));
        final rect = await message(tester, find.text('Carte'));
        final locate = tester.getRect(locateButton);
        final zoom = tester.getRect(
          find.ancestor(of: find.byTooltip('Zoomer'), matching: find.byType(FloatingSurface)),
        );
        expect(rect.bottom, greaterThan(locate.top), reason: 'level with the button');
        expect(rect.overlaps(locate), isFalse);
        expect(rect.overlaps(zoom), isFalse);
        expect(rect.right, closeTo(locate.left - 8, 1), reason: 'moved by the overlap, no more');
        expect(rect.width, 440, reason: 'moved, not narrowed');
      });
    });

    testWidgets('a window grown taller: still aside from the position button, where it is now', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        await pumpLunaway(tester, size: const Size(640, 900));
        tester.view.physicalSize = const Size(640, 1000);
        await settleShort(tester);
        final rect = await message(tester, find.text('Carte'));
        final locate = tester.getRect(locateButton);
        expect(locate.bottom, closeTo(1000 - 16, 1), reason: 'the button went down with the foot');
        expect(rect.overlaps(locate), isFalse);
        expect(rect.right, closeTo(locate.left - 8, 1));
      });
    });

    testWidgets('at 1440 px, in the middle of the map beside the list', (tester) async {
      await pumpLunaway(tester, size: const Size(1440, 900));
      final rect = await message(tester, find.text('Carte'));
      final map = mapRect(tester);
      expect(rect.center.dx, closeTo(map.center.dx, 1));
      expect(rect.left, greaterThan(map.left), reason: 'clear of the list');
    });

    for (final size in const [Size(820, 1180), Size(1440, 900)]) {
      testWidgets('on the favourites at ${size.width.round()} px, in the middle of the page', (
        tester,
      ) async {
        await pumpLunaway(tester, size: size);
        await tester.tap(find.text('Favoris').first);
        await settleShort(tester);
        final rect = await message(tester, find.byType(FavoritesScreen));
        final page = tester.getRect(find.byType(FavoritesScreen));
        expect(rect.center.dx, closeTo(page.center.dx, 1));
      });
    }

    testWidgets('a cut-out on one side of a phone moves it only by what it would cover', (
      tester,
    ) async {
      await pumpLunaway(
        tester,
        size: const Size(390, 844),
        viewPadding: const FakeViewPadding(left: 40),
      );
      final rect = await message(tester, find.text('Carte'));
      expect(rect.left, closeTo(40, 1), reason: 'against the cut-out, not 16 past it');
      expect(rect.right, closeTo(390 - 16, 1));
    });

    testWidgets('a cut-out on one side of a tablet on its side leaves it in the middle', (
      tester,
    ) async {
      await pumpLunaway(
        tester,
        size: const Size(1440, 900),
        viewPadding: const FakeViewPadding(left: 48),
      );
      final rect = await message(tester, find.text('Carte'));
      expect(rect.center.dx, closeTo(mapRect(tester).center.dx, 1));
    });
  });

  group("the first download's card on a phone", () {
    Rect card(WidgetTester tester) => tester.getRect(
      find
          .ancestor(
            of: find.text('Téléchargement des lieux de France'),
            matching: find.byType(FloatingSurface),
          )
          .first,
    );

    Future<void> download(WidgetTester tester, Size size) => pumpLunaway(
      tester,
      size: size,
      places: const [],
      neverSynced: true,
      syncService: SyncService(source: _PendingSource(), store: MemorySyncStore()),
    );

    for (final size in const [Size(360, 800), Size(390, 844)]) {
      testWidgets('at ${size.width.round()} px, above the position button, in the middle', (
        tester,
      ) async {
        await download(tester, size);
        final rect = card(tester);
        final locate = tester.getRect(locateButton);
        expect(rect.bottom, lessThan(locate.top), reason: 'above the button: it does not count');
        expect(rect.center.dx, closeTo(size.width / 2, 1));
      });
    }

    for (final size in const [Size(360, 640), Size(390, 640)]) {
      testWidgets('at ${size.width.round()} px, down by the position button, beside it', (
        tester,
      ) async {
        await download(tester, size);
        final rect = card(tester);
        final locate = tester.getRect(locateButton);
        expect(rect.bottom, greaterThan(locate.top), reason: 'level with the button');
        expect(rect.overlaps(locate), isFalse);
        expect(rect.left, closeTo(16, 1), reason: 'moved aside from the middle, no further');
        expect(rect.right, closeTo(locate.left - 8, 1));
      });
    }
  });

  group("the first download's card in a low wide window, with a mouse", () {
    Rect card(WidgetTester tester) => tester.getRect(
      find
          .ancestor(
            of: find.text('Téléchargement des lieux de France'),
            matching: find.byType(FloatingSurface),
          )
          .first,
    );

    for (final size in const [Size(1024, 480), Size(700, 420), Size(1024, 900)]) {
      testWidgets('at ${size.width.round()} by ${size.height.round()}, clear of the buttons', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpLunaway(
            tester,
            size: size,
            places: const [],
            neverSynced: true,
            syncService: SyncService(source: _PendingSource(), store: MemorySyncStore()),
          );
          final rect = card(tester);
          final zoom = tester.getRect(
            find
                .ancestor(of: find.byTooltip('Zoomer'), matching: find.byType(FloatingSurface))
                .first,
          );
          expect(rect.overlaps(zoom), isFalse, reason: 'the zoom buttons');
          expect(rect.overlaps(tester.getRect(locateButton)), isFalse, reason: 'the position');
          final chips = tester.getRect(find.byType(QuickFilters));
          expect(
            rect.overlaps(chips),
            isFalse,
            reason: 'the chips over the map, or beside it in the list pane',
          );
          if (size.height >= 900) {
            // Room enough: in the middle of the map, as before.
            final map = tester.getRect(find.byType(MessageStage).last);
            expect(rect.center.dx, closeTo(map.center.dx, 1));
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  group('the page beside the rail, a phone on its side', () {
    double margin(WidgetTester tester) {
      final title = tester.getRect(
        find.descendant(of: find.byType(ProfileScreen), matching: find.text('Profil')).first,
      );
      final rail = tester.getRect(
        find.ancestor(of: find.text('Carte').first, matching: find.byType(Container)).last,
      );
      return title.left - rail.right;
    }

    testWidgets('keeps the left cut-out once, in the rail', (tester) async {
      Future<double> profileMargin(FakeViewPadding? cutOut) async {
        await pumpLunaway(tester, size: const Size(844, 390), viewPadding: cutOut);
        await tester.tap(find.text('Profil').last);
        await settleShort(tester);
        return margin(tester);
      }

      final plain = await profileMargin(null);
      final cut = await profileMargin(const FakeViewPadding(left: 47));
      expect(cut, closeTo(plain, 0.5), reason: 'the rail grows by the cut-out, the page does not');
    });
  });

  group('the placement of a new place', () {
    Rect card(WidgetTester tester) => tester.getRect(
      find.ancestor(of: find.text('Placez le lieu'), matching: find.byType(FloatingSurface)).first,
    );
    Rect confirm(WidgetTester tester) => tester.getRect(
      find.ancestor(of: find.text('Valider cet emplacement'), matching: find.byType(FilledButton)),
    );

    Future<void> place(WidgetTester tester, Size size, {FakeViewPadding? cutOut}) async {
      await pumpLunaway(tester, size: size, viewPadding: cutOut);
      unawaited(pickPlacement(tester.element(find.text('Carte').first), const LatLng(45.9, 6.12)));
      await settleShort(tester);
    }

    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets('at ${size.width.round()} px, card and button over the crosshair', (
        tester,
      ) async {
        await place(tester, size);
        expect(card(tester).center.dx, closeTo(size.width / 2, 1));
        expect(confirm(tester).center.dx, closeTo(size.width / 2, 1));
        // The map's credit, which no engine shows, over the button.
        final credit = tester.getRect(find.byType(MapCredit));
        expect(credit.overlaps(confirm(tester)), isFalse);
        expect(credit.bottom, lessThanOrEqualTo(confirm(tester).top));
        expect(credit.left, greaterThanOrEqualTo(0));
      });
    }

    for (final size in const [Size(820, 390), Size(1440, 900)]) {
      testWidgets(
        'at ${size.width.round()} px with a cut-out on one side, still over the crosshair',
        (tester) async {
          await place(tester, size, cutOut: const FakeViewPadding(left: 48));
          expect(card(tester).center.dx, closeTo(size.width / 2, 1));
          expect(confirm(tester).center.dx, closeTo(size.width / 2, 1));
          expect(card(tester).left, greaterThanOrEqualTo(48), reason: 'clear of the cut-out');
          final credit = tester.getRect(find.byType(MapCredit));
          expect(credit.left, greaterThanOrEqualTo(48), reason: 'the credit clear of it too');
          expect(credit.overlaps(confirm(tester)), isFalse);
        },
      );
    }
  });

  group('the dock', () {
    for (final width in const [360.0, 390.0]) {
      testWidgets('at ${width.round()} px with a cut-out on one side, in the middle', (
        tester,
      ) async {
        await pumpLunaway(
          tester,
          size: Size(width, 800),
          viewPadding: const FakeViewPadding(left: 24),
        );
        final dock = tester.getRect(find.byKey(const ValueKey('dock')));
        expect(dock.center.dx, closeTo(width / 2, 1));
        expect(dock.left, greaterThanOrEqualTo(24), reason: 'clear of the cut-out');
      });
    }
  });
}

/// A server that never answers: the first download stays running.
final class _PendingSource implements ChangesSource {
  final _never = Completer<ChangeSet>();

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) =>
      _never.future;
}
