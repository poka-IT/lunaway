import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/guidance_places_sheet.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show utrillo;

/// The sheets over the guidance: on a phone on its side they stand beside
/// the maneuver's panel, and they follow the phone when it turns.
void main() {
  const upright = Size(400, 860);
  const onItsSide = Size(900, 400);

  Future<void> guide(WidgetTester tester, Size size) async {
    final plan = routeFixture('limoges_drive');
    final app = await pumpLunaway(
      tester,
      size: size,
      overrides: navigationOverrides(
        routes: FakeRouteService([plan]),
        feed: FakeLocationFeed(position: plan.routes.first.line.first),
        engine: LineEngine([plan]),
        fuel: FakeFuelStations(const []),
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
        );
    unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.guidance));
    await settleShort(tester);
  }

  /// The part of the height under the handle the list takes.
  double share(Rect sheet, Size window) => sheet.height / (window.height - SheetHandle.height);

  Rect maneuver(WidgetTester tester) => tester.getRect(find.byType(ManeuverIcon).first);

  Future<void> turn(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await settleShort(tester);
  }

  testWidgets('"Sur le trajet" stands beside the maneuver on a phone on its side', (tester) async {
    await guide(tester, onItsSide);
    await tester.tap(find.byTooltip('Sur le trajet'));
    await settleShort(tester);
    final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
    expect(sheet.left, greaterThanOrEqualTo(maneuver(tester).right), reason: 'the panel uncovered');
    expect(sheet.right, closeTo(onItsSide.width, 1));
    expect(share(sheet, onItsSide), closeTo(0.94, 0.02), reason: 'nearly whole');
  });

  testWidgets('"Sur le trajet" takes the height and the place of the turned phone', (tester) async {
    await guide(tester, upright);
    await tester.tap(find.byTooltip('Sur le trajet'));
    await settleShort(tester);
    Rect sheet() => tester.getRect(find.byType(DraggableScrollableSheet));
    expect(share(sheet(), upright), closeTo(0.5, 0.02), reason: 'half, upright');
    expect(sheet().left, 0);
    await turn(tester, onItsSide);
    expect(share(sheet(), onItsSide), closeTo(0.94, 0.02), reason: 'nearly whole');
    expect(sheet().left, greaterThanOrEqualTo(maneuver(tester).right));
    await turn(tester, upright);
    expect(share(sheet(), upright), closeTo(0.5, 0.02), reason: 'half again');
    expect(sheet().left, 0, reason: 'the whole width again');
    // Dragged taller by hand, then turned: the new window decides.
    await tester.drag(find.byType(DraggableScrollableSheet), const Offset(0, -150));
    await settleShort(tester);
    expect(share(sheet(), upright), greaterThan(0.6));
    await turn(tester, onItsSide);
    expect(share(sheet(), onItsSide), closeTo(0.94, 0.02));
  });

  testWidgets('"Lieux sur la carte" stands beside the maneuver on a phone on its side', (
    tester,
  ) async {
    await guide(tester, onItsSide);
    await tester.tap(find.byTooltip('Lieux sur la carte'));
    await settleShort(tester);
    final sheet = tester.getRect(find.byType(GuidancePlacesSheet));
    expect(sheet.left, greaterThanOrEqualTo(maneuver(tester).right));
    await turn(tester, upright);
    expect(tester.getRect(find.byType(GuidancePlacesSheet)).left, 0);
  });
}
