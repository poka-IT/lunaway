import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;
import 'package:path_provider/path_provider.dart';

/// The places by region against the real API, for screenshots: a first
/// launch from an empty device (the first download named, the choice of
/// the regions), the regions kept in the profile, and a station's price
/// over the last days. Run through
/// `tool/screens/capture.py --test integration_test/regions_tour_test.dart --api <API>`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'tour');

/// A station of Brive on the A20 whose prices the feed gives every day.
const _station = '01a110e9-f037-7172-b861-f4e0e3e52c09';

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(
  WidgetTester tester,
  String name, {
  Duration wait = const Duration(milliseconds: 1200),
}) async {
  await settle(tester, wait);
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2000));
}

Future<void> until(WidgetTester tester, bool Function() done, {required String what}) async {
  final end = DateTime.now().add(const Duration(minutes: 3));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw StateError('no $what in time');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // An empty device: no place and no choice of regions yet.
    final cache = await CacheDatabase.directory();
    final support = await getApplicationSupportDirectory();
    for (final (dir, name) in [(cache, 'lunaway'), (support, 'lunaway_user')]) {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('${dir.path}/$name.sqlite$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
  });

  testWidgets('regions tour', (tester) async {
    await app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    unawaited(settings.setLocale(AppLocaleUtils.parse(_locale)));
    unawaited(settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light));
    unawaited(settings.setFilter(PlaceFilter.none));
    final t = AppLocaleUtils.parse(_locale).buildSync();

    // The first download names its region over the empty map.
    await until(
      tester,
      () => find.text(t.regions.choose).evaluate().isNotEmpty,
      what: 'the first download',
    );
    // At once: the region lands in a few seconds and the banner goes.
    await shot(tester, 'first-sync', wait: Duration.zero);
    unawaited(showRegionPicker(tester.element(find.byType(Scaffold).first)));
    await until(
      tester,
      () => find.text(t.regions.wholeFrance).evaluate().isNotEmpty,
      what: 'the regions',
    );
    // The regions of France unfolded, Spain added.
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip(t.regions.showFrance));
    await until(
      tester,
      () => find.text(_locale == 'fr' ? 'Bretagne' : 'Brittany').evaluate().isNotEmpty,
      what: 'the regions of France',
    );
    await shot(tester, 'regions-picker');
    final list = find
        .descendant(of: find.byType(RegionPicker), matching: find.byType(Scrollable))
        .first;
    final spain = find.text(_locale == 'fr' ? 'Espagne' : 'Spain');
    await tester.scrollUntilVisible(spain, 200, scrollable: list);
    await tester.tap(spain);
    await settle(tester, const Duration(milliseconds: 600));
    await shot(tester, 'regions-picker-spain');
    await tester.tap(find.textContaining(t.regions.download(size: '')).last);

    // Everything downloaded, the profile lists the regions kept.
    await until(
      tester,
      () =>
          container.read(syncControllerProvider) is SyncDone &&
          (container.read(keptRegionsControllerProvider).value?.contains('ES') ?? false),
      what: 'the sync',
    );
    await settle(tester, const Duration(seconds: 2));
    await container
        .read(vehicleRepositoryProvider)
        .save(Vehicle.typical(VehicleType.campervan).copyWith(fuel: () => FuelType.diesel));
    await tester.tap(find.text(t.nav.profile).last);
    await settle(tester, const Duration(seconds: 1));
    // The regions kept are in the offline maps, the profile's entry.
    final entry = find.text(t.offlineMaps.title);
    await tester.scrollUntilVisible(entry, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(entry);
    await settle(tester, const Duration(seconds: 1));
    await shot(tester, 'offline-regions');
    await tester.pageBack();
    await settle(tester, const Duration(seconds: 1));

    // A station's page: its prices and how gazole moved.
    await tester.tap(find.text(t.nav.map).last);
    await settle(tester, const Duration(seconds: 1));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/map?poi=$_station');
    await until(tester, () => find.byType(PoiDetails).evaluate().isNotEmpty, what: 'the station');
    await settle(tester, const Duration(seconds: 3));
    final trend = find.text(t.poi.trend.title(fuel: t.poi.fuel.diesel));
    await tester.scrollUntilVisible(
      trend,
      300,
      scrollable: find
          .descendant(of: find.byType(PoiDetails), matching: find.byType(Scrollable))
          .first,
    );
    await tester.drag(trend, const Offset(0, -500));
    await settle(tester, const Duration(seconds: 2));
    await shot(tester, 'fuel-trend');
    debugPrint('TOUR DONE');
  });
}
