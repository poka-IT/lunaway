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

import 'fixtures/drive_routes.dart';

/// A drive in the real app on a real phone (the Android emulator): the
/// guidance library the build hook compiled, the real map, the platform's
/// voice, the screen kept on. The position is simulated along routes
/// recorded from the Lunaway API, at 12 m/s: ten times real speed between
/// the moments the test looks at, real speed around them, so a capture
/// shows what a driver sees (an alert lasts ten seconds of the drive):
///
/// 1. the preview of the Limoges drive, "C'est parti !";
/// 2. 680 m in, a closure of Port du Naveix appears in the road events
///    (no position sent): a new route avoids it, from the vehicle;
/// 3. the driver then misses the right turn into Rue Aristide Briand: off
///    the route, a new route from where the vehicle is;
/// 4. the arrival card.
///
///   fvm flutter test integration_test/navigation_drive_test.dart -d emulator-5554 --flavor store
///
/// `tool/screens/capture.py --test integration_test/navigation_drive_test.dart`
/// captures the screen at each `SHOT` line.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'drive');

const _vehicle = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.3,
  widthM: 2.3,
  lengthM: 7.4,
  weightT: 3.5,
);

Future<RoutePlan> _plan(String body) {
  final data = (jsonDecode(body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  return withShapes(routePlanFromJson(data['route'] as Map<String, dynamic>));
}

/// The first `metres` of `line`, cut at that distance.
List<LatLng> _upTo(List<LatLng> line, double metres) {
  final out = <LatLng>[line.first];
  var along = 0.0;
  for (var i = 1; i < line.length; i++) {
    final d = line[i - 1].distanceTo(line[i]);
    if (along + d >= metres) {
      out.add(_at(line, metres));
      return out;
    }
    along += d;
    out.add(line[i]);
  }
  return out;
}

/// The point `metres` along `line`.
LatLng _at(List<LatLng> line, double metres) {
  var along = 0.0;
  for (var i = 1; i < line.length; i++) {
    final d = line[i - 1].distanceTo(line[i]);
    if (along + d >= metres) {
      final t = d == 0 ? 0.0 : (metres - along) / d;
      final p = line[i - 1];
      final q = line[i];
      return LatLng(p.lat + (q.lat - p.lat) * t, p.lon + (q.lon - p.lon) * t);
    }
    along += d;
  }
  return line.last;
}

/// The routes in the order the guidance asks for them.
final class _Routes implements RouteService {
  new(this.plans);

  final List<RoutePlan> plans;
  final List<RouteRequest> requests = [];

  @override
  Future<RoutePlan> route(RouteRequest request) async {
    requests.add(request);
    return plans[(requests.length - 1).clamp(0, plans.length - 1)];
  }

  @override
  // An answer that fails, as a server without the query: the preview then
  // leaves the trip to the route request (a synchronous throw would fail it).
  Future<RoutingInfo> info() async => throw UnimplementedError();
}

/// No road event, then the closure once the test publishes it.
final class _Events implements RoadEventsSource {
  RoadEventsDelta? next;
  final List<String?> cursors = [];

  @override
  Future<RoadEventsDelta> delta({String? cursor}) async {
    cursors.add(cursor);
    final d = next;
    next = null;
    return d ?? RoadEventsDelta(cursor: 'c${cursors.length}', asOf: DateTime.now().toUtc());
  }
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

const _fast = Duration(milliseconds: 100);
const _real = Duration(seconds: 1);

/// The permission to notify, out of the drive: its system dialog would wait
/// for a tap no test gives.
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

Future<void> until(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 90),
  String what = 'a condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(
  WidgetTester tester,
  String name, {
  Duration wait = const Duration(milliseconds: 800),
}) async {
  await settle(tester, wait);
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 1200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a drive with a closure ahead and a missed turn, to the arrival', (tester) async {
    final first = await _plan(limogesDrive);
    final detour = await _plan(closureDetour);
    final missed = await _plan(missedTurn);
    final routes = _Routes([first, detour, missed]);
    final events = _Events();

    // The path driven: the Limoges route to Avenue des Bénédictins, the
    // detour round the closure until the turn into Rue Aristide Briand,
    // straight on past it, then the route from there.
    final a = first.routes.single.line;
    final b = detour.routes.single.line;
    final c = missed.routes.single.line;
    const turnAt = 1258.0;
    final path = [..._upTo(a, 690), ..._upTo(b, turnAt), ...c];
    final feed = _PacedFeed(
      drive(
        path,
        stepM: 12,
        start: DateTime.utc(2026, 10, 6, 9),
        tick: const Duration(seconds: 1),
        speedMps: 12,
      ),
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
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
          routeServiceProvider.overrideWithValue(routes),
          locationFeedProvider.overrideWithValue(feed),
          roadEventsSourceProvider.overrideWithValue(events),
          roadEventsPollProvider.overrideWithValue(const Duration(hours: 1)),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = container.read(settingsProvider).localeCode == 'en'
        ? AppLocale.en.buildSync()
        : AppLocale.fr.buildSync();
    // The route settings from a clean slate: an earlier run leaves its own.
    await container.read(routeSettingsStoreProvider).save(const NavigationSettings());
    container.invalidate(routeSettingsControllerProvider);

    unawaited(
      container
          .read(routerProvider)
          .push(
            NavigationRoutes.previewOf(
              const RouteTarget(
                destination: LatLng(45.84510, 1.28637),
                label: 'Rue Maurice Utrillo',
                placeId: 'utrillo',
              ),
            ),
          ),
    );
    final start = find.text(t.navigation.preview.start);
    await until(tester, () => start.evaluate().isNotEmpty, what: 'the preview');
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'preview');
    expect(routes.requests.single.vehicle.heightM, 3.3);

    // The fuel list asks the API for the stations around the route: real
    // stations of Limoges, their prices of the day.
    await tester.tap(find.text(t.navigation.onTheWay.title));
    await until(
      tester,
      () =>
          find.text(t.navigation.fuel.add).evaluate().isNotEmpty ||
          find.text(t.navigation.fuel.empty).evaluate().isNotEmpty ||
          find.text(t.navigation.fuel.failed).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      what: 'the stations',
    );
    debugPrint('FUEL STATIONS ${find.text(t.navigation.fuel.add).evaluate().length}');
    await shot(tester, 'fuel');
    await tester.tapAt(const Offset(20, 40));
    await settle(tester, const Duration(seconds: 1));

    await tester.tap(start);
    await settle(tester, const Duration(seconds: 1));
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    await until(tester, () => session()?.snapshot != null, what: 'the first fix');
    expect(events.cursors, [null], reason: 'road events asked at once, without a position');

    double along() => session()?.snapshot?.distanceAlongM ?? 0;
    await until(tester, () => along() >= 400, what: '400 m along');
    feed.pace = _real;
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'guidance');
    feed.pace = _fast;

    // 2. The closure, published as the vehicle nears the detour's start:
    // the detour leaves this route about 100 m further on.
    await until(tester, () => along() >= 660, what: '660 m along');
    feed.pace = _real;
    await until(tester, () => along() >= 680, what: '680 m along');
    final closure = [for (var m = 1500.0; m <= 1900; m += 25) _at(a, m)];
    events.next = RoadEventsDelta(
      cursor: 'c-closure',
      asOf: DateTime.now().toUtc(),
      upserts: [
        RoadEvent(
          id: 'dir-naveix',
          eventClass: RoadEventClass.closure,
          placement: RoadEventPlacement.matched,
          source: 'dir',
          mayBlock: true,
          lines: [closure],
        ),
      ],
      sources: [RoadEventSourceStatus(id: 'dir', fresh: true, lastReadAt: DateTime.now().toUtc())],
    );
    unawaited(container.read(guidanceControllerProvider.notifier).refreshRoadEvents());
    await until(tester, () => session()?.reroutes == 1, what: 'the closure detour');
    expect(session()!.plan, same(detour));
    final reroute = session()!.alert;
    expect(reroute, isA<ReroutedAlert>());
    expect((reroute! as ReroutedAlert).reason, RerouteReason.roadEvent);
    await shot(tester, 'closure-detour');
    feed.pace = _fast;

    // 3. The missed turn: off the route, then a new route from there.
    await until(tester, () => along() >= 1200, what: 'the turn into Rue Aristide Briand');
    feed.pace = _real;
    await until(
      tester,
      () => session()?.phase == GuidancePhase.offRoute || (session()?.reroutes ?? 0) >= 2,
      what: 'off the route',
    );
    if (session()?.phase == GuidancePhase.offRoute) {
      await shot(tester, 'off-route', wait: const Duration(milliseconds: 100));
    }
    await until(tester, () => session()?.reroutes == 2, what: 'the new route');
    expect(session()!.plan, same(missed));
    expect(routes.requests.last.headingDeg, isNotNull);
    expect(session()!.alert, isA<ReroutedAlert>());
    await shot(tester, 'rerouted', wait: const Duration(seconds: 2));
    feed.pace = _fast;

    // 4. The arrival.
    await until(
      tester,
      () => session()?.phase == GuidancePhase.arrived,
      timeout: const Duration(seconds: 180),
      what: 'the arrival',
    );
    await shot(tester, 'arrival');
    await tester.tap(find.text(t.navigation.guidance.done));
    await settle(tester, const Duration(seconds: 1));
    expect(session(), isNull);
    debugPrint('DRIVE DONE');
  });
}
