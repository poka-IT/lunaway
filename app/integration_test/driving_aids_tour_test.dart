import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
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
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The limit for the vehicle and a danger zone in a real guidance on the
/// emulator: a route of the API with its speed limits (Limoges, the A20
/// north, for a motorhome of 4.4 t), the danger zones of France from the
/// API's delta, the country read on the device by the guidance library.
/// The position is simulated along the route: fast, then at real speed
/// near the zone, as a driver sees it.
///
///     tool/screens/capture.py --test integration_test/driving_aids_tour_test.dart --api URL
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'aids');

const _vehicle = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.1,
  widthM: 2.35,
  lengthM: 7.4,
  weightT: 4.4,
);

const _from = LatLng(45.8010, 1.2940);
const _to = LatLng(45.8800, 1.2700);

/// The route of the drive, asked once; the guidance's own requests get it
/// again.
final class _Once implements RouteService {
  new(this.plan);

  final RoutePlan plan;

  @override
  Future<RoutePlan> route(RouteRequest request) async => plan;

  @override
  // An answer that fails, as a server without the query: the preview then
  // leaves the trip to the route request (a synchronous throw would fail it).
  Future<RoutingInfo> info() async => throw UnimplementedError();
}

/// The fixes of the drive at a pace the test sets.
final class _PacedFeed implements LocationFeed {
  new(this.fixes);

  final List<Fix> fixes;
  Duration pace = const Duration(milliseconds: 60);

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

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> until(WidgetTester tester, bool Function() done, {required String what}) async {
  final end = DateTime.now().add(const Duration(minutes: 4));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 600));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 1500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a guidance through a danger zone, the limit for the vehicle beside the speed', (
    tester,
  ) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final client = GraphQLClient(
      endpoint: config.graphqlEndpoint,
      httpClient: http.Client(),
      userAgent: AppConfig.userAgent('tour'),
    );
    final plan = await GraphQLRouteService(client).route(
      RouteRequest(
        origin: _from,
        destination: _to,
        vehicle: checkVehicle(_vehicle).profile!,
        avoid: const AvoidOptions(),
        language: _locale == 'en' ? RouteLanguage.en : RouteLanguage.fr,
      ),
    );
    final route = plan.routes.first;
    debugPrint('ROUTE ${route.distanceM.round()} m, limits ${route.speedLimits?.length}');
    // 25 m/s fixes along the route, one a second.
    final feed = _PacedFeed(
      drive(
        route.line,
        stepM: 25,
        start: DateTime.now().toUtc(),
        tick: const Duration(seconds: 1),
        speedMps: 25,
      ),
    );

    final cache = CacheDatabase.open(demo: false);
    final user = UserDatabase.open(demo: false);
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          cacheDatabaseProvider.overrideWithValue(cache),
          userDatabaseProvider.overrideWithValue(user),
          initialSettingsProvider.overrideWithValue(settings),
          basemapTemplatesProvider.overrideWithValue(basemap),
          locationPermissionsProvider.overrideWithValue(_Granted()),
          notificationAccessProvider.overrideWithValue(const _NoNotifications()),
          routeServiceProvider.overrideWithValue(_Once(plan)),
          locationFeedProvider.overrideWithValue(feed),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = _locale == 'en' ? AppLocale.en.buildSync() : AppLocale.fr.buildSync();
    await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: route.index,
          target: const RouteTarget(destination: _to, label: 'A20, Limoges nord', placeId: 'a20'),
          words: TranslatedWording(t, DistanceUnits.metric),
        );
    unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    await until(tester, () => session()?.snapshot != null, what: 'the first fix');
    // In town, 50 for the vehicle: at 90 km/h the speed warns.
    await until(
      tester,
      () => (session()?.snapshot?.distanceAlongM ?? 0) > 500,
      what: '500 m along',
    );
    feed.pace = const Duration(seconds: 1);
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'over-speed');
    feed.pace = const Duration(milliseconds: 60);
    await until(
      tester,
      () => (session()?.snapshot?.distanceAlongM ?? 0) > 1500,
      what: '1.5 km along',
    );
    await shot(tester, 'limit');

    await until(tester, () => session()?.aids.alert != null, what: 'the zone ahead');
    feed.pace = const Duration(seconds: 1);
    await shot(tester, 'zone-ahead');
    feed.pace = const Duration(milliseconds: 60);
    await until(tester, () => session()?.aids.alert?.inside ?? false, what: 'inside the zone');
    feed.pace = const Duration(seconds: 1);
    await settle(tester, const Duration(seconds: 6));
    await shot(tester, 'zone-inside');
    debugPrint(
      'AIDS mode ${session()?.aids.mode} country ${session()?.aids.country} '
      'limit ${session()?.aids.limit?.kmh} ${session()?.aids.limit?.source}',
    );
    container.read(guidanceControllerProvider.notifier).stop();
    await settle(tester, const Duration(seconds: 1));
    container.read(mapFlowProvider.notifier).select(null);
    debugPrint('TOUR DONE');
  });
}
