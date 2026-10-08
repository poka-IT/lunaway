// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place_digests.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(placeDigestSource)
final placeDigestSourceProvider = PlaceDigestSourceProvider._();

final class PlaceDigestSourceProvider
    extends
        $FunctionalProvider<
          PlaceDigestSource,
          PlaceDigestSource,
          PlaceDigestSource
        >
    with $Provider<PlaceDigestSource> {
  PlaceDigestSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeDigestSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeDigestSourceHash();

  @$internal
  @override
  $ProviderElement<PlaceDigestSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlaceDigestSource create(Ref ref) {
    return placeDigestSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceDigestSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceDigestSource>(value),
    );
  }
}

String _$placeDigestSourceHash() => r'a7cb48d4f16eefb7399f4ece2cbd7187e87b8bb9';

/// The digests the lists read during this run, by place id, in the
/// interface's language: held in memory only, so the external source's
/// ratings never reach the device's stores. An area or a place is asked
/// once; a failed request is asked again by the next list that needs it.
// keepAlive: the rows of a list come back as the map pans to and fro, and
// reading them again at each pan would cost a request each time.

@ProviderFor(PlaceDigests)
final placeDigestsProvider = PlaceDigestsProvider._();

/// The digests the lists read during this run, by place id, in the
/// interface's language: held in memory only, so the external source's
/// ratings never reach the device's stores. An area or a place is asked
/// once; a failed request is asked again by the next list that needs it.
// keepAlive: the rows of a list come back as the map pans to and fro, and
// reading them again at each pan would cost a request each time.
final class PlaceDigestsProvider
    extends $NotifierProvider<PlaceDigests, Map<String, PlaceDigest>> {
  /// The digests the lists read during this run, by place id, in the
  /// interface's language: held in memory only, so the external source's
  /// ratings never reach the device's stores. An area or a place is asked
  /// once; a failed request is asked again by the next list that needs it.
  // keepAlive: the rows of a list come back as the map pans to and fro, and
  // reading them again at each pan would cost a request each time.
  PlaceDigestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeDigestsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeDigestsHash();

  @$internal
  @override
  PlaceDigests create() => PlaceDigests();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, PlaceDigest> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, PlaceDigest>>(value),
    );
  }
}

String _$placeDigestsHash() => r'162dc666df193e43552f68d4454ce1bc7f1e3fcc';

/// The digests the lists read during this run, by place id, in the
/// interface's language: held in memory only, so the external source's
/// ratings never reach the device's stores. An area or a place is asked
/// once; a failed request is asked again by the next list that needs it.
// keepAlive: the rows of a list come back as the map pans to and fro, and
// reading them again at each pan would cost a request each time.

abstract class _$PlaceDigests extends $Notifier<Map<String, PlaceDigest>> {
  Map<String, PlaceDigest> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<Map<String, PlaceDigest>, Map<String, PlaceDigest>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, PlaceDigest>, Map<String, PlaceDigest>>,
              Map<String, PlaceDigest>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
