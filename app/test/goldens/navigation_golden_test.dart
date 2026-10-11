@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_credit_fold.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/fonts.dart';
import '../helpers/navigation.dart';
import '../helpers/poi_fakes.dart';
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
        // A guidance starts after the run's first map has shown its credit
        // in full: it shows the mark alone.
        container.read(mapCreditFoldedProvider.notifier).fold();
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

  // A camera of Spain limited to 70 ahead, under then over its limit, and a
  // zone of France entered: the pill beside the speed, the camera on its
  // place with its limit's sign, the zone's stretch of the route.
  for (final (name, country, kmh, brightness) in [
    ('a camera ahead', 'ES', 36.0, Brightness.light),
    ("over a camera's limit", 'ES', 90.0, Brightness.dark),
    ('in a danger zone', 'FR', 36.0, Brightness.light),
  ]) {
    testWidgets(
      'guidance, $name, compact, ${brightness.name}',
      skip: skip,
      (tester) => _withShadows(() async {
        final plan = routeFixture(
          'limoges_drive',
          edit: (answer) {
            final routes = answer['routes'] as List<dynamic>;
            (routes.first as Map<String, dynamic>)['speedLimits'] = [
              {'fromM': 0.0, 'toM': 3000.0, 'kmh': 80, 'source': 'VEHICLE'},
            ];
          },
        );
        final route = plan.routes.first;
        final track = LineTrack(route);
        final feed = FakeLocationFeed(position: route.line.first);
        const rules = EnforcementRules(
          version: 1,
          countries: {'FR': EnforcementMode.zones, 'ES': EnforcementMode.exact},
        );
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
            countries: FakeCountries((_) => country, rules: rules),
            enforcement: FixedEnforcement(
              rules: rules,
              items: [
                if (country == 'ES')
                  EnforcementItem(
                    id: 'camera',
                    kind: EnforcementKind.camera,
                    category: 'FIXED',
                    country: 'ES',
                    position: track.at(1000),
                    limitKmh: 70,
                  )
                else
                  EnforcementItem(
                    id: 'zone',
                    kind: EnforcementKind.zone,
                    category: 'FIXED',
                    country: 'FR',
                    line: [for (var m = 700.0; m <= 1500; m += 50) track.at(m)],
                  ),
              ],
            ),
          ),
        );
        final container = app.container(tester);
        container.read(mapCreditFoldedProvider.notifier).fold();
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
        var at = DateTime.utc(2026, 10, 6, 8, 20);
        for (var m = 0.0; m <= 820; m += kmh / 3.6) {
          feed.send(Fix(position: track.at(m), accuracyM: 5, at: at, speedMps: kmh / 3.6));
          at = at.add(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 10));
        }
        await settleShort(tester);
        final file = name.replaceAll(RegExp('[^a-z]+'), '_');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('images/guidance_${file}_${brightness.name}.png'),
        );
      }),
    );
  }

  // The guidance with the stations of "Pour le plein" around the vehicle
  // and two of the fuel list: the price of the vehicle's fuel by each,
  // coloured from the cheapest to the dearest.
  testWidgets(
    "guidance, the stations' prices, compact, light",
    skip: skip,
    (tester) => _withShadows(() async {
      final plan = routeFixture('limoges_drive');
      final route = plan.routes.first;
      final track = LineTrack(route);
      final start = route.line.first;
      final feed = FakeLocationFeed(position: start);
      final app = await pumpLunaway(
        tester,
        size: _phone,
        online: FakeOnlinePlaces(const []),
        pois: FakePoiSource(
          pois: [
            for (final (id, m, price, north) in [
              ('a', 60.0, 1.799, 0.0012),
              ('b', 330.0, 1.829, -0.0012),
            ])
              stationWith(
                id,
                'Station $id',
                {'DIESEL': price},
                lat: track.at(m).lat + north,
                lon: track.at(m).lon,
              ),
          ],
        ),
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: feed,
          engine: LineEngine([plan]),
          vehicle: const Vehicle(type: VehicleType.integrated, heightM: 3.3, fuel: FuelType.diesel),
          settings: MemoryRouteSettings(
            NavigationSettings(
              guidancePlaces: GuidancePlaces(selection: GuidancePreset.fill.selection),
            ),
          ),
        ),
      );
      final container = app.container(tester);
      container.read(mapCreditFoldedProvider.notifier).fold();
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
      FuelOffer offer(String id, double m, double price) => FuelOffer(
        id: id,
        poiId: id,
        position: track.at(m),
        priceEur: price,
        priceUpdatedAt: DateTime.utc(2026, 10, 6, 6),
        detourM: 0,
        detourS: 0,
        alongM: m,
        fuel: FuelType.diesel,
      );
      container.read(shownFuelOffersProvider(route.line).notifier).show([
        offer('list-cheap', 420, 1.749),
        offer('list-dear', 200, 1.869),
      ]);
      feed.send(Fix(position: start, accuracyM: 5, at: DateTime.utc(2026, 10, 6, 8, 20)));
      await tester.pump(const Duration(milliseconds: 400));
      await settleShort(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/guidance_station_prices_light.png'),
      );
    }),
  );

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
