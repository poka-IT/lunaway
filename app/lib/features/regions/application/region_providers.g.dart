// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'region_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(regionStore)
final regionStoreProvider = RegionStoreProvider._();

final class RegionStoreProvider
    extends $FunctionalProvider<RegionStore, RegionStore, RegionStore>
    with $Provider<RegionStore> {
  RegionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'regionStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionStoreHash();

  @$internal
  @override
  $ProviderElement<RegionStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RegionStore create(Ref ref) {
    return regionStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RegionStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RegionStore>(value),
    );
  }
}

String _$regionStoreHash() => r'6c4a0ccecc245c629728bd1e90d366c022eacd32';

@ProviderFor(keptRegionsStore)
final keptRegionsStoreProvider = KeptRegionsStoreProvider._();

final class KeptRegionsStoreProvider
    extends
        $FunctionalProvider<
          KeptRegionsStore,
          KeptRegionsStore,
          KeptRegionsStore
        >
    with $Provider<KeptRegionsStore> {
  KeptRegionsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keptRegionsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keptRegionsStoreHash();

  @$internal
  @override
  $ProviderElement<KeptRegionsStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KeptRegionsStore create(Ref ref) {
    return keptRegionsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeptRegionsStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeptRegionsStore>(value),
    );
  }
}

String _$keptRegionsStoreHash() => r'50c8e80005b68c722976be2ea6640efffcbdcf98';

@ProviderFor(regionCatalogCopy)
final regionCatalogCopyProvider = RegionCatalogCopyProvider._();

final class RegionCatalogCopyProvider
    extends
        $FunctionalProvider<
          RegionCatalogCopy,
          RegionCatalogCopy,
          RegionCatalogCopy
        >
    with $Provider<RegionCatalogCopy> {
  RegionCatalogCopyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'regionCatalogCopyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionCatalogCopyHash();

  @$internal
  @override
  $ProviderElement<RegionCatalogCopy> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RegionCatalogCopy create(Ref ref) {
    return regionCatalogCopy(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RegionCatalogCopy value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RegionCatalogCopy>(value),
    );
  }
}

String _$regionCatalogCopyHash() => r'57625777222bb2b0ec7d4ebd5e835f4ff7b0b31f';

/// The packs' files; a stand-in that keeps none on the web.
// keepAlive: one folder for the run.

@ProviderFor(regionPackFiles)
final regionPackFilesProvider = RegionPackFilesProvider._();

/// The packs' files; a stand-in that keeps none on the web.
// keepAlive: one folder for the run.

final class RegionPackFilesProvider
    extends
        $FunctionalProvider<RegionPackFiles, RegionPackFiles, RegionPackFiles>
    with $Provider<RegionPackFiles> {
  /// The packs' files; a stand-in that keeps none on the web.
  // keepAlive: one folder for the run.
  RegionPackFilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'regionPackFilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionPackFilesHash();

  @$internal
  @override
  $ProviderElement<RegionPackFiles> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RegionPackFiles create(Ref ref) {
    return regionPackFiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RegionPackFiles value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RegionPackFiles>(value),
    );
  }
}

String _$regionPackFilesHash() => r'bc51e7711a772bf2edd424e293ec60e561f7f619';

/// The country of the device's region settings (`FR` for fr_FR), a hint
/// of where the user lives before any position is known; replaced in tests.
// keepAlive: a constant of the run.

@ProviderFor(deviceCountry)
final deviceCountryProvider = DeviceCountryProvider._();

/// The country of the device's region settings (`FR` for fr_FR), a hint
/// of where the user lives before any position is known; replaced in tests.
// keepAlive: a constant of the run.

final class DeviceCountryProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The country of the device's region settings (`FR` for fr_FR), a hint
  /// of where the user lives before any position is known; replaced in tests.
  // keepAlive: a constant of the run.
  DeviceCountryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceCountryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceCountryHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return deviceCountry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$deviceCountryHash() => r'beca34aa87e852615777422847ab513def88e367';

/// The regions of the manifest: the copy of the last one read at once,
/// the fresh one once read; null against an API without regions (the sync
/// by box then runs, as before).
// keepAlive: the sync, the map and the profile read it for the whole run.

@ProviderFor(RegionCatalogController)
final regionCatalogControllerProvider = RegionCatalogControllerProvider._();

/// The regions of the manifest: the copy of the last one read at once,
/// the fresh one once read; null against an API without regions (the sync
/// by box then runs, as before).
// keepAlive: the sync, the map and the profile read it for the whole run.
final class RegionCatalogControllerProvider
    extends $AsyncNotifierProvider<RegionCatalogController, RegionCatalog?> {
  /// The regions of the manifest: the copy of the last one read at once,
  /// the fresh one once read; null against an API without regions (the sync
  /// by box then runs, as before).
  // keepAlive: the sync, the map and the profile read it for the whole run.
  RegionCatalogControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'regionCatalogControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionCatalogControllerHash();

  @$internal
  @override
  RegionCatalogController create() => RegionCatalogController();
}

String _$regionCatalogControllerHash() =>
    r'c1268591f51a8ce18b39ea677ba675555c6783a6';

/// The regions of the manifest: the copy of the last one read at once,
/// the fresh one once read; null against an API without regions (the sync
/// by box then runs, as before).
// keepAlive: the sync, the map and the profile read it for the whole run.

abstract class _$RegionCatalogController
    extends $AsyncNotifier<RegionCatalog?> {
  FutureOr<RegionCatalog?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<RegionCatalog?>, RegionCatalog?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RegionCatalog?>, RegionCatalog?>,
              AsyncValue<RegionCatalog?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The regions the user keeps; null until a first choice.
// keepAlive: the sync and the profile read it for the whole run.

@ProviderFor(KeptRegionsController)
final keptRegionsControllerProvider = KeptRegionsControllerProvider._();

/// The regions the user keeps; null until a first choice.
// keepAlive: the sync and the profile read it for the whole run.
final class KeptRegionsControllerProvider
    extends $AsyncNotifierProvider<KeptRegionsController, Set<String>?> {
  /// The regions the user keeps; null until a first choice.
  // keepAlive: the sync and the profile read it for the whole run.
  KeptRegionsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keptRegionsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keptRegionsControllerHash();

  @$internal
  @override
  KeptRegionsController create() => KeptRegionsController();
}

String _$keptRegionsControllerHash() =>
    r'9ecd030432ef4599bc974d3f0e9240014bbbdbd4';

/// The regions the user keeps; null until a first choice.
// keepAlive: the sync and the profile read it for the whole run.

abstract class _$KeptRegionsController extends $AsyncNotifier<Set<String>?> {
  FutureOr<Set<String>?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Set<String>?>, Set<String>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>?>, Set<String>?>,
              AsyncValue<Set<String>?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Syncs one region, its pack then its feed.
// keepAlive: a stateless service, wired once.

@ProviderFor(regionSyncService)
final regionSyncServiceProvider = RegionSyncServiceProvider._();

/// Syncs one region, its pack then its feed.
// keepAlive: a stateless service, wired once.

final class RegionSyncServiceProvider
    extends
        $FunctionalProvider<
          RegionSyncService,
          RegionSyncService,
          RegionSyncService
        >
    with $Provider<RegionSyncService> {
  /// Syncs one region, its pack then its feed.
  // keepAlive: a stateless service, wired once.
  RegionSyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'regionSyncServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionSyncServiceHash();

  @$internal
  @override
  $ProviderElement<RegionSyncService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RegionSyncService create(Ref ref) {
    return regionSyncService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RegionSyncService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RegionSyncService>(value),
    );
  }
}

String _$regionSyncServiceHash() => r'2a3ce7c29b093f652608fe26a73201271aa07a23';

/// The sync of every region kept, or of France by box against an API
/// without regions.
// keepAlive: a stateless service, wired once.

@ProviderFor(placesSync)
final placesSyncProvider = PlacesSyncProvider._();

/// The sync of every region kept, or of France by box against an API
/// without regions.
// keepAlive: a stateless service, wired once.

final class PlacesSyncProvider
    extends $FunctionalProvider<PlacesSync, PlacesSync, PlacesSync>
    with $Provider<PlacesSync> {
  /// The sync of every region kept, or of France by box against an API
  /// without regions.
  // keepAlive: a stateless service, wired once.
  PlacesSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placesSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placesSyncHash();

  @$internal
  @override
  $ProviderElement<PlacesSync> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlacesSync create(Ref ref) {
    return placesSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlacesSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlacesSync>(value),
    );
  }
}

String _$placesSyncHash() => r'094eb6061a2243b16cec6aa260579d918a150cad';

/// The state of each region held, and the places of each.

@ProviderFor(regionStates)
final regionStatesProvider = RegionStatesProvider._();

/// The state of each region held, and the places of each.

final class RegionStatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, SyncState>>,
          Map<String, SyncState>,
          Stream<Map<String, SyncState>>
        >
    with
        $FutureModifier<Map<String, SyncState>>,
        $StreamProvider<Map<String, SyncState>> {
  /// The state of each region held, and the places of each.
  RegionStatesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'regionStatesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionStatesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, SyncState>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, SyncState>> create(Ref ref) {
    return regionStates(ref);
  }
}

String _$regionStatesHash() => r'9e9e084d5264838fcc9b99e76437b5c69f80dbe6';

@ProviderFor(regionPlaceCounts)
final regionPlaceCountsProvider = RegionPlaceCountsProvider._();

final class RegionPlaceCountsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, int>>,
          Map<String, int>,
          Stream<Map<String, int>>
        >
    with $FutureModifier<Map<String, int>>, $StreamProvider<Map<String, int>> {
  RegionPlaceCountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'regionPlaceCountsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$regionPlaceCountsHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, int>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, int>> create(Ref ref) {
    return regionPlaceCounts(ref);
  }
}

String _$regionPlaceCountsHash() => r'e65774fa5a6116b7eeb52383c7871e64c7f19edd';
