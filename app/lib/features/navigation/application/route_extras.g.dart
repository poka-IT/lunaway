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
    r'e4d1279f16e1ff72f63124a8ae64680218413cf6';

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

String _$placesNearRouteHash() => r'66ebfacd6204f142201386aa2a364233aed88496';

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

/// The places along [line] the guidance may show, offline: those of the
/// guidance's own choice (`GuidancePlaces`) the vehicle's height lets
/// through, whatever the main map's filters, as online it picks among the
/// tiles'; narrowed by the map's filters first, a choice of every place
/// would show online what it hides offline. Chosen before the nearest are
/// kept, so the cap leaves out none of the choice for places it hides.

@ProviderFor(guidancePlacesNearRoute)
final guidancePlacesNearRouteProvider = GuidancePlacesNearRouteFamily._();

/// The places along [line] the guidance may show, offline: those of the
/// guidance's own choice (`GuidancePlaces`) the vehicle's height lets
/// through, whatever the main map's filters, as online it picks among the
/// tiles'; narrowed by the map's filters first, a choice of every place
/// would show online what it hides offline. Chosen before the nearest are
/// kept, so the cap leaves out none of the choice for places it hides.

final class GuidancePlacesNearRouteProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PlaceSummary>>,
          List<PlaceSummary>,
          FutureOr<List<PlaceSummary>>
        >
    with
        $FutureModifier<List<PlaceSummary>>,
        $FutureProvider<List<PlaceSummary>> {
  /// The places along [line] the guidance may show, offline: those of the
  /// guidance's own choice (`GuidancePlaces`) the vehicle's height lets
  /// through, whatever the main map's filters, as online it picks among the
  /// tiles'; narrowed by the map's filters first, a choice of every place
  /// would show online what it hides offline. Chosen before the nearest are
  /// kept, so the cap leaves out none of the choice for places it hides.
  GuidancePlacesNearRouteProvider._({
    required GuidancePlacesNearRouteFamily super.from,
    required List<LatLng> super.argument,
  }) : super(
         retry: null,
         name: r'guidancePlacesNearRouteProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$guidancePlacesNearRouteHash();

  @override
  String toString() {
    return r'guidancePlacesNearRouteProvider'
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
    return guidancePlacesNearRoute(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GuidancePlacesNearRouteProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$guidancePlacesNearRouteHash() =>
    r'fab64cceed3fdc8856a20defb5352e6d1280e01f';

/// The places along [line] the guidance may show, offline: those of the
/// guidance's own choice (`GuidancePlaces`) the vehicle's height lets
/// through, whatever the main map's filters, as online it picks among the
/// tiles'; narrowed by the map's filters first, a choice of every place
/// would show online what it hides offline. Chosen before the nearest are
/// kept, so the cap leaves out none of the choice for places it hides.

final class GuidancePlacesNearRouteFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<PlaceSummary>>, List<LatLng>> {
  GuidancePlacesNearRouteFamily._()
    : super(
        retry: null,
        name: r'guidancePlacesNearRouteProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The places along [line] the guidance may show, offline: those of the
  /// guidance's own choice (`GuidancePlaces`) the vehicle's height lets
  /// through, whatever the main map's filters, as online it picks among the
  /// tiles'; narrowed by the map's filters first, a choice of every place
  /// would show online what it hides offline. Chosen before the nearest are
  /// kept, so the cap leaves out none of the choice for places it hides.

  GuidancePlacesNearRouteProvider call(List<LatLng> line) =>
      GuidancePlacesNearRouteProvider._(argument: line, from: this);

  @override
  String toString() => r'guidancePlacesNearRouteProvider';
}

/// Stations along a route: the server's search along it, the nearby
/// search around points of it against an API without that search. Through
/// the routing client, which does not wait out a rate limit: the list
/// says at once that the server asks to wait.
// keepAlive: stateless, wired once.

@ProviderFor(fuelStations)
final fuelStationsProvider = FuelStationsProvider._();

/// Stations along a route: the server's search along it, the nearby
/// search around points of it against an API without that search. Through
/// the routing client, which does not wait out a rate limit: the list
/// says at once that the server asks to wait.
// keepAlive: stateless, wired once.

final class FuelStationsProvider
    extends
        $FunctionalProvider<
          FuelStationsSource,
          FuelStationsSource,
          FuelStationsSource
        >
    with $Provider<FuelStationsSource> {
  /// Stations along a route: the server's search along it, the nearby
  /// search around points of it against an API without that search. Through
  /// the routing client, which does not wait out a rate limit: the list
  /// says at once that the server asks to wait.
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

String _$fuelStationsHash() => r'6a70cf69dc3613bc6e27a255ffdc8365e52b13ac';

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

String _$fuelOffersHash() => r'2ed1aaf2e7b39394b7f6cd2aabdde630772adc0d';

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

/// The stations the fuel list showed last for the route [line], drawn on
/// its map so they can be tapped there too; another route starts without.

@ProviderFor(ShownFuelOffers)
final shownFuelOffersProvider = ShownFuelOffersFamily._();

/// The stations the fuel list showed last for the route [line], drawn on
/// its map so they can be tapped there too; another route starts without.
final class ShownFuelOffersProvider
    extends $NotifierProvider<ShownFuelOffers, List<FuelOffer>> {
  /// The stations the fuel list showed last for the route [line], drawn on
  /// its map so they can be tapped there too; another route starts without.
  ShownFuelOffersProvider._({
    required ShownFuelOffersFamily super.from,
    required List<LatLng> super.argument,
  }) : super(
         retry: null,
         name: r'shownFuelOffersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shownFuelOffersHash();

  @override
  String toString() {
    return r'shownFuelOffersProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is ShownFuelOffersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shownFuelOffersHash() => r'27bb3b0b2d3fa10d4d40ed0d2149bb2ff04937f1';

/// The stations the fuel list showed last for the route [line], drawn on
/// its map so they can be tapped there too; another route starts without.

final class ShownFuelOffersFamily extends $Family
    with
        $ClassFamilyOverride<
          ShownFuelOffers,
          List<FuelOffer>,
          List<FuelOffer>,
          List<FuelOffer>,
          List<LatLng>
        > {
  ShownFuelOffersFamily._()
    : super(
        retry: null,
        name: r'shownFuelOffersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The stations the fuel list showed last for the route [line], drawn on
  /// its map so they can be tapped there too; another route starts without.

  ShownFuelOffersProvider call(List<LatLng> line) =>
      ShownFuelOffersProvider._(argument: line, from: this);

  @override
  String toString() => r'shownFuelOffersProvider';
}

/// The stations the fuel list showed last for the route [line], drawn on
/// its map so they can be tapped there too; another route starts without.

abstract class _$ShownFuelOffers extends $Notifier<List<FuelOffer>> {
  late final _$args = ref.$arg as List<LatLng>;
  List<LatLng> get line => _$args;

  List<FuelOffer> build(List<LatLng> line);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}
