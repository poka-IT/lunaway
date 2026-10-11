// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rich_marks_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The photos and prices of the places the route maps draw rich.
// keepAlive: it remembers each place it asked about for the whole run, so
// a place passed again or shown on the preview then the guidance is asked
// once.

@ProviderFor(placeThumbs)
final placeThumbsProvider = PlaceThumbsProvider._();

/// The photos and prices of the places the route maps draw rich.
// keepAlive: it remembers each place it asked about for the whole run, so
// a place passed again or shown on the preview then the guidance is asked
// once.

final class PlaceThumbsProvider extends $FunctionalProvider<PlaceThumbs, PlaceThumbs, PlaceThumbs>
    with $Provider<PlaceThumbs> {
  /// The photos and prices of the places the route maps draw rich.
  // keepAlive: it remembers each place it asked about for the whole run, so
  // a place passed again or shown on the preview then the guidance is asked
  // once.
  PlaceThumbsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeThumbsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeThumbsHash();

  @$internal
  @override
  $ProviderElement<PlaceThumbs> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaceThumbs create(Ref ref) {
    return placeThumbs(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceThumbs value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceThumbs>(value),
    );
  }
}

String _$placeThumbsHash() => r'cd39274a1c6114bb2df5e157fd060ec63051fac2';

/// What draws the rich marks of the route maps.
// keepAlive: it remembers which photos failed for the run, so a place
// whose photo would not come is not asked again at each pass.

@ProviderFor(richArt)
final richArtProvider = RichArtProvider._();

/// What draws the rich marks of the route maps.
// keepAlive: it remembers which photos failed for the run, so a place
// whose photo would not come is not asked again at each pass.

final class RichArtProvider extends $FunctionalProvider<RichArt, RichArt, RichArt>
    with $Provider<RichArt> {
  /// What draws the rich marks of the route maps.
  // keepAlive: it remembers which photos failed for the run, so a place
  // whose photo would not come is not asked again at each pass.
  RichArtProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'richArtProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$richArtHash();

  @$internal
  @override
  $ProviderElement<RichArt> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  RichArt create(Ref ref) {
    return richArt(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RichArt value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<RichArt>(value));
  }
}

String _$richArtHash() => r'5afefbdb596cd9097be8935b95ce5aad84163c1d';
