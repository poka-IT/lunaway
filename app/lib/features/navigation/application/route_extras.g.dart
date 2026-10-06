// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route_extras.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The stops on the way to [target], in order, as the preview edits them.

@ProviderFor(RouteStopsController)
final routeStopsControllerProvider = RouteStopsControllerFamily._();

/// The stops on the way to [target], in order, as the preview edits them.
final class RouteStopsControllerProvider
    extends $NotifierProvider<RouteStopsController, List<RouteStop>> {
  /// The stops on the way to [target], in order, as the preview edits them.
  RouteStopsControllerProvider._({
    required RouteStopsControllerFamily super.from,
    required RouteTarget super.argument,
  }) : super(
         retry: null,
         name: r'routeStopsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$routeStopsControllerHash();

  @override
  String toString() {
    return r'routeStopsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RouteStopsController create() => RouteStopsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<RouteStop> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<RouteStop>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RouteStopsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$routeStopsControllerHash() =>
    r'708e88b5bd24e520b3681e2c23c8df61176cd50f';

/// The stops on the way to [target], in order, as the preview edits them.

final class RouteStopsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          RouteStopsController,
          List<RouteStop>,
          List<RouteStop>,
          List<RouteStop>,
          RouteTarget
        > {
  RouteStopsControllerFamily._()
    : super(
        retry: null,
        name: r'routeStopsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The stops on the way to [target], in order, as the preview edits them.

  RouteStopsControllerProvider call(RouteTarget target) =>
      RouteStopsControllerProvider._(argument: target, from: this);

  @override
  String toString() => r'routeStopsControllerProvider';
}

/// The stops on the way to [target], in order, as the preview edits them.

abstract class _$RouteStopsController extends $Notifier<List<RouteStop>> {
  late final _$args = ref.$arg as RouteTarget;
  RouteTarget get target => _$args;

  List<RouteStop> build(RouteTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<RouteStop>, List<RouteStop>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<RouteStop>, List<RouteStop>>,
              List<RouteStop>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The places of the device along [line], those the user's filters keep,
/// nearest the route first: the pins of the route map, a tap from a stop.
/// Asked stretch by stretch, so a long route has its places from the start
/// to the end, not only around its middle; the first 300 km.

@ProviderFor(placesNearRoute)
final placesNearRouteProvider = PlacesNearRouteFamily._();

/// The places of the device along [line], those the user's filters keep,
/// nearest the route first: the pins of the route map, a tap from a stop.
/// Asked stretch by stretch, so a long route has its places from the start
/// to the end, not only around its middle; the first 300 km.

final class PlacesNearRouteProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PlaceSummary>>,
          List<PlaceSummary>,
          FutureOr<List<PlaceSummary>>
        >
    with
        $FutureModifier<List<PlaceSummary>>,
        $FutureProvider<List<PlaceSummary>> {
  /// The places of the device along [line], those the user's filters keep,
  /// nearest the route first: the pins of the route map, a tap from a stop.
  /// Asked stretch by stretch, so a long route has its places from the start
  /// to the end, not only around its middle; the first 300 km.
  PlacesNearRouteProvider._({
    required PlacesNearRouteFamily super.from,
    required List<LatLng> super.argument,
  }) : super(
         retry: null,
         name: r'placesNearRouteProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$placesNearRouteHash();

  @override
  String toString() {
    return r'placesNearRouteProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<PlaceSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<PlaceSummary>> create(Ref ref) {
    final argument = this.argument as List<LatLng>;
    return placesNearRoute(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlacesNearRouteProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placesNearRouteHash() => r'142b1ea25b8cf149e4c5f384a51db2b865161cd8';

/// The places of the device along [line], those the user's filters keep,
/// nearest the route first: the pins of the route map, a tap from a stop.
/// Asked stretch by stretch, so a long route has its places from the start
/// to the end, not only around its middle; the first 300 km.

final class PlacesNearRouteFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<PlaceSummary>>, List<LatLng>> {
  PlacesNearRouteFamily._()
    : super(
        retry: null,
        name: r'placesNearRouteProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The places of the device along [line], those the user's filters keep,
  /// nearest the route first: the pins of the route map, a tap from a stop.
  /// Asked stretch by stretch, so a long route has its places from the start
  /// to the end, not only around its middle; the first 300 km.

  PlacesNearRouteProvider call(List<LatLng> line) =>
      PlacesNearRouteProvider._(argument: line, from: this);

  @override
  String toString() => r'placesNearRouteProvider';
}

/// Stations along a route; the server's search along a route replaces the
/// nearby search when it exists.
// keepAlive: stateless, wired once.

@ProviderFor(fuelStations)
final fuelStationsProvider = FuelStationsProvider._();

/// Stations along a route; the server's search along a route replaces the
/// nearby search when it exists.
// keepAlive: stateless, wired once.

final class FuelStationsProvider
    extends
        $FunctionalProvider<
          FuelStationsSource,
          FuelStationsSource,
          FuelStationsSource
        >
    with $Provider<FuelStationsSource> {
  /// Stations along a route; the server's search along a route replaces the
  /// nearby search when it exists.
  // keepAlive: stateless, wired once.
  FuelStationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fuelStationsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fuelStationsHash();

  @$internal
  @override
  $ProviderElement<FuelStationsSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FuelStationsSource create(Ref ref) {
    return fuelStations(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FuelStationsSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FuelStationsSource>(value),
    );
  }
}

String _$fuelStationsHash() => r'cbe944a344c40a5e260b3dbeace1fbc6f708696e';

/// The stations of [query], cheapest first, the detour counted at the
/// vehicle's consumption. A failure shows at once (`noRetry`).

@ProviderFor(fuelOffers)
final fuelOffersProvider = FuelOffersFamily._();

/// The stations of [query], cheapest first, the detour counted at the
/// vehicle's consumption. A failure shows at once (`noRetry`).

final class FuelOffersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FuelOffer>>,
          List<FuelOffer>,
          FutureOr<List<FuelOffer>>
        >
    with $FutureModifier<List<FuelOffer>>, $FutureProvider<List<FuelOffer>> {
  /// The stations of [query], cheapest first, the detour counted at the
  /// vehicle's consumption. A failure shows at once (`noRetry`).
  FuelOffersProvider._({
    required FuelOffersFamily super.from,
    required FuelQuery super.argument,
  }) : super(
         retry: noRetry,
         name: r'fuelOffersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fuelOffersHash();

  @override
  String toString() {
    return r'fuelOffersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<FuelOffer>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FuelOffer>> create(Ref ref) {
    final argument = this.argument as FuelQuery;
    return fuelOffers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FuelOffersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fuelOffersHash() => r'c5af96b734965b6963a21a987d90c30898eea96c';

/// The stations of [query], cheapest first, the detour counted at the
/// vehicle's consumption. A failure shows at once (`noRetry`).

final class FuelOffersFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<FuelOffer>>, FuelQuery> {
  FuelOffersFamily._()
    : super(
        retry: noRetry,
        name: r'fuelOffersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The stations of [query], cheapest first, the detour counted at the
  /// vehicle's consumption. A failure shows at once (`noRetry`).

  FuelOffersProvider call(FuelQuery query) =>
      FuelOffersProvider._(argument: query, from: this);

  @override
  String toString() => r'fuelOffersProvider';
}

/// The stations the fuel list showed last, drawn on the route map so they
/// can be tapped there too.

@ProviderFor(ShownFuelOffers)
final shownFuelOffersProvider = ShownFuelOffersProvider._();

/// The stations the fuel list showed last, drawn on the route map so they
/// can be tapped there too.
final class ShownFuelOffersProvider
    extends $NotifierProvider<ShownFuelOffers, List<FuelOffer>> {
  /// The stations the fuel list showed last, drawn on the route map so they
  /// can be tapped there too.
  ShownFuelOffersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shownFuelOffersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shownFuelOffersHash();

  @$internal
  @override
  ShownFuelOffers create() => ShownFuelOffers();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<FuelOffer> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<FuelOffer>>(value),
    );
  }
}

String _$shownFuelOffersHash() => r'a00b18ad541426473234d4e8b9d3cbbfe4e4a2ef';

/// The stations the fuel list showed last, drawn on the route map so they
/// can be tapped there too.

abstract class _$ShownFuelOffers extends $Notifier<List<FuelOffer>> {
  List<FuelOffer> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<FuelOffer>, List<FuelOffer>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<FuelOffer>, List<FuelOffer>>,
              List<FuelOffer>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The danger zones of a route: none until a source is chosen for the
/// countries that allow them.
// keepAlive: stateless, wired once.

@ProviderFor(dangerZones)
final dangerZonesProvider = DangerZonesProvider._();

/// The danger zones of a route: none until a source is chosen for the
/// countries that allow them.
// keepAlive: stateless, wired once.

final class DangerZonesProvider
    extends
        $FunctionalProvider<
          DangerZoneSource,
          DangerZoneSource,
          DangerZoneSource
        >
    with $Provider<DangerZoneSource> {
  /// The danger zones of a route: none until a source is chosen for the
  /// countries that allow them.
  // keepAlive: stateless, wired once.
  DangerZonesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dangerZonesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dangerZonesHash();

  @$internal
  @override
  $ProviderElement<DangerZoneSource> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DangerZoneSource create(Ref ref) {
    return dangerZones(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DangerZoneSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DangerZoneSource>(value),
    );
  }
}

String _$dangerZonesHash() => r'8ebcecb912bbbe0632d66381a0ea347fa72b3c14';
