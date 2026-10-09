import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';
import 'package:lunaway/shared/widgets/segmented.dart';
import 'package:lunaway/shared/widgets/spring_sheet.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/sub_page.dart';

import '../helpers/cursors.dart';
import '../helpers/fake_api.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// A desktop window tall enough that the long panes are built whole.
const tallDesktop = Size(1280, 2400);

/// A phone tall enough that the profile and the sheets are built whole.
const tallPhone = Size(400, 3200);

/// Runs [body] as in a browser on a computer: a mouse, and the denser look
/// the app draws for it in a wide window.
Future<void> onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> go(WidgetTester tester, TestApp app, String route) async {
  app.container(tester).read(routerProvider).go(route);
  await settleShort(tester);
}

void main() {
  // Each test opens a screen and hovers every control on it with a mouse:
  // the pointing hand over what reacts to a click, the text cursor over a
  // field, the arrow over a disabled button, a resize or grab cursor over a
  // drag handle.
  group('under the mouse, the map screen', () {
    for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
      testWidgets('on a $name shows the right cursor everywhere', (tester) async {
        await onDesktop(() async {
          await pumpLunaway(tester, size: size);
          await expectCursors(tester, atLeast: 10);
        });
      });
    }

    testWidgets('the filters as a sheet on a phone', (tester) async {
      await onDesktop(() async {
        await pumpLunaway(tester, size: tallPhone);
        await tester.tap(find.text('Filtres'));
        await settleShort(tester);
        await expectCursors(tester, atLeast: 15);
      });
    });

    testWidgets('the filters as a dialog on a desktop', (tester) async {
      await onDesktop(() async {
        await pumpLunaway(tester, size: tallDesktop);
        await tester.tap(find.text('Filtres'));
        await settleShort(tester);
        await expectCursors(tester, atLeast: 15);
      });
    });
  });

  group('under the mouse, a place', () {
    testWidgets('its details beside the map', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallDesktop);
        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester);
        await expectCursors(tester, atLeast: 20);
      });
    });

    testWidgets('its details in the sheet of a phone', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallPhone);
        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester);
        await expectCursors(tester, atLeast: 15);
      });
    });

    testWidgets('the "still there?" sheet of a contribution', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallDesktop, api: FakeApi());
        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester);
        await tester.tap(find.text(t.contribute.stillThere).first);
        await settleShort(tester);
        expect(find.text(t.confirmSheet.body), findsOneWidget);
        await expectCursors(tester, atLeast: 3);
      });
    });
    testWidgets('the menu of a place', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallDesktop, api: FakeApi(), signedIn: true);
        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester);
        await tester.tap(find.byTooltip(t.contribute.more).first);
        await settleShort(tester);
        expect(find.text(t.contribute.reportIssue), findsWidgets);
        await expectCursors(tester, atLeast: 3);
      });
    });

    testWidgets('the review sheet, with its vehicle dropdown', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(
          tester,
          size: tallDesktop,
          api: FakeApi(level: 1),
          signedIn: true,
        );
        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester);
        final write = find.descendant(
          of: find.byType(PlaceDetailsBody),
          matching: find.text(t.contribute.writeReview),
        );
        await tester.ensureVisible(write);
        await tester.pump();
        await tester.tap(write);
        await settleShort(tester);
        expect(find.text(t.reviewSheet.licence), findsOneWidget);
        await expectCursors(tester, atLeast: 8);
      });
    });
  });

  group('under the mouse, the tabs', () {
    testWidgets('the favourites, with a list and a place in it', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallDesktop);
        final trip = await app.favorites.createList('Bretagne');
        await app.favorites.add(trip, campsite.summary);
        await app.favorites.addToDefault(lakeArea.summary);
        await go(tester, app, AppRoutes.favorites);
        await expectCursors(tester, atLeast: 5);
      });
    });

    testWidgets('the menu of a favourites list', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallDesktop);
        // Only a list of the user's own can be renamed: the menu is its.
        final trip = await app.favorites.createList('Bretagne');
        await app.favorites.add(trip, campsite.summary);
        await go(tester, app, AppRoutes.favorites);
        await tester.tap(find.text('Bretagne').first);
        await settleShort(tester);
        await tester.tap(find.byTooltip(t.favorites.listActions).first);
        await settleShort(tester);
        expect(find.text(t.favorites.renameList), findsOneWidget);
        await expectCursors(tester, atLeast: 2);
      });
    });

    testWidgets('the profile on a phone', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallPhone);
        await go(tester, app, AppRoutes.profile);
        await expectCursors(tester, atLeast: 15);
      });
    });

    testWidgets('the vehicle editor', (tester) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallPhone);
        await go(tester, app, AppRoutes.profile);
        await tester.tap(find.text(t.vehicle.add));
        await settleShort(tester);
        expect(find.byType(VehicleEditor), findsOneWidget);
        await expectCursors(tester, atLeast: 8);
      });
    });

    testWidgets("a sheet's handle shows the pointing hand, and a click on it closes the sheet", (
      tester,
    ) async {
      await onDesktop(() async {
        final app = await pumpLunaway(tester, size: tallPhone);
        await go(tester, app, AppRoutes.profile);
        await tester.tap(find.text(t.vehicle.add));
        await settleShort(tester);
        final handle = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.bySemanticsLabel(
            MaterialLocalizations.of(tester.element(find.byType(VehicleEditor)))
                .modalBarrierDismissLabel,
          ),
        );
        expect(handle, findsOneWidget);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(handle));
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );
        await mouse.down(tester.getCenter(handle));
        await mouse.up();
        await mouse.removePointer();
        await settleShort(tester);
        expect(find.byType(VehicleEditor), findsNothing);
      });
    });
  });

  group('under the mouse, the account', () {
    for (final route in [
      AppRoutes.profile,
      AppRoutes.recoveryCard,
      AppRoutes.recover,
      AppRoutes.contributions,
      AppRoutes.muted,
      AppRoutes.devices,
      AppRoutes.deleteAccount,
      AppRoutes.offlineMaps,
    ]) {
      testWidgets('signed in, $route', (tester) async {
        await onDesktop(() async {
          final app = await pumpLunaway(tester, size: tallDesktop, api: FakeApi(), signedIn: true);
          await go(tester, app, route);
          await expectCursors(tester, atLeast: 3);
        });
      });
    }
  });

  group('under the mouse, the navigation', () {
    testWidgets('the route preview on a desktop, with two stops to reorder', (tester) async {
      await onDesktop(() async {
        const target = RouteTarget(
          destination: LatLng(45.84510, 1.28637),
          label: 'Aire de la rue Utrillo',
          placeId: 'utrillo',
        );
        final plan = routeFixture('utrillo_motorhome');
        final app = await pumpLunaway(
          tester,
          size: tallDesktop,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            engine: LineEngine([plan]),
          ),
        );
        final container = app.container(tester);
        unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(target)));
        await settleShort(tester);
        container.read(routeStopsControllerProvider(target).notifier).set(const [
          RouteStop(position: LatLng(45.846, 1.283), label: 'Étape A'),
          RouteStop(position: LatLng(45.845, 1.285), label: 'Étape B'),
        ]);
        await settleShort(tester);
        final sweep = await expectCursors(tester, atLeast: 8);
        expect(sweep.byKind['drag handle'], 2, reason: 'the handles of the two stops');
      });
    });

    Future<void> guide(WidgetTester tester, Size size) async {
      final plan = routeFixture('limoges_drive');
      final app = await pumpLunaway(
        tester,
        size: size,
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: FakeLocationFeed(position: plan.routes.first.line.first),
          engine: LineEngine([plan]),
        ),
      );
      final container = app.container(tester);
      final t = await AppLocale.fr.build();
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: plan.routes.first.index,
            target: const RouteTarget(destination: LatLng(45.84510, 1.28637), label: 'Arrivée'),
            words: TranslatedWording(t, DistanceUnits.metric),
          );
      unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
      await settleShort(tester);
    }

    testWidgets('"On the way", its chips and a list along the route', (tester) async {
      await onDesktop(() async {
        const target = RouteTarget(destination: LatLng(45.84510, 1.28637), label: 'Arrivée');
        final plan = routeFixture('utrillo_motorhome');
        final app = await pumpLunaway(
          tester,
          size: tallDesktop,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            onTheWay: FakeOnTheWay(
              pages: {
                'toilets': [
                  const OnTheWayPage(
                    items: [
                      PoiOnTheWay(
                        id: 'poi-1',
                        position: LatLng(45.846, 1.283),
                        alongM: 6000,
                        offM: 40,
                        detourM: 0,
                        detourS: 0,
                        kind: PoiKind.toilets,
                        name: 'Halle',
                      ),
                    ],
                  ),
                ],
              },
            ),
          ),
        );
        unawaited(
          app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(target)),
        );
        await settleShort(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Sur le trajet'));
        await settleShort(tester);
        final chip = find.widgetWithText(ChoiceChip, 'Toilettes, douches');
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await settleShort(tester);
        expect(find.text('Halle'), findsOneWidget);
        await expectCursors(tester, atLeast: 6);
      });
    });

    testWidgets('the guidance', (tester) async {
      await onDesktop(() async {
        await guide(tester, tablet);
        await expectCursors(tester, atLeast: 3);
      });
    });

    testWidgets('the guidance overview, its stops, a notice and a folded one', (tester) async {
      await onDesktop(() async {
        final plan = routeFixture('limoges_drive');
        final app = await pumpLunaway(
          tester,
          size: tablet,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: FakeLocationFeed(position: plan.routes.first.line.first),
            engine: LineEngine([plan]),
            voice: RecordingVoice(readiness: VoiceReadiness.none),
          ),
        );
        final container = app.container(tester);
        final t = await AppLocale.fr.build();
        await container
            .read(guidanceControllerProvider.notifier)
            .start(
              plan: plan,
              routeIndex: plan.routes.first.index,
              target: const RouteTarget(destination: LatLng(45.84510, 1.28637), label: 'Arrivée'),
              words: TranslatedWording(t, DistanceUnits.metric),
              stops: [RouteStop(position: LineTrack(plan.routes.first).at(800), label: 'Pause')],
            );
        unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
        await settleShort(tester);
        // The voice's notice folded into its chip, a message over the map.
        await tester.tap(find.textContaining('Aucune voix'));
        await settleShort(tester);
        await tester.tap(find.byTooltip('Tout le trajet'));
        await settleShort(tester);
        showMessage(
          ScaffoldMessenger.of(tester.element(find.byType(GuidanceScreen))),
          'Signalement envoyé',
        );
        await settleShort(tester);
        expect(find.text('Signalement envoyé'), findsOneWidget);
        expect(find.textContaining('Pause ·'), findsOneWidget);
        await expectCursors(tester, atLeast: 8);
      });
    });

    testWidgets('the places of the guidance, presets, categories and displays', (tester) async {
      await onDesktop(() async {
        await guide(tester, const Size(1280, 1800));
        await tester.tap(find.byTooltip('Lieux sur la carte'));
        await settleShort(tester);
        await tester.tap(find.text('Personnaliser'));
        await settleShort(tester);
        expect(find.text('Boulangeries'), findsOneWidget, reason: 'the categories unfolded');
        // Five presets, "Personnaliser", every place and eleven categories,
        // the ratings, three displays.
        await expectCursors(tester, atLeast: 25);
      });
    });
  });

  testWidgets('under the mouse, the shared widgets of the design system', (tester) async {
    await onDesktop(() async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await LocaleSettings.setLocale(AppLocale.fr);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: lunaTheme(Brightness.light, pointer: true),
            home: Stack(
              children: [
                SubPage(
                  title: 'Page',
                  children: [
                    Row(
                      children: [
                        MapButton(icon: AppIcons.close, tooltip: 'Fermer', onPressed: () {}),
                        const MapButton(icon: AppIcons.close, tooltip: 'Inactif', onPressed: null),
                      ],
                    ),
                    LunaSegmented<int>(
                      segments: const [
                        Segment(value: 1, label: 'Un'),
                        Segment(value: 2, label: 'Deux'),
                      ],
                      selected: 1,
                      onChanged: (_) {},
                    ),
                    ChoiceTile(icon: AppIcons.close, label: 'Choix', onTap: () {}),
                    SizedBox(
                      height: 400,
                      child: MessageView(title: 'Vide', action: 'Réessayer', onAction: () {}),
                    ),
                  ],
                ),
                SpringSheet(
                  snaps: const [120, 300],
                  initial: 120,
                  builder: (context, scroll) => ListView(
                    controller: scroll,
                    children: [ListTile(title: const Text('Ligne'), onTap: () {})],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final sweep = await expectCursors(tester, atLeast: 7);
      expect(sweep.byKind['drag handle'], 1, reason: 'the sheet handle is hovered');
      expect(sweep.byKind['disabled button'], 1, reason: 'the disabled map button is hovered');
    });
  });
}
