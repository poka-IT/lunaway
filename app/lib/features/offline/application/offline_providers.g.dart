// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The files of the offline maps; an empty stand-in on the web and the
/// desktops.
// keepAlive: one folder for the run, its path resolved once.

@ProviderFor(packFiles)
final packFilesProvider = PackFilesProvider._();

/// The files of the offline maps; an empty stand-in on the web and the
/// desktops.
// keepAlive: one folder for the run, its path resolved once.

final class PackFilesProvider
    extends $FunctionalProvider<PackFiles, PackFiles, PackFiles>
    with $Provider<PackFiles> {
  /// The files of the offline maps; an empty stand-in on the web and the
  /// desktops.
  // keepAlive: one folder for the run, its path resolved once.
  PackFilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'packFilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$packFilesHash();

  @$internal
  @override
  $ProviderElement<PackFiles> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PackFiles create(Ref ref) {
    return packFiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PackFiles value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PackFiles>(value),
    );
  }
}

String _$packFilesHash() => r'49f0149912cb7c7cb2d060b042cc418fb37a4c22';

/// Whether this platform keeps maps offline (Android and iOS).

@ProviderFor(offlineMapsSupported)
final offlineMapsSupportedProvider = OfflineMapsSupportedProvider._();

/// Whether this platform keeps maps offline (Android and iOS).

final class OfflineMapsSupportedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether this platform keeps maps offline (Android and iOS).
  OfflineMapsSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'offlineMapsSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$offlineMapsSupportedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return offlineMapsSupported(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$offlineMapsSupportedHash() =>
    r'fc290891edf9683a7683d648ce0961ca4f5d0738';

/// The outlines of the packs, from the app's assets.
// keepAlive: a constant of the run, read by the map at every move.

@ProviderFor(packOutlines)
final packOutlinesProvider = PackOutlinesProvider._();

/// The outlines of the packs, from the app's assets.
// keepAlive: a constant of the run, read by the map at every move.

final class PackOutlinesProvider
    extends
        $FunctionalProvider<
          AsyncValue<PackOutlines>,
          PackOutlines,
          FutureOr<PackOutlines>
        >
    with $FutureModifier<PackOutlines>, $FutureProvider<PackOutlines> {
  /// The outlines of the packs, from the app's assets.
  // keepAlive: a constant of the run, read by the map at every move.
  PackOutlinesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'packOutlinesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$packOutlinesHash();

  @$internal
  @override
  $FutureProviderElement<PackOutlines> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PackOutlines> create(Ref ref) {
    return packOutlines(ref);
  }
}

String _$packOutlinesHash() => r'6fd0c18c6763efac646bf8e70fa020fa7e9aa818';

/// The manifest's address on the tile host.

@ProviderFor(packManifestUrl)
final packManifestUrlProvider = PackManifestUrlProvider._();

/// The manifest's address on the tile host.

final class PackManifestUrlProvider extends $FunctionalProvider<Uri, Uri, Uri>
    with $Provider<Uri> {
  /// The manifest's address on the tile host.
  PackManifestUrlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'packManifestUrlProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$packManifestUrlHash();

  @$internal
  @override
  $ProviderElement<Uri> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Uri create(Ref ref) {
    return packManifestUrl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Uri value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Uri>(value),
    );
  }
}

String _$packManifestUrlHash() => r'49768ef7731e564f9f7770fa101c85143355ac67';

/// The packs to download: the manifest online, its copy offline. Offline
/// without a copy, the error reaches the screen.

@ProviderFor(packCatalog)
final packCatalogProvider = PackCatalogProvider._();

/// The packs to download: the manifest online, its copy offline. Offline
/// without a copy, the error reaches the screen.

final class PackCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<PackCatalog>,
          PackCatalog,
          FutureOr<PackCatalog>
        >
    with $FutureModifier<PackCatalog>, $FutureProvider<PackCatalog> {
  /// The packs to download: the manifest online, its copy offline. Offline
  /// without a copy, the error reaches the screen.
  PackCatalogProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'packCatalogProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$packCatalogHash();

  @$internal
  @override
  $FutureProviderElement<PackCatalog> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PackCatalog> create(Ref ref) {
    return packCatalog(ref);
  }
}

String _$packCatalogHash() => r'7b759bc5a6323c356e3c462272bbc28b07424ad9';

/// The packs on the device and their downloads, one at a time, in the
/// order asked. A download stops when the user pauses it, when the network
/// goes, when the app leaves the screen and at the end of the app; it
/// resumes from where it stopped (`Range`): when the user asks, when the
/// app comes back or starts again, and when the basemap's host answers
/// again after a failure for want of network. A whole file is checked
/// against the manifest's SHA-256 before it replaces anything.
// keepAlive: a download outlives the screen that started it.

@ProviderFor(OfflinePacks)
final offlinePacksProvider = OfflinePacksProvider._();

/// The packs on the device and their downloads, one at a time, in the
/// order asked. A download stops when the user pauses it, when the network
/// goes, when the app leaves the screen and at the end of the app; it
/// resumes from where it stopped (`Range`): when the user asks, when the
/// app comes back or starts again, and when the basemap's host answers
/// again after a failure for want of network. A whole file is checked
/// against the manifest's SHA-256 before it replaces anything.
// keepAlive: a download outlives the screen that started it.
final class OfflinePacksProvider
    extends $AsyncNotifierProvider<OfflinePacks, OfflineMaps> {
  /// The packs on the device and their downloads, one at a time, in the
  /// order asked. A download stops when the user pauses it, when the network
  /// goes, when the app leaves the screen and at the end of the app; it
  /// resumes from where it stopped (`Range`): when the user asks, when the
  /// app comes back or starts again, and when the basemap's host answers
  /// again after a failure for want of network. A whole file is checked
  /// against the manifest's SHA-256 before it replaces anything.
  // keepAlive: a download outlives the screen that started it.
  OfflinePacksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'offlinePacksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$offlinePacksHash();

  @$internal
  @override
  OfflinePacks create() => OfflinePacks();
}

String _$offlinePacksHash() => r'1564a9516ccda954393b62f067601730ee2f0972';

/// The packs on the device and their downloads, one at a time, in the
/// order asked. A download stops when the user pauses it, when the network
/// goes, when the app leaves the screen and at the end of the app; it
/// resumes from where it stopped (`Range`): when the user asks, when the
/// app comes back or starts again, and when the basemap's host answers
/// again after a failure for want of network. A whole file is checked
/// against the manifest's SHA-256 before it replaces anything.
// keepAlive: a download outlives the screen that started it.

abstract class _$OfflinePacks extends $AsyncNotifier<OfflineMaps> {
  FutureOr<OfflineMaps> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OfflineMaps>, OfflineMaps>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OfflineMaps>, OfflineMaps>,
              AsyncValue<OfflineMaps>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Where an offline style finds its files: the packs' folder, and that of
/// the glyphs and sprites; null before they are read, or where no map is
/// kept offline. Equal from one progress of a download to the next, so the
/// map's style is not made again four times a second.

@ProviderFor(offlineStyleFiles)
final offlineStyleFilesProvider = OfflineStyleFilesProvider._();

/// Where an offline style finds its files: the packs' folder, and that of
/// the glyphs and sprites; null before they are read, or where no map is
/// kept offline. Equal from one progress of a download to the next, so the
/// map's style is not made again four times a second.

final class OfflineStyleFilesProvider
    extends
        $FunctionalProvider<
          ({String directory, String styleAssets})?,
          ({String directory, String styleAssets})?,
          ({String directory, String styleAssets})?
        >
    with $Provider<({String directory, String styleAssets})?> {
  /// Where an offline style finds its files: the packs' folder, and that of
  /// the glyphs and sprites; null before they are read, or where no map is
  /// kept offline. Equal from one progress of a download to the next, so the
  /// map's style is not made again four times a second.
  OfflineStyleFilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'offlineStyleFilesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$offlineStyleFilesHash();

  @$internal
  @override
  $ProviderElement<({String directory, String styleAssets})?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ({String directory, String styleAssets})? create(Ref ref) {
    return offlineStyleFiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({String directory, String styleAssets})? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<({String directory, String styleAssets})?>(value),
    );
  }
}

String _$offlineStyleFilesHash() => r'8abcb2846dea1e85f5026a1ecb9817d32ebc05f8';

/// Whether the basemap's host answers: null until the first probe, false
/// when it does not (the device is offline, or the host is down: the map
/// then reads a downloaded pack where there is one). A small TileJSON read,
/// at launch, on each return to the foreground, every ten minutes online
/// and every minute offline, only while the app is in the foreground; and
/// when the map comes to rest or the guidance moves on with an answer older
/// than [staleAfter] (see [probeIfStale]).
// keepAlive: the map and its notice read it for the whole run.

@ProviderFor(BasemapReachability)
final basemapReachabilityProvider = BasemapReachabilityProvider._();

/// Whether the basemap's host answers: null until the first probe, false
/// when it does not (the device is offline, or the host is down: the map
/// then reads a downloaded pack where there is one). A small TileJSON read,
/// at launch, on each return to the foreground, every ten minutes online
/// and every minute offline, only while the app is in the foreground; and
/// when the map comes to rest or the guidance moves on with an answer older
/// than [staleAfter] (see [probeIfStale]).
// keepAlive: the map and its notice read it for the whole run.
final class BasemapReachabilityProvider
    extends $NotifierProvider<BasemapReachability, bool?> {
  /// Whether the basemap's host answers: null until the first probe, false
  /// when it does not (the device is offline, or the host is down: the map
  /// then reads a downloaded pack where there is one). A small TileJSON read,
  /// at launch, on each return to the foreground, every ten minutes online
  /// and every minute offline, only while the app is in the foreground; and
  /// when the map comes to rest or the guidance moves on with an answer older
  /// than [staleAfter] (see [probeIfStale]).
  // keepAlive: the map and its notice read it for the whole run.
  BasemapReachabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'basemapReachabilityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$basemapReachabilityHash();

  @$internal
  @override
  BasemapReachability create() => BasemapReachability();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool?>(value),
    );
  }
}

String _$basemapReachabilityHash() =>
    r'5229f908c41528dca750658f8b7c306848cba591';

/// Whether the basemap's host answers: null until the first probe, false
/// when it does not (the device is offline, or the host is down: the map
/// then reads a downloaded pack where there is one). A small TileJSON read,
/// at launch, on each return to the foreground, every ten minutes online
/// and every minute offline, only while the app is in the foreground; and
/// when the map comes to rest or the guidance moves on with an answer older
/// than [staleAfter] (see [probeIfStale]).
// keepAlive: the map and its notice read it for the whole run.

abstract class _$BasemapReachability extends $Notifier<bool?> {
  bool? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool?, bool?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool?, bool?>,
              bool?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The pack the map draws while the basemap's host does not answer: the
/// installed one under the centre of the view (the smallest, a region
/// before its country), and the last one while the view leaves every pack;
/// null online.
// keepAlive: the style of the map follows it for the whole run.

@ProviderFor(ActiveOfflinePack)
final activeOfflinePackProvider = ActiveOfflinePackProvider._();

/// The pack the map draws while the basemap's host does not answer: the
/// installed one under the centre of the view (the smallest, a region
/// before its country), and the last one while the view leaves every pack;
/// null online.
// keepAlive: the style of the map follows it for the whole run.
final class ActiveOfflinePackProvider
    extends $NotifierProvider<ActiveOfflinePack, InstalledPack?> {
  /// The pack the map draws while the basemap's host does not answer: the
  /// installed one under the centre of the view (the smallest, a region
  /// before its country), and the last one while the view leaves every pack;
  /// null online.
  // keepAlive: the style of the map follows it for the whole run.
  ActiveOfflinePackProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeOfflinePackProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeOfflinePackHash();

  @$internal
  @override
  ActiveOfflinePack create() => ActiveOfflinePack();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InstalledPack? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InstalledPack?>(value),
    );
  }
}

String _$activeOfflinePackHash() => r'3b2591704584d461b0f280c1e4cd463c649aa736';

/// The pack the map draws while the basemap's host does not answer: the
/// installed one under the centre of the view (the smallest, a region
/// before its country), and the last one while the view leaves every pack;
/// null online.
// keepAlive: the style of the map follows it for the whole run.

abstract class _$ActiveOfflinePack extends $Notifier<InstalledPack?> {
  InstalledPack? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<InstalledPack?, InstalledPack?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<InstalledPack?, InstalledPack?>,
              InstalledPack?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The places of the favourites, for the packs to suggest.

@ProviderFor(favoritePositions)
final favoritePositionsProvider = FavoritePositionsProvider._();

/// The places of the favourites, for the packs to suggest.

final class FavoritePositionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LatLng>>,
          List<LatLng>,
          FutureOr<List<LatLng>>
        >
    with $FutureModifier<List<LatLng>>, $FutureProvider<List<LatLng>> {
  /// The places of the favourites, for the packs to suggest.
  FavoritePositionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoritePositionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritePositionsHash();

  @$internal
  @override
  $FutureProviderElement<List<LatLng>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LatLng>> create(Ref ref) {
    return favoritePositions(ref);
  }
}

String _$favoritePositionsHash() => r'4fc085b9a0b5ca749be55dff0fe09bcfa198b98d';
