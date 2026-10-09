import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import 'fixtures/roundabout_route.dart';

/// A drive through the seven roundabouts north of Brive-la-Gaillarde, in
/// the real app with the real guidance engine and map, the position
/// simulated along a route recorded from the Lunaway API: the banner is
/// captured 70 m before each roundabout, the exit's pictogram and the
/// "Then" line under it, and the route's list of steps before the start.
/// The exits go right (151 degrees round), left (254), almost back (326),
/// a little left (207), back again (333), left (223 and 255).
///
///   python3 tool/screens/capture.py --test integration_test/roundabouts_drive_test.dart \
///       --device android:emulator-5554 --size 1080x1920 --out ../data/tmp/rings
///
/// prints a `SHOT` line at each capture.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'rings');

const _vehicle = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.3,
  widthM: 2.3,
  lengthM: 7.4,
  weightT: 3.5,
);

/// The route, always the same.
final class _Route implements RouteService {
  new(this.plan);

  final RoutePlan plan;

  @override
  Future<RoutePlan> route(RouteRequest request) async => plan;

  @override
  // A server without the query: the preview leaves the trip to the route.
  Future<RoutingInfo> info() async => throw UnimplementedError();
}

final class _NoEvents implements RoadEventsSource {
  @override
  Future<RoadEventsDelta> delta({String? cursor}) async =>
      RoadEventsDelta(cursor: 'c', asOf: DateTime.now().toUtc());
}

/// The fixes of the drive, one per simulated second, at a pace the test
/// sets.
final class _PacedFeed implements LocationFeed {
  new(this.fixes);

  final List<Fix> fixes;
  Duration pace = _fast;

  @override
  Future<Fix?> current() async => fixes.first;

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    for (final f in fixes) {
      await Future<void>.delayed(pace);
      yield f;
    }
  }
}

const _fast = Duration(milliseconds: 80);
const _real = Duration(seconds: 1);

final class _NoNotifications implements NotificationAccess {
  const new();

  @override
  Future<bool> wouldAsk() async => false;

  @override
  Future<void> ask() async {}
}

final class _Granted implements LocationPermissions {
  @override
  Future<LocationAccess> status() async => LocationAccess.granted;

  @override
  Future<LocationAccess> request() async => LocationAccess.granted;

  @override
  Future<bool> openSettings() async => true;
}

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 120),
  String what = 'a condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester, const Duration(milliseconds: 800));
  debugPrint('SHOT $_tag-$name');
  await _settle(tester, const Duration(milliseconds: 1500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the banner before each of seven roundabouts', (tester) async {
    final data =
        (jsonDecode(briveRoundabouts) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final plan = await withShapes(routePlanFromJson(data['route'] as Map<String, dynamic>));
    final route = plan.routes.single;
    final feed = _PacedFeed(
      drive(
        route.line,
        stepM: 15,
        start: DateTime.utc(2026, 10, 9, 9),
        tick: const Duration(seconds: 1),
        speedMps: 15,
      ),
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
          cacheDatabaseProvider.overrideWithValue(CacheDatabase.open(demo: false)),
          userDatabaseProvider.overrideWithValue(UserDatabase.open(demo: false)),
          initialSettingsProvider.overrideWithValue(settings),
          basemapTemplatesProvider.overrideWithValue(basemap),
          locationPermissionsProvider.overrideWithValue(_Granted()),
          notificationAccessProvider.overrideWithValue(const _NoNotifications()),
          routeServiceProvider.overrideWithValue(_Route(plan)),
          locationFeedProvider.overrideWithValue(feed),
          roadEventsSourceProvider.overrideWithValue(_NoEvents()),
          roadEventsPollProvider.overrideWithValue(const Duration(hours: 1)),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await _settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = _locale == 'en' ? AppLocale.en.buildSync() : AppLocale.fr.buildSync();
    await container.read(routeSettingsStoreProvider).save(const NavigationSettings());
    container.invalidate(routeSettingsControllerProvider);

    unawaited(
      container
          .read(routerProvider)
          .push(
            NavigationRoutes.previewOf(
              const RouteTarget(destination: LatLng(45.280987, 1.615099), label: 'Brive nord'),
            ),
          ),
    );
    final start = find.text(t.navigation.preview.start);
    await _until(tester, () => start.evaluate().isNotEmpty, what: 'the preview');
    debugPrint('TOUR preview');
    await _settle(tester, const Duration(seconds: 4));

    // The list of steps, where the roundabouts read the same as on the way;
    // on a phone it lies down the sheet, out of the lazy list until scrolled
    // to.
    final show = find.text(t.navigation.preview.roadbookShow);
    if (show.evaluate().isEmpty) {
      try {
        await tester.scrollUntilVisible(show, 250, scrollable: find.byType(Scrollable).first);
      } on Object catch (e) {
        debugPrint('no list of steps on this screen: $e');
      }
    }
    if (show.evaluate().isNotEmpty) {
      await tester.ensureVisible(show);
      await tester.tap(show);
      await _settle(tester, const Duration(seconds: 1));
      final firstRing = find.textContaining('2e sortie').first;
      await tester.ensureVisible(firstRing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await _settle(tester, const Duration(seconds: 1));
      await _shot(tester, 'roadbook');
    }

    await tester.ensureVisible(start);
    await tester.tap(start);
    await _settle(tester, const Duration(seconds: 1));
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    await _until(tester, () => session()?.snapshot != null, what: 'the first fix');
    debugPrint('TOUR guiding');
    double along() => session()?.snapshot?.distanceAlongM ?? 0;

    var from = 0.0;
    var ring = 0;
    for (final step in route.steps) {
      if (step.maneuverType == 'roundabout' || step.maneuverType == 'rotary') {
        ring++;
        final at = from;
        await _until(tester, () => along() >= at - 170, what: 'roundabout $ring');
        feed.pace = _real;
        await _until(tester, () => along() >= at - 75, what: '75 m before roundabout $ring');
        await _shot(tester, 'ring$ring-${step.exitDegrees}');
        feed.pace = _fast;
      }
      from += step.distanceM;
    }
    expect(ring, 7);
    debugPrint('TOUR DONE');
  });
}
