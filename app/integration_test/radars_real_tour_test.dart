import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
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
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/data/web_voice.dart'
    if (dart.library.js_interop) 'package:lunaway/features/navigation/data/web_voice_web.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
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

/// Guidances on real routes with the real speed camera data: the route of
/// the production API for a motorhome of 3.5 t, the cameras and zones the
/// API serves for the countries it crosses (`Query.enforcement`, as the app
/// asks for them), the country read on the device by the guidance library.
/// The vehicle drives the route at the road's limit, simulated: fast
/// between the alerts, one fix a second (real time) on the approach, at
/// the start and the end of a zone and around a border, over the limit of
/// the first alert that knows one, so the app says "Ralentissez".
///
/// Each sentence the guidance hands to the voice is said by the platform's
/// voice and written to a transcript (a `WRITE <file> <line>` line that
/// `tool/screens/capture.py` appends to the file in its output folder):
/// simulated time, distance along, country, voice mode, chime, text. The
/// screen is captured at each `SHOT` line: the preview, an alert coming,
/// inside a zone, over the limit, its end, a border.
///
///     python3 tool/screens/capture.py --test integration_test/radars_real_tour_test.dart \
///         --api https://api.lunaway.net --size 540x960 --out ../plan/screenshots/radars \
///         --define LUNAWAY_RADARS_SCENARIO=a7
///
/// Scenarios: [_scenarios]. Two requests per run reach the API besides the
/// app's own (the route once, the cameras of its countries once).
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'fr-540x960-light');
const _scenarioName = String.fromEnvironment('LUNAWAY_RADARS_SCENARIO', defaultValue: 'a7');

const _vehicle = Vehicle(
  type: VehicleType.integrated,
  heightM: 3.1,
  widthM: 2.35,
  lengthM: 7.4,
  weightT: 3.5,
);

/// One drive of the tour.
final class _Scenario {
  const new({
    required this.from,
    required this.to,
    required this.label,
    this.avoid = const AvoidOptions(),
    this.exactIn = const {},
    this.voice = VoiceMode.full,
    this.stopAfterM,
    this.nothing = false,
    this.cycleVoice = false,
  });

  final LatLng from;
  final LatLng to;
  final String label;
  final AvoidOptions avoid;

  /// The countries whose positions the user asked for.
  final Set<String> exactIn;
  final VoiceMode voice;

  /// Where the drive ends before the destination, metres along.
  final double? stopAfterM;

  /// A country where nothing at all may show or be said.
  final bool nothing;

  /// Goes through the three states of the voice button at the end.
  final bool cycleVoice;
}

const _perpignan = LatLng(42.6700, 2.8800);
const _figueres = LatLng(42.2669, 2.9606);

const _scenarios = {
  // France, the A7 from Valence to Orange: danger zones.
  'a7': _Scenario(from: LatLng(44.9180, 4.9010), to: LatLng(44.1300, 4.8350), label: 'Orange'),
  // The same with France's positions asked for.
  'a7-exact': _Scenario(
    from: LatLng(44.9180, 4.9010),
    to: LatLng(44.1300, 4.8350),
    label: 'Orange',
    exactIn: {'FR'},
  ),
  // Spain, the AP-7 from Sant Celoni to Martorell, north of Barcelona.
  'es': _Scenario(from: LatLng(41.6890, 2.4890), to: LatLng(41.4750, 1.9300), label: 'Martorell'),
  // Italy, the A1 from Bologna to Florence.
  'it': _Scenario(from: LatLng(44.4750, 11.2750), to: LatLng(43.8600, 11.1900), label: 'Firenze'),
  // The Netherlands, the A2 from Amsterdam to Utrecht.
  'nl': _Scenario(from: LatLng(52.3300, 4.9200), to: LatLng(52.0900, 5.1100), label: 'Utrecht'),
  // France into Spain by Le Perthus, motorways avoided: the D900, then
  // the N-II.
  'perthus': _Scenario(
    from: _perpignan,
    to: _figueres,
    label: 'Figueres',
    avoid: AvoidOptions(motorways: true),
  ),
  // Switzerland, the A1 from Geneva to Lausanne: nothing at all.
  'ch': _Scenario(
    from: LatLng(46.2100, 6.1420),
    to: LatLng(46.5200, 6.6300),
    label: 'Lausanne',
    nothing: true,
  ),
  // The three voice modes on the first 24 km of the Le Perthus drive.
  'voix-complete': _Scenario(
    from: _perpignan,
    to: _figueres,
    label: 'Figueres',
    avoid: AvoidOptions(motorways: true),
    stopAfterM: 24000,
    cycleVoice: true,
  ),
  'voix-alertes': _Scenario(
    from: _perpignan,
    to: _figueres,
    label: 'Figueres',
    avoid: AvoidOptions(motorways: true),
    voice: VoiceMode.alerts,
    stopAfterM: 24000,
  ),
  'voix-muette': _Scenario(
    from: _perpignan,
    to: _figueres,
    label: 'Figueres',
    avoid: AvoidOptions(motorways: true),
    voice: VoiceMode.muted,
    stopAfterM: 24000,
  ),
};

const _fast = Duration(milliseconds: 35);
const _medium = Duration(milliseconds: 250);
const _real = Duration(seconds: 1);

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

/// A drive along [line], one fix a simulated second, at the speed and the
/// pace the test decides fix by fix.
final class _Drive implements LocationFeed {
  new(this.line, this.limits, {required this.start}) {
    _cum.add(0);
    for (var i = 1; i < line.length; i++) {
      _cum.add(_cum.last + line[i - 1].distanceTo(line[i]));
    }
  }

  final List<LatLng> line;
  final List<SpeedLimitSpan>? limits;
  final DateTime start;
  final List<double> _cum = [];

  /// Real time before the next fix.
  Duration Function() pace = () => _fast;

  /// The speed, km/h, at a distance along where the road's limit is the
  /// second argument.
  double Function(double alongM, double roadKmh) kmh = (_, road) => road - 2;

  /// Added to the limit that matters while the test drives over it.
  double overKmh = 0;

  /// Metres driven, and the time of the last fix.
  double along = 0;
  DateTime at = DateTime.utc(2026);

  double get lengthM => _cum.last;

  /// The road's limit at [m], 80 where the route gives none.
  double roadKmh(double m) {
    for (final s in limits ?? const <SpeedLimitSpan>[]) {
      if (m >= s.fromM && m < s.toM) return s.kmh.toDouble();
    }
    return 80;
  }

  /// The point [m] metres along, with the course of its segment.
  (LatLng, double) _at(double m) {
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
  Future<Fix?> current() async => Fix(position: line.first, accuracyM: 5, at: start);

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    at = start;
    along = 0;
    while (along < lengthM) {
      await Future<void>.delayed(pace());
      final speed = kmh(along, roadKmh(along)).clamp(20.0, 150.0) / 3.6;
      final (p, course) = _at(along);
      yield Fix(position: p, accuracyM: 5, at: at, courseDeg: course, speedMps: speed);
      along += speed;
      at = at.add(const Duration(seconds: 1));
    }
    // Parked at the end: the arrival needs a fix there.
    for (var k = 0; k < 3; k++) {
      await Future<void>.delayed(_real);
      yield Fix(position: line.last, accuracyM: 5, at: at, speedMps: 0);
      at = at.add(const Duration(seconds: 1));
    }
  }
}

/// A sentence handed to the voice.
final class _Said {
  new({
    required this.text,
    required this.chime,
    required this.mode,
    required this.at,
    required this.alongM,
    required this.country,
    required this.started,
  });

  final String text;
  final bool chime;
  final VoiceMode? mode;
  final DateTime? at;
  final double alongM;
  final String? country;
  final DateTime started;
  DateTime? ended;
  bool? said;
}

/// The platform's voice, every sentence written down with the state of
/// the guidance when it started.
final class _RecordingVoice implements VoiceOutput {
  new(this._inner, this._write);

  final VoiceOutput _inner;
  final void Function(_Said said) _write;
  GuidanceSession? Function() session = () => null;
  final List<_Said> records = [];
  _Said? _speaking;
  int overlaps = 0;

  bool get speaking => _speaking != null;

  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async {
    final readiness = await _inner.prepare(language);
    debugPrint('VOICE ${language.speechTag} $readiness chime ${_inner.chimes}');
    return readiness;
  }

  @override
  bool get chimes => _inner.chimes;

  @override
  Future<bool> say(String text, {bool chime = false}) async {
    final s = session();
    if (_speaking != null) {
      overlaps++;
      debugPrint('OVERLAP "${_speaking!.text}" still playing as "$text" starts');
    }
    final record = _Said(
      text: text,
      chime: chime,
      mode: s?.voiceMode,
      at: s?.lastFix?.at,
      alongM: s?.snapshot?.distanceAlongM ?? 0,
      country: s?.aids.country,
      started: DateTime.now(),
    );
    records.add(record);
    _speaking = record;
    var ok = false;
    try {
      ok = await _inner.say(text, chime: chime);
    } finally {
      record
        ..ended = DateTime.now()
        ..said = ok;
      if (identical(_speaking, record)) _speaking = null;
      _write(record);
    }
    return ok;
  }

  /// Cuts the sentence being said: the next one may start at once, the
  /// platform stops this one first.
  @override
  Future<void> stop() async {
    if (_speaking case final s?) debugPrint('VOICE STOP "${s.text}"');
    _speaking = null;
    await _inner.stop();
  }

  @override
  Future<bool> installVoices() async => false;
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

/// Real time passing. The frames are drawn as the app asks for them
/// ([LiveTestWidgetsFlutterBindingFramePolicy.fullyLive]): a pump would wait
/// for a frame the window does not draw while it is hidden, and the drive's
/// watch would stop with it.
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

/// The props of the route map on screen, whichever map the platform has.
RouteMapProps? _map() {
  final web = find.byType(WebViewRouteMap).evaluate();
  if (web.isNotEmpty) return (web.last.widget as WebViewRouteMap).props;
  final gl = find.byType(GlRouteMap).evaluate();
  if (gl.isNotEmpty) return (gl.last.widget as GlRouteMap).props;
  return null;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(DateTime? at) {
  if (at == null) return '--:--:--';
  final l = at.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

String _km(double m) => (m / 1000).toStringAsFixed(1).replaceAll('.', ',');

String _modeName(VoiceMode? mode) => switch (mode) {
  VoiceMode.full => 'complète',
  VoiceMode.alerts => 'alertes',
  VoiceMode.muted => 'muette',
  null => '?',
};

/// The name of an alert's kind in the captures' names.
String _kindOf(EnforcementAlert a) => switch ((a.kind, a.category)) {
  (EnforcementKind.zone, _) => 'zone',
  (_, _) when a.isSection => 'troncon',
  (_, CameraCategory.fixed) => 'radar-fixe',
  (_, CameraCategory.redLight) => 'feu-rouge',
  (_, CameraCategory.section) => 'radar-troncon',
  (_, CameraCategory.levelCrossing) => 'passage-niveau',
  (_, null) => 'radar',
};

/// An alert as the log tells it.
String _describe(EnforcementAlert a) =>
    'alert ${a.id.substring(0, math.min(8, a.id.length))} ${_kindOf(a)} '
    'ahead ${a.aheadM.round()} remaining ${a.remainingM.round()} limit ${a.limitKmh}'
    '${a.limitEstimated ? '?' : ''} inside ${a.inside} over ${a.over}'
    '${a.averageKmh == null ? '' : ' average ${a.averageKmh!.round()}'}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('a real route with the real speed cameras, driven and heard', (tester) async {
    // Whether the window draws: a hidden one leaves the captures stale.
    var frames = 0;
    void count(List<FrameTiming> timings) => frames += timings.length;
    WidgetsBinding.instance.addTimingsCallback(count);
    addTearDown(() => WidgetsBinding.instance.removeTimingsCallback(count));
    final lifecycle = AppLifecycleListener(
      onStateChange: (state) => debugPrint('LIFECYCLE ${state.name}'),
    );
    addTearDown(lifecycle.dispose);
    final scenario = _scenarios[_scenarioName];
    if (scenario == null) throw TestFailure('unknown scenario $_scenarioName');
    final parts = _tag.split('-');
    final size = parts.length > 1 ? parts[1] : 'size';
    final suffix = '$_locale-$size';
    final reference = _locale == 'fr' && size == '540x960';
    final transcript = 'phrases-$_scenarioName${reference ? '' : '-$suffix'}.txt';
    void write(String line) => debugPrint('WRITE $transcript $line');

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await LocaleSettings.setLocale(AppLocaleUtils.parse(_locale));
    final config = AppConfig.fromEnvironment();
    final client = GraphQLClient(
      endpoint: config.graphqlEndpoint,
      httpClient: http.Client(),
      userAgent: AppConfig.userAgent('tour-radars'),
    );
    const language = _locale == 'en' ? RouteLanguage.en : RouteLanguage.fr;
    final plan = await GraphQLRouteService(client).route(
      RouteRequest(
        origin: scenario.from,
        destination: scenario.to,
        vehicle: checkVehicle(_vehicle).profile!,
        avoid: scenario.avoid,
        language: language,
      ),
    );
    final route = plan.routes.first;
    debugPrint(
      'ROUTE $_scenarioName ${route.distanceM.round()} m ${(route.durationS / 60).round()} min, '
      'limits ${route.speedLimits?.length}',
    );

    final drive = _Drive(
      route.line,
      route.speedLimits,
      start: DateTime.now().toUtc().copyWith(second: 0, millisecond: 0, microsecond: 0),
    );
    final recorder = _RecordingVoice(kIsWeb ? browserVoice() : PlatformVoiceOutput(), (s) {
      final seconds = s.ended!.difference(s.started).inMilliseconds / 1000;
      write(
        '${_clock(s.at)} | ${_km(s.alongM)} km | ${s.country ?? '--'} | ${_modeName(s.mode)} | '
        'son ${s.chime ? 'oui' : 'non'} | ${s.text.isEmpty ? '(signal seul)' : s.text} | '
        '${seconds.toStringAsFixed(1).replaceAll('.', ',')} s${s.said ?? false ? '' : ' | coupée'}',
      );
    });
    write(
      '# $_scenarioName : ${scenario.label}, ${_km(route.distanceM)} km, '
      'voix ${_modeName(scenario.voice)}, langue $_locale, taille $size'
      '${scenario.exactIn.isEmpty ? '' : ', positions demandées en ${scenario.exactIn.join(', ')}'}',
    );
    write("# heure simulée | distance | pays | mode | son d'alerte | texte | durée dite");

    var stored = DrivingAidsSettings(exactIn: scenario.exactIn).encode();
    final basemap = await BasemapTemplates.load();
    const settings = AppSettings(
      localeCode: _locale,
      theme: _theme == 'dark' ? ThemePreference.dark : ThemePreference.light,
    );
    // Stores of their own, beside the device's: the speed camera data of
    // the tour never mixes with a user's, and nothing of the user's is
    // changed.
    final cache = CacheDatabase(
      driftDatabase(
        name: 'lunaway_radars_tour',
        native: const DriftNativeOptions(databaseDirectory: CacheDatabase.directory),
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );
    final user = UserDatabase(
      driftDatabase(
        name: 'lunaway_user_radars_tour',
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
          initialSettingsProvider.overrideWithValue(settings),
          basemapTemplatesProvider.overrideWithValue(basemap),
          locationPermissionsProvider.overrideWithValue(_Granted()),
          notificationAccessProvider.overrideWithValue(const _NoNotifications()),
          routeServiceProvider.overrideWithValue(_Once(plan)),
          locationFeedProvider.overrideWithValue(drive),
          vehicleProvider.overrideWith((ref) => Stream.value(_vehicle)),
          voiceOutputProvider.overrideWithValue(recorder),
          routeSettingsStoreProvider.overrideWithValue(
            _Settings(
              NavigationSettings(
                avoid: scenario.avoid,
                voiceMode: scenario.voice,
                acceptedDisclaimer: 'tour',
                legendSeen: true,
              ),
            ),
          ),
          drivingAidsStoreProvider.overrideWithValue(
            DrivingAidsStore(() async => stored, (v) async => stored = v),
          ),
          // One poll of the road events per drive.
          roadEventsPollProvider.overrideWithValue(const Duration(hours: 2)),
        ],
        child: TranslationProvider(child: const LunawayApp()),
      ),
    );
    await settle(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = _locale == 'en' ? AppLocale.en.buildSync() : AppLocale.fr.buildSync();
    GuidanceSession? session() => container.read(guidanceControllerProvider);
    recorder.session = session;
    var forceReal = false;
    final shots = <String>{};
    Future<void> shot(String moment) async {
      if (!shots.add(moment)) return;
      forceReal = true;
      await settle(const Duration(milliseconds: 800));
      debugPrint('SHOT $_scenarioName-$moment-$suffix');
      await settle(const Duration(milliseconds: 1500));
      forceReal = false;
    }

    final target = RouteTarget(destination: scenario.to, label: scenario.label, placeId: 'radars');
    unawaited(container.read(routerProvider).push(NavigationRoutes.previewOf(target)));
    final start = find.text(t.navigation.preview.start);
    await until(() => start.evaluate().isNotEmpty, what: 'the preview');
    // The preview asks the API for the cameras of the route's countries.
    await settle(const Duration(seconds: 8));
    final previewMarks = _map()?.marks ?? const [];
    debugPrint(
      'PREVIEW marks ${previewMarks.length}, cameras '
      '${previewMarks.where((m) => m.kind == RouteMarkKind.camera).length}',
    );
    await shot('apercu');
    final camera = previewMarks.where((m) => m.kind == RouteMarkKind.camera).firstOrNull;
    if (camera != null && _map()?.onMarkTap != null) {
      _map()!.onMarkTap!(camera.id, at: const Offset(270, 420));
      await shot('apercu-fiche');
      await tester.tapAt(const Offset(20, 40));
      await settle(const Duration(seconds: 1));
    }

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

    // Where the route crosses a border, by the library the guidance reads.
    final locator = await container.read(countryLocatorProvider.future);
    final borders = <double>[];
    String? last;
    for (var m = 0.0; m < drive.lengthM; m += 200) {
      final at = locator.around(drive._at(m).$1).at;
      if (at == null) continue;
      if (last != null && at != last) {
        borders.add(m);
        debugPrint('BORDER $last > $at at ${m.round()} m');
      }
      last = at;
    }

    final insideSince = <String, DateTime>{};
    drive.kmh = (m, road) {
      final a = session()?.aids.alert;
      var v = road - 2;
      // A driver keeps to the limit of a camera announced.
      if (a != null && a.cameraLimit && a.limitKmh != null) v = math.min(v, a.limitKmh! - 2);
      if (drive.overKmh > 0 && a?.limitKmh != null) v = a!.limitKmh! + drive.overKmh;
      return v;
    };
    drive.pace = () {
      if (forceReal || recorder.speaking || drive.overKmh > 0) return _real;
      final s = session();
      if (s == null) return _fast;
      final aids = s.aids;
      if (aids.exit != null || aids.ruleChange != null) return _real;
      final along = s.snapshot?.distanceAlongM ?? 0;
      if (borders.any((b) => along > b - 1500 && along < b + 3000)) return _real;
      final a = aids.alert;
      if (a == null) return _fast;
      if (!a.inside || a.kind == EnforcementKind.camera && !a.isSection) return _real;
      final since = insideSince[a.id];
      if (since == null || DateTime.now().difference(since) < const Duration(seconds: 8)) {
        return _real;
      }
      return a.remainingM < 600 ? _real : _medium;
    };

    var lastState = '';
    var lastOnRoute = '';
    String? seenId;
    var seenAt = DateTime.now();
    var approaches = 0;
    String? overTarget;
    DateTime? overSince;
    var overDone = false;
    var alerts = 0;
    final kinds = <String>{};
    final deadline = DateTime.now().add(const Duration(minutes: 40));
    var beat = DateTime.now();
    while (true) {
      await settle(const Duration(milliseconds: 100));
      final s = session();
      if (s == null) break;
      final along = s.snapshot?.distanceAlongM ?? 0;
      if (DateTime.now().difference(beat) > const Duration(seconds: 30)) {
        beat = DateTime.now();
        debugPrint('BEAT ${_km(along)} km, frames $frames');
      }
      if (s.phase == GuidancePhase.arrived) {
        // The arrival said to its end before the guidance stops.
        await settle(const Duration(seconds: 5));
        break;
      }
      if (scenario.stopAfterM case final stop? when along >= stop) break;
      if (DateTime.now().isAfter(deadline)) throw TestFailure('the drive took too long');
      final aids = s.aids;
      final onRoute = '${aids.mode.name} zones ${aids.zones.length} cameras ${aids.cameras.length}';
      if (onRoute != lastOnRoute) {
        lastOnRoute = onRoute;
        debugPrint('ONROUTE ${_km(along)} km ${aids.country} $onRoute');
      }
      final a = aids.alert;
      final state = [
        if (a != null) _describe(a),
        if (aids.exit case final e?) 'exit ${e.section ? 'section' : 'zone'}',
        if (aids.ruleChange case final r?) 'rule ${r.country} ${r.mode.name}',
      ].join(', ');
      // Logged when what the banner shows changes, its distances aside.
      final key = state.replaceAll(RegExp(r'(ahead|remaining|average) \d+'), '');
      if (key != lastState) {
        lastState = key;
        debugPrint(
          'AIDS ${_clock(s.lastFix?.at)} ${_km(along)} km ${aids.country} ${state.isEmpty ? 'none' : state}',
        );
      }

      if (a != null) {
        final kind = _kindOf(a);
        if (seenId != a.id) {
          seenId = a.id;
          seenAt = DateTime.now();
          alerts++;
          kinds.add(kind);
        }
        if (a.inside && (a.kind == EnforcementKind.zone || a.isSection)) {
          insideSince.putIfAbsent(a.id, DateTime.now);
        }
        if (!a.inside &&
            approaches < 3 &&
            DateTime.now().difference(seenAt) > const Duration(seconds: 4) &&
            !shots.contains('approche-$kind')) {
          approaches++;
          await shot('approche-$kind');
        }
        if (insideSince[a.id] case final since?
            when DateTime.now().difference(since) > const Duration(seconds: 3)) {
          await shot('dedans-$kind');
        }
        final measures =
            a.category != CameraCategory.redLight && a.category != CameraCategory.levelCrossing;
        // Over the limit once the alert was seen as a driver sees it: inside
        // a zone or a section once its capture is taken, a camera's point
        // from 500 m.
        final ready = a.kind == EnforcementKind.zone || a.isSection
            ? shots.contains('dedans-$kind')
            : a.aheadM < 500;
        if (!overDone &&
            overTarget == null &&
            a.limitKmh != null &&
            !a.limitEstimated &&
            measures &&
            ready) {
          overTarget = a.id;
          overSince = DateTime.now();
          drive.overKmh = 15;
          debugPrint('OVER driving at ${a.limitKmh! + 15} km/h for ${a.id}');
        }
        if (a.over) await shot('depassement');
      }
      if (overTarget != null) {
        final heard = recorder.records.any(
          (r) => r.started.isAfter(overSince!) && r.text.contains(RegExp('Ralentissez|Slow down')),
        );
        if (heard || DateTime.now().difference(overSince!) > const Duration(seconds: 12)) {
          debugPrint('OVER done, slow down heard: $heard');
          drive.overKmh = 0;
          overDone = true;
          overTarget = null;
        }
      }
      if (aids.exit case final e?) await shot(e.section ? 'sortie-troncon' : 'sortie-zone');
      if (aids.ruleChange case final r?) await shot('frontiere-${r.country.toLowerCase()}');
      if (scenario.nothing && along > drive.lengthM * 0.4) await shot('sans-radar');
    }

    if (scenario.cycleVoice && session() != null) {
      drive.pace = () => _real;
      for (final (mode, name) in [
        (VoiceMode.full, 'voix-complete'),
        (VoiceMode.alerts, 'voix-alertes'),
        (VoiceMode.muted, 'voix-muette'),
      ]) {
        await until(() => session()?.voiceMode == mode, what: 'the voice $name');
        await shot('bouton-$name');
        final tooltip = switch (mode) {
          VoiceMode.full => t.navigation.guidance.voiceMode.full,
          VoiceMode.alerts => t.navigation.guidance.voiceMode.alerts,
          VoiceMode.muted => t.navigation.guidance.voiceMode.muted,
        };
        await tester.tap(find.byTooltip(tooltip).last);
        await settle(const Duration(milliseconds: 500));
      }
    }

    final s = session();
    debugPrint(
      'SUMMARY $_scenarioName along ${_km(s?.snapshot?.distanceAlongM ?? drive.along)} km, '
      'alerts $alerts (${kinds.join(', ')}), sentences ${recorder.records.length}, '
      'overlaps ${recorder.overlaps}, shots ${shots.join(' ')}',
    );
    container.read(guidanceControllerProvider.notifier).stop();
    await settle(const Duration(seconds: 1));
    container.read(selectionProvider.notifier).select(null);
    await cache.close();
    await user.close();

    final sayable = recorder.records.where((r) => r.text.isNotEmpty);
    if (scenario.nothing) {
      expect(alerts, 0, reason: 'no alert where the rule is off');
      expect(
        sayable.where((r) => r.text.contains(RegExp('Radar|Zone de danger|camera|danger zone'))),
        isEmpty,
      );
    }
    if (scenario.voice == VoiceMode.alerts) {
      expect(
        recorder.records.where((r) => !r.chime && recorder.chimes),
        isEmpty,
        reason: 'alerts only: every sentence is an alert, after its chime',
      );
    }
    if (scenario.voice == VoiceMode.muted && !scenario.cycleVoice) {
      expect(recorder.records, isEmpty, reason: 'muted: nothing reaches the voice');
    }
    expect(recorder.overlaps, 0, reason: 'one sentence at a time');
    debugPrint('TOUR DONE');
  });
}
