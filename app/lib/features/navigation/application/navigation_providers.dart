import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/app_foreground.dart';
import 'package:lunaway/features/navigation/data/country_locator.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/road_events_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/data/web_voice.dart'
    if (dart.library.js_interop) 'package:lunaway/features/navigation/data/web_voice_web.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/domain/trip_check.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/application/places_providers.dart' show noRetry;
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'navigation_providers.g.dart';

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
RouteSettingsStore routeSettingsStore(Ref ref) =>
    DriftRouteSettingsStore(ref.watch(userDatabaseProvider));

/// The route settings: avoid options, voice, units. The state changes at
/// once, the write follows.
// keepAlive: the preview, the guidance and the profile read them for the
// whole run.
@Riverpod(keepAlive: true)
class RouteSettingsController extends _$RouteSettingsController {
  @override
  Future<NavigationSettings> build() => ref.watch(routeSettingsStoreProvider).load();

  Future<void> setAvoid(AvoidOptions avoid) => _update((s) => s.copyWith(avoid: avoid));

  Future<void> setVoice({required bool on}) => _update((s) => s.copyWith(voice: on));

  Future<void> setUnits(DistanceUnits units) => _update((s) => s.copyWith(units: units));

  /// Records that the user read the disclaimer of [key].
  Future<void> acceptDisclaimer(String key) => _update((s) => s.copyWith(acceptedDisclaimer: key));

  /// Records that the route map's legend was shown open.
  Future<void> legendShown() async {
    if (state.value?.legendSeen ?? false) return;
    await _update((s) => s.copyWith(legendSeen: true));
  }

  Future<void> _update(NavigationSettings Function(NavigationSettings) change) async {
    final next = change(state.value ?? const NavigationSettings());
    state = AsyncData(next);
    await ref.read(routeSettingsStoreProvider).save(next);
  }
}

/// The client of the route requests: no automatic retry on a rate limit,
/// so the user hears at once that the server asks to wait.
// keepAlive: a stateless client over the shared HTTP client.
@Riverpod(keepAlive: true)
GraphQLClient routingClient(Ref ref) => GraphQLClient(
  endpoint: ref.watch(appConfigProvider).graphqlEndpoint,
  httpClient: ref.watch(httpClientProvider),
  userAgent: ref.watch(userAgentProvider),
  timeout: const Duration(seconds: 20),
  rateLimitRetries: 0,
  persistedQueries: true,
);

// keepAlive: a service over the routing client, with its few recent answers.
@Riverpod(keepAlive: true)
RouteService routeService(Ref ref) =>
    CachingRouteService(GraphQLRouteService(ref.watch(routingClientProvider)));

/// Whether routing works now, its data and its bounds.
@Riverpod(retry: noRetry)
Future<RoutingInfo> routingInfo(Ref ref) => ref.watch(routeServiceProvider).info();

/// The device position, once and while guiding; a simulated drive in tests.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
LocationFeed locationFeed(Ref ref) => const GeolocatorFeed();

/// Whether the guidance drives itself along its route instead of following
/// the device: a demonstration on a computer without GPS. Only a debug
/// build started with `--dart-define=LUNAWAY_DEMO_DRIVE=true` has it; a
/// profile or release build never does, whatever its defines.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
bool demoDrive(Ref ref) => kDebugMode && const bool.fromEnvironment('LUNAWAY_DEMO_DRIVE');

/// The guidance engine; null where the library is missing or failed to
/// load (Linux has no app; a web page whose WebAssembly did not load).
// keepAlive: the native library loads once per run.
@Riverpod(keepAlive: true)
Future<GuidanceEngine?> guidanceEngine(Ref ref) => loadFerrostarEngine();

/// The spoken instructions: the platform's speech engine on Android, iOS
/// and macOS, the browser's on the web; none on Windows yet.
// keepAlive: one speech engine for the run.
@Riverpod(keepAlive: true)
VoiceOutput voiceOutput(Ref ref) {
  if (kIsWeb) return browserVoice();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => PlatformVoiceOutput(),
    _ => const SilentVoice(),
  };
}

// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
ScreenWake screenWake(Ref ref) => const WakelockScreenWake();

// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
AppForeground appForeground(Ref ref) => const LifecycleAppForeground();

// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
NotificationAccess notificationAccess(Ref ref) => const SystemNotificationAccess();

/// The road events of the area, from the API's `roadEvents` delta. Until
/// the server serves it, its refusal leaves the guidance without events,
/// as before.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
RoadEventsSource roadEventsSource(Ref ref) =>
    GraphQLRoadEventsSource(ref.watch(routingClientProvider));

/// How often the guidance asks for road events: every three minutes, the
/// rhythm of the national feed's increments
/// (`plan/research/20-travaux-temps-reel.md`, 5.6).
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
Duration roadEventsPoll(Ref ref) => const Duration(minutes: 3);

/// What the arrival card offers about the place reached, when a
/// contribution flow exists (the "Toujours là ?" of the place sheet). Null
/// until one registers by overriding this provider.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
ArrivalConfirmation? arrivalConfirmation(Ref ref) => null;

/// Asks the user, at the arrival, whether the place is still as described.
abstract interface class ArrivalConfirmation {
  /// The label of the button ("Toujours là ?").
  String label(String languageCode);

  /// Opens the confirmation for [placeId].
  Future<void> confirm(String placeId);
}

/// Where a route goes.
@immutable
final class RouteTarget {
  const new({required this.destination, this.label, this.placeId});

  final LatLng destination;

  /// The place's name, or nothing for a long-pressed point.
  final String? label;
  final String? placeId;

  @override
  bool operator ==(Object other) =>
      other is RouteTarget &&
      other.destination == destination &&
      other.label == label &&
      other.placeId == placeId;

  @override
  int get hashCode => Object.hash(destination, label, placeId);
}

/// What the preview shows: the vehicle check, the start, and the plan.
@immutable
final class RoutePreview {
  const new({
    required this.vehicle,
    this.origin,
    this.plan,
    this.selected = 0,
    this.stops = const [],
    this.unreachable = const [],
    this.coveredCountries = const [],
  });

  final VehicleCheck vehicle;

  /// Null: the position is unknown.
  final LatLng? origin;

  /// Null until both the vehicle and the start are known.
  final RoutePlan? plan;

  /// The index (in the OSRM answer) of the route chosen.
  final int selected;

  /// The stops the plan was computed with.
  final List<RouteStop> stops;

  /// Why there is no route, told on the device before asking (a stop
  /// outside the covered countries, a trip too long): no request was
  /// sent, and [plan] is null.
  final List<NoRouteReason> unreachable;

  /// The countries routes are computed in, to name them when a stop lies
  /// outside; empty when the API did not say.
  final List<String> coveredCountries;

  RouteOption? get route => plan?.routes.where((r) => r.index == selected).firstOrNull;

  /// Why the trip has no route, from the device or from the server.
  List<NoRouteReason> get noRouteReasons =>
      unreachable.isNotEmpty ? unreachable : plan?.noRouteReasons ?? const [];

  RoutePreview select(int index) => RoutePreview(
    vehicle: vehicle,
    origin: origin,
    plan: plan,
    selected: index,
    stops: stops,
    unreachable: unreachable,
    coveredCountries: coveredCountries,
  );
}

/// The start of the preview's route: the device position, else the one the
/// map located this run.
@riverpod
class PreviewOrigin extends _$PreviewOrigin {
  @override
  Future<LatLng?> build() async {
    final fallback = ref.watch(userLocationProvider);
    final fix = await ref.read(locationFeedProvider).current();
    return fix?.position ?? fallback;
  }

  /// Asks the device again, after the user allowed the position.
  Future<void> refresh() async {
    state = const AsyncLoading<LatLng?>();
    final fix = await ref.read(locationFeedProvider).current();
    if (!ref.mounted) return;
    state = AsyncData(fix?.position ?? ref.read(userLocationProvider));
  }
}

/// The route to [target] for the user's vehicle, with alternatives,
/// computed again when the vehicle, the settings or the start change. A
/// refused, rate-limited or offline request shows at once (`noRetry`).
@Riverpod(retry: noRetry)
class RoutePreviewController extends _$RoutePreviewController {
  @override
  Future<RoutePreview> build(RouteTarget target) async {
    // Every dependency is watched before the first await: one request once
    // the three are known, and a new one when any of them changes.
    final vehicleFuture = ref.watch(vehicleProvider.future);
    // The avoid options only: the voice or the units change no route.
    final avoidFuture = ref.watch(routeSettingsControllerProvider.selectAsync((s) => s.avoid));
    final originFuture = ref.watch(previewOriginProvider.future);
    final language = RouteLanguage.of(ref.watch(routeLanguageCodeProvider));
    final stops = ref.watch(routeStopsControllerProvider(target));
    final service = ref.watch(routeServiceProvider);
    // Asked at once, beside the vehicle and the position; a failure or a
    // slow answer leaves the server to decide alone.
    final infoFuture = service
        .info()
        .timeout(const Duration(seconds: 4))
        .then<RoutingInfo?>((i) => i, onError: (Object _) => null);
    final check = checkVehicle(await vehicleFuture);
    final avoid = await avoidFuture;
    final start = await originFuture;
    if (!check.ready || start == null) return RoutePreview(vehicle: check, origin: start);
    final info = await infoFuture;
    final covered = info?.coveredCountries ?? const <String>[];
    final locator = await _locator();
    final unreachable = checkTrip(
      stops: [start, for (final s in stops) s.position, target.destination],
      covered: covered,
      maxTripKm: info?.maxTripKm,
      countries: locator.around,
    );
    if (unreachable.isNotEmpty) {
      return RoutePreview(
        vehicle: check,
        origin: start,
        stops: stops,
        unreachable: unreachable,
        coveredCountries: covered,
      );
    }
    final plan = await service.route(
      _request(
        origin: start,
        vehicle: check.profile!,
        avoid: avoid,
        language: language,
        stops: stops,
      ),
    );
    return RoutePreview(
      vehicle: check,
      origin: start,
      plan: plan,
      selected: plan.routes.firstOrNull?.index ?? 0,
      stops: stops,
      coveredCountries: covered,
    );
  }

  /// The device's reading of countries; none where the guidance library
  /// did not load, and the server then decides.
  Future<CountryLocator> _locator() async {
    try {
      return await ref.read(countryLocatorProvider.future);
    } on Object {
      return const NoCountryLocator();
    }
  }

  RouteRequest _request({
    required LatLng origin,
    required VehicleProfile vehicle,
    required AvoidOptions avoid,
    required RouteLanguage language,
    required List<RouteStop> stops,
  }) => RouteRequest(
    origin: origin,
    destination: target.destination,
    vehicle: vehicle,
    avoid: avoid,
    language: language,
    stops: [for (final s in stops) s.position],
    // The API's most, asked only without stops as it requires.
    alternatives: stops.isEmpty ? 2 : 0,
  );

  /// The route with [stop] added where it lengthens the trip the least,
  /// and what it adds; null when there is no route to change, or no room
  /// for another stop. The answer is kept: adding the stop then asks for
  /// nothing more.
  Future<StopQuote?> quoteStop(RouteStop stop) async {
    final current = state.value;
    final origin = current?.origin;
    final profile = current?.vehicle.profile;
    final base = ref.read(routeStopsControllerProvider(target));
    if (current == null || origin == null || profile == null || current.plan == null) return null;
    if (base.length >= maxRouteStops) return null;
    final at = bestInsertion(
      origin: origin,
      stops: base,
      destination: target.destination,
      stop: stop.position,
    );
    final stops = insertStop(base, at, stop);
    // The settings and the language the build reads: the request is the
    // one the build makes once the stop is added, and its answer is reused.
    final language = RouteLanguage.of(ref.read(routeLanguageCodeProvider));
    final service = ref.read(routeServiceProvider);
    final settings = await ref.read(routeSettingsControllerProvider.future);
    if (!ref.mounted) return null;
    final next = await service.route(
      _request(
        origin: origin,
        vehicle: profile,
        avoid: settings.avoid,
        language: language,
        stops: stops,
      ),
    );
    final before = current.route;
    final after = next.routes.firstOrNull;
    final comparable = before != null && after != null && next.status == RouteStatus.ok;
    return StopQuote(
      stop: stop,
      stops: stops,
      base: base,
      plan: next,
      extraS: comparable ? after.durationS - before.durationS : null,
      extraM: comparable ? after.distanceM - before.distanceM : null,
    );
  }

  /// Chooses another route. Ignored while routes are computed or after a
  /// failure: the ones on screen are those of the vehicle or the options
  /// before the change.
  void select(int index) {
    final current = state;
    if (current is AsyncData<RoutePreview> && !current.isLoading) {
      state = AsyncData(current.value.select(index));
    }
  }
}

/// The route map widget, swapped for a plain one in widget tests where
/// platform views do not render.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
RouteMapBuilder routeMapBuilder(Ref ref) => buildPlatformRouteMap;

/// The language code of the app's locale, for the router's instructions;
/// set by the preview screen from its translations.
// keepAlive: follows the app's language for the whole run.
@Riverpod(keepAlive: true)
class RouteLanguageCode extends _$RouteLanguageCode {
  @override
  String build() => 'fr';

  void set(String code) {
    if (code != state) state = code;
  }
}
