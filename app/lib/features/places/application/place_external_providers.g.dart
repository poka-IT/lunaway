// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place_external_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(placeExternalSource)
final placeExternalSourceProvider = PlaceExternalSourceProvider._();

final class PlaceExternalSourceProvider
    extends
        $FunctionalProvider<
          PlaceExternalSource,
          PlaceExternalSource,
          PlaceExternalSource
        >
    with $Provider<PlaceExternalSource> {
  PlaceExternalSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeExternalSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeExternalSourceHash();

  @$internal
  @override
  $ProviderElement<PlaceExternalSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlaceExternalSource create(Ref ref) {
    return placeExternalSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceExternalSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceExternalSource>(value),
    );
  }
}

String _$placeExternalSourceHash() =>
    r'bc4bbed541a026320186ff34344ed1187394644d';

/// What the external community source says of a place, read when its card
/// opens and held in memory while it shows: never written to the device's
/// stores, so it is gone with the card. A failure surfaces without retry:
/// the card shows Lunaway's own content and leaves the source out.

@ProviderFor(PlaceExternal)
final placeExternalProvider = PlaceExternalFamily._();

/// What the external community source says of a place, read when its card
/// opens and held in memory while it shows: never written to the device's
/// stores, so it is gone with the card. A failure surfaces without retry:
/// the card shows Lunaway's own content and leaves the source out.
final class PlaceExternalProvider
    extends $AsyncNotifierProvider<PlaceExternal, ExternalList> {
  /// What the external community source says of a place, read when its card
  /// opens and held in memory while it shows: never written to the device's
  /// stores, so it is gone with the card. A failure surfaces without retry:
  /// the card shows Lunaway's own content and leaves the source out.
  PlaceExternalProvider._({
    required PlaceExternalFamily super.from,
    required String super.argument,
  }) : super(
         retry: noRetry,
         name: r'placeExternalProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$placeExternalHash();

  @override
  String toString() {
    return r'placeExternalProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PlaceExternal create() => PlaceExternal();

  @override
  bool operator ==(Object other) {
    return other is PlaceExternalProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeExternalHash() => r'a295688da05b5c2e892b840028b93b1c6515e959';

/// What the external community source says of a place, read when its card
/// opens and held in memory while it shows: never written to the device's
/// stores, so it is gone with the card. A failure surfaces without retry:
/// the card shows Lunaway's own content and leaves the source out.

final class PlaceExternalFamily extends $Family
    with
        $ClassFamilyOverride<
          PlaceExternal,
          AsyncValue<ExternalList>,
          ExternalList,
          FutureOr<ExternalList>,
          String
        > {
  PlaceExternalFamily._()
    : super(
        retry: noRetry,
        name: r'placeExternalProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What the external community source says of a place, read when its card
  /// opens and held in memory while it shows: never written to the device's
  /// stores, so it is gone with the card. A failure surfaces without retry:
  /// the card shows Lunaway's own content and leaves the source out.

  PlaceExternalProvider call(String placeId) =>
      PlaceExternalProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeExternalProvider';
}

/// What the external community source says of a place, read when its card
/// opens and held in memory while it shows: never written to the device's
/// stores, so it is gone with the card. A failure surfaces without retry:
/// the card shows Lunaway's own content and leaves the source out.

abstract class _$PlaceExternal extends $AsyncNotifier<ExternalList> {
  late final _$args = ref.$arg as String;
  String get placeId => _$args;

  FutureOr<ExternalList> build(String placeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ExternalList>, ExternalList>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ExternalList>, ExternalList>,
              AsyncValue<ExternalList>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Lunaway's reviews of a place merged with the external source's. The
/// external list counts as empty until it arrives or when it fails: the
/// card never waits on it. A muted author's reviews never show, nor the
/// account's own, which has its own card above the list.

@ProviderFor(placeReviewFeed)
final placeReviewFeedProvider = PlaceReviewFeedFamily._();

/// Lunaway's reviews of a place merged with the external source's. The
/// external list counts as empty until it arrives or when it fails: the
/// card never waits on it. A muted author's reviews never show, nor the
/// account's own, which has its own card above the list.

final class PlaceReviewFeedProvider
    extends $FunctionalProvider<ReviewFeed, ReviewFeed, ReviewFeed>
    with $Provider<ReviewFeed> {
  /// Lunaway's reviews of a place merged with the external source's. The
  /// external list counts as empty until it arrives or when it fails: the
  /// card never waits on it. A muted author's reviews never show, nor the
  /// account's own, which has its own card above the list.
  PlaceReviewFeedProvider._({
    required PlaceReviewFeedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'placeReviewFeedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$placeReviewFeedHash();

  @override
  String toString() {
    return r'placeReviewFeedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ReviewFeed> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ReviewFeed create(Ref ref) {
    final argument = this.argument as String;
    return placeReviewFeed(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReviewFeed value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReviewFeed>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaceReviewFeedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeReviewFeedHash() => r'4d9ab84996f0f180b8686415ab8b9aede50d24d0';

/// Lunaway's reviews of a place merged with the external source's. The
/// external list counts as empty until it arrives or when it fails: the
/// card never waits on it. A muted author's reviews never show, nor the
/// account's own, which has its own card above the list.

final class PlaceReviewFeedFamily extends $Family
    with $FunctionalFamilyOverride<ReviewFeed, String> {
  PlaceReviewFeedFamily._()
    : super(
        retry: null,
        name: r'placeReviewFeedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Lunaway's reviews of a place merged with the external source's. The
  /// external list counts as empty until it arrives or when it fails: the
  /// card never waits on it. A muted author's reviews never show, nor the
  /// account's own, which has its own card above the list.

  PlaceReviewFeedProvider call(String placeId) =>
      PlaceReviewFeedProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeReviewFeedProvider';
}
