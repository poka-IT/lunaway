// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listed_places.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The list beside the map as it shows. The digests of its rows come from
/// the API: by the ids of a page the API sent, by the area (on the API's
/// grid) of a list read from the tiles or the device, so that no request
/// says more of the view than the tiles or the list's own requests do. The
/// list waits for them a moment, so the rows do not jump when the ratings
/// come.
// No retry of its own: it fails only when the page of the view does,
// which retries already; retried twice over, the list would stay loading
// long after that page gave up.

@ProviderFor(listedPlaces)
final listedPlacesProvider = ListedPlacesProvider._();

/// The list beside the map as it shows. The digests of its rows come from
/// the API: by the ids of a page the API sent, by the area (on the API's
/// grid) of a list read from the tiles or the device, so that no request
/// says more of the view than the tiles or the list's own requests do. The
/// list waits for them a moment, so the rows do not jump when the ratings
/// come.
// No retry of its own: it fails only when the page of the view does,
// which retries already; retried twice over, the list would stay loading
// long after that page gave up.

final class ListedPlacesProvider
    extends $FunctionalProvider<AsyncValue<ListedPage>, ListedPage, FutureOr<ListedPage>>
    with $FutureModifier<ListedPage>, $FutureProvider<ListedPage> {
  /// The list beside the map as it shows. The digests of its rows come from
  /// the API: by the ids of a page the API sent, by the area (on the API's
  /// grid) of a list read from the tiles or the device, so that no request
  /// says more of the view than the tiles or the list's own requests do. The
  /// list waits for them a moment, so the rows do not jump when the ratings
  /// come.
  // No retry of its own: it fails only when the page of the view does,
  // which retries already; retried twice over, the list would stay loading
  // long after that page gave up.
  ListedPlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'listedPlacesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$listedPlacesHash();

  @$internal
  @override
  $FutureProviderElement<ListedPage> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<ListedPage> create(Ref ref) {
    return listedPlaces(ref);
  }
}

String _$listedPlacesHash() => r'c915515cc6978ae8995eac30b90b0f2c3a279418';
