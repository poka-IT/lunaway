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

@ProviderFor(listedPlaces)
final listedPlacesProvider = ListedPlacesProvider._();

/// The list beside the map as it shows. The digests of its rows come from
/// the API: by the ids of a page the API sent, by the area (on the API's
/// grid) of a list read from the tiles or the device, so that no request
/// says more of the view than the tiles or the list's own requests do. The
/// list waits for them a moment, so the rows do not jump when the ratings
/// come.

final class ListedPlacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<ListedPage>,
          ListedPage,
          FutureOr<ListedPage>
        >
    with $FutureModifier<ListedPage>, $FutureProvider<ListedPage> {
  /// The list beside the map as it shows. The digests of its rows come from
  /// the API: by the ids of a page the API sent, by the area (on the API's
  /// grid) of a list read from the tiles or the device, so that no request
  /// says more of the view than the tiles or the list's own requests do. The
  /// list waits for them a moment, so the rows do not jump when the ratings
  /// come.
  ListedPlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
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

String _$listedPlacesHash() => r'd23ad19a8e86321e61943cf37caadd423e380d25';
