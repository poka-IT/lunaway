import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/browser_location.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

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
      final over = tester.getCenter(find.widgetWithText(MapChip, 'Filtres'));
      tester.binding.handlePointerEvent(mouse.hover(over));
      tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 400)));
      await tester.pump();
      expect(tester.getCenter(last).dx, lessThan(before - 300));
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
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(campsite.id));
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
      {...PlaceChip.values, for (final c in PoiCategory.values) PoiChip(c)},
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
