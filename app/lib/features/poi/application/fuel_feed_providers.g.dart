// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fuel_feed_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The point the server's search near a point is asked about: the user's
/// position, else the centre of the view, rounded to a twentieth of a
/// degree (about 5 km) before it leaves the device, as the search of shops
/// does. Watched alone, so the view moving within the same square asks
/// nothing again.

@ProviderFor(nearbyFuelPoint)
final nearbyFuelPointProvider = NearbyFuelPointProvider._();

/// The point the server's search near a point is asked about: the user's
/// position, else the centre of the view, rounded to a twentieth of a
/// degree (about 5 km) before it leaves the device, as the search of shops
/// does. Watched alone, so the view moving within the same square asks
/// nothing again.

final class NearbyFuelPointProvider extends $FunctionalProvider<LatLng?, LatLng?, LatLng?>
    with $Provider<LatLng?> {
  /// The point the server's search near a point is asked about: the user's
  /// position, else the centre of the view, rounded to a twentieth of a
  /// degree (about 5 km) before it leaves the device, as the search of shops
  /// does. Watched alone, so the view moving within the same square asks
  /// nothing again.
  NearbyFuelPointProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nearbyFuelPointProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nearbyFuelPointHash();

  @$internal
  @override
  $ProviderElement<LatLng?> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  LatLng? create(Ref ref) {
    return nearbyFuelPoint(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LatLng? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<LatLng?>(value));
  }
}

String _$nearbyFuelPointHash() => r'7273106584537e8f3381336f3a12b5aa8888fafd';

/// The cheapest stations of the chosen fuel around the user, from the
/// server (`fuelNearby`): what the list shows where the stations of the
/// view cannot all be read (far out, or a dense town). Null against an API
/// without that search. The distances are measured on the device, from
/// the user's own position when known.

@ProviderFor(nearbyFuel)
final nearbyFuelProvider = NearbyFuelProvider._();

/// The cheapest stations of the chosen fuel around the user, from the
/// server (`fuelNearby`): what the list shows where the stations of the
/// view cannot all be read (far out, or a dense town). Null against an API
/// without that search. The distances are measured on the device, from
/// the user's own position when known.

final class NearbyFuelProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FuelOffer>?>,
          List<FuelOffer>?,
          FutureOr<List<FuelOffer>?>
        >
    with $FutureModifier<List<FuelOffer>?>, $FutureProvider<List<FuelOffer>?> {
  /// The cheapest stations of the chosen fuel around the user, from the
  /// server (`fuelNearby`): what the list shows where the stations of the
  /// view cannot all be read (far out, or a dense town). Null against an API
  /// without that search. The distances are measured on the device, from
  /// the user's own position when known.
  NearbyFuelProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'nearbyFuelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nearbyFuelHash();

  @$internal
  @override
  $FutureProviderElement<List<FuelOffer>?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<FuelOffer>?> create(Ref ref) {
    return nearbyFuel(ref);
  }
}

String _$nearbyFuelHash() => r'2e9a05da53142727f06cafb0fa89cb3babd0b8ea';

/// The price of [fuel] at the station [poiId] over the last 30 days, read
/// when its sheet opens; null when the server saw none. A failure shows at
/// once, beside the prices that did load.

@ProviderFor(fuelTrend)
final fuelTrendProvider = FuelTrendFamily._();

/// The price of [fuel] at the station [poiId] over the last 30 days, read
/// when its sheet opens; null when the server saw none. A failure shows at
/// once, beside the prices that did load.

final class FuelTrendProvider
    extends $FunctionalProvider<AsyncValue<FuelTrend?>, FuelTrend?, FutureOr<FuelTrend?>>
    with $FutureModifier<FuelTrend?>, $FutureProvider<FuelTrend?> {
  /// The price of [fuel] at the station [poiId] over the last 30 days, read
  /// when its sheet opens; null when the server saw none. A failure shows at
  /// once, beside the prices that did load.
  FuelTrendProvider._({
    required FuelTrendFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: noRetry,
         name: r'fuelTrendProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fuelTrendHash();

  @override
  String toString() {
    return r'fuelTrendProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<FuelTrend?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<FuelTrend?> create(Ref ref) {
    final argument = this.argument as (String, String);
    return fuelTrend(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is FuelTrendProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fuelTrendHash() => r'db619c85c3ba0597f58aec21dcf2465f4aa8446e';

/// The price of [fuel] at the station [poiId] over the last 30 days, read
/// when its sheet opens; null when the server saw none. A failure shows at
/// once, beside the prices that did load.

final class FuelTrendFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<FuelTrend?>, (String, String)> {
  FuelTrendFamily._()
    : super(
        retry: noRetry,
        name: r'fuelTrendProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The price of [fuel] at the station [poiId] over the last 30 days, read
  /// when its sheet opens; null when the server saw none. A failure shows at
  /// once, beside the prices that did load.

  FuelTrendProvider call(String poiId, String fuel) =>
      FuelTrendProvider._(argument: (poiId, fuel), from: this);

  @override
  String toString() => r'fuelTrendProvider';
}
