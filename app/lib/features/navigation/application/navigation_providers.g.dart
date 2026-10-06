// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(routeSettingsStore)
final routeSettingsStoreProvider = RouteSettingsStoreProvider._();

final class RouteSettingsStoreProvider
    extends
        $FunctionalProvider<
          RouteSettingsStore,
          RouteSettingsStore,
          RouteSettingsStore
        >
    with $Provider<RouteSettingsStore> {
  RouteSettingsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeSettingsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeSettingsStoreHash();

  @$internal
  @override
  $ProviderElement<RouteSettingsStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RouteSettingsStore create(Ref ref) {
    return routeSettingsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RouteSettingsStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RouteSettingsStore>(value),
    );
  }
}

String _$routeSettingsStoreHash() =>
    r'238e3b485415e5cfa99e2ba9ff45684c29aac08d';

/// The route settings: avoid options, voice, units. The state changes at
/// once, the write follows.
// keepAlive: the preview, the guidance and the profile read them for the
// whole run.

@ProviderFor(RouteSettingsController)
final routeSettingsControllerProvider = RouteSettingsControllerProvider._();

/// The route settings: avoid options, voice, units. The state changes at
/// once, the write follows.
// keepAlive: the preview, the guidance and the profile read them for the
// whole run.
final class RouteSettingsControllerProvider
    extends
        $AsyncNotifierProvider<RouteSettingsController, NavigationSettings> {
  /// The route settings: avoid options, voice, units. The state changes at
  /// once, the write follows.
  // keepAlive: the preview, the guidance and the profile read them for the
  // whole run.
  RouteSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeSettingsControllerHash();

  @$internal
  @override
  RouteSettingsController create() => RouteSettingsController();
}

String _$routeSettingsControllerHash() =>
    r'7f22d693abfa7f0099c5b67f8c11d672495c21e0';

/// The route settings: avoid options, voice, units. The state changes at
/// once, the write follows.
// keepAlive: the preview, the guidance and the profile read them for the
// whole run.

abstract class _$RouteSettingsController
    extends $AsyncNotifier<NavigationSettings> {
  FutureOr<NavigationSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<NavigationSettings>, NavigationSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<NavigationSettings>, NavigationSettings>,
              AsyncValue<NavigationSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The client of the route requests: no automatic retry on a rate limit,
/// so the user hears at once that the server asks to wait.
// keepAlive: a stateless client over the shared HTTP client.

@ProviderFor(routingClient)
final routingClientProvider = RoutingClientProvider._();

/// The client of the route requests: no automatic retry on a rate limit,
/// so the user hears at once that the server asks to wait.
// keepAlive: a stateless client over the shared HTTP client.

final class RoutingClientProvider
    extends $FunctionalProvider<GraphQLClient, GraphQLClient, GraphQLClient>
    with $Provider<GraphQLClient> {
  /// The client of the route requests: no automatic retry on a rate limit,
  /// so the user hears at once that the server asks to wait.
  // keepAlive: a stateless client over the shared HTTP client.
  RoutingClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routingClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routingClientHash();

  @$internal
  @override
  $ProviderElement<GraphQLClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GraphQLClient create(Ref ref) {
    return routingClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GraphQLClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GraphQLClient>(value),
    );
  }
}

String _$routingClientHash() => r'4ee0074ab654ebe3f31548186e24e2e5bff5582a';

@ProviderFor(routeService)
final routeServiceProvider = RouteServiceProvider._();

final class RouteServiceProvider
    extends $FunctionalProvider<RouteService, RouteService, RouteService>
    with $Provider<RouteService> {
  RouteServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeServiceHash();

  @$internal
  @override
  $ProviderElement<RouteService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RouteService create(Ref ref) {
    return routeService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RouteService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RouteService>(value),
    );
  }
}

String _$routeServiceHash() => r'57bf564c2da41e80da3558d7562d96ab3c1b6207';

/// Whether routing works now, its data and its bounds.

@ProviderFor(routingInfo)
final routingInfoProvider = RoutingInfoProvider._();

/// Whether routing works now, its data and its bounds.

final class RoutingInfoProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoutingInfo>,
          RoutingInfo,
          FutureOr<RoutingInfo>
        >
    with $FutureModifier<RoutingInfo>, $FutureProvider<RoutingInfo> {
  /// Whether routing works now, its data and its bounds.
  RoutingInfoProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'routingInfoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routingInfoHash();

  @$internal
  @override
  $FutureProviderElement<RoutingInfo> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RoutingInfo> create(Ref ref) {
    return routingInfo(ref);
  }
}

String _$routingInfoHash() => r'e3072fd6944bdc9f19a1539af33078d9160412e1';

/// The device position, once and while guiding; a simulated drive in tests.
// keepAlive: stateless, wired once.

@ProviderFor(locationFeed)
final locationFeedProvider = LocationFeedProvider._();

/// The device position, once and while guiding; a simulated drive in tests.
// keepAlive: stateless, wired once.

final class LocationFeedProvider
    extends $FunctionalProvider<LocationFeed, LocationFeed, LocationFeed>
    with $Provider<LocationFeed> {
  /// The device position, once and while guiding; a simulated drive in tests.
  // keepAlive: stateless, wired once.
  LocationFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'locationFeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$locationFeedHash();

  @$internal
  @override
  $ProviderElement<LocationFeed> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LocationFeed create(Ref ref) {
    return locationFeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocationFeed value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocationFeed>(value),
    );
  }
}

String _$locationFeedHash() => r'ac7ff6a7066fbc626c14e2801afb214d48383123';

/// The guidance engine; null where the device cannot guide (desktop, web,
/// a library that failed to load).
// keepAlive: the native library loads once per run.

@ProviderFor(guidanceEngine)
final guidanceEngineProvider = GuidanceEngineProvider._();

/// The guidance engine; null where the device cannot guide (desktop, web,
/// a library that failed to load).
// keepAlive: the native library loads once per run.

final class GuidanceEngineProvider
    extends
        $FunctionalProvider<
          AsyncValue<GuidanceEngine?>,
          GuidanceEngine?,
          FutureOr<GuidanceEngine?>
        >
    with $FutureModifier<GuidanceEngine?>, $FutureProvider<GuidanceEngine?> {
  /// The guidance engine; null where the device cannot guide (desktop, web,
  /// a library that failed to load).
  // keepAlive: the native library loads once per run.
  GuidanceEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceEngineHash();

  @$internal
  @override
  $FutureProviderElement<GuidanceEngine?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GuidanceEngine?> create(Ref ref) {
    return guidanceEngine(ref);
  }
}

String _$guidanceEngineHash() => r'606015d5a08b387e6155c5f407b09d1d435f7a14';

/// The spoken instructions.
// keepAlive: one speech engine for the run.

@ProviderFor(voiceOutput)
final voiceOutputProvider = VoiceOutputProvider._();

/// The spoken instructions.
// keepAlive: one speech engine for the run.

final class VoiceOutputProvider
    extends $FunctionalProvider<VoiceOutput, VoiceOutput, VoiceOutput>
    with $Provider<VoiceOutput> {
  /// The spoken instructions.
  // keepAlive: one speech engine for the run.
  VoiceOutputProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceOutputProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceOutputHash();

  @$internal
  @override
  $ProviderElement<VoiceOutput> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VoiceOutput create(Ref ref) {
    return voiceOutput(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceOutput value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceOutput>(value),
    );
  }
}

String _$voiceOutputHash() => r'5121cddfe166d77db4c74f2ee547de30e1b8ff00';

@ProviderFor(screenWake)
final screenWakeProvider = ScreenWakeProvider._();

final class ScreenWakeProvider
    extends $FunctionalProvider<ScreenWake, ScreenWake, ScreenWake>
    with $Provider<ScreenWake> {
  ScreenWakeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'screenWakeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$screenWakeHash();

  @$internal
  @override
  $ProviderElement<ScreenWake> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ScreenWake create(Ref ref) {
    return screenWake(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScreenWake value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScreenWake>(value),
    );
  }
}

String _$screenWakeHash() => r'52a14e528c239808da4b03caf9757bcdd7140556';

@ProviderFor(appForeground)
final appForegroundProvider = AppForegroundProvider._();

final class AppForegroundProvider
    extends $FunctionalProvider<AppForeground, AppForeground, AppForeground>
    with $Provider<AppForeground> {
  AppForegroundProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appForegroundProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appForegroundHash();

  @$internal
  @override
  $ProviderElement<AppForeground> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppForeground create(Ref ref) {
    return appForeground(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppForeground value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppForeground>(value),
    );
  }
}

String _$appForegroundHash() => r'ed81b3ea1368862459d2e2f5f4742caf86407957';

@ProviderFor(notificationAccess)
final notificationAccessProvider = NotificationAccessProvider._();

final class NotificationAccessProvider
    extends
        $FunctionalProvider<
          NotificationAccess,
          NotificationAccess,
          NotificationAccess
        >
    with $Provider<NotificationAccess> {
  NotificationAccessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationAccessProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationAccessHash();

  @$internal
  @override
  $ProviderElement<NotificationAccess> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationAccess create(Ref ref) {
    return notificationAccess(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationAccess value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationAccess>(value),
    );
  }
}

String _$notificationAccessHash() =>
    r'b0d02c4bc9b7e39b5840b362504748b162ff9661';

/// The road events of the area, from the API's `roadEvents` delta. Until
/// the server serves it, its refusal leaves the guidance without events,
/// as before.
// keepAlive: stateless, wired once.

@ProviderFor(roadEventsSource)
final roadEventsSourceProvider = RoadEventsSourceProvider._();

/// The road events of the area, from the API's `roadEvents` delta. Until
/// the server serves it, its refusal leaves the guidance without events,
/// as before.
// keepAlive: stateless, wired once.

final class RoadEventsSourceProvider
    extends
        $FunctionalProvider<
          RoadEventsSource,
          RoadEventsSource,
          RoadEventsSource
        >
    with $Provider<RoadEventsSource> {
  /// The road events of the area, from the API's `roadEvents` delta. Until
  /// the server serves it, its refusal leaves the guidance without events,
  /// as before.
  // keepAlive: stateless, wired once.
  RoadEventsSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roadEventsSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roadEventsSourceHash();

  @$internal
  @override
  $ProviderElement<RoadEventsSource> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoadEventsSource create(Ref ref) {
    return roadEventsSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoadEventsSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoadEventsSource>(value),
    );
  }
}

String _$roadEventsSourceHash() => r'11498a9c00d6ef110d0c4638c2632dbd7229042d';

/// How often the guidance asks for road events: every three minutes, the
/// rhythm of the national feed's increments
/// (`plan/research/20-travaux-temps-reel.md`, 5.6).
// keepAlive: a constant of the run.

@ProviderFor(roadEventsPoll)
final roadEventsPollProvider = RoadEventsPollProvider._();

/// How often the guidance asks for road events: every three minutes, the
/// rhythm of the national feed's increments
/// (`plan/research/20-travaux-temps-reel.md`, 5.6).
// keepAlive: a constant of the run.

final class RoadEventsPollProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// How often the guidance asks for road events: every three minutes, the
  /// rhythm of the national feed's increments
  /// (`plan/research/20-travaux-temps-reel.md`, 5.6).
  // keepAlive: a constant of the run.
  RoadEventsPollProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roadEventsPollProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roadEventsPollHash();

  @$internal
  @override
  $ProviderElement<Duration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration create(Ref ref) {
    return roadEventsPoll(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$roadEventsPollHash() => r'42a11a3cdb50e1b1f5be3f4a083def9223d44685';

/// What the arrival card offers about the place reached, when a
/// contribution flow exists (the "Toujours là ?" of the place sheet). Null
/// until one registers by overriding this provider.
// keepAlive: a constant of the run.

@ProviderFor(arrivalConfirmation)
final arrivalConfirmationProvider = ArrivalConfirmationProvider._();

/// What the arrival card offers about the place reached, when a
/// contribution flow exists (the "Toujours là ?" of the place sheet). Null
/// until one registers by overriding this provider.
// keepAlive: a constant of the run.

final class ArrivalConfirmationProvider
    extends
        $FunctionalProvider<
          ArrivalConfirmation?,
          ArrivalConfirmation?,
          ArrivalConfirmation?
        >
    with $Provider<ArrivalConfirmation?> {
  /// What the arrival card offers about the place reached, when a
  /// contribution flow exists (the "Toujours là ?" of the place sheet). Null
  /// until one registers by overriding this provider.
  // keepAlive: a constant of the run.
  ArrivalConfirmationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'arrivalConfirmationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$arrivalConfirmationHash();

  @$internal
  @override
  $ProviderElement<ArrivalConfirmation?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ArrivalConfirmation? create(Ref ref) {
    return arrivalConfirmation(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ArrivalConfirmation? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ArrivalConfirmation?>(value),
    );
  }
}

String _$arrivalConfirmationHash() =>
    r'6d6ac5e91a70d79235d2f66c6039f1af7b27acc9';

/// The start of the preview's route: the device position, else the one the
/// map located this run.

@ProviderFor(PreviewOrigin)
final previewOriginProvider = PreviewOriginProvider._();

/// The start of the preview's route: the device position, else the one the
/// map located this run.
final class PreviewOriginProvider
    extends $AsyncNotifierProvider<PreviewOrigin, LatLng?> {
  /// The start of the preview's route: the device position, else the one the
  /// map located this run.
  PreviewOriginProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'previewOriginProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$previewOriginHash();

  @$internal
  @override
  PreviewOrigin create() => PreviewOrigin();
}

String _$previewOriginHash() => r'0144f3ce2174e93a6aaf2703d8fb06a4a4c00871';

/// The start of the preview's route: the device position, else the one the
/// map located this run.

abstract class _$PreviewOrigin extends $AsyncNotifier<LatLng?> {
  FutureOr<LatLng?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<LatLng?>, LatLng?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<LatLng?>, LatLng?>,
              AsyncValue<LatLng?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The route to [target] for the user's vehicle, with alternatives,
/// computed again when the vehicle, the settings or the start change. A
/// refused, rate-limited or offline request shows at once (`noRetry`).

@ProviderFor(RoutePreviewController)
final routePreviewControllerProvider = RoutePreviewControllerFamily._();

/// The route to [target] for the user's vehicle, with alternatives,
/// computed again when the vehicle, the settings or the start change. A
/// refused, rate-limited or offline request shows at once (`noRetry`).
final class RoutePreviewControllerProvider
    extends $AsyncNotifierProvider<RoutePreviewController, RoutePreview> {
  /// The route to [target] for the user's vehicle, with alternatives,
  /// computed again when the vehicle, the settings or the start change. A
  /// refused, rate-limited or offline request shows at once (`noRetry`).
  RoutePreviewControllerProvider._({
    required RoutePreviewControllerFamily super.from,
    required RouteTarget super.argument,
  }) : super(
         retry: noRetry,
         name: r'routePreviewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$routePreviewControllerHash();

  @override
  String toString() {
    return r'routePreviewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RoutePreviewController create() => RoutePreviewController();

  @override
  bool operator ==(Object other) {
    return other is RoutePreviewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$routePreviewControllerHash() =>
    r'4c91d889ee7544da4c88356e2c863186ed39efa1';

/// The route to [target] for the user's vehicle, with alternatives,
/// computed again when the vehicle, the settings or the start change. A
/// refused, rate-limited or offline request shows at once (`noRetry`).

final class RoutePreviewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          RoutePreviewController,
          AsyncValue<RoutePreview>,
          RoutePreview,
          FutureOr<RoutePreview>,
          RouteTarget
        > {
  RoutePreviewControllerFamily._()
    : super(
        retry: noRetry,
        name: r'routePreviewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The route to [target] for the user's vehicle, with alternatives,
  /// computed again when the vehicle, the settings or the start change. A
  /// refused, rate-limited or offline request shows at once (`noRetry`).

  RoutePreviewControllerProvider call(RouteTarget target) =>
      RoutePreviewControllerProvider._(argument: target, from: this);

  @override
  String toString() => r'routePreviewControllerProvider';
}

/// The route to [target] for the user's vehicle, with alternatives,
/// computed again when the vehicle, the settings or the start change. A
/// refused, rate-limited or offline request shows at once (`noRetry`).

abstract class _$RoutePreviewController extends $AsyncNotifier<RoutePreview> {
  late final _$args = ref.$arg as RouteTarget;
  RouteTarget get target => _$args;

  FutureOr<RoutePreview> build(RouteTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<RoutePreview>, RoutePreview>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RoutePreview>, RoutePreview>,
              AsyncValue<RoutePreview>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The route map widget, swapped for a plain one in widget tests where
/// platform views do not render.
// keepAlive: a constant of the run.

@ProviderFor(routeMapBuilder)
final routeMapBuilderProvider = RouteMapBuilderProvider._();

/// The route map widget, swapped for a plain one in widget tests where
/// platform views do not render.
// keepAlive: a constant of the run.

final class RouteMapBuilderProvider
    extends
        $FunctionalProvider<RouteMapBuilder, RouteMapBuilder, RouteMapBuilder>
    with $Provider<RouteMapBuilder> {
  /// The route map widget, swapped for a plain one in widget tests where
  /// platform views do not render.
  // keepAlive: a constant of the run.
  RouteMapBuilderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeMapBuilderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeMapBuilderHash();

  @$internal
  @override
  $ProviderElement<RouteMapBuilder> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RouteMapBuilder create(Ref ref) {
    return routeMapBuilder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RouteMapBuilder value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RouteMapBuilder>(value),
    );
  }
}

String _$routeMapBuilderHash() => r'34a33f23800ba6fbb40d881421e93296990d05a4';

/// The language code of the app's locale, for the router's instructions;
/// set by the preview screen from its translations.
// keepAlive: follows the app's language for the whole run.

@ProviderFor(RouteLanguageCode)
final routeLanguageCodeProvider = RouteLanguageCodeProvider._();

/// The language code of the app's locale, for the router's instructions;
/// set by the preview screen from its translations.
// keepAlive: follows the app's language for the whole run.
final class RouteLanguageCodeProvider
    extends $NotifierProvider<RouteLanguageCode, String> {
  /// The language code of the app's locale, for the router's instructions;
  /// set by the preview screen from its translations.
  // keepAlive: follows the app's language for the whole run.
  RouteLanguageCodeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routeLanguageCodeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routeLanguageCodeHash();

  @$internal
  @override
  RouteLanguageCode create() => RouteLanguageCode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$routeLanguageCodeHash() => r'dc99f4548a7ac16780fa76ad68df688d2c99718a';

/// The language code of the app's locale, for the router's instructions;
/// set by the preview screen from its translations.
// keepAlive: follows the app's language for the whole run.

abstract class _$RouteLanguageCode extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
