import 'dart:async';

import 'package:drift/native.dart';
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
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/web_view_route_map.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The speed cameras of a route in the real app on the desktop's map: the
/// preview with their marks and legend, a camera's card, then a guidance
/// with a zone, a camera coming, over its limit, an average speed section
/// and its end. The route and its limits come from the API; the items are
/// placed along it by the test, as the API serves France's positions to a
/// user who asked for them (`exactIn`), and the choice is made in memory.
/// The country is read on the device by the guidance library.
///
///     python3 tool/screens/capture.py --test integration_test/speed_cameras_tour_test.dart \
///         --api https://api.lunaway.net --out ../plan/screenshots/radars
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'radars');

const _vehicle = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.1,
  widthM: 2.35,
  lengthM: 7.4,
  weightT: 3.5,
);

const _from = LatLng(45.8010, 1.2940);
const _to = LatLng(45.8800, 1.2700);

final _list = EnforcementSource(
  id: 'securite-routiere',
  name: 'Sécurité routière',
  attribution: 'Sécurité routière, radars.securite-routiere.gouv.fr',
  fetchedAt: DateTime.now().toUtc(),
);

/// The route of the drive, asked once; the guidance's own requests get it
/// again.
final class _Once implements RouteService {
  new(this.plan);

  final RoutePlan plan;

  @override
  Future<RoutePlan> route(RouteRequest request) async => plan;

  @override
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

/// The items placed along the route; the rules the library was built with.
final class _Placed implements EnforcementFeed {
  new(this.items);

  final List<EnforcementItem> items;

  @override
  Future<EnforcementData> refresh(Set<String> countries, DateTime now) async => (
    rules: null,
    items: items,
    sources: [_list],
    pollInterval: const Duration(hours: 6),
    polledAt: now,
  );

  @override
  Future<void> purge() async {}
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
  await settle(tester, const Duration(milliseconds: 800));
  debugPrint('SHOT carte-$name-$_tag');
  await settle(tester, const Duration(milliseconds: 1500));
}

/// The point [m] metres along [line].
LatLng _at(List<LatLng> line, double m) => lineAlong(line, RouteSpan(m, m + 1)).first;

/// The road of [line] from [from] to [to] metres, a point every 50 m.
List<LatLng> _road(List<LatLng> line, double from, double to) => [
  for (var m = from; m <= to; m += 50) _at(line, m),
];

/// The props of the route map on screen.
RouteMapProps _map(WidgetTester tester) =>
    tester.widgetList<WebViewRouteMap>(find.byType(WebViewRouteMap)).last.props;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the speed cameras of a route, previewed then driven through', (tester) async {
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
    final line = route.line;
    debugPrint('ROUTE ${route.distanceM.round()} m, limits ${route.speedLimits?.length}');
    final items = [
      EnforcementItem(
        id: 'zone',
        kind: EnforcementKind.zone,
        category: 'FIXED',
        country: 'FR',
        line: _road(line, 900, 1500),
        sourceIds: [_list.id],
      ),
      EnforcementItem(
        id: 'fixed',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'FR',
        position: _at(line, 2600),
        limitKmh: 50,
        sourceIds: [_list.id],
      ),
      EnforcementItem(
        id: 'section',
        kind: EnforcementKind.camera,
        category: 'SECTION_CONTROL',
        country: 'FR',
        position: _at(line, 3800),
        line: _road(line, 3800, 6400),
        limitKmh: 70,
        sourceIds: [_list.id],
      ),
      EnforcementItem(
        id: 'red',
        kind: EnforcementKind.camera,
        category: 'RED_LIGHT',
        country: 'FR',
        position: _at(line, 7400),
        sourceIds: [_list.id],
      ),
    ];
    // 25 m/s fixes along the route, one a second.
    final feed = _PacedFeed(
      drive(
        line,
        stepM: 25,
        start: DateTime.now().toUtc(),
        tick: const Duration(seconds: 1),
        speedMps: 25,
      ),
    );
    var stored = const DrivingAidsSettings(exactIn: {'FR'}).encode();
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(localeCode: _locale, theme: ThemePreference.light);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          cacheDatabaseProvider.overrideWithValue(CacheDatabase(NativeDatabase.memory())),
          userDatabaseProvider.overrideWithValue(UserDatabase(NativeDatabase.memory())),
          initialSettingsProvider.overrideWithValue(
            _theme == 'dark' ? settings.copyWith(theme: ThemePreference.dark) : settings,
          ),
          basemapTemplatesProvider.overrideWithValue(basemap),
          locationPermissionsProvider.overrideWithValue(_Granted()),
          notificationAccessProvider.overrideWithValue(const _NoNotifications()),
          routeServiceProvider.overrideWithValue(_Once(plan)),
          locationFeedProvider.overrideWithValue(feed),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
          enforcementFeedProvider.overrideWithValue(_Placed(items)),
          drivingAidsStoreProvider.overrideWithValue(
            DrivingAidsStore(() async => stored, (v) async => stored = v),
          ),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = _locale == 'en' ? AppLocale.en.buildSync() : AppLocale.fr.buildSync();
    const target = RouteTarget(destination: _to, label: 'A20, Limoges nord', placeId: 'a20');

    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(target)));
    await until(
      tester,
      () =>
          find.byType(WebViewRouteMap).evaluate().isNotEmpty &&
          _map(tester).marks.where((m) => m.kind == RouteMarkKind.camera).length == 3,
      what: 'the cameras on the preview',
    );
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'apercu');
    final fixed = _map(tester).marks.firstWhere((m) => m.id == 'camera:fixed');
    _map(tester).onMarkTap!(fixed.id, at: const Offset(270, 420));
    await shot(tester, 'apercu-fiche');

    await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: route.index,
          target: target,
          words: TranslatedWording(t, DistanceUnits.metric),
        );
    unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    EnforcementAlert? alert() => session()?.aids.alert;
    await until(tester, () => session()?.snapshot != null, what: 'the first fix');

    await until(tester, () => alert()?.id == 'zone', what: 'the zone ahead');
    feed.pace = const Duration(seconds: 1);
    await shot(tester, 'zone');
    feed.pace = const Duration(milliseconds: 60);

    await until(tester, () => alert()?.id == 'fixed', what: 'the camera ahead');
    feed.pace = const Duration(seconds: 1);
    await shot(tester, 'approche');
    await until(tester, () => alert()?.over ?? false, what: 'over its limit');
    await shot(tester, 'depassement');
    _map(tester).onMarkTap!('camera:fixed');
    await shot(tester, 'fiche-guidage');
    await tester.tapAt(const Offset(20, 40));
    await settle(tester, const Duration(seconds: 1));
    feed.pace = const Duration(milliseconds: 60);

    await until(
      tester,
      () => alert()?.id == 'section' && alert()!.averageKmh != null,
      what: 'the average of the section',
    );
    feed.pace = const Duration(seconds: 1);
    await shot(tester, 'troncon');
    feed.pace = const Duration(milliseconds: 60);
    await until(tester, () => session()?.aids.exit != null, what: 'the end of the section');
    feed.pace = const Duration(seconds: 1);
    await shot(tester, 'fin');
    debugPrint(
      'AIDS mode ${session()?.aids.mode} country ${session()?.aids.country} '
      'cameras ${session()?.aids.cameras.length}',
    );
    container.read(guidanceControllerProvider.notifier).stop();
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE');
  });
}
