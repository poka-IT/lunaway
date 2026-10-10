import 'dart:async';
import 'dart:math' as math;

import 'package:drift_flutter/drift_flutter.dart';
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
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The order of the route map's layers, seen where it matters: places whose
/// small pin lies on or right beside the route line, on a real route of the
/// production API, in the route preview and in guidance. From Plouharnel
/// to Port Haliguen (Quiberon) by the D768 and Penthièvre, where the API
/// knows parkings, a picnic area and a service point a few metres from the
/// line. The vehicle drives the route, simulated: fast between the places,
/// real time from 300 m before each, a capture when the place is 110 m
/// then 55 m ahead (inside the stretch kept free of rich marks, so the
/// place is drawn as a small pin). At the two last places the vehicle
/// stops for a third capture in the display "Points discrets".
///
/// The places are found by the test itself (`Query.places` over the route's
/// box, then their distance to the line), so a place added or moved near
/// the road changes the moments, never the code. Each capture is named and
/// described in `<tag>-moments.txt` (a `WRITE` line).
///
/// On the web, `tool/screens/tour_web.py` forwards the places' and the
/// points' tiles, so the pins are drawn:
///
///     python3 tool/screens/tour_web.py --test integration_test/layer_order_tour_test.dart \
///         --viewport 412x732 --locale fr --out ../plan/screenshots/ordre-calques/web
///
/// On Android, with an application id of its own beside the others on a
/// shared emulator:
///
///     ORG_GRADLE_PROJECT_testIdSuffix=.calques python3 tool/screens/capture.py \
///         --device android:emulator-5554 --size 1080x1920 \
///         --test integration_test/layer_order_tour_test.dart --api https://api.lunaway.net \
///         --out ../plan/screenshots/ordre-calques/android --define LUNAWAY_TOUR_TAG=android
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'calques');

/// Near Plouharnel, on the D768 towards the Quiberon peninsula.
const _from = LatLng(47.5870, -3.1240);

const _target = RouteTarget(destination: LatLng(47.4878, -3.0995), label: 'Port Haliguen');

const _vehicle = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.1,
  widthM: 2.35,
  lengthM: 7.4,
  weightT: 3.5,
);

/// 50 km/h: the guidance camera's zoom (16.7) and the stretch kept free
/// ahead (8 s, 120 m) of a drive through a town.
const _speedMps = 14.0;

/// A place this close to the line has its pin on it or touching it at the
/// guidance's zoom: the line and its casing are about 10 px wide, a pin
/// about 20 px high, a pixel about a metre.
const _nearLineM = 18.0;

/// Where the captures are taken, metres before the place along the route.
const _aheads = [110.0, 55.0];

/// The pace slows to real time this far before a place, so the camera has
/// settled behind the vehicle when the capture comes.
const _slowFromM = 300.0;

const _fast = Duration(milliseconds: 50);
const _real = Duration(seconds: 1);

/// The fixes of the drive, one per simulated second, at a pace the test
/// sets; [held] keeps the next fix back while the display changes, so two
/// captures show the same spot.
final class _PacedFeed implements LocationFeed {
  new(this.fixes);

  final List<Fix> fixes;
  Duration pace = _fast;
  bool held = false;

  @override
  Future<Fix?> current() async => fixes.first;

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    for (final f in fixes) {
      await Future<void>.delayed(pace);
      while (held) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      yield f;
    }
  }
}

/// The route of the drive, asked once: the preview and the guidance draw
/// the very line the moments were measured on.
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

/// The route settings in memory: the device's own are left alone.
final class _Settings implements RouteSettingsStore {
  new(this._value);

  NavigationSettings _value;

  @override
  Future<NavigationSettings> load() async => _value;

  @override
  Future<void> save(NavigationSettings settings) async => _value = settings;
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

/// A place near the line: where it is along the route, and how far from it.
final class _Near {
  const new({required this.place, required this.alongM, required this.offM});

  final PlaceSummary place;
  final double alongM;
  final double offM;

  String describe() =>
      '${place.kind.name}${place.name == null ? '' : ' "${place.name}"'} '
      '${offM.toStringAsFixed(1)} m from the line, ${alongM.round()} m along';
}

/// Where [p] falls on [line]: metres along, and metres from it. A plane
/// around [p] is close enough over a few hundred metres.
(double, double) _project(List<LatLng> line, LatLng p) {
  final kx = 111320.0 * math.cos(p.lat * math.pi / 180);
  const ky = 110540.0;
  (double, double) xy(LatLng q) => ((q.lon - p.lon) * kx, (q.lat - p.lat) * ky);
  var best = double.infinity;
  var bestAlong = 0.0;
  var along = 0.0;
  for (var i = 1; i < line.length; i++) {
    final (ax, ay) = xy(line[i - 1]);
    final (bx, by) = xy(line[i]);
    final dx = bx - ax;
    final dy = by - ay;
    final length2 = dx * dx + dy * dy;
    final t = length2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / length2).clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final d = math.sqrt(cx * cx + cy * cy);
    final length = math.sqrt(length2);
    if (d < best) {
      best = d;
      bestAlong = along + t * length;
    }
    along += length;
  }
  return (bestAlong, best);
}

/// The places the API knows in the route's box, every page.
Future<List<PlaceSummary>> _placesAround(GraphQLClient client, List<LatLng> line) async {
  final bbox = {
    'south': line.map((p) => p.lat).reduce(math.min) - 0.003,
    'west': line.map((p) => p.lon).reduce(math.min) - 0.004,
    'north': line.map((p) => p.lat).reduce(math.max) + 0.003,
    'east': line.map((p) => p.lon).reduce(math.max) + 0.004,
  };
  final out = <PlaceSummary>[];
  String? after;
  do {
    final page = await client.execute(nearbyPlacesOperation, {
      'bbox': bbox,
      'first': 200,
      'after': ?after,
    });
    out.addAll(page.places);
    after = page.hasNextPage ? page.endCursor : null;
  } while (after != null);
  return out;
}

/// Real time passing. The frames are drawn as the app asks for them
/// ([LiveTestWidgetsFlutterBindingFramePolicy.fullyLive]): a pump would wait
/// for a frame a hidden window does not draw, and the drive would stop.
Future<void> settle(Duration duration) => Future<void>.delayed(duration);

Future<void> until(
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await settle(const Duration(milliseconds: 100));
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('pins beside the route line, in the preview and in guidance', (tester) async {
    const notes = '$_tag-moments.txt';
    void note(String line) => debugPrint('WRITE $notes $line');

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final client = GraphQLClient(
      endpoint: config.graphqlEndpoint,
      httpClient: http.Client(),
      userAgent: AppConfig.userAgent('tour-calques'),
    );
    final plan = await GraphQLRouteService(client).route(
      RouteRequest(
        origin: _from,
        destination: _target.destination,
        vehicle: checkVehicle(_vehicle).profile!,
        avoid: const AvoidOptions(),
        language: _locale == 'en' ? RouteLanguage.en : RouteLanguage.fr,
      ),
    );
    final route = plan.routes.first;
    final line = route.line;
    debugPrint('ROUTE ${route.distanceM.round()} m, ${line.length} points');

    // The places whose pin the line may cover, in the order the vehicle
    // meets them; one moment per stretch of 200 m, the others in view.
    final near = <_Near>[
      for (final p in await _placesAround(client, line))
        if (_project(line, LatLng(p.lat, p.lon)) case (final along, final off)
            when off <= _nearLineM && along > _slowFromM && along < route.distanceM - 150)
          _Near(place: p, alongM: along, offM: off),
    ]..sort((a, b) => a.alongM.compareTo(b.alongM));
    final moments = <_Near>[];
    for (final n in near) {
      debugPrint('NEAR ${n.describe()}');
      if (moments.isEmpty || n.alongM - moments.last.alongM > 200) moments.add(n);
    }
    if (moments.isEmpty) throw TestFailure('no place within $_nearLineM m of the route');
    // The display "Points discrets" at the last two moments.
    final dotsFrom = math.max(0, moments.length - 2);

    final feed = _PacedFeed(
      drive(
        line,
        stepM: _speedMps,
        start: DateTime.now().toUtc(),
        tick: const Duration(seconds: 1),
        speedMps: _speedMps,
      ),
    );
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    // Stores of their own, beside the device's: nothing of a user's is read
    // or changed.
    DriftWebOptions web() => DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    );
    final cache = CacheDatabase(
      driftDatabase(
        name: 'lunaway_calques_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
    );
    final user = UserDatabase(
      driftDatabase(
        name: 'lunaway_user_calques_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: web(),
      ),
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
          // The guidance's own choice of places (every place, in photos),
          // the legend already seen so it does not cover the map.
          routeSettingsStoreProvider.overrideWithValue(
            _Settings(const NavigationSettings(legendSeen: true)),
          ),
          // One poll of the road events per drive.
          roadEventsPollProvider.overrideWithValue(const Duration(hours: 2)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocaleUtils.parse(_locale).buildSync();
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    double along() => session()?.snapshot?.distanceAlongM ?? 0;

    Future<void> shot(String name, String what) async {
      await settle(const Duration(milliseconds: 800));
      debugPrint('SHOT $_tag-$name');
      note('$_tag-$name | $what');
      await settle(const Duration(milliseconds: 1500));
    }

    Future<void> look(GuidanceLook look) async {
      await container
          .read(routeSettingsControllerProvider.notifier)
          .setGuidancePlaces(GuidancePlaces(look: look));
    }

    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(_target)));
    final start = find.text(t.navigation.preview.start);
    await until(() => start.evaluate().isNotEmpty, what: 'the preview');
    // The places along the route, their photos and the map's tiles.
    await settle(const Duration(seconds: 12));
    await shot(
      'apercu-00',
      'aperçu cadré sur le trajet, ${(route.distanceM / 1000).toStringAsFixed(1)} km',
    );

    await tester.tap(start);
    await until(() => session()?.snapshot != null, what: 'the first fix');
    // The guidance's tiles and places around the start.
    feed.held = true;
    await settle(const Duration(seconds: 6));
    feed.held = false;

    var index = 0;
    for (final (i, m) in moments.indexed) {
      final others = near.where((n) => n != m && (n.alongM - m.alongM).abs() <= 200);
      debugPrint('MOMENT ${m.describe()}${others.isEmpty ? '' : ', with ${others.length} more'}');
      await until(
        () => along() >= m.alongM - _slowFromM || session() == null,
        what: 'the approach of ${m.describe()}',
      );
      feed.pace = _real;
      for (final ahead in _aheads) {
        await until(() => along() >= m.alongM - ahead, what: '${ahead.round()} m before');
        final actual = m.alongM - along();
        final what =
            '${m.place.kind.name}${m.place.name == null ? '' : ' « ${m.place.name} »'} à '
            '${m.offM.toStringAsFixed(1).replaceAll('.', ',')} m du tracé, '
            '${actual.round()} m devant le véhicule'
            '${others.isEmpty ? '' : ', et ${others.map((o) => '${o.place.kind.name} à ${o.offM.toStringAsFixed(1).replaceAll('.', ',')} m').join(', ')}'}';
        index++;
        if (i >= dotsFrom && ahead == _aheads.last) {
          // The same spot in both displays: the vehicle waits while the
          // display changes, well under the time a position counts as lost.
          feed.held = true;
          await shot('guidage-${_two(index)}', '$what, affichage Photos');
          await look(GuidanceLook.dots);
          await settle(const Duration(seconds: 2));
          await shot('guidage-${_two(index)}-points', '$what, affichage Points discrets');
          await look(GuidanceLook.photos);
          feed.held = false;
        } else {
          await shot('guidage-${_two(index)}', '$what, affichage Photos');
        }
      }
      feed.pace = _fast;
    }

    container.read(guidanceControllerProvider.notifier).stop();
    await settle(const Duration(seconds: 1));
    container.read(selectionProvider.notifier).select(null);
    await cache.close();
    await user.close();
    expect(index, moments.length * _aheads.length);
    debugPrint('TOUR DONE');
  });
}
