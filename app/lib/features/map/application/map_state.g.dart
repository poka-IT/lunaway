// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How many times the selection was chosen again while it showed: the page
/// open goes back to its top, as for a place newly opened. The same place
/// chosen again (from the search, the list, its pin) changes no selection
/// (`MapFlow.select`).
// keepAlive: a count of the run, read by whichever page is open.

@ProviderFor(Reselections)
final reselectionsProvider = ReselectionsProvider._();

/// How many times the selection was chosen again while it showed: the page
/// open goes back to its top, as for a place newly opened. The same place
/// chosen again (from the search, the list, its pin) changes no selection
/// (`MapFlow.select`).
// keepAlive: a count of the run, read by whichever page is open.
final class ReselectionsProvider extends $NotifierProvider<Reselections, int> {
  /// How many times the selection was chosen again while it showed: the page
  /// open goes back to its top, as for a place newly opened. The same place
  /// chosen again (from the search, the list, its pin) changes no selection
  /// (`MapFlow.select`).
  // keepAlive: a count of the run, read by whichever page is open.
  ReselectionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reselectionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reselectionsHash();

  @$internal
  @override
  Reselections create() => Reselections();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$reselectionsHash() => r'56810264725188a9b290effac91a57d0deee7dab';

/// How many times the selection was chosen again while it showed: the page
/// open goes back to its top, as for a place newly opened. The same place
/// chosen again (from the search, the list, its pin) changes no selection
/// (`MapFlow.select`).
// keepAlive: a count of the run, read by whichever page is open.

abstract class _$Reselections extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
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
final class MapControllerProvider
    extends $NotifierProvider<MapController, LunaMapController?> {
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

/// The location permission of the platform; a fake in widget tests.
// keepAlive: stateless, wired once.

@ProviderFor(locationPermissions)
final locationPermissionsProvider = LocationPermissionsProvider._();

/// The location permission of the platform; a fake in widget tests.
// keepAlive: stateless, wired once.

final class LocationPermissionsProvider
    extends
        $FunctionalProvider<
          LocationPermissions,
          LocationPermissions,
          LocationPermissions
        >
    with $Provider<LocationPermissions> {
  /// The location permission of the platform; a fake in widget tests.
  // keepAlive: stateless, wired once.
  LocationPermissionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'locationPermissionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$locationPermissionsHash();

  @$internal
  @override
  $ProviderElement<LocationPermissions> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LocationPermissions create(Ref ref) {
    return locationPermissions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocationPermissions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocationPermissions>(value),
    );
  }
}

String _$locationPermissionsHash() =>
    r'fb5f761a3e8c462f7b337a02a3a81f902341b560';

/// Where the last known position is kept between runs.
// keepAlive: a repository over the app-wide database.

@ProviderFor(lastPositionStore)
final lastPositionStoreProvider = LastPositionStoreProvider._();

/// Where the last known position is kept between runs.
// keepAlive: a repository over the app-wide database.

final class LastPositionStoreProvider
    extends
        $FunctionalProvider<
          LastPositionStore,
          LastPositionStore,
          LastPositionStore
        >
    with $Provider<LastPositionStore> {
  /// Where the last known position is kept between runs.
  // keepAlive: a repository over the app-wide database.
  LastPositionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastPositionStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastPositionStoreHash();

  @$internal
  @override
  $ProviderElement<LastPositionStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LastPositionStore create(Ref ref) {
    return lastPositionStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LastPositionStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LastPositionStore>(value),
    );
  }
}

String _$lastPositionStoreHash() => r'0fa82364011926925c58fda56981d3283e06d553';

/// The coarse position stored by the previous run, read in `main` before the
/// first frame so the automatic theme is right from the start.
// keepAlive: a constant of the run.

@ProviderFor(initialPosition)
final initialPositionProvider = InitialPositionProvider._();

/// The coarse position stored by the previous run, read in `main` before the
/// first frame so the automatic theme is right from the start.
// keepAlive: a constant of the run.

final class InitialPositionProvider
    extends $FunctionalProvider<LatLng?, LatLng?, LatLng?>
    with $Provider<LatLng?> {
  /// The coarse position stored by the previous run, read in `main` before the
  /// first frame so the automatic theme is right from the start.
  // keepAlive: a constant of the run.
  InitialPositionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'initialPositionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$initialPositionHash();

  @$internal
  @override
  $ProviderElement<LatLng?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LatLng? create(Ref ref) {
    return initialPosition(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LatLng? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LatLng?>(value),
    );
  }
}

String _$initialPositionHash() => r'884e07dfdbad8cd36ac154a7522d6bd68c61e432';

/// Where the map was left between runs.
// keepAlive: a repository over the app-wide database.

@ProviderFor(lastViewStore)
final lastViewStoreProvider = LastViewStoreProvider._();

/// Where the map was left between runs.
// keepAlive: a repository over the app-wide database.

final class LastViewStoreProvider
    extends $FunctionalProvider<LastViewStore, LastViewStore, LastViewStore>
    with $Provider<LastViewStore> {
  /// Where the map was left between runs.
  // keepAlive: a repository over the app-wide database.
  LastViewStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastViewStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastViewStoreHash();

  @$internal
  @override
  $ProviderElement<LastViewStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LastViewStore create(Ref ref) {
    return lastViewStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LastViewStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LastViewStore>(value),
    );
  }
}

String _$lastViewStoreHash() => r'8ed3bd4c9a87515efc8f0f616b232006a29fcbcb';

/// The view the previous run left the map on, read in `main` before the
/// first frame: the map opens there, null on a first launch.
// keepAlive: a constant of the run.

@ProviderFor(initialView)
final initialViewProvider = InitialViewProvider._();

/// The view the previous run left the map on, read in `main` before the
/// first frame: the map opens there, null on a first launch.
// keepAlive: a constant of the run.

final class InitialViewProvider
    extends $FunctionalProvider<SavedView?, SavedView?, SavedView?>
    with $Provider<SavedView?> {
  /// The view the previous run left the map on, read in `main` before the
  /// first frame: the map opens there, null on a first launch.
  // keepAlive: a constant of the run.
  InitialViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'initialViewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$initialViewHash();

  @$internal
  @override
  $ProviderElement<SavedView?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SavedView? create(Ref ref) {
    return initialView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SavedView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SavedView?>(value),
    );
  }
}

String _$initialViewHash() => r'abd69ee251f63556df03a37d4565c6b8e53c7ea6';

/// The basemap style templates, read from the assets in `main` before the
/// first frame, so the map never waits on a file to get its style.
// keepAlive: a constant of the run.

@ProviderFor(basemapTemplates)
final basemapTemplatesProvider = BasemapTemplatesProvider._();

/// The basemap style templates, read from the assets in `main` before the
/// first frame, so the map never waits on a file to get its style.
// keepAlive: a constant of the run.

final class BasemapTemplatesProvider
    extends
        $FunctionalProvider<
          BasemapTemplates,
          BasemapTemplates,
          BasemapTemplates
        >
    with $Provider<BasemapTemplates> {
  /// The basemap style templates, read from the assets in `main` before the
  /// first frame, so the map never waits on a file to get its style.
  // keepAlive: a constant of the run.
  BasemapTemplatesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'basemapTemplatesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$basemapTemplatesHash();

  @$internal
  @override
  $ProviderElement<BasemapTemplates> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BasemapTemplates create(Ref ref) {
    return basemapTemplates(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BasemapTemplates value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BasemapTemplates>(value),
    );
  }
}

String _$basemapTemplatesHash() => r'270783c70eba3bef13f43889b25816b10b3d5542';

/// The basemap style the map loads: Minuit when [dark], Aube otherwise,
/// pointed at the configured tile host, labelled in [language]; while the
/// host does not answer, at the pack downloaded for the view, with the
/// glyphs and sprites the app carries.

@ProviderFor(basemapStyle)
final basemapStyleProvider = BasemapStyleFamily._();

/// The basemap style the map loads: Minuit when [dark], Aube otherwise,
/// pointed at the configured tile host, labelled in [language]; while the
/// host does not answer, at the pack downloaded for the view, with the
/// glyphs and sprites the app carries.

final class BasemapStyleProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The basemap style the map loads: Minuit when [dark], Aube otherwise,
  /// pointed at the configured tile host, labelled in [language]; while the
  /// host does not answer, at the pack downloaded for the view, with the
  /// glyphs and sprites the app carries.
  BasemapStyleProvider._({
    required BasemapStyleFamily super.from,
    required ({bool dark, String language}) super.argument,
  }) : super(
         retry: null,
         name: r'basemapStyleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$basemapStyleHash();

  @override
  String toString() {
    return r'basemapStyleProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    final argument = this.argument as ({bool dark, String language});
    return basemapStyle(ref, dark: argument.dark, language: argument.language);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BasemapStyleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$basemapStyleHash() => r'85c6cdeb962da3c0b119e50a6cffc33acae65e95';

/// The basemap style the map loads: Minuit when [dark], Aube otherwise,
/// pointed at the configured tile host, labelled in [language]; while the
/// host does not answer, at the pack downloaded for the view, with the
/// glyphs and sprites the app carries.

final class BasemapStyleFamily extends $Family
    with $FunctionalFamilyOverride<String, ({bool dark, String language})> {
  BasemapStyleFamily._()
    : super(
        retry: null,
        name: r'basemapStyleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The basemap style the map loads: Minuit when [dark], Aube otherwise,
  /// pointed at the configured tile host, labelled in [language]; while the
  /// host does not answer, at the pack downloaded for the view, with the
  /// glyphs and sprites the app carries.

  BasemapStyleProvider call({required bool dark, required String language}) =>
      BasemapStyleProvider._(
        argument: (dark: dark, language: language),
        from: this,
      );

  @override
  String toString() => r'basemapStyleProvider';
}

/// The device position located during this run.
// keepAlive: distances in the list keep using it across tabs.

@ProviderFor(UserLocation)
final userLocationProvider = UserLocationProvider._();

/// The device position located during this run.
// keepAlive: distances in the list keep using it across tabs.
final class UserLocationProvider
    extends $NotifierProvider<UserLocation, LatLng?> {
  /// The device position located during this run.
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
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LatLng?>(value),
    );
  }
}

String _$userLocationHash() => r'ea17efdb5740934bcb5f43cc436acc8242c6f968';

/// The device position located during this run.
// keepAlive: distances in the list keep using it across tabs.

abstract class _$UserLocation extends $Notifier<LatLng?> {
  LatLng? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LatLng?, LatLng?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LatLng?, LatLng?>,
              LatLng?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The position the sun is computed at for the automatic theme: this run's,
/// else the one the previous run stored.

@ProviderFor(sunPosition)
final sunPositionProvider = SunPositionProvider._();

/// The position the sun is computed at for the automatic theme: this run's,
/// else the one the previous run stored.

final class SunPositionProvider
    extends $FunctionalProvider<LatLng?, LatLng?, LatLng?>
    with $Provider<LatLng?> {
  /// The position the sun is computed at for the automatic theme: this run's,
  /// else the one the previous run stored.
  SunPositionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sunPositionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sunPositionHash();

  @$internal
  @override
  $ProviderElement<LatLng?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LatLng? create(Ref ref) {
    return sunPosition(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LatLng? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LatLng?>(value),
    );
  }
}

String _$sunPositionHash() => r'846cbf1e9ddb9e1e9f9849671a1ab058d7b7cd5a';

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
    with
        $FutureModifier<List<PlaceSummary>>,
        $StreamProvider<List<PlaceSummary>> {
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
  $StreamProviderElement<List<PlaceSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PlaceSummary>> create(Ref ref) {
    return nearbyPlaces(ref);
  }
}

String _$nearbyPlacesHash() => r'7be2753b027bd88e436462ff4cd350be1b8e4127';

/// The selected place as the map draws its pin and the sheet titles it:
/// the place once read, what the tap or the row knew before that.

@ProviderFor(selectedPlace)
final selectedPlaceProvider = SelectedPlaceProvider._();

/// The selected place as the map draws its pin and the sheet titles it:
/// the place once read, what the tap or the row knew before that.

final class SelectedPlaceProvider
    extends $FunctionalProvider<PlaceSummary?, PlaceSummary?, PlaceSummary?>
    with $Provider<PlaceSummary?> {
  /// The selected place as the map draws its pin and the sheet titles it:
  /// the place once read, what the tap or the row knew before that.
  SelectedPlaceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedPlaceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedPlaceHash();

  @$internal
  @override
  $ProviderElement<PlaceSummary?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaceSummary? create(Ref ref) {
    return selectedPlace(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceSummary? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceSummary?>(value),
    );
  }
}

String _$selectedPlaceHash() => r'9fbc396825f64453c59b7642d9448d365a4826ca';

/// The list beside the map. With the places from the tiles: from the zoom
/// of their names, the places the tiles hold inside the view, read on the
/// device without a request (exact, at once, and nothing of where the user
/// looks leaves it beyond the tiles themselves), except when the tiles
/// cannot answer: no map yet, a tile that failed, or a view whose tiles
/// hold no place, which the API's page of the widened view answers, kept to
/// the view on the device; below it, a page of the API at a time, the view
/// widened to a grid of 0.05 degree and ranked from the user when the map
/// shows them, else from the map's centre, that point snapped to the same
/// grid on the device. Either way sorted again on the device from the
/// user when the map shows them, else from the map's centre. Otherwise
/// the places the device holds. A network failure is not asked again
/// behind the user's back ([nearbyRetry]): the list says at once that
/// there is no connection, and the network's return rebuilds it.

@ProviderFor(NearbyPlacesPage)
final nearbyPlacesPageProvider = NearbyPlacesPageProvider._();

/// The list beside the map. With the places from the tiles: from the zoom
/// of their names, the places the tiles hold inside the view, read on the
/// device without a request (exact, at once, and nothing of where the user
/// looks leaves it beyond the tiles themselves), except when the tiles
/// cannot answer: no map yet, a tile that failed, or a view whose tiles
/// hold no place, which the API's page of the widened view answers, kept to
/// the view on the device; below it, a page of the API at a time, the view
/// widened to a grid of 0.05 degree and ranked from the user when the map
/// shows them, else from the map's centre, that point snapped to the same
/// grid on the device. Either way sorted again on the device from the
/// user when the map shows them, else from the map's centre. Otherwise
/// the places the device holds. A network failure is not asked again
/// behind the user's back ([nearbyRetry]): the list says at once that
/// there is no connection, and the network's return rebuilds it.
final class NearbyPlacesPageProvider
    extends $AsyncNotifierProvider<NearbyPlacesPage, NearbyPage> {
  /// The list beside the map. With the places from the tiles: from the zoom
  /// of their names, the places the tiles hold inside the view, read on the
  /// device without a request (exact, at once, and nothing of where the user
  /// looks leaves it beyond the tiles themselves), except when the tiles
  /// cannot answer: no map yet, a tile that failed, or a view whose tiles
  /// hold no place, which the API's page of the widened view answers, kept to
  /// the view on the device; below it, a page of the API at a time, the view
  /// widened to a grid of 0.05 degree and ranked from the user when the map
  /// shows them, else from the map's centre, that point snapped to the same
  /// grid on the device. Either way sorted again on the device from the
  /// user when the map shows them, else from the map's centre. Otherwise
  /// the places the device holds. A network failure is not asked again
  /// behind the user's back ([nearbyRetry]): the list says at once that
  /// there is no connection, and the network's return rebuilds it.
  NearbyPlacesPageProvider._()
    : super(
        from: null,
        argument: null,
        retry: nearbyRetry,
        name: r'nearbyPlacesPageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nearbyPlacesPageHash();

  @$internal
  @override
  NearbyPlacesPage create() => NearbyPlacesPage();
}

String _$nearbyPlacesPageHash() => r'121c643e3956fe8eafe2e340e21ff9328f35cc81';

/// The list beside the map. With the places from the tiles: from the zoom
/// of their names, the places the tiles hold inside the view, read on the
/// device without a request (exact, at once, and nothing of where the user
/// looks leaves it beyond the tiles themselves), except when the tiles
/// cannot answer: no map yet, a tile that failed, or a view whose tiles
/// hold no place, which the API's page of the widened view answers, kept to
/// the view on the device; below it, a page of the API at a time, the view
/// widened to a grid of 0.05 degree and ranked from the user when the map
/// shows them, else from the map's centre, that point snapped to the same
/// grid on the device. Either way sorted again on the device from the
/// user when the map shows them, else from the map's centre. Otherwise
/// the places the device holds. A network failure is not asked again
/// behind the user's back ([nearbyRetry]): the list says at once that
/// there is no connection, and the network's return rebuilds it.

abstract class _$NearbyPlacesPage extends $AsyncNotifier<NearbyPage> {
  FutureOr<NearbyPage> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<NearbyPage>, NearbyPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<NearbyPage>, NearbyPage>,
              AsyncValue<NearbyPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(PlacesInView)
final placesInViewProvider = PlacesInViewProvider._();

final class PlacesInViewProvider
    extends $NotifierProvider<PlacesInView, PlacesInViewReport> {
  PlacesInViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placesInViewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placesInViewHash();

  @$internal
  @override
  PlacesInView create() => PlacesInView();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlacesInViewReport value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlacesInViewReport>(value),
    );
  }
}

String _$placesInViewHash() => r'cbe022b72d0b0ea9578a55bdd1e9d1057781b76b';

abstract class _$PlacesInView extends $Notifier<PlacesInViewReport> {
  PlacesInViewReport build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PlacesInViewReport, PlacesInViewReport>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlacesInViewReport, PlacesInViewReport>,
              PlacesInViewReport,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

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
// keepAlive: part of what the map screen shows, which MapFlow (kept) holds
// together: an open search is a change of the screen, and the system back
// closes it.

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

/// What the user typed in the map's search field.
// keepAlive: part of what the map screen shows, which MapFlow (kept) holds
// together: an open search is a change of the screen, and the system back
// closes it.
final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  /// What the user typed in the map's search field.
  // keepAlive: part of what the map screen shows, which MapFlow (kept) holds
  // together: an open search is a change of the screen, and the system back
  // closes it.
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: false,
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
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$searchQueryHash() => r'ff14e9c5e43eb24d49984c7983708ee590ff4ef8';

/// What the user typed in the map's search field.
// keepAlive: part of what the map screen shows, which MapFlow (kept) holds
// together: an open search is a change of the screen, and the system back
// closes it.

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
