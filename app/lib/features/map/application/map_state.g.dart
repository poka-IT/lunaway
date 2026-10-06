// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Selection)
final selectionProvider = SelectionProvider._();

final class SelectionProvider extends $NotifierProvider<Selection, MapSelection?> {
  SelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectionHash();

  @$internal
  @override
  Selection create() => Selection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapSelection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapSelection?>(value),
    );
  }
}

String _$selectionHash() => r'd145d9ce37604751d3543f555fc9c54f78e45327';

abstract class _$Selection extends $Notifier<MapSelection?> {
  MapSelection? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MapSelection?, MapSelection?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MapSelection?, MapSelection?>,
              MapSelection?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(Viewport)
final viewportProvider = ViewportProvider._();

final class ViewportProvider extends $NotifierProvider<Viewport, MapViewport?> {
  ViewportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewportProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewportHash();

  @$internal
  @override
  Viewport create() => Viewport();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapViewport? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapViewport?>(value),
    );
  }
}

String _$viewportHash() => r'7681554266d50dfd5930e3268bbe02ce2dbaf22e';

abstract class _$Viewport extends $Notifier<MapViewport?> {
  MapViewport? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MapViewport?, MapViewport?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MapViewport?, MapViewport?>,
              MapViewport?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The controller of the live map, once it is ready; null before.
// keepAlive: the list, the search and the favourites move the same map.

@ProviderFor(MapController)
final mapControllerProvider = MapControllerProvider._();

/// The controller of the live map, once it is ready; null before.
// keepAlive: the list, the search and the favourites move the same map.
final class MapControllerProvider extends $NotifierProvider<MapController, LunaMapController?> {
  /// The controller of the live map, once it is ready; null before.
  // keepAlive: the list, the search and the favourites move the same map.
  MapControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapControllerHash();

  @$internal
  @override
  MapController create() => MapController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LunaMapController? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LunaMapController?>(value),
    );
  }
}

String _$mapControllerHash() => r'ce76ddd496e4749acbc67801de8c17b94dbb0d05';

/// The controller of the live map, once it is ready; null before.
// keepAlive: the list, the search and the favourites move the same map.

abstract class _$MapController extends $Notifier<LunaMapController?> {
  LunaMapController? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LunaMapController?, LunaMapController?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LunaMapController?, LunaMapController?>,
              LunaMapController?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The last known device position.
// keepAlive: distances in the list keep using it across tabs.

@ProviderFor(UserLocation)
final userLocationProvider = UserLocationProvider._();

/// The last known device position.
// keepAlive: distances in the list keep using it across tabs.
final class UserLocationProvider extends $NotifierProvider<UserLocation, LatLng?> {
  /// The last known device position.
  // keepAlive: distances in the list keep using it across tabs.
  UserLocationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userLocationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userLocationHash();

  @$internal
  @override
  UserLocation create() => UserLocation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LatLng? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<LatLng?>(value));
  }
}

String _$userLocationHash() => r'9477fab4c5f3d6a95351dc797125e9c43bd86f69';

/// The last known device position.
// keepAlive: distances in the list keep using it across tabs.

abstract class _$UserLocation extends $Notifier<LatLng?> {
  LatLng? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LatLng?, LatLng?>;
    final element =
        ref.element
            as $ClassProviderElement<AnyNotifier<LatLng?, LatLng?>, LatLng?, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// The places in the viewport, nearest to the user (or to the map centre)
/// first: the list beside the map.

@ProviderFor(nearbyPlaces)
final nearbyPlacesProvider = NearbyPlacesProvider._();

/// The places in the viewport, nearest to the user (or to the map centre)
/// first: the list beside the map.

final class NearbyPlacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PlaceSummary>>,
          List<PlaceSummary>,
          Stream<List<PlaceSummary>>
        >
    with $FutureModifier<List<PlaceSummary>>, $StreamProvider<List<PlaceSummary>> {
  /// The places in the viewport, nearest to the user (or to the map centre)
  /// first: the list beside the map.
  NearbyPlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nearbyPlacesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nearbyPlacesHash();

  @$internal
  @override
  $StreamProviderElement<List<PlaceSummary>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<PlaceSummary>> create(Ref ref) {
    return nearbyPlaces(ref);
  }
}

String _$nearbyPlacesHash() => r'5a314be6d7902fca52c6f37a68b149ad91a48912';

/// The map widget, swapped for a fake in widget tests where platform views do
/// not render.
// keepAlive: a constant of the run.

@ProviderFor(lunaMapBuilder)
final lunaMapBuilderProvider = LunaMapBuilderProvider._();

/// The map widget, swapped for a fake in widget tests where platform views do
/// not render.
// keepAlive: a constant of the run.

final class LunaMapBuilderProvider
    extends $FunctionalProvider<LunaMapBuilder, LunaMapBuilder, LunaMapBuilder>
    with $Provider<LunaMapBuilder> {
  /// The map widget, swapped for a fake in widget tests where platform views do
  /// not render.
  // keepAlive: a constant of the run.
  LunaMapBuilderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lunaMapBuilderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lunaMapBuilderHash();

  @$internal
  @override
  $ProviderElement<LunaMapBuilder> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LunaMapBuilder create(Ref ref) {
    return lunaMapBuilder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LunaMapBuilder value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LunaMapBuilder>(value),
    );
  }
}

String _$lunaMapBuilderHash() => r'baf8efb60a9daae0cd5c4998723a37f1547ddeba';

/// What the user typed in the map's search field.

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

/// What the user typed in the map's search field.
final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  /// What the user typed in the map's search field.
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<String>(value));
  }
}

String _$searchQueryHash() => r'010d2d1ceac3b2594e8d7295041c08541c88f4bb';

/// What the user typed in the map's search field.

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element as $ClassProviderElement<AnyNotifier<String, String>, String, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
