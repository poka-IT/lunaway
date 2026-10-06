import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/app_foreground.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/notification_access.dart';
import 'package:lunaway/features/navigation/data/road_events_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
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

  Future<void> setFuel(VehicleFuel fuel) => _update((s) => s.copyWith(fuel: fuel));

  /// Litres per 100 km, kept within the range the form accepts.
  Future<void> setConsumption(double litres) => _update(
    (s) => s.copyWith(
      consumptionL100: litres.clamp(
        NavigationSettings.consumptionRange.min,
        NavigationSettings.consumptionRange.max,
      ),
    ),
  );

  /// Records that the user read the disclaimer of [key].
  Future<void> acceptDisclaimer(String key) => _update((s) => s.copyWith(acceptedDisclaimer: key));

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

/// The guidance engine; null where the device cannot guide (desktop, web,
/// a library that failed to load).
// keepAlive: the native library loads once per run.
@Riverpod(keepAlive: true)
Future<GuidanceEngine?> guidanceEngine(Ref ref) => loadFerrostarEngine();

/// The spoken instructions.
// keepAlive: one speech engine for the run.
@Riverpod(keepAlive: true)
VoiceOutput voiceOutput(Ref ref) {
  final phone =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return phone ? PlatformVoiceOutput() : const SilentVoice();
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

  RouteOption? get route => plan?.routes.where((r) => r.index == selected).firstOrNull;

  RoutePreview select(int index) =>
      RoutePreview(vehicle: vehicle, origin: origin, plan: plan, selected: index, stops: stops);
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
    final check = checkVehicle(await vehicleFuture);
    final avoid = await avoidFuture;
    final start = await originFuture;
    if (!check.ready || start == null) return RoutePreview(vehicle: check, origin: start);
    final plan = await ref
        .read(routeServiceProvider)
        .route(
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
    );
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
    final plan = current?.plan;
    if (current == null || origin == null || profile == null || plan == null) return null;
    if (current.stops.length >= maxRouteStops) return null;
    final at = bestInsertion(
      origin: origin,
      stops: current.stops,
      destination: target.destination,
      stop: stop.position,
    );
    final stops = insertStop(current.stops, at, stop);
    final next = await ref
        .read(routeServiceProvider)
        .route(
          _request(
            origin: origin,
            vehicle: profile,
            avoid: plan.applied.avoid,
            language: plan.applied.language,
            stops: stops,
          ),
        );
    final before = current.route;
    final after = next.routes.firstOrNull;
    final comparable = before != null && after != null && next.status == RouteStatus.ok;
    return StopQuote(
      stops: stops,
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
