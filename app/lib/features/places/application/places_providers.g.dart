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

String _$graphQLClientHash() => r'c7aed3570c124e3f38725c95636d52328e08f1b5';

@ProviderFor(driftPlacesRepository)
final driftPlacesRepositoryProvider = DriftPlacesRepositoryProvider._();

final class DriftPlacesRepositoryProvider
    extends
        $FunctionalProvider<
          DriftPlacesRepository,
          DriftPlacesRepository,
          DriftPlacesRepository
        >
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
  $ProviderElement<DriftPlacesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

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

String _$driftPlacesRepositoryHash() =>
    r'2462291bdf100b47e896dc6db7cc5a16de40cb43';

/// The read side every screen uses; tests replace it with a fake.
// keepAlive: a repository over the app-wide database.

@ProviderFor(placesRepository)
final placesRepositoryProvider = PlacesRepositoryProvider._();

/// The read side every screen uses; tests replace it with a fake.
// keepAlive: a repository over the app-wide database.

final class PlacesRepositoryProvider
    extends
        $FunctionalProvider<
          PlacesRepository,
          PlacesRepository,
          PlacesRepository
        >
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

final class SyncServiceProvider
    extends $FunctionalProvider<SyncService, SyncService, SyncService>
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

/// Whether this device keeps places of its own for offline use (regions,
/// packs, the change feed): not the web, which reads them from the API's
/// tiles and queries and keeps only what the user opened.
// keepAlive: a constant of the run.

@ProviderFor(keepsPlaces)
final keepsPlacesProvider = KeepsPlacesProvider._();

/// Whether this device keeps places of its own for offline use (regions,
/// packs, the change feed): not the web, which reads them from the API's
/// tiles and queries and keeps only what the user opened.
// keepAlive: a constant of the run.

final class KeepsPlacesProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether this device keeps places of its own for offline use (regions,
  /// packs, the change feed): not the web, which reads them from the API's
  /// tiles and queries and keeps only what the user opened.
  // keepAlive: a constant of the run.
  KeepsPlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keepsPlacesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keepsPlacesHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return keepsPlaces(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$keepsPlacesHash() => r'2e13fbf018579399196d94ecc411b0caea4d83f4';

/// How long the first sync of a run waits behind the map: `afterMap` once
/// the map has drawn its first view (the tiles of that view load first),
/// `atLatest` when no map shows; replaced in tests.
// keepAlive: a constant of the run.

@ProviderFor(syncStartDelays)
final syncStartDelaysProvider = SyncStartDelaysProvider._();

/// How long the first sync of a run waits behind the map: `afterMap` once
/// the map has drawn its first view (the tiles of that view load first),
/// `atLatest` when no map shows; replaced in tests.
// keepAlive: a constant of the run.

final class SyncStartDelaysProvider
    extends
        $FunctionalProvider<
          ({Duration afterMap, Duration atLatest}),
          ({Duration afterMap, Duration atLatest}),
          ({Duration afterMap, Duration atLatest})
        >
    with $Provider<({Duration afterMap, Duration atLatest})> {
  /// How long the first sync of a run waits behind the map: `afterMap` once
  /// the map has drawn its first view (the tiles of that view load first),
  /// `atLatest` when no map shows; replaced in tests.
  // keepAlive: a constant of the run.
  SyncStartDelaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncStartDelaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncStartDelaysHash();

  @$internal
  @override
  $ProviderElement<({Duration afterMap, Duration atLatest})> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ({Duration afterMap, Duration atLatest}) create(Ref ref) {
    return syncStartDelays(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({Duration afterMap, Duration atLatest}) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<({Duration afterMap, Duration atLatest})>(value),
    );
  }
}

String _$syncStartDelaysHash() => r'ce755d588b3dbb94304a19b757c344168cabfe1a';

/// The waits between automatic retries of a failed sync, the last one
/// repeated; replaced in tests.
// keepAlive: a constant of the run.

@ProviderFor(syncRetryDelays)
final syncRetryDelaysProvider = SyncRetryDelaysProvider._();

/// The waits between automatic retries of a failed sync, the last one
/// repeated; replaced in tests.
// keepAlive: a constant of the run.

final class SyncRetryDelaysProvider
    extends $FunctionalProvider<List<Duration>, List<Duration>, List<Duration>>
    with $Provider<List<Duration>> {
  /// The waits between automatic retries of a failed sync, the last one
  /// repeated; replaced in tests.
  // keepAlive: a constant of the run.
  SyncRetryDelaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncRetryDelaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncRetryDelaysHash();

  @$internal
  @override
  $ProviderElement<List<Duration>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Duration> create(Ref ref) {
    return syncRetryDelays(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Duration> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Duration>>(value),
    );
  }
}

String _$syncRetryDelaysHash() => r'a95d2893ba7ae768cab9842e2e9d7520b2e9f5dd';

/// Runs the sync of the region and reports its progress. Started once by
/// the app: it syncs at launch when the data is old or a run was cut short,
/// again each time the app comes back to the foreground, after the user's
/// contributions reach the server, and retries a failed sync on its own
/// with a growing wait.
// keepAlive: a sync outlives the screen that started it.

@ProviderFor(SyncController)
final syncControllerProvider = SyncControllerProvider._();

/// Runs the sync of the region and reports its progress. Started once by
/// the app: it syncs at launch when the data is old or a run was cut short,
/// again each time the app comes back to the foreground, after the user's
/// contributions reach the server, and retries a failed sync on its own
/// with a growing wait.
// keepAlive: a sync outlives the screen that started it.
final class SyncControllerProvider
    extends $NotifierProvider<SyncController, SyncStatus> {
  /// Runs the sync of the region and reports its progress. Started once by
  /// the app: it syncs at launch when the data is old or a run was cut short,
  /// again each time the app comes back to the foreground, after the user's
  /// contributions reach the server, and retries a failed sync on its own
  /// with a growing wait.
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
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncStatus>(value),
    );
  }
}

String _$syncControllerHash() => r'cabf15f7b32a13607ce1a3ba448fd02ff1c74106';

/// Runs the sync of the region and reports its progress. Started once by
/// the app: it syncs at launch when the data is old or a run was cut short,
/// again each time the app comes back to the foreground, after the user's
/// contributions reach the server, and retries a failed sync on its own
/// with a growing wait.
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

/// The filter the map and the list query with: the user's filters, with
/// "my vehicle fits" turned into the stored vehicle's height.

@ProviderFor(effectiveFilter)
final effectiveFilterProvider = EffectiveFilterProvider._();

/// The filter the map and the list query with: the user's filters, with
/// "my vehicle fits" turned into the stored vehicle's height.

final class EffectiveFilterProvider
    extends $FunctionalProvider<PlaceFilter, PlaceFilter, PlaceFilter>
    with $Provider<PlaceFilter> {
  /// The filter the map and the list query with: the user's filters, with
  /// "my vehicle fits" turned into the stored vehicle's height.
  EffectiveFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'effectiveFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$effectiveFilterHash();

  @$internal
  @override
  $ProviderElement<PlaceFilter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaceFilter create(Ref ref) {
    return effectiveFilter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceFilter>(value),
    );
  }
}

String _$effectiveFilterHash() => r'db9a04415798b3cb7ae51aa20e45bc6bce202b84';

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
    with
        $FutureModifier<List<PlaceSummary>>,
        $StreamProvider<List<PlaceSummary>> {
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
  $StreamProviderElement<List<PlaceSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PlaceSummary>> create(Ref ref) {
    return mapPlaces(ref);
  }
}

String _$mapPlacesHash() => r'979c36a3a26865a95b52303ad4886ac4e826aa34';

/// One place for its page: the synced copy, the copy of an earlier
/// opening, or the API's ([PlaceReader]).

@ProviderFor(place)
final placeProvider = PlaceFamily._();

/// One place for its page: the synced copy, the copy of an earlier
/// opening, or the API's ([PlaceReader]).

final class PlaceProvider
    extends $FunctionalProvider<AsyncValue<Place?>, Place?, Stream<Place?>>
    with $FutureModifier<Place?>, $StreamProvider<Place?> {
  /// One place for its page: the synced copy, the copy of an earlier
  /// opening, or the API's ([PlaceReader]).
  PlaceProvider._({
    required PlaceFamily super.from,
    required String super.argument,
  }) : super(
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

String _$placeHash() => r'c3d7194ee4a2e3de1d90b8c4c485c5ef8971dd5e';

/// One place for its page: the synced copy, the copy of an earlier
/// opening, or the API's ([PlaceReader]).

final class PlaceFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Place?>, String> {
  PlaceFamily._()
    : super(
        retry: null,
        name: r'placeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One place for its page: the synced copy, the copy of an earlier
  /// opening, or the API's ([PlaceReader]).

  PlaceProvider call(String id) => PlaceProvider._(argument: id, from: this);

  @override
  String toString() => r'placeProvider';
}

@ProviderFor(onlinePlaces)
final onlinePlacesProvider = OnlinePlacesProvider._();

final class OnlinePlacesProvider
    extends $FunctionalProvider<OnlinePlaces, OnlinePlaces, OnlinePlaces>
    with $Provider<OnlinePlaces> {
  OnlinePlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onlinePlacesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onlinePlacesHash();

  @$internal
  @override
  $ProviderElement<OnlinePlaces> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OnlinePlaces create(Ref ref) {
    return onlinePlaces(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnlinePlaces value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnlinePlaces>(value),
    );
  }
}

String _$onlinePlacesHash() => r'8ed2be8458dc84b6a7d21e237351b75718ea5724';

@ProviderFor(placeReader)
final placeReaderProvider = PlaceReaderProvider._();

final class PlaceReaderProvider
    extends $FunctionalProvider<PlaceReader, PlaceReader, PlaceReader>
    with $Provider<PlaceReader> {
  PlaceReaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeReaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeReaderHash();

  @$internal
  @override
  $ProviderElement<PlaceReader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaceReader create(Ref ref) {
    return placeReader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceReader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceReader>(value),
    );
  }
}

String _$placeReaderHash() => r'777f5e63f0f0fef4f0558a6ce13babdc58355780';

/// The TileJSON of the places' vector tiles on the API.

@ProviderFor(placeTileJsonUrl)
final placeTileJsonUrlProvider = PlaceTileJsonUrlProvider._();

/// The TileJSON of the places' vector tiles on the API.

final class PlaceTileJsonUrlProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The TileJSON of the places' vector tiles on the API.
  PlaceTileJsonUrlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeTileJsonUrlProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeTileJsonUrlHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return placeTileJsonUrl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$placeTileJsonUrlHash() => r'8b054d955d9d7295744948b848e29d9783b12241';

/// Whether the map draws the places from the API's vector tiles, and the
/// list and the search ask the API: always on the web, which keeps no
/// places; on a phone while the network answers (the places the device
/// holds take over offline). A demo build has no server behind its tiles.
// keepAlive: the map, the list and the reader of places follow it all the run.

@ProviderFor(placesFromTiles)
final placesFromTilesProvider = PlacesFromTilesProvider._();

/// Whether the map draws the places from the API's vector tiles, and the
/// list and the search ask the API: always on the web, which keeps no
/// places; on a phone while the network answers (the places the device
/// holds take over offline). A demo build has no server behind its tiles.
// keepAlive: the map, the list and the reader of places follow it all the run.

final class PlacesFromTilesProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the map draws the places from the API's vector tiles, and the
  /// list and the search ask the API: always on the web, which keeps no
  /// places; on a phone while the network answers (the places the device
  /// holds take over offline). A demo build has no server behind its tiles.
  // keepAlive: the map, the list and the reader of places follow it all the run.
  PlacesFromTilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placesFromTilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placesFromTilesHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return placesFromTiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$placesFromTilesHash() => r'3812bbd31fe46555b8ccb0c944a61114d24cff56';

@ProviderFor(placeCount)
final placeCountProvider = PlaceCountProvider._();

final class PlaceCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
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

/// How many places a filter keeps, before the user applies it: those the
/// device holds, or with the places from the tiles, those of the map's
/// view as the API counts them once the choice pauses.

@ProviderFor(filterPreviewCount)
final filterPreviewCountProvider = FilterPreviewCountFamily._();

/// How many places a filter keeps, before the user applies it: those the
/// device holds, or with the places from the tiles, those of the map's
/// view as the API counts them once the choice pauses.

final class FilterPreviewCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// How many places a filter keeps, before the user applies it: those the
  /// device holds, or with the places from the tiles, those of the map's
  /// view as the API counts them once the choice pauses.
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

String _$filterPreviewCountHash() =>
    r'ee600a955d3533efb2af61e7a1c4cbe21fcc38a4';

/// How many places a filter keeps, before the user applies it: those the
/// device holds, or with the places from the tiles, those of the map's
/// view as the API counts them once the choice pauses.

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

  /// How many places a filter keeps, before the user applies it: those the
  /// device holds, or with the places from the tiles, those of the map's
  /// view as the API counts them once the choice pauses.

  FilterPreviewCountProvider call(PlaceFilter filter) =>
      FilterPreviewCountProvider._(argument: filter, from: this);

  @override
  String toString() => r'filterPreviewCountProvider';
}

/// Where the sync stands, as stored: every region kept together
/// ([overallSyncState]), or France by box before any region was chosen.

@ProviderFor(syncState)
final syncStateProvider = SyncStateProvider._();

/// Where the sync stands, as stored: every region kept together
/// ([overallSyncState]), or France by box before any region was chosen.

final class SyncStateProvider
    extends
        $FunctionalProvider<AsyncValue<SyncState>, SyncState, Stream<SyncState>>
    with $FutureModifier<SyncState>, $StreamProvider<SyncState> {
  /// Where the sync stands, as stored: every region kept together
  /// ([overallSyncState]), or France by box before any region was chosen.
  SyncStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncStateHash();

  @$internal
  @override
  $StreamProviderElement<SyncState> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<SyncState> create(Ref ref) {
    return syncState(ref);
  }
}

String _$syncStateHash() => r'9c7b4871b63a878b1563fae82f0d0a2792723955';

@ProviderFor(storageSize)
final storageSizeProvider = StorageSizeProvider._();

final class StorageSizeProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
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
    extends
        $FunctionalProvider<
          PlaceExtrasRepository,
          PlaceExtrasRepository,
          PlaceExtrasRepository
        >
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
  $ProviderElement<PlaceExtrasRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

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

String _$placeExtrasRepositoryHash() =>
    r'edcafdbd7434c0467785a2e6bd2a8759095d4ef5';

/// Photos and reviews of a place, online with a cache. A failure without a
/// cached copy surfaces, so the screen can say a connection is needed.

@ProviderFor(placeExtras)
final placeExtrasProvider = PlaceExtrasFamily._();

/// Photos and reviews of a place, online with a cache. A failure without a
/// cached copy surfaces, so the screen can say a connection is needed.

final class PlaceExtrasProvider
    extends
        $FunctionalProvider<
          AsyncValue<PlaceExtras?>,
          PlaceExtras?,
          Stream<PlaceExtras?>
        >
    with $FutureModifier<PlaceExtras?>, $StreamProvider<PlaceExtras?> {
  /// Photos and reviews of a place, online with a cache. A failure without a
  /// cached copy surfaces, so the screen can say a connection is needed.
  PlaceExtrasProvider._({
    required PlaceExtrasFamily super.from,
    required String super.argument,
  }) : super(
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
  $StreamProviderElement<PlaceExtras?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

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

  PlaceExtrasProvider call(String placeId) =>
      PlaceExtrasProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeExtrasProvider';
}

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand. Like the extras it reads, a failure surfaces at
/// once instead of being retried behind the user's back.

@ProviderFor(PlaceReviews)
final placeReviewsProvider = PlaceReviewsFamily._();

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand. Like the extras it reads, a failure surfaces at
/// once instead of being retried behind the user's back.
final class PlaceReviewsProvider
    extends $AsyncNotifierProvider<PlaceReviews, ReviewList> {
  /// The reviews shown for a place: the first page with the extras, the next
  /// ones appended on demand. Like the extras it reads, a failure surfaces at
  /// once instead of being retried behind the user's back.
  PlaceReviewsProvider._({
    required PlaceReviewsFamily super.from,
    required String super.argument,
  }) : super(
         retry: noRetry,
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

String _$placeReviewsHash() => r'a9a54e3d33e23233e6816574a4c4491cf1e4a2bd';

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand. Like the extras it reads, a failure surfaces at
/// once instead of being retried behind the user's back.

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
        retry: noRetry,
        name: r'placeReviewsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The reviews shown for a place: the first page with the extras, the next
  /// ones appended on demand. Like the extras it reads, a failure surfaces at
  /// once instead of being retried behind the user's back.

  PlaceReviewsProvider call(String placeId) =>
      PlaceReviewsProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeReviewsProvider';
}

/// The reviews shown for a place: the first page with the extras, the next
/// ones appended on demand. Like the extras it reads, a failure surfaces at
/// once instead of being retried behind the user's back.

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

/// The search of the map; [near] ranks the nearest matches first. On the
/// device when it holds places (no request, and it works in a tunnel),
/// else the API's once typing pauses.

@ProviderFor(searchResults)
final searchResultsProvider = SearchResultsFamily._();

/// The search of the map; [near] ranks the nearest matches first. On the
/// device when it holds places (no request, and it works in a tunnel),
/// else the API's once typing pauses.

final class SearchResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<SearchResults>,
          SearchResults,
          FutureOr<SearchResults>
        >
    with $FutureModifier<SearchResults>, $FutureProvider<SearchResults> {
  /// The search of the map; [near] ranks the nearest matches first. On the
  /// device when it holds places (no request, and it works in a tunnel),
  /// else the API's once typing pauses.
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
  $FutureProviderElement<SearchResults> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

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

String _$searchResultsHash() => r'9a08d662f63eadc8a2c69985fac3b8f8adcf916b';

/// The search of the map; [near] ranks the nearest matches first. On the
/// device when it holds places (no request, and it works in a tunnel),
/// else the API's once typing pauses.

final class SearchResultsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<SearchResults>,
          (String, {LatLng? near})
        > {
  SearchResultsFamily._()
    : super(
        retry: null,
        name: r'searchResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The search of the map; [near] ranks the nearest matches first. On the
  /// device when it holds places (no request, and it works in a tunnel),
  /// else the API's once typing pauses.

  SearchResultsProvider call(String query, {LatLng? near}) =>
      SearchResultsProvider._(argument: (query, near: near), from: this);

  @override
  String toString() => r'searchResultsProvider';
}
