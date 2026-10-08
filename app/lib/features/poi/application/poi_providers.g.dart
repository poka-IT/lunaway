// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poi_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The points of interest read online, with the copies kept for offline.
// keepAlive: a repository over the app-wide database and client.

@ProviderFor(poiRepository)
final poiRepositoryProvider = PoiRepositoryProvider._();

/// The points of interest read online, with the copies kept for offline.
// keepAlive: a repository over the app-wide database and client.

final class PoiRepositoryProvider
    extends $FunctionalProvider<PoiRepository, PoiRepository, PoiRepository>
    with $Provider<PoiRepository> {
  /// The points of interest read online, with the copies kept for offline.
  // keepAlive: a repository over the app-wide database and client.
  PoiRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'poiRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$poiRepositoryHash();

  @$internal
  @override
  $ProviderElement<PoiRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PoiRepository create(Ref ref) {
    return poiRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PoiRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PoiRepository>(value),
    );
  }
}

String _$poiRepositoryHash() => r'c20709b49bd38bdf23f0ecc6c0aa93c1629c25f3';

/// The TileJSON of the points layer, on the API's host (`/poi/tiles.json`):
/// the map reads the tiles it names, of the layer's current version.

@ProviderFor(poiTileJsonUrl)
final poiTileJsonUrlProvider = PoiTileJsonUrlProvider._();

/// The TileJSON of the points layer, on the API's host (`/poi/tiles.json`):
/// the map reads the tiles it names, of the layer's current version.

final class PoiTileJsonUrlProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The TileJSON of the points layer, on the API's host (`/poi/tiles.json`):
  /// the map reads the tiles it names, of the layer's current version.
  PoiTileJsonUrlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'poiTileJsonUrlProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$poiTileJsonUrlHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return poiTileJsonUrl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$poiTileJsonUrlHash() => r'581749d921bcaa6926a30f9c4b104ab43a8ecc71';

@ProviderFor(PoiLayer)
final poiLayerProvider = PoiLayerProvider._();

final class PoiLayerProvider
    extends $NotifierProvider<PoiLayer, PoiLayerChoice> {
  PoiLayerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'poiLayerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$poiLayerHash();

  @$internal
  @override
  PoiLayer create() => PoiLayer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PoiLayerChoice value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PoiLayerChoice>(value),
    );
  }
}

String _$poiLayerHash() => r'0c227fcd94d8771bbfd67a4a532b3ae95f094462';

abstract class _$PoiLayer extends $Notifier<PoiLayerChoice> {
  PoiLayerChoice build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PoiLayerChoice, PoiLayerChoice>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PoiLayerChoice, PoiLayerChoice>,
              PoiLayerChoice,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The points of the tiles under the map's view, as the map reported them
/// once it settled: what their hours and their neighbours decide.
// keepAlive: the map reports them; the layer state reads them at each tick.

@ProviderFor(PoisInView)
final poisInViewProvider = PoisInViewProvider._();

/// The points of the tiles under the map's view, as the map reported them
/// once it settled: what their hours and their neighbours decide.
// keepAlive: the map reports them; the layer state reads them at each tick.
final class PoisInViewProvider
    extends $NotifierProvider<PoisInView, List<PoiFeature>> {
  /// The points of the tiles under the map's view, as the map reported them
  /// once it settled: what their hours and their neighbours decide.
  // keepAlive: the map reports them; the layer state reads them at each tick.
  PoisInViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'poisInViewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$poisInViewHash();

  @$internal
  @override
  PoisInView create() => PoisInView();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PoiFeature> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PoiFeature>>(value),
    );
  }
}

String _$poisInViewHash() => r'9ac919e14e13c3851176dde689772978ba826be6';

/// The points of the tiles under the map's view, as the map reported them
/// once it settled: what their hours and their neighbours decide.
// keepAlive: the map reports them; the layer state reads them at each tick.

abstract class _$PoisInView extends $Notifier<List<PoiFeature>> {
  List<PoiFeature> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<PoiFeature>, List<PoiFeature>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<PoiFeature>, List<PoiFeature>>,
              List<PoiFeature>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Which points of the view are open, closed, or left to a place of the
/// map; read again every minute.

@ProviderFor(poiLayerState)
final poiLayerStateProvider = PoiLayerStateProvider._();

/// Which points of the view are open, closed, or left to a place of the
/// map; read again every minute.

final class PoiLayerStateProvider
    extends $FunctionalProvider<PoiLayerState, PoiLayerState, PoiLayerState>
    with $Provider<PoiLayerState> {
  /// Which points of the view are open, closed, or left to a place of the
  /// map; read again every minute.
  PoiLayerStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'poiLayerStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$poiLayerStateHash();

  @$internal
  @override
  $ProviderElement<PoiLayerState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PoiLayerState create(Ref ref) {
    return poiLayerState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PoiLayerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PoiLayerState>(value),
    );
  }
}

String _$poiLayerStateHash() => r'adecd1df7daa7f4d875e3bb7690f80a384fd2e11';

/// Whether it is night now, when what is open around the clock comes first.

@ProviderFor(poiNight)
final poiNightProvider = PoiNightProvider._();

/// Whether it is night now, when what is open around the clock comes first.

final class PoiNightProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether it is night now, when what is open around the clock comes first.
  PoiNightProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'poiNightProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$poiNightHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return poiNight(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$poiNightHash() => r'edce6f07b79d32db47a03f2d9b92bed85f0c73b8';

/// "Around this place": the copy kept on the device first, then the API's.
/// A failure shows at once (no automatic retry): offline without a copy,
/// the section says so and offers to try again.

@ProviderFor(placeSurroundings)
final placeSurroundingsProvider = PlaceSurroundingsFamily._();

/// "Around this place": the copy kept on the device first, then the API's.
/// A failure shows at once (no automatic retry): offline without a copy,
/// the section says so and offers to try again.

final class PlaceSurroundingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Read<List<NearbyPois>>>,
          Read<List<NearbyPois>>,
          Stream<Read<List<NearbyPois>>>
        >
    with
        $FutureModifier<Read<List<NearbyPois>>>,
        $StreamProvider<Read<List<NearbyPois>>> {
  /// "Around this place": the copy kept on the device first, then the API's.
  /// A failure shows at once (no automatic retry): offline without a copy,
  /// the section says so and offers to try again.
  PlaceSurroundingsProvider._({
    required PlaceSurroundingsFamily super.from,
    required String super.argument,
  }) : super(
         retry: noRetry,
         name: r'placeSurroundingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$placeSurroundingsHash();

  @override
  String toString() {
    return r'placeSurroundingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Read<List<NearbyPois>>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Read<List<NearbyPois>>> create(Ref ref) {
    final argument = this.argument as String;
    return placeSurroundings(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlaceSurroundingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeSurroundingsHash() => r'ae8f9a97c0446702a95c428c60ed00d14f33b364';

/// "Around this place": the copy kept on the device first, then the API's.
/// A failure shows at once (no automatic retry): offline without a copy,
/// the section says so and offers to try again.

final class PlaceSurroundingsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Read<List<NearbyPois>>>, String> {
  PlaceSurroundingsFamily._()
    : super(
        retry: noRetry,
        name: r'placeSurroundingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// "Around this place": the copy kept on the device first, then the API's.
  /// A failure shows at once (no automatic retry): offline without a copy,
  /// the section says so and offers to try again.

  PlaceSurroundingsProvider call(String placeId) =>
      PlaceSurroundingsProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeSurroundingsProvider';
}

/// The page of a point; null inside when it is gone or hidden. A failure
/// shows at once, as for [placeSurroundings].

@ProviderFor(poiPage)
final poiPageProvider = PoiPageFamily._();

/// The page of a point; null inside when it is gone or hidden. A failure
/// shows at once, as for [placeSurroundings].

final class PoiPageProvider
    extends
        $FunctionalProvider<
          AsyncValue<Read<PoiPage?>>,
          Read<PoiPage?>,
          Stream<Read<PoiPage?>>
        >
    with $FutureModifier<Read<PoiPage?>>, $StreamProvider<Read<PoiPage?>> {
  /// The page of a point; null inside when it is gone or hidden. A failure
  /// shows at once, as for [placeSurroundings].
  PoiPageProvider._({
    required PoiPageFamily super.from,
    required String super.argument,
  }) : super(
         retry: noRetry,
         name: r'poiPageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$poiPageHash();

  @override
  String toString() {
    return r'poiPageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Read<PoiPage?>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Read<PoiPage?>> create(Ref ref) {
    final argument = this.argument as String;
    return poiPage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PoiPageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$poiPageHash() => r'd0aef01cbcbd1cb81f01f3f642ece170c07be236';

/// The page of a point; null inside when it is gone or hidden. A failure
/// shows at once, as for [placeSurroundings].

final class PoiPageFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Read<PoiPage?>>, String> {
  PoiPageFamily._()
    : super(
        retry: noRetry,
        name: r'poiPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The page of a point; null inside when it is gone or hidden. A failure
  /// shows at once, as for [placeSurroundings].

  PoiPageProvider call(String poiId) =>
      PoiPageProvider._(argument: poiId, from: this);

  @override
  String toString() => r'poiPageProvider';
}

/// The points whose name or brand matches what the user typed in the map's
/// search, online, once typing pauses. Fewer than three letters ask
/// nothing.

@ProviderFor(poiSearch)
final poiSearchProvider = PoiSearchFamily._();

/// The points whose name or brand matches what the user typed in the map's
/// search, online, once typing pauses. Fewer than three letters ask
/// nothing.

final class PoiSearchProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Poi>>,
          List<Poi>,
          FutureOr<List<Poi>>
        >
    with $FutureModifier<List<Poi>>, $FutureProvider<List<Poi>> {
  /// The points whose name or brand matches what the user typed in the map's
  /// search, online, once typing pauses. Fewer than three letters ask
  /// nothing.
  PoiSearchProvider._({
    required PoiSearchFamily super.from,
    required (String, {LatLng? near}) super.argument,
  }) : super(
         retry: noRetry,
         name: r'poiSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$poiSearchHash();

  @override
  String toString() {
    return r'poiSearchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<Poi>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Poi>> create(Ref ref) {
    final argument = this.argument as (String, {LatLng? near});
    return poiSearch(ref, argument.$1, near: argument.near);
  }

  @override
  bool operator ==(Object other) {
    return other is PoiSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$poiSearchHash() => r'e6be4a30bd9ac3cc2ef9b557a3f6ea7bd1315d54';

/// The points whose name or brand matches what the user typed in the map's
/// search, online, once typing pauses. Fewer than three letters ask
/// nothing.

final class PoiSearchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<Poi>>,
          (String, {LatLng? near})
        > {
  PoiSearchFamily._()
    : super(
        retry: noRetry,
        name: r'poiSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The points whose name or brand matches what the user typed in the map's
  /// search, online, once typing pauses. Fewer than three letters ask
  /// nothing.

  PoiSearchProvider call(String query, {LatLng? near}) =>
      PoiSearchProvider._(argument: (query, near: near), from: this);

  @override
  String toString() => r'poiSearchProvider';
}

/// The fuel the price labels and the cheapest stations show: the vehicle's
/// by default, another one when the user switches in the list.
// keepAlive: the choice holds while the user moves between tabs.

@ProviderFor(ChosenFuel)
final chosenFuelProvider = ChosenFuelProvider._();

/// The fuel the price labels and the cheapest stations show: the vehicle's
/// by default, another one when the user switches in the list.
// keepAlive: the choice holds while the user moves between tabs.
final class ChosenFuelProvider extends $NotifierProvider<ChosenFuel, FuelType> {
  /// The fuel the price labels and the cheapest stations show: the vehicle's
  /// by default, another one when the user switches in the list.
  // keepAlive: the choice holds while the user moves between tabs.
  ChosenFuelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chosenFuelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chosenFuelHash();

  @$internal
  @override
  ChosenFuel create() => ChosenFuel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FuelType value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FuelType>(value),
    );
  }
}

String _$chosenFuelHash() => r'c8db50dbf8a3755b945098512c78c8208f2d9e20';

/// The fuel the price labels and the cheapest stations show: the vehicle's
/// by default, another one when the user switches in the list.
// keepAlive: the choice holds while the user moves between tabs.

abstract class _$ChosenFuel extends $Notifier<FuelType> {
  FuelType build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FuelType, FuelType>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FuelType, FuelType>,
              FuelType,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The fuel stations of a box with their prices, read once the view rests;
/// null when the box holds too many to read them all.

@ProviderFor(fuelStations)
final fuelStationsProvider = FuelStationsFamily._();

/// The fuel stations of a box with their prices, read once the view rests;
/// null when the box holds too many to read them all.

final class FuelStationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Poi>?>,
          List<Poi>?,
          FutureOr<List<Poi>?>
        >
    with $FutureModifier<List<Poi>?>, $FutureProvider<List<Poi>?> {
  /// The fuel stations of a box with their prices, read once the view rests;
  /// null when the box holds too many to read them all.
  FuelStationsProvider._({
    required FuelStationsFamily super.from,
    required GeoBounds super.argument,
  }) : super(
         retry: noRetry,
         name: r'fuelStationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fuelStationsHash();

  @override
  String toString() {
    return r'fuelStationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Poi>?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Poi>?> create(Ref ref) {
    final argument = this.argument as GeoBounds;
    return fuelStations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FuelStationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fuelStationsHash() => r'fd87fd636294e3a6fef04f9d943fe04f22761e20';

/// The fuel stations of a box with their prices, read once the view rests;
/// null when the box holds too many to read them all.

final class FuelStationsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Poi>?>, GeoBounds> {
  FuelStationsFamily._()
    : super(
        retry: noRetry,
        name: r'fuelStationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The fuel stations of a box with their prices, read once the view rests;
  /// null when the box holds too many to read them all.

  FuelStationsProvider call(GeoBounds box) =>
      FuelStationsProvider._(argument: box, from: this);

  @override
  String toString() => r'fuelStationsProvider';
}

/// The fuel stations of the view while the fuel chip is on; empty
/// otherwise, or far out; null when the view holds too many to read.
// Fails only when [fuelStations] does, which shows at once: no retry here.

@ProviderFor(fuelStationsInView)
final fuelStationsInViewProvider = FuelStationsInViewProvider._();

/// The fuel stations of the view while the fuel chip is on; empty
/// otherwise, or far out; null when the view holds too many to read.
// Fails only when [fuelStations] does, which shows at once: no retry here.

final class FuelStationsInViewProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Poi>?>,
          List<Poi>?,
          FutureOr<List<Poi>?>
        >
    with $FutureModifier<List<Poi>?>, $FutureProvider<List<Poi>?> {
  /// The fuel stations of the view while the fuel chip is on; empty
  /// otherwise, or far out; null when the view holds too many to read.
  // Fails only when [fuelStations] does, which shows at once: no retry here.
  FuelStationsInViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'fuelStationsInViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fuelStationsInViewHash();

  @$internal
  @override
  $FutureProviderElement<List<Poi>?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Poi>?> create(Ref ref) {
    return fuelStationsInView(ref);
  }
}

String _$fuelStationsInViewHash() =>
    r'ab864757297d4ace8d8484e2fd75ab28a863866c';

/// The cheapest offers of the chosen fuel among the stations of the view
/// (the same ones as the labels, so a colour means the same price in both),
/// then the nearest to the user, or to the centre of the view; null when
/// the view holds too many stations to read them all.
// Fails only when [fuelStations] does, which shows at once: no retry here.

@ProviderFor(cheapestFuel)
final cheapestFuelProvider = CheapestFuelProvider._();

/// The cheapest offers of the chosen fuel among the stations of the view
/// (the same ones as the labels, so a colour means the same price in both),
/// then the nearest to the user, or to the centre of the view; null when
/// the view holds too many stations to read them all.
// Fails only when [fuelStations] does, which shows at once: no retry here.

final class CheapestFuelProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FuelOffer>?>,
          List<FuelOffer>?,
          FutureOr<List<FuelOffer>?>
        >
    with $FutureModifier<List<FuelOffer>?>, $FutureProvider<List<FuelOffer>?> {
  /// The cheapest offers of the chosen fuel among the stations of the view
  /// (the same ones as the labels, so a colour means the same price in both),
  /// then the nearest to the user, or to the centre of the view; null when
  /// the view holds too many stations to read them all.
  // Fails only when [fuelStations] does, which shows at once: no retry here.
  CheapestFuelProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'cheapestFuelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cheapestFuelHash();

  @$internal
  @override
  $FutureProviderElement<List<FuelOffer>?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FuelOffer>?> create(Ref ref) {
    return cheapestFuel(ref);
  }
}

String _$cheapestFuelHash() => r'fd3331c7e33bd21d35e609e5428a6460cde6c080';

/// The price of the chosen fuel under each station of the view, coloured
/// from the cheapest to the dearest of those in view, written in
/// [language] ("1,789" or "1.789").

@ProviderFor(fuelLabels)
final fuelLabelsProvider = FuelLabelsFamily._();

/// The price of the chosen fuel under each station of the view, coloured
/// from the cheapest to the dearest of those in view, written in
/// [language] ("1,789" or "1.789").

final class FuelLabelsProvider
    extends
        $FunctionalProvider<List<FuelLabel>, List<FuelLabel>, List<FuelLabel>>
    with $Provider<List<FuelLabel>> {
  /// The price of the chosen fuel under each station of the view, coloured
  /// from the cheapest to the dearest of those in view, written in
  /// [language] ("1,789" or "1.789").
  FuelLabelsProvider._({
    required FuelLabelsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'fuelLabelsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fuelLabelsHash();

  @override
  String toString() {
    return r'fuelLabelsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<FuelLabel>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<FuelLabel> create(Ref ref) {
    final argument = this.argument as String;
    return fuelLabels(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<FuelLabel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<FuelLabel>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FuelLabelsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fuelLabelsHash() => r'10ed9c0c413fe629ac6044d3dad85f3fcc7fd8ab';

/// The price of the chosen fuel under each station of the view, coloured
/// from the cheapest to the dearest of those in view, written in
/// [language] ("1,789" or "1.789").

final class FuelLabelsFamily extends $Family
    with $FunctionalFamilyOverride<List<FuelLabel>, String> {
  FuelLabelsFamily._()
    : super(
        retry: null,
        name: r'fuelLabelsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The price of the chosen fuel under each station of the view, coloured
  /// from the cheapest to the dearest of those in view, written in
  /// [language] ("1,789" or "1.789").

  FuelLabelsProvider call(String language) =>
      FuelLabelsProvider._(argument: language, from: this);

  @override
  String toString() => r'fuelLabelsProvider';
}
