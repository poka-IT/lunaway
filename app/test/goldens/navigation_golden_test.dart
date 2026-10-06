@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fonts.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../widget/navigation_test.dart' show driveFixes, utrillo;

/// The guidance and the route preview, reviewed as images: the route drawn
/// schematically (the map is a platform view, absent from tests), the
/// panels as the app draws them. macOS only, like the other goldens.
const _phone = Size(412, 915);

Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(loadRealFonts);
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));
  final skip = !Platform.isMacOS;

  for (final brightness in Brightness.values) {
    testWidgets(
      'guidance, compact, ${brightness.name}',
      skip: skip,
      (tester) => _withShadows(() async {
        final plan = routeFixture('limoges_drive');
        final feed = FakeLocationFeed(position: plan.routes.first.line.first);
        final app = await pumpLunaway(
          tester,
          size: _phone,
          brightness: brightness,
          settings: AppSettings(
            theme: brightness == Brightness.dark ? ThemePreference.dark : ThemePreference.light,
          ),
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: feed,
            engine: LineEngine([plan]),
          ),
        );
        final container = app.container(tester);
        await container
            .read(guidanceControllerProvider.notifier)
            .start(
              plan: plan,
              routeIndex: 0,
              target: utrillo,
              words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
            );
        unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
        await settleShort(tester);
        // On Place Jourdan, the lanes of the junction where the route bears
        // right onto Avenue des Bénédictins.
        for (final f in driveFixes(plan.routes.first, toM: 380)) {
          feed.send(f);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await settleShort(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('images/guidance_compact_${brightness.name}.png'),
        );
      }),
    );
  }

  Future<void> preview(WidgetTester tester, RoutePlan plan, Size size) async {
    final app = await pumpLunaway(
      tester,
      size: size,
      overrides: navigationOverrides(routes: FakeRouteService([plan]), engine: LineEngine([plan])),
    );
    unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)));
    await settleShort(tester);
  }

  testWidgets(
    'route preview, compact',
    skip: skip,
    (tester) => _withShadows(() async {
      await preview(tester, routeFixture('utrillo_motorhome'), _phone);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/route_preview_compact.png'),
      );
    }),
  );

  testWidgets(
    'route preview, no safe route, expanded',
    skip: skip,
    (tester) => _withShadows(() async {
      await preview(tester, routeFixture('bregere_bar'), const Size(1280, 800));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/route_preview_no_safe_expanded.png'),
      );
    }),
  );
}
