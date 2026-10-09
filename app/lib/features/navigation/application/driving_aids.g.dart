// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'driving_aids.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(drivingAidsStore)
final drivingAidsStoreProvider = DrivingAidsStoreProvider._();

final class DrivingAidsStoreProvider
    extends
        $FunctionalProvider<
          DrivingAidsStore,
          DrivingAidsStore,
          DrivingAidsStore
        >
    with $Provider<DrivingAidsStore> {
  DrivingAidsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'drivingAidsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$drivingAidsStoreHash();

  @$internal
  @override
  $ProviderElement<DrivingAidsStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DrivingAidsStore create(Ref ref) {
    return drivingAidsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DrivingAidsStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DrivingAidsStore>(value),
    );
  }
}

String _$drivingAidsStoreHash() => r'6a9e21df1ff65fc78733ec8b9cba47d3e71906de';

/// Whether the limit shows, whether it is said, and where the cameras'
/// positions were asked for.
// keepAlive: the guidance reads it at every fix, the profile edits it.

@ProviderFor(DrivingAidsSettingsController)
final drivingAidsSettingsControllerProvider =
    DrivingAidsSettingsControllerProvider._();

/// Whether the limit shows, whether it is said, and where the cameras'
/// positions were asked for.
// keepAlive: the guidance reads it at every fix, the profile edits it.
final class DrivingAidsSettingsControllerProvider
    extends
        $AsyncNotifierProvider<
          DrivingAidsSettingsController,
          DrivingAidsSettings
        > {
  /// Whether the limit shows, whether it is said, and where the cameras'
  /// positions were asked for.
  // keepAlive: the guidance reads it at every fix, the profile edits it.
  DrivingAidsSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'drivingAidsSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$drivingAidsSettingsControllerHash();

  @$internal
  @override
  DrivingAidsSettingsController create() => DrivingAidsSettingsController();
}

String _$drivingAidsSettingsControllerHash() =>
    r'214d8117f749892617becd4d35b6f5aaf614368b';

/// Whether the limit shows, whether it is said, and where the cameras'
/// positions were asked for.
// keepAlive: the guidance reads it at every fix, the profile edits it.

abstract class _$DrivingAidsSettingsController
    extends $AsyncNotifier<DrivingAidsSettings> {
  FutureOr<DrivingAidsSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<DrivingAidsSettings>, DrivingAidsSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DrivingAidsSettings>, DrivingAidsSettings>,
              AsyncValue<DrivingAidsSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(enforcementStore)
final enforcementStoreProvider = EnforcementStoreProvider._();

final class EnforcementStoreProvider
    extends
        $FunctionalProvider<
          EnforcementStore,
          EnforcementStore,
          EnforcementStore
        >
    with $Provider<EnforcementStore> {
  EnforcementStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'enforcementStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$enforcementStoreHash();

  @$internal
  @override
  $ProviderElement<EnforcementStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EnforcementStore create(Ref ref) {
    return enforcementStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EnforcementStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EnforcementStore>(value),
    );
  }
}

String _$enforcementStoreHash() => r'063820bfaf5b4aabf5d40ff27ebe41f22b018fa0';

/// The speed camera data, through the routing client: no position goes
/// with it, only the countries of the trip and, among them, those where
/// the user asked for the positions.
// keepAlive: a stateless service, wired once.

@ProviderFor(enforcementFeed)
final enforcementFeedProvider = EnforcementFeedProvider._();

/// The speed camera data, through the routing client: no position goes
/// with it, only the countries of the trip and, among them, those where
/// the user asked for the positions.
// keepAlive: a stateless service, wired once.

final class EnforcementFeedProvider
    extends
        $FunctionalProvider<EnforcementFeed, EnforcementFeed, EnforcementFeed>
    with $Provider<EnforcementFeed> {
  /// The speed camera data, through the routing client: no position goes
  /// with it, only the countries of the trip and, among them, those where
  /// the user asked for the positions.
  // keepAlive: a stateless service, wired once.
  EnforcementFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'enforcementFeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$enforcementFeedHash();

  @$internal
  @override
  $ProviderElement<EnforcementFeed> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EnforcementFeed create(Ref ref) {
    return enforcementFeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EnforcementFeed value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EnforcementFeed>(value),
    );
  }
}

String _$enforcementFeedHash() => r'62c3ab955ce6277b64efa1c351a9eae902cb3631';

/// The lists of speed cameras as the API last described them, for the
/// credits: a list the app does not know yet is cited in its own words.

@ProviderFor(heldEnforcementSources)
final heldEnforcementSourcesProvider = HeldEnforcementSourcesProvider._();

/// The lists of speed cameras as the API last described them, for the
/// credits: a list the app does not know yet is cited in its own words.

final class HeldEnforcementSourcesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<EnforcementSource>>,
          List<EnforcementSource>,
          FutureOr<List<EnforcementSource>>
        >
    with
        $FutureModifier<List<EnforcementSource>>,
        $FutureProvider<List<EnforcementSource>> {
  /// The lists of speed cameras as the API last described them, for the
  /// credits: a list the app does not know yet is cited in its own words.
  HeldEnforcementSourcesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'heldEnforcementSourcesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$heldEnforcementSourcesHash();

  @$internal
  @override
  $FutureProviderElement<List<EnforcementSource>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<EnforcementSource>> create(Ref ref) {
    return heldEnforcementSources(ref);
  }
}

String _$heldEnforcementSourcesHash() =>
    r'4749b5a59f271914f872a1438d242024d968b03c';

/// The countries around a position, read on the device by the guidance
/// library; where it is not loaded, none (every rule then reads as off).
// keepAlive: the library loads once per run.

@ProviderFor(countryLocator)
final countryLocatorProvider = CountryLocatorProvider._();

/// The countries around a position, read on the device by the guidance
/// library; where it is not loaded, none (every rule then reads as off).
// keepAlive: the library loads once per run.

final class CountryLocatorProvider
    extends
        $FunctionalProvider<
          AsyncValue<CountryLocator>,
          CountryLocator,
          FutureOr<CountryLocator>
        >
    with $FutureModifier<CountryLocator>, $FutureProvider<CountryLocator> {
  /// The countries around a position, read on the device by the guidance
  /// library; where it is not loaded, none (every rule then reads as off).
  // keepAlive: the library loads once per run.
  CountryLocatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'countryLocatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$countryLocatorHash();

  @$internal
  @override
  $FutureProviderElement<CountryLocator> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CountryLocator> create(Ref ref) {
    return countryLocator(ref);
  }
}

String _$countryLocatorHash() => r'91b5057101dc4fbaad74c5424dcd449859da3529';
