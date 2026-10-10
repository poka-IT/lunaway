import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
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
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/data/web_voice.dart'
    if (dart.library.js_interop) 'package:lunaway/features/navigation/data/web_voice_web.dart';
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

/// The guidance on a real route with its fixes far apart, and with a jump
/// of the position: Perpignan to Figueres without tolls by the D 900, the
/// route of the production API, the real guidance library (native, or
/// WebAssembly in a browser), the platform's voice. A browser's position
/// at 25 m/s a second, then one that jumps 900 m, froze the guidance on
/// "0 m" after the fork of the Pont Sergent Rodolphe Penon and on the
/// roundabout of the Route du Perthus.
///
/// Each sentence handed to the voice is written to a transcript (`WRITE`)
/// with the vehicle's true distance along the route and the step the
/// guidance shows; the screen is captured at each `SHOT`.
///
///     python3 tool/screens/tour_web.py --test integration_test/step_advance_tour_test.dart \
///         --viewport 390x844 --out ../data/tmp/step-tour \
///         --define LUNAWAY_STEP_SCENARIO=fourche-25
///     python3 tool/screens/capture.py --test integration_test/step_advance_tour_test.dart \
///         --api https://api.lunaway.net --out ../data/tmp/step-tour \
///         --define LUNAWAY_STEP_SCENARIO=saut-900
///
/// Scenarios: `fourche-25` (a fix every 25 m, a second apart, from the
/// start to 3 km), `saut-900` (two fixes a second at 25 m/s to 3.2 km,
/// then from 4.1 km to 5.2 km). One request reaches the API besides the
/// app's own: the route.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'fr-540x960-light');
const _scenario = String.fromEnvironment('LUNAWAY_STEP_SCENARIO', defaultValue: 'fourche-25');

/// The run's name in the files it writes: before or after a change.
const _run = String.fromEnvironment('LUNAWAY_STEP_RUN', defaultValue: 'apres');

const _from = LatLng(42.670001, 2.880037);
const _to = LatLng(42.266461, 2.960676);

const _vehicle = Vehicle(
  type: VehicleType.lowProfile,
  heightM: 2.9,
  widthM: 2.3,
  lengthM: 7,
  weightT: 3.5,
);

/// The fixes of a scenario: where along the route, and the time between
/// two of them.
({List<double> metres, Duration tick}) _plan(String scenario) => switch (scenario) {
  'fourche-25' => (
    metres: [for (double m = 0; m <= 3000; m += 25) m],
    tick: const Duration(seconds: 1),
  ),
  'saut-900' => (
    metres: [
      for (double m = 0; m <= 3200; m += 12.5) m,
      for (var m = 4100.0; m <= 5200; m += 12.5) m,
    ],
    tick: const Duration(milliseconds: 500),
  ),
  _ => throw ArgumentError('unknown scenario $scenario'),
};

/// The route of the drive, asked once.
final class _Once implements RouteService {
  new(this.plan);

  final RoutePlan plan;

  @override
  Future<RoutePlan> route(RouteRequest request) async => plan;

  @override
  Future<RoutingInfo> info() async => throw UnimplementedError();
}

/// The fixes along [line] at [metres], one each [tick] of real time, at
/// 25 m/s.
final class _Drive implements LocationFeed {
  new(this.line, this.metres, this.tick) {
    _cum.add(0);
    for (var i = 1; i < line.length; i++) {
      _cum.add(_cum.last + line[i - 1].distanceTo(line[i]));
    }
  }

  final List<LatLng> line;
  final List<double> metres;
  final Duration tick;
  final List<double> _cum = [];

  /// Where the last fix sent was, metres along.
  double along = 0;

  (LatLng, double) at(double m) {
    var lo = 0;
    var hi = _cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (_cum[mid] <= m) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = line[lo];
    final b = line[hi];
    final d = _cum[hi] - _cum[lo];
    final t = d == 0 ? 0.0 : ((m - _cum[lo]) / d).clamp(0.0, 1.0);
    return (LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t), bearing(a, b));
  }

  @override
  Future<Fix?> current() async => Fix(position: line.first, accuracyM: 5, at: DateTime.now());

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    for (final m in metres) {
      await Future<void>.delayed(tick);
      final (p, course) = at(m);
      along = m;
      yield Fix(
        position: p,
        accuracyM: 5,
        at: DateTime.now().toUtc(),
        courseDeg: course,
        speedMps: 25,
      );
    }
  }
}

/// The platform's voice, every sentence written down with where the
/// vehicle was.
final class _RecordingVoice implements VoiceOutput {
  new(this._inner, this._write);

  final VoiceOutput _inner;
  final void Function(String text, {required bool said}) _write;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    final readiness = await _inner.prepare(language);
    debugPrint('VOICE ${language.speechTag} $readiness');
    return readiness;
  }

  @override
  bool get chimes => _inner.chimes;

  @override
  Future<bool> say(String text, {bool chime = false}) async {
    var ok = false;
    try {
      ok = await _inner.say(text, chime: chime);
    } finally {
      _write(text, said: ok);
    }
    return ok;
  }

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<bool> installVoices() async => false;
}

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

Future<void> settle(Duration duration) => Future<void>.delayed(duration);

Future<void> until(bool Function() done, {required String what}) async {
  final end = DateTime.now().add(const Duration(minutes: 3));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('timed out waiting for $what');
    await settle(const Duration(milliseconds: 100));
  }
}

String _m(double m) => '${m.round()} m';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('a real route driven with fixes far apart, then a jump, and heard', (tester) async {
    final plan0 = _plan(_scenario);
    final parts = _tag.split('-');
    final device = switch (defaultTargetPlatform) {
      _ when kIsWeb => '',
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => '',
    };
    final suffix = '$device${parts.length > 1 ? parts[1] : 'size'}';
    final transcript = 'phrases-$_scenario-$_run-$suffix.txt';
    void write(String line) => debugPrint('WRITE $transcript $line');

    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final client = GraphQLClient(
      endpoint: config.graphqlEndpoint,
      httpClient: http.Client(),
      userAgent: AppConfig.userAgent('tour-step-advance'),
    );
    final plan = await GraphQLRouteService(client).route(
      RouteRequest(
        origin: _from,
        destination: _to,
        vehicle: checkVehicle(_vehicle).profile!,
        avoid: const AvoidOptions(tolls: true),
        language: RouteLanguage.fr,
      ),
    );
    final route = plan.routes.first;
    debugPrint('ROUTE $_scenario ${route.distanceM.round()} m, ${route.steps.length} steps');
    final drive = _Drive(route.line, plan0.metres, plan0.tick);
    GuidanceSession? Function() session = () => null;
    final recorder = _RecordingVoice(kIsWeb ? browserVoice() : PlatformVoiceOutput(), (
      text, {
      required said,
    }) {
      final s = session();
      final snap = s?.snapshot;
      write(
        '${_m(drive.along)} | moteur ${snap == null ? '-' : _m(snap.distanceAlongM)} | '
        'étape ${snap?.stepIndex ?? '-'} | ${text.isEmpty ? '(signal seul)' : text}'
        '${said ? '' : ' | non dite'}',
      );
    });
    write('# $_scenario ($_run) : Perpignan vers Figueres sans péage, ${_m(route.distanceM)}');
    write('# position vraie | position du guidage | étape | phrase');

    final basemap = await BasemapTemplates.load();
    final cache = CacheDatabase(
      driftDatabase(
        name: 'lunaway_step_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );
    final user = UserDatabase(
      driftDatabase(
        name: 'lunaway_user_step_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          cacheDatabaseProvider.overrideWithValue(cache),
          userDatabaseProvider.overrideWithValue(user),
          initialSettingsProvider.overrideWithValue(const AppSettings(localeCode: _locale)),
          basemapTemplatesProvider.overrideWithValue(basemap),
          locationPermissionsProvider.overrideWithValue(_Granted()),
          notificationAccessProvider.overrideWithValue(const _NoNotifications()),
          routeServiceProvider.overrideWithValue(_Once(plan)),
          locationFeedProvider.overrideWithValue(drive),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
          voiceOutputProvider.overrideWithValue(recorder),
          routeSettingsStoreProvider.overrideWithValue(
            _Settings(const NavigationSettings(avoid: AvoidOptions(tolls: true), legendSeen: true)),
          ),
          drivingAidsStoreProvider.overrideWithValue(
            DrivingAidsStore(() async => null, (_) async {}),
          ),
          roadEventsPollProvider.overrideWithValue(const Duration(hours: 2)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocale.fr.buildSync();
    session = () => container.read(guidanceControllerProvider);

    final shots = <String>{};
    Future<void> shot(String moment) async {
      if (!shots.add(moment)) return;
      debugPrint('SHOT $_scenario-$moment-$_run-$suffix');
      await settle(const Duration(milliseconds: 600));
    }

    const target = RouteTarget(destination: _to, label: 'Figueres', placeId: 'step-tour');
    await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: route.index,
          target: target,
          words: TranslatedWording(t, DistanceUnits.metric),
        );
    unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
    await until(() => session()?.snapshot != null, what: 'the first fix');

    // The fixes run out at the end of the scenario; captured at the fork,
    // after the jump, and at the end.
    final last = plan0.metres.last;
    var lastStep = -1;
    while (drive.along < last) {
      await settle(const Duration(milliseconds: 100));
      final snap = session()?.snapshot;
      if (snap == null) continue;
      if (snap.stepIndex != lastStep) {
        lastStep = snap.stepIndex;
        write(
          '${_m(drive.along)} | moteur ${_m(snap.distanceAlongM)} | étape ${snap.stepIndex} | '
          '(bandeau : ${_m(snap.distanceToManeuverM)} ${snap.banner?.primary ?? '-'})',
        );
      }
      if (drive.along >= 600) await shot('apres-la-fourche');
      if (_scenario == 'saut-900' && drive.along >= 4200) await shot('apres-le-saut');
    }
    await settle(plan0.tick * 2);
    await shot('fin');
    final snap = session()?.snapshot;
    write(
      '# fin : vrai ${_m(drive.along)}, guidage ${snap == null ? '-' : _m(snap.distanceAlongM)}, '
      'étape ${snap?.stepIndex}, bandeau ${snap == null ? '-' : _m(snap.distanceToManeuverM)}',
    );
    container.read(guidanceControllerProvider.notifier).stop();
    await settle(const Duration(seconds: 1));
    await cache.close();
    await user.close();
    debugPrint('TOUR DONE');
  });
}
