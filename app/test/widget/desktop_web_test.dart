import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/browser_location.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../helpers/fonts.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The browser's answer, decided by the test.
final class FakeBrowserLocation implements BrowserLocation {
  new(this.answer);

  BrowserFix answer;
  int calls = 0;

  @override
  Future<BrowserFix> locate() async {
    calls++;
    return answer;
  }
}

/// The chips of the row under the search, in their order.
final Finder _chips = find.descendant(
  of: find.byType(QuickFilters),
  matching: find.byType(MapChip),
);

/// Whether [chip] shows whole in the row: past the fade, and the arrow in
/// it, on each side that has more.
bool _whole(WidgetTester tester, Finder chip) {
  final row = tester.getRect(find.byType(QuickFilters));
  final r = tester.getRect(chip);
  final before = find.byTooltip('Voir les filtres précédents').evaluate().isNotEmpty;
  final after = find.byTooltip('Voir les filtres suivants').evaluate().isNotEmpty;
  return r.left >= row.left + (before ? SidewaysRow.moreFade : 0) - 0.5 &&
      r.right <= row.right - (after ? SidewaysRow.moreFade : 0) + 0.5;
}

/// The first chip of the row not whole at its end.
Finder _firstCut(WidgetTester tester) {
  for (var i = 0; i < _chips.evaluate().length; i++) {
    if (!_whole(tester, _chips.at(i))) return _chips.at(i);
  }
  throw StateError('every chip whole');
}

/// Runs [body] as on a computer with a mouse (a desktop build, or a browser
/// on a desktop system).
Future<void> onDesktopSystem(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  // The chips' widths are the app's: in the test font, a chip of the row
  // is wider than the room between its fades, a pane's whole width even.
  setUpAll(loadRealFonts);

  group('the desktop look', () {
    testWidgets('with a mouse the search, the chips and the buttons lose a notch of height', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        await pumpLunaway(tester, size: desktop);
        expect(tester.getSize(find.byType(MapSearch)).height, 48);
        expect(tester.getSize(find.widgetWithText(MapChip, 'Filtres')).height, 40);
        expect(tester.getSize(locateButton).height, lessThan(48));
      });
    });

    testWidgets('the zoom buttons stay under the mouse when the position button turns round', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        // Wide enough for the words beside the credit in the tests' font,
        // whose letters are as wide as they are tall.
        final app = await pumpLunaway(tester, size: const Size(1600, 900));
        expect(app.map.viewport.zoom, lessThan(7), reason: 'the country view');
        final words = find.ancestor(
          of: find.text('Voir autour de moi'),
          matching: find.byType(TextButton),
        );
        expect(words, findsOneWidget, reason: 'room for the words beside the credit');
        expect(tester.getRect(words).overlaps(tester.getRect(find.byType(MapCredit))), isFalse);
        final before = tester.getRect(find.byTooltip('Zoomer'));
        app.map.lastProps!.onViewportChanged(
          const MapViewport(
            bounds: GeoBounds(south: 45.6, west: 5.7, north: 46.2, east: 6.6),
            center: LatLng(45.9, 6.15),
            zoom: 8,
          ),
        );
        await settleShort(tester);
        expect(find.byTooltip('Afficher ma position'), findsOneWidget, reason: 'round again');
        expect(tester.getRect(find.byTooltip('Zoomer')), before);
      });
    });

    testWidgets('a touch tablet as wide keeps the touch sizes', (tester) async {
      await pumpLunaway(tester, size: desktop);
      expect(tester.getSize(find.byType(MapSearch)).height, 56);
      expect(tester.getSize(find.widgetWithText(MapChip, 'Filtres')).height, 48);
    });

    testWidgets('a narrow browser window keeps the touch sizes, laid out as a phone', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        await pumpLunaway(tester);
        expect(tester.getSize(find.widgetWithText(MapChip, 'Filtres')).height, 48);
      });
    });

    testWidgets('the rail folds to its icons, and stays folded the next time', (tester) async {
      await onDesktopSystem(() async {
        final app = await pumpLunaway(tester, size: desktop);
        final unfolded = tester.getTopLeft(find.byType(MapSearch)).dx;
        expect(find.byType(BrandLockup), findsOneWidget);
        await tester.tap(find.byTooltip('Réduire le menu'));
        await settleShort(tester);
        expect(app.settings.value.railCollapsed, isTrue);
        expect(find.byType(BrandLockup), findsNothing);
        expect(find.text('Favoris'), findsOneWidget, reason: 'the labels stay under the icons');
        final folded = tester.getTopLeft(find.byType(MapSearch)).dx;
        expect(unfolded - folded, greaterThan(100), reason: 'the map and the list get the room');
      });
    });

    testWidgets('a folded rail comes back folded, and unfolds', (tester) async {
      await onDesktopSystem(() async {
        final app = await pumpLunaway(
          tester,
          size: desktop,
          settings: const AppSettings(theme: ThemePreference.light, railCollapsed: true),
        );
        expect(find.byType(BrandLockup), findsNothing);
        await tester.tap(find.byTooltip('Afficher le menu en entier'));
        await settleShort(tester);
        expect(find.byType(BrandLockup), findsOneWidget);
        expect(app.settings.value.railCollapsed, isFalse);
      });
    });

    testWidgets('the wheel of a mouse brings the chips past the edge of the pane into reach', (
      tester,
    ) async {
      await pumpLunaway(tester, size: desktop);
      final last = find.descendant(
        of: find.byType(QuickFilters),
        matching: find.text('Distributeurs alimentaires'),
      );
      final before = tester.getCenter(last).dx;
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final over = tester.getCenter(find.widgetWithText(MapChip, 'Carburant et énergie'));
      tester.binding.handlePointerEvent(mouse.hover(over));
      tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 400)));
      await tester.pump();
      expect(tester.getCenter(last).dx, lessThan(before - 300));
    });

    testWidgets('with a mouse, an arrow shows where the chips go on, and brings them', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        await pumpLunaway(tester, size: desktop);
        final next = find.byTooltip('Voir les filtres suivants');
        expect(next, findsOneWidget, reason: 'the row is cut at the edge of the pane');
        expect(
          find.byTooltip('Voir les filtres précédents'),
          findsNothing,
          reason: 'nothing before the first chip',
        );
        final cut = _firstCut(tester);
        await tester.tap(next);
        await settleShort(tester);
        expect(_whole(tester, cut), isTrue, reason: 'the chip cut at the end comes in whole');
        expect(find.byTooltip('Voir les filtres précédents'), findsOneWidget);
      });
    });

    testWidgets('in the pane of a wide window, the chips keep one row, each reached whole', (
      tester,
    ) async {
      await onDesktopSystem(() async {
        await pumpLunaway(tester, size: const Size(1440, 900));
        final count = _chips.evaluate().length;
        expect(count, greaterThan(8));
        final tops = {for (var i = 0; i < count; i++) tester.getRect(_chips.at(i)).top.round()};
        expect(tops, hasLength(1), reason: 'one row, not three lines (the PO, 2026-10-10)');
        // From the first to the last, the arrow brings each one in whole,
        // where a click at its middle reaches it.
        var presses = 0;
        for (var i = 0; i < count; i++) {
          final chip = _chips.at(i);
          while (!_whole(tester, chip) && presses < count) {
            await tester.tap(find.byTooltip('Voir les filtres suivants'));
            await settleShort(tester);
            presses++;
          }
          expect(_whole(tester, chip), isTrue, reason: 'chip $i, after $presses presses');
          final path = tester.hitTestOnBinding(tester.getCenter(chip)).path;
          final ink = tester.renderObject(
            find.descendant(of: chip, matching: find.byType(InkWell)),
          );
          expect(path.any((e) => e.target == ink), isTrue, reason: 'chip $i under the mouse');
        }
        expect(find.byTooltip('Voir les filtres suivants'), findsNothing, reason: 'the end');
      });
    });

    testWidgets('with less motion asked, the arrow moves the chips at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await onDesktopSystem(() async {
        await pumpLunaway(tester, size: desktop);
        final cut = _firstCut(tester);
        await tester.tap(find.byTooltip('Voir les filtres suivants'));
        await tester.pump();
        expect(_whole(tester, cut), isTrue, reason: 'in one frame');
      });
    });

    testWidgets('a row of chips that fits shows no arrow, nor a touch screen', (tester) async {
      Future<void> pumpRow(double width) async {
        await LocaleSettings.setLocale(AppLocale.fr);
        await tester.pumpWidget(
          TranslationProvider(
            child: MaterialApp(
              theme: lunaTheme(Brightness.light, pointer: true),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: SidewaysRow(
                      child: Row(children: [SizedBox(width: width, height: 40)]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // The row measures itself after a layout, and shows its arrows the
        // frame after.
        await tester.pump();
        await tester.pump();
      }

      await onDesktopSystem(() async {
        await pumpRow(300);
        expect(find.byType(IconButton), findsNothing, reason: 'all of it shows');
        await pumpRow(900);
        expect(find.byTooltip('Voir les filtres suivants'), findsOneWidget);
      });
      await pumpRow(900);
      expect(
        find.byType(IconButton),
        findsNothing,
        reason: 'a finger swipes the row; the fade says there is more',
      );
    });

    testWidgets('a question with a long text keeps the width of a dialog on a wide window', (
      tester,
    ) async {
      await pumpLunaway(tester, size: const Size(1920, 1080));
      final long = List.filled(40, 'La nouvelle carte aura un autre code.').join(' ');
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(MapSearch)),
          builder: (_) => AlertDialog(title: const Text('Remplacer ?'), content: Text(long)),
        ),
      );
      await settleShort(tester);
      final surface = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Material),
      );
      expect(tester.getSize(surface.first).width, lessThanOrEqualTo(560));
    });

    testWidgets('a tablet rail has nothing to fold', (tester) async {
      await pumpLunaway(tester, size: tablet);
      expect(find.byTooltip('Réduire le menu'), findsNothing);
      expect(find.byTooltip('Afficher le menu en entier'), findsNothing);
    });
  });

  group('the web map under a dialog, a sheet or a menu', () {
    setUp(() => MapShield.enabled = true);
    tearDown(() => MapShield.enabled = kIsWeb);

    Finder shield() =>
        find.descendant(of: find.byType(MapShield), matching: find.byType(PointerInterceptor));

    testWidgets('the filters cover the whole map while open, so the wheel scrolls them only', (
      tester,
    ) async {
      await pumpLunaway(tester, size: desktop);
      expect(shield(), findsNothing, reason: 'the map takes its gestures');
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      expect(shield(), findsOneWidget);
      expect(tester.getRect(shield()), tester.getRect(find.byType(MapShield)));
      Navigator.of(tester.element(find.text('Tout effacer'))).pop();
      await settleShort(tester);
      expect(shield(), findsNothing);
    });

    testWidgets('a menu opened from a panel covers it too', (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(campsite.id));
      await settleShort(tester);
      final menu = find.byTooltip('Choisir le format copié');
      await tester.scrollUntilVisible(
        menu,
        200,
        scrollable: find
            .descendant(of: find.byType(PlaceDetails), matching: find.byType(Scrollable))
            .first,
      );
      await tester.pump();
      await tester.tap(menu);
      await settleShort(tester);
      expect(shield(), findsOneWidget);
      Navigator.of(tester.element(find.text('Degrés décimaux'))).pop();
      await settleShort(tester);
      expect(shield(), findsNothing);
    });
  });

  group('the position on the web', () {
    testWidgets('the button asks the browser at once, then shows and centres the position', (
      tester,
    ) async {
      const here = LatLng(45.9, 6.12);
      final browser = FakeBrowserLocation(const BrowserPosition(here, accuracy: 30));
      final app = await pumpLunaway(
        tester,
        size: desktop,
        overrides: [browserLocationProvider.overrideWithValue(browser)],
      );
      await tester.tap(locateButton);
      // Within the click: some browsers show their prompt only then.
      expect(browser.calls, 1);
      await settleShort(tester);
      expect(find.text('Afficher votre position ?'), findsNothing, reason: 'the browser asks');
      expect(app.location.requests, 0);
      expect(app.map.shown, [here]);
      expect(app.map.moves.last.center, here);
    });

    testWidgets('a refusal says where the browser keeps the setting', (tester) async {
      final browser = FakeBrowserLocation(const BrowserDenied());
      final app = await pumpLunaway(
        tester,
        size: desktop,
        overrides: [browserLocationProvider.overrideWithValue(browser)],
      );
      await tester.tap(locateButton);
      await settleShort(tester);
      expect(find.text(t.location.browserDeniedTitle), findsOneWidget);
      expect(find.text(t.location.browserDenied), findsOneWidget);
      expect(app.map.shown, isEmpty);
      expect(app.map.moves, isEmpty);
    });

    testWidgets('no position from the browser is said, the map stays', (tester) async {
      final browser = FakeBrowserLocation(const BrowserNoFix());
      final app = await pumpLunaway(
        tester,
        size: desktop,
        overrides: [browserLocationProvider.overrideWithValue(browser)],
      );
      await tester.tap(locateButton);
      await settleShort(tester);
      expect(find.text(t.location.browserNoFix), findsOneWidget);
      expect(app.map.moves, isEmpty);
    });
  });

  test('the order of the chips holds every category and every filter of the row', () {
    expect(
      {for (final c in QuickFilters.order) c},
      {...PlaceChip.values, for (final c in PoiCategory.values.where((c) => c.tiled)) PoiChip(c)},
    );
  });

  testWidgets('the chips put the road first: fuel, water, the night, the vehicle', (tester) async {
    await pumpLunaway(tester);
    final order = [
      'Filtres',
      'Carburant et énergie',
      'Eau et vidange',
      'Nuit possible',
      'Mon véhicule passe',
      'Gratuit',
      'Courses',
      'Santé',
      'Services',
      'Distributeurs alimentaires',
    ];
    final row = find.byType(QuickFilters);
    final xs = [
      for (final label in order)
        tester.getCenter(find.descendant(of: row, matching: find.text(label))).dx,
    ];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]), reason: '${order[i]} after ${order[i - 1]}');
    }
  });
}
