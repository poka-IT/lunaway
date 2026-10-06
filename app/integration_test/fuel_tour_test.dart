import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/cheapest_fuel.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;
import 'package:lunaway/shared/labels.dart';

/// The fuel prices against the real API, for screenshots: the price of the
/// vehicle's fuel under each station, the cheapest around, another fuel,
/// a station's page, and the vehicle's fuel in its editor. The vehicle the
/// device had is put back at the end. Run through
/// `tool/screens/capture.py --test integration_test/fuel_tour_test.dart`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'tour');

/// Annecy, where the stations of the price feed are many.
const _town = LatLng(45.8992, 6.1294);
const _stations = LatLng(45.905, 6.115);

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<T> waitFor<T>(WidgetTester tester, Future<T> work) async {
  var done = false;
  late T value;
  unawaited(
    work.then((v) {
      value = v;
      done = true;
    }),
  );
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return value;
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fuel tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLocale(AppLocaleUtils.parse(_locale));
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    await settings.setFilter(PlaceFilter.none);
    final t = AppLocaleUtils.parse(_locale).buildSync();
    final ready = DateTime.now().add(const Duration(minutes: 4));
    while ((container.read(syncStateProvider).value?.completedAt == null ||
            container.read(viewportProvider) == null) &&
        DateTime.now().isBefore(ready)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final map = container.read(mapControllerProvider)!;
    final layer = container.read(poiLayerProvider.notifier)..clear();
    await settle(tester, const Duration(seconds: 4));

    // A van on gazole whose living area heats on LPG.
    final vehicles = container.read(vehicleRepositoryProvider);
    final before = await waitFor(tester, vehicles.watch().first);
    await waitFor(
      tester,
      vehicles.save(
        (before ?? Vehicle.typical(VehicleType.campervan)).copyWith(
          fuel: () => FuelType.diesel,
          consumptionL100: () => 11.5,
          lpgHeating: true,
        ),
      ),
    );
    container.read(userLocationProvider.notifier).update(_town);

    // The chip on: the price of gazole under each station, and the list.
    layer.toggle(PoiCategory.fuel);
    await waitFor(tester, map.moveTo(_stations, zoom: 13.4));
    await settle(tester, const Duration(seconds: 6));
    await shot(tester, 'fuel-map');
    // A tablet opens the list with its button; a phone raises its sheet.
    final open = find.text(t.poi.cheapest.show);
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open);
    } else {
      await tester.drag(
        find.text(t.poi.cheapest.title),
        const Offset(0, -420),
        warnIfMissed: false,
      );
    }
    await shot(tester, 'fuel-list');

    // Another fuel, from the list's header: its chip may be past the edge
    // of the row, which scrolls sideways.
    final lpg = find.descendant(
      of: find.byType(CheapestFuelList),
      matching: find.widgetWithText(ChoiceChip, t.fuelType(FuelType.lpg)),
    );
    await tester.ensureVisible(lpg);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(lpg);
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'fuel-list-lpg');
    container.read(chosenFuelProvider.notifier).choose(FuelType.diesel);
    await settle(tester, const Duration(seconds: 2));

    // The cheapest station's page: every price, gazole first, then LPG.
    final offers = await waitFor(tester, container.read(cheapestFuelProvider.future)) ?? const [];
    if (offers.isNotEmpty) {
      final station = offers.first.station;
      container.read(selectionProvider.notifier).select(PoiSelection(station.feature));
      await waitFor(tester, map.moveTo(station.position, zoom: 15));
      await settle(tester, const Duration(seconds: 3));
      await tester.drag(find.byType(PoiDetails).first, const Offset(0, -300), warnIfMissed: false);
      await shot(tester, 'fuel-station');
      container.read(selectionProvider.notifier).select(null);
    }
    layer.clear();
    await settle(tester, const Duration(seconds: 1));

    // The vehicle's fuel in its editor.
    final editor = showVehicleEditor(tester.element(find.byType(Scaffold).first));
    await settle(tester, const Duration(seconds: 2));
    await tester.scrollUntilVisible(
      find.text(t.vehicle.lpgHeating),
      250,
      scrollable: find
          .descendant(of: find.byType(VehicleEditor), matching: find.byType(Scrollable))
          .first,
    );
    await shot(tester, 'vehicle-fuel');
    Navigator.of(tester.element(find.byType(VehicleEditor))).pop();
    await waitFor(tester, editor);

    // The device ends with the vehicle it had.
    await waitFor(tester, before == null ? vehicles.clear() : vehicles.save(before));
    await waitFor(tester, map.moveTo(_town, zoom: 9));
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE');
    expect(container.read(vehicleFuelProvider).fuel, before?.fuel);
  });
}
