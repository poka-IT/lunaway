import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show utrillo;

/// The motorhome of the tests, its fuel said or not.
Vehicle _vehicle(FuelType? fuel) => Vehicle(
  type: motorhome.type,
  heightM: motorhome.heightM,
  widthM: motorhome.widthM,
  lengthM: motorhome.lengthM,
  weightT: motorhome.weightT,
  fuel: fuel,
);

void main() {
  late FakePoiSource pois;

  /// A guidance from Limoges, the stations around its start as the API
  /// gives them, the pins of [selection] on its map; one fix at the start.
  Future<({TestApp app, RoutePlan plan})> guide(
    WidgetTester tester, {
    FuelType? fuel = FuelType.diesel,
    GuidanceSelection? selection,
  }) async {
    final plan = routeFixture('limoges_drive');
    final start = plan.routes.first.line.first;
    pois = FakePoiSource(
      pois: [
        stationWith(
          'near',
          'Station du lac',
          {'DIESEL': 1.789, 'E10': 1.85},
          lat: start.lat + 0.002,
          lon: start.lon + 0.002,
        ),
        stationWith('dear', 'Relais', {'DIESEL': 1.849}, lat: start.lat - 0.003, lon: start.lon),
        stationWith('petrol', 'Essence', {'E10': 1.70}, lat: start.lat, lon: start.lon + 0.004),
      ],
    );
    final feed = FakeLocationFeed(position: start);
    final app = await pumpLunaway(
      tester,
      online: FakeOnlinePlaces(const []),
      pois: pois,
      overrides: navigationOverrides(
        routes: FakeRouteService([plan]),
        feed: feed,
        engine: LineEngine([plan]),
        vehicle: _vehicle(fuel),
        settings: MemoryRouteSettings(
          NavigationSettings(
            guidancePlaces: GuidancePlaces(selection: selection ?? GuidancePreset.fill.selection),
          ),
        ),
      ),
    );
    final container = app.container(tester);
    await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: plan.routes.first.index,
          target: utrillo,
          words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
        );
    unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
    await settleShort(tester);
    feed.send(
      Fix(position: start, accuracyM: 5, at: DateTime.utc(2026, 10, 6, 8, 29), speedMps: 8),
    );
    // The stations are read once the position rests a moment.
    await tester.pump(const Duration(milliseconds: 400));
    await settleShort(tester);
    return (app: app, plan: plan);
  }

  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  testWidgets("under the stations' pins, the price of the vehicle's fuel, coloured as on the main "
      'map; none for a station without it', (tester) async {
    await guide(tester);
    final prices = SchematicRouteMap.last!.fuelPrices;
    expect({for (final l in prices) l.id: l.text}, {'near': '1,789', 'dear': '1,849'});
    expect(prices.firstWhere((l) => l.id == 'near').rank, 0, reason: 'the cheapest');
    expect(prices.firstWhere((l) => l.id == 'dear').rank, 1, reason: 'the dearest');
    expect(pois.fuelReads, 1, reason: "one read for the vehicle's cell");
  });

  testWidgets('without a fuel in the profile, the stations show their logo alone', (tester) async {
    await guide(tester, fuel: null);
    expect(SchematicRouteMap.last!.fuelPrices, isEmpty);
    expect(pois.fuelReads, 0, reason: 'nothing to price, nothing read');
  });

  testWidgets('while the map shows no station, no price and nothing read', (tester) async {
    await guide(tester, selection: GuidancePreset.sleep.selection);
    expect(SchematicRouteMap.last!.fuelPrices, isEmpty);
    expect(pois.fuelReads, 0);
  });

  testWidgets("the fuel list's stations: the vehicle's fuel beside their pump, coloured; another "
      "fuel's, the pump alone", (tester) async {
    final (:app, :plan) = await guide(tester);
    final container = app.container(tester);
    final line = plan.routes.first.line;
    FuelOffer offer(String id, double price, FuelType fuel) => FuelOffer(
      id: id,
      poiId: id,
      position: line[5],
      priceEur: price,
      priceUpdatedAt: DateTime.utc(2026, 10, 6, 6),
      detourM: 200,
      detourS: 30,
      alongM: 500,
      fuel: fuel,
    );
    container.read(shownFuelOffersProvider(line).notifier).show([
      offer('cheap', 1.699, FuelType.diesel),
      offer('gas', 0.999, FuelType.lpg),
    ]);
    await tester.pump();
    final marks = {
      for (final m in SchematicRouteMap.last!.marks)
        if (m.kind == RouteMarkKind.fuel) m.id: m,
    };
    expect(marks['poi:cheap']!.side, '1,699');
    expect(marks['poi:cheap']!.sideInk, PoiLook.price(0, dark: false));
    expect(marks['poi:gas']!.side, isNull, reason: "not the vehicle's fuel");
    // Ranked with the stations around: the list's is the cheapest.
    expect(
      SchematicRouteMap.last!.fuelPrices.firstWhere((l) => l.id == 'near').rank,
      greaterThan(0),
    );
  });
}
