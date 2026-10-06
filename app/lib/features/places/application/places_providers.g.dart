// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'places_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(graphQLClient)
final graphQLClientProvider = GraphQLClientProvider._();

final class GraphQLClientProvider
    extends $FunctionalProvider<GraphQLClient, GraphQLClient, GraphQLClient>
    with $Provider<GraphQLClient> {
  GraphQLClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'graphQLClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$graphQLClientHash();

  @$internal
  @override
  $ProviderElement<GraphQLClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GraphQLClient create(Ref ref) {
    return graphQLClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GraphQLClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GraphQLClient>(value),
    );
  }
}

String _$graphQLClientHash() => r'1c42650d01626d7a9b188e656814f36bce3f6258';

@ProviderFor(driftPlacesRepository)
final driftPlacesRepositoryProvider = DriftPlacesRepositoryProvider._();

final class DriftPlacesRepositoryProvider
    extends $FunctionalProvider<DriftPlacesRepository, DriftPlacesRepository, DriftPlacesRepository>
    with $Provider<DriftPlacesRepository> {
  DriftPlacesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'driftPlacesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$driftPlacesRepositoryHash();

  @$internal
  @override
  $ProviderElement<DriftPlacesRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DriftPlacesRepository create(Ref ref) {
    return driftPlacesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DriftPlacesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DriftPlacesRepository>(value),
    );
  }
}

String _$driftPlacesRepositoryHash() => r'65ebf086997a072d8546b06d0e857d0290c37b58';

/// The read side every screen uses; tests replace it with a fake.
// keepAlive: a repository over the app-wide database.

@ProviderFor(placesRepository)
final placesRepositoryProvider = PlacesRepositoryProvider._();

/// The read side every screen uses; tests replace it with a fake.
// keepAlive: a repository over the app-wide database.

final class PlacesRepositoryProvider
    extends $FunctionalProvider<PlacesRepository, PlacesRepository, PlacesRepository>
    with $Provider<PlacesRepository> {
  /// The read side every screen uses; tests replace it with a fake.
  // keepAlive: a repository over the app-wide database.
  PlacesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placesRepositoryHash();

  @$internal
  @override
  $ProviderElement<PlacesRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlacesRepository create(Ref ref) {
    return placesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlacesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlacesRepository>(value),
    );
  }
}

String _$placesRepositoryHash() => r'91a69d9c2faa3cfbed5ec48c05636d9715711e2b';

@ProviderFor(syncService)
final syncServiceProvider = SyncServiceProvider._();

final class SyncServiceProvider extends $FunctionalProvider<SyncService, SyncService, SyncService>
    with $Provider<SyncService> {
  SyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncServiceHash();

  @$internal
  @override
  $ProviderElement<SyncService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncService create(Ref ref) {
    return syncService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncService>(value),
    );
  }
}

String _$syncServiceHash() => r'be7ed1cffea8b9c4fe57457d9a4962fedab3140c';

/// Runs the sync of the region and reports its progress.
// keepAlive: a sync outlives the screen that started it.

@ProviderFor(SyncController)
final syncControllerProvider = SyncControllerProvider._();

/// Runs the sync of the region and reports its progress.
// keepAlive: a sync outlives the screen that started it.
final class SyncControllerProvider extends $NotifierProvider<SyncController, SyncStatus> {
  /// Runs the sync of the region and reports its progress.
  // keepAlive: a sync outlives the screen that started it.
  SyncControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncControllerHash();

  @$internal
  @override
  SyncController create() => SyncController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncStatus value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<SyncStatus>(value));
  }
}

String _$syncControllerHash() => r'22fd4c89a5af50fe87962626c8decf19d8838f26';

/// Runs the sync of the region and reports its progress.
// keepAlive: a sync outlives the screen that started it.

abstract class _$SyncController extends $Notifier<SyncStatus> {
  SyncStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SyncStatus, SyncStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncStatus, SyncStatus>,
              SyncStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Every place passing the filter, for the map.

@ProviderFor(mapPlaces)
final mapPlacesProvider = MapPlacesProvider._();

/// Every place passing the filter, for the map.

final class MapPlacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PlaceSummary>>,
          List<PlaceSummary>,
          Stream<List<PlaceSummary>>
        >
    with $FutureModifier<List<PlaceSummary>>, $StreamProvider<List<PlaceSummary>> {
  /// Every place passing the filter, for the map.
  MapPlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapPlacesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapPlacesHash();

  @$internal
  @override
  $StreamProviderElement<List<PlaceSummary>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<PlaceSummary>> create(Ref ref) {
    return mapPlaces(ref);
  }
}

String _$mapPlacesHash() => r'dffa56747fb214dc0919ac928a49809e3d00a520';

@ProviderFor(place)
final placeProvider = PlaceFamily._();

final class PlaceProvider extends $FunctionalProvider<AsyncValue<Place?>, Place?, Stream<Place?>>
    with $FutureModifier<Place?>, $StreamProvider<Place?> {
  PlaceProvider._({required PlaceFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'placeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeHash();

  @override
  String toString() {
    return r'placeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Place?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Place?> create(Ref ref) {
    final argument = this.argument as String;
    return place(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlaceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeHash() => r'adbd4ef4e04016208154346db9d0bd2a83637130';

final class PlaceFamily extends $Family with $FunctionalFamilyOverride<Stream<Place?>, String> {
  PlaceFamily._()
    : super(
        retry: null,
        name: r'placeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PlaceProvider call(String id) => PlaceProvider._(argument: id, from: this);

  @override
  String toString() => r'placeProvider';
}

@ProviderFor(placeCount)
final placeCountProvider = PlaceCountProvider._();

final class PlaceCountProvider extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  PlaceCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeCountHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return placeCount(ref);
  }
}

String _$placeCountHash() => r'2d060b78030305c4daafe89ae5b3331e749ce7c5';

/// How many places a filter keeps, before the user applies it.

@ProviderFor(filterPreviewCount)
final filterPreviewCountProvider = FilterPreviewCountFamily._();

/// How many places a filter keeps, before the user applies it.

final class FilterPreviewCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// How many places a filter keeps, before the user applies it.
  FilterPreviewCountProvider._({
    required FilterPreviewCountFamily super.from,
    required PlaceFilter super.argument,
  }) : super(
         retry: null,
         name: r'filterPreviewCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$filterPreviewCountHash();

  @override
  String toString() {
    return r'filterPreviewCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as PlaceFilter;
    return filterPreviewCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FilterPreviewCountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$filterPreviewCountHash() => r'6e2bdce56aed682567e8109cba1ed61c2146aa7c';

/// How many places a filter keeps, before the user applies it.

final class FilterPreviewCountFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, PlaceFilter> {
  FilterPreviewCountFamily._()
    : super(
        retry: null,
        name: r'filterPreviewCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// How many places a filter keeps, before the user applies it.

  FilterPreviewCountProvider call(PlaceFilter filter) =>
      FilterPreviewCountProvider._(argument: filter, from: this);

  @override
  String toString() => r'filterPreviewCountProvider';
}

@ProviderFor(lastSync)
final lastSyncProvider = LastSyncProvider._();

final class LastSyncProvider
    extends $FunctionalProvider<AsyncValue<DateTime?>, DateTime?, Stream<DateTime?>>
    with $FutureModifier<DateTime?>, $StreamProvider<DateTime?> {
  LastSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastSyncProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastSyncHash();

  @$internal
  @override
  $StreamProviderElement<DateTime?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<DateTime?> create(Ref ref) {
    return lastSync(ref);
  }
}

String _$lastSyncHash() => r'de13539ca64f39d847c287b53c15debf30e71d13';

@ProviderFor(storageSize)
final storageSizeProvider = StorageSizeProvider._();

final class StorageSizeProvider extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  StorageSizeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageSizeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageSizeHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return storageSize(ref);
  }
}

String _$storageSizeHash() => r'ef0dee521e0843231b2daf75320f28ecfe922f91';

@ProviderFor(placeExtrasRepository)
final placeExtrasRepositoryProvider = PlaceExtrasRepositoryProvider._();

final class PlaceExtrasRepositoryProvider
    extends $FunctionalProvider<PlaceExtrasRepository, PlaceExtrasRepository, PlaceExtrasRepository>
    with $Provider<PlaceExtrasRepository> {
  PlaceExtrasRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeExtrasRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeExtrasRepositoryHash();

  @$internal
  @override
  $ProviderElement<PlaceExtrasRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaceExtrasRepository create(Ref ref) {
    return placeExtrasRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceExtrasRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceExtrasRepository>(value),
    );
  }
}

String _$placeExtrasRepositoryHash() => r'e8d5836fc63388b4b04e8de38fc27fbb9657ee51';

/// Photos and reviews of a place, online with a cache. A failure without a
/// cached copy surfaces, so the screen can say a connection is needed.

@ProviderFor(placeExtras)
final placeExtrasProvider = PlaceExtrasFamily._();

/// Photos and reviews of a place, online with a cache. A failure without a
/// cached copy surfaces, so the screen can say a connection is needed.

final class PlaceExtrasProvider
    extends $FunctionalProvider<AsyncValue<PlaceExtras?>, PlaceExtras?, Stream<PlaceExtras?>>
    with $FutureModifier<PlaceExtras?>, $StreamProvider<PlaceExtras?> {
  /// Photos and reviews of a place, online with a cache. A failure without a
  /// cached copy surfaces, so the screen can say a connection is needed.
  PlaceExtrasProvider._({required PlaceExtrasFamily super.from, required String super.argument})
    : super(
        retry: noRetry,
        name: r'placeExtrasProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeExtrasHash();

  @override
  String toString() {
    return r'placeExtrasProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<PlaceExtras?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<PlaceExtras?> create(Ref ref) {
    final argument = this.argument as String;
    return placeExtras(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlaceExtrasProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeExtrasHash() => r'c0013923004e6295b0b4227cb58fb3962c78aae1';

/// Photos and reviews of a place, online with a cache. A failure without a
/// cached copy surfaces, so the screen can say a connection is needed.

final class PlaceExtrasFamily extends $Family
    with $FunctionalFamilyOverride<Stream<PlaceExtras?>, String> {
  PlaceExtrasFamily._()
    : super(
        retry: noRetry,
        name: r'placeExtrasProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Photos and reviews of a place, online with a cache. A failure without a
  /// cached copy surfaces, so the screen can say a connection is needed.

  PlaceExtrasProvider call(String placeId) => PlaceExtrasProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeExtrasProvider';
}

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand.

@ProviderFor(PlaceReviews)
final placeReviewsProvider = PlaceReviewsFamily._();

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand.
final class PlaceReviewsProvider extends $AsyncNotifierProvider<PlaceReviews, ReviewList> {
  /// The reviews shown for a place: the first page with the extras, the next
  /// ones appended on demand.
  PlaceReviewsProvider._({required PlaceReviewsFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'placeReviewsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeReviewsHash();

  @override
  String toString() {
    return r'placeReviewsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PlaceReviews create() => PlaceReviews();

  @override
  bool operator ==(Object other) {
    return other is PlaceReviewsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeReviewsHash() => r'2fc02142b4bdf723d782a26869e909a617bc7358';

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand.

final class PlaceReviewsFamily extends $Family
    with
        $ClassFamilyOverride<
          PlaceReviews,
          AsyncValue<ReviewList>,
          ReviewList,
          FutureOr<ReviewList>,
          String
        > {
  PlaceReviewsFamily._()
    : super(
        retry: null,
        name: r'placeReviewsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The reviews shown for a place: the first page with the extras, the next
  /// ones appended on demand.

  PlaceReviewsProvider call(String placeId) =>
      PlaceReviewsProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeReviewsProvider';
}

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand.

abstract class _$PlaceReviews extends $AsyncNotifier<ReviewList> {
  late final _$args = ref.$arg as String;
  String get placeId => _$args;

  FutureOr<ReviewList> build(String placeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ReviewList>, ReviewList>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReviewList>, ReviewList>,
              AsyncValue<ReviewList>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Local search; [near] ranks the nearest matches first.

@ProviderFor(searchResults)
final searchResultsProvider = SearchResultsFamily._();

/// Local search; [near] ranks the nearest matches first.

final class SearchResultsProvider
    extends $FunctionalProvider<AsyncValue<SearchResults>, SearchResults, FutureOr<SearchResults>>
    with $FutureModifier<SearchResults>, $FutureProvider<SearchResults> {
  /// Local search; [near] ranks the nearest matches first.
  SearchResultsProvider._({
    required SearchResultsFamily super.from,
    required (String, {LatLng? near}) super.argument,
  }) : super(
         retry: null,
         name: r'searchResultsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$searchResultsHash();

  @override
  String toString() {
    return r'searchResultsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<SearchResults> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<SearchResults> create(Ref ref) {
    final argument = this.argument as (String, {LatLng? near});
    return searchResults(ref, argument.$1, near: argument.near);
  }

  @override
  bool operator ==(Object other) {
    return other is SearchResultsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$searchResultsHash() => r'3ca1ef9a91f023662ede7e32513a9178cef19e07';

/// Local search; [near] ranks the nearest matches first.

final class SearchResultsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SearchResults>, (String, {LatLng? near})> {
  SearchResultsFamily._()
    : super(
        retry: null,
        name: r'searchResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Local search; [near] ranks the nearest matches first.

  SearchResultsProvider call(String query, {LatLng? near}) =>
      SearchResultsProvider._(argument: (query, near: near), from: this);

  @override
  String toString() => r'searchResultsProvider';
}
