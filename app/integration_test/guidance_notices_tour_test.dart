import 'dart:async';

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
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The guidance's notices and the stops of "Tout le trajet", against the
/// real API, for screenshots: from Valence to Montélimar through two stops,
/// a new route after a wrong turn and its notice going by itself, the
/// strip of the stops in the overview (a leg framed, a stop taken out and
/// put back), a position that stops coming (folded, then open again when
/// lost), then the same on a phone on its side. Run through
/// `tool/screens/capture.py --test integration_test/guidance_notices_tour_test.dart
/// --api https://api.lunaway.net`.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'avis');

/// Valence, Avenue de Romans.
const _start = LatLng(44.9415, 4.8981);

const _target = RouteTarget(destination: LatLng(44.5581, 4.7508), label: 'Montélimar');

const _stops = [
  RouteStop(position: LatLng(44.7563, 4.8202), label: 'Loriol-sur-Drôme'),
  RouteStop(position: LatLng(44.7010, 4.7967), label: 'Saulce-sur-Rhône'),
];

const _vehicle = Vehicle(
  type: VehicleType.overcab,
  heightM: 3.1,
  widthM: 2.3,
  lengthM: 7,
  weightT: 3.5,
  fuel: FuelType.diesel,
  consumptionL100: 11.5,
);

/// The device at the start until the guidance, then the fixes the tour
/// sends; an error ends the stream, as geolocator's does, and the guidance
/// asks for a new one.
final class _Feed implements LocationFeed {
  StreamController<Fix>? _live;

  @override
  Future<Fix?> current() async =>
      Fix(position: _start, accuracyM: 5, at: DateTime.now().toUtc(), speedMps: 0);

  @override
  Stream<Fix> guidance(BackgroundNotice notice) {
    final live = StreamController<Fix>();
    _live = live;
    return live.stream;
  }

  void send(Fix fix) => _live?.add(fix);

  void fail() {
    final live = _live;
    _live = null;
    live?.addError(StateError('location turned off'));
    unawaited(live?.close());
  }
}

/// The permission to notify, out of the tour: its system dialog would wait
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
  Duration timeout = const Duration(seconds: 60),
  String what = 'a condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A capture now: the notices come and go by the second.
Future<void> shot(WidgetTester tester, String name, {Duration before = Duration.zero}) async {
  await settle(tester, before);
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 900));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the guidance notices and its stops, from Valence to Montélimar', (tester) async {
    final feed = _Feed();
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
          locationFeedProvider.overrideWithValue(feed),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    // The route settings from a clean slate: an earlier run leaves its own.
    await container.read(routeSettingsStoreProvider).save(const NavigationSettings());
    container.invalidate(routeSettingsControllerProvider);
    GuidanceSession? session() => container.read(guidanceControllerProvider);

    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(_target)));
    final start = find.text(t.navigation.preview.start);
    await until(tester, () => start.evaluate().isNotEmpty, what: 'the route');
    // The two stops, as the preview's map would add them; the route asked
    // again through them.
    container.read(routeStopsControllerProvider(_target).notifier).set(_stops);
    bool startable() {
      final button = find.ancestor(of: start, matching: find.bySubtype<FilledButton>());
      return button.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(button.first).onPressed != null;
    }

    await settle(tester, const Duration(seconds: 1));
    await until(tester, startable, what: 'the route through the stops');
    await shot(tester, '00-apercu', before: const Duration(seconds: 3));
    await tester.tap(start);
    await until(tester, () => session() != null, what: 'the guidance');

    // Drives [metres] of the route in use, from [from] metres along it,
    // [stepM] at a time, a fix every [every].
    var at = DateTime.now().toUtc();
    Future<double> driveOn(
      double from,
      double metres, {
      double stepM = 25,
      Duration every = const Duration(milliseconds: 250),
    }) async {
      final line = session()!.route.line;
      final fixes = drive(
        line,
        stepM: stepM,
        start: at,
        tick: const Duration(seconds: 1),
        speedMps: 25,
      );
      final skip = (from / stepM).round();
      for (final f in fixes.skip(skip).take((metres / stepM).round())) {
        feed.send(
          Fix(
            position: f.position,
            accuracyM: 5,
            at: DateTime.now().toUtc(),
            courseDeg: f.courseDeg,
            speedMps: f.speedMps,
          ),
        );
        await settle(tester, every);
      }
      at = DateTime.now().toUtc();
      return from + metres;
    }

    var along = await driveOn(0, 1500);
    await shot(tester, '01-guidage');

    // A wrong turn: 400 m beside the road, then a new route.
    final before = session()!.reroutes;
    final last = session()!.lastFix!;
    for (var i = 1; i <= 4 && session()!.reroutes == before; i++) {
      feed.send(
        Fix(
          position: LatLng(last.position.lat + 0.0036 + i * 0.0002, last.position.lon),
          accuracyM: 5,
          at: DateTime.now().toUtc(),
          courseDeg: 0,
          speedMps: 12,
        ),
      );
      await settle(tester, const Duration(milliseconds: 400));
      if (session()!.phase == GuidancePhase.offRoute) {
        debugPrint('SHOT $_tag-02-hors-itineraire');
        await settle(tester, const Duration(milliseconds: 300));
      }
    }
    await until(tester, () => session()!.reroutes > before, what: 'the new route');
    await shot(tester, '03-nouvel-itineraire', before: const Duration(milliseconds: 400));
    // Said for a moment, gone by itself: the vehicle drives on meanwhile.
    along = await driveOn(0, 600, every: const Duration(milliseconds: 500));
    await shot(tester, '04-avis-parti');

    // The overview and its stops.
    await tester.tap(find.byTooltip(t.navigation.guidance.overview));
    await shot(tester, '05-tout-le-trajet', before: const Duration(seconds: 2));
    final first = find.textContaining('${_stops.first.label} ·');
    await tester.ensureVisible(first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(first);
    await shot(tester, '06-troncon-1', before: const Duration(seconds: 2));
    await tester.tap(find.text(t.navigation.legs.all));
    await settle(tester, const Duration(seconds: 1));
    final cross = find.byTooltip(t.navigation.legs.remove(number: '1', name: _stops.first.label!));
    await tester.ensureVisible(cross);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(cross);
    await shot(tester, '07-etape-retiree', before: const Duration(milliseconds: 600));
    await tester.tap(find.text(t.common.undo));
    await until(tester, () => session()!.stops.length == 2, what: 'the stop back');
    await shot(tester, '08-etape-remise', before: const Duration(seconds: 2));
    await tester.tap(find.byTooltip(t.navigation.guidance.recenter));
    await settle(tester, const Duration(seconds: 1));
    along = await driveOn(along, 300);

    // No position for a minute: a state that lasts, folded, then graver.
    await settle(tester, const Duration(seconds: 62));
    final stale = find.textContaining(
      t.navigation.guidance.positionStale(minutes: '1').split(':').first,
    );
    await until(tester, () => stale.evaluate().isNotEmpty, what: 'the old position');
    await shot(tester, '09-position-ancienne');
    await tester.tap(stale.first);
    await shot(tester, '10-avis-replie', before: const Duration(milliseconds: 600));
    feed.fail();
    final lost = find.text(t.navigation.guidance.positionLost);
    await until(
      tester,
      () => lost.evaluate().isNotEmpty,
      what: 'the lost position',
      timeout: const Duration(seconds: 40),
    );
    await shot(tester, '11-position-perdue-rouvert');
    // The position comes back: the state is over, its notice goes.
    await until(tester, () => feed._live != null, what: 'the position asked again');
    along = await driveOn(along, 300);
    await shot(tester, '12-etat-fini');

    // The same on a phone on its side.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await settle(tester, const Duration(seconds: 3));
    along = await driveOn(along, 300);
    await shot(tester, '13-paysage-guidage');
    await tester.tap(find.byTooltip(t.navigation.guidance.overview));
    await shot(tester, '14-paysage-tout-le-trajet', before: const Duration(seconds: 2));
    final crossSide = find.byTooltip(
      t.navigation.legs.remove(number: '1', name: _stops.first.label!),
    );
    await tester.ensureVisible(crossSide);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(crossSide);
    await shot(tester, '15-paysage-etape-retiree', before: const Duration(milliseconds: 600));
    await tester.tap(find.text(t.common.undo));
    await until(tester, () => session()!.stops.length == 2, what: 'the stop back');
    await SystemChrome.setPreferredOrientations([]);
    await settle(tester, const Duration(seconds: 2));
    container.read(guidanceControllerProvider.notifier).stop();
    await settle(tester, const Duration(seconds: 1));
    debugPrint('TOUR DONE');
  });
}
