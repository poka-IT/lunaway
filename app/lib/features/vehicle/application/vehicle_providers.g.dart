// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vehicle_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(vehicleRepository)
final vehicleRepositoryProvider = VehicleRepositoryProvider._();

final class VehicleRepositoryProvider
    extends $FunctionalProvider<VehicleRepository, VehicleRepository, VehicleRepository>
    with $Provider<VehicleRepository> {
  VehicleRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vehicleRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vehicleRepositoryHash();

  @$internal
  @override
  $ProviderElement<VehicleRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VehicleRepository create(Ref ref) {
    return vehicleRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VehicleRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VehicleRepository>(value),
    );
  }
}

String _$vehicleRepositoryHash() => r'b96292f9d6b35f1eb36065ae32254e4c88675eeb';

/// The user's vehicle; null until described.
// keepAlive: the map filter reads it on every query; reopening the stream
// each time the filter screen closes would flash the unfiltered map.

@ProviderFor(vehicle)
final vehicleProvider = VehicleProvider._();

/// The user's vehicle; null until described.
// keepAlive: the map filter reads it on every query; reopening the stream
// each time the filter screen closes would flash the unfiltered map.

final class VehicleProvider
    extends $FunctionalProvider<AsyncValue<Vehicle?>, Vehicle?, Stream<Vehicle?>>
    with $FutureModifier<Vehicle?>, $StreamProvider<Vehicle?> {
  /// The user's vehicle; null until described.
  // keepAlive: the map filter reads it on every query; reopening the stream
  // each time the filter screen closes would flash the unfiltered map.
  VehicleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vehicleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vehicleHash();

  @$internal
  @override
  $StreamProviderElement<Vehicle?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Vehicle?> create(Ref ref) {
    return vehicle(ref);
  }
}

String _$vehicleHash() => r'4eda88ae6967aaff07010c91ef9d6321bb08409c';

/// The height of the user's vehicle, when known: what "my vehicle fits"
/// filters with.

@ProviderFor(vehicleHeight)
final vehicleHeightProvider = VehicleHeightProvider._();

/// The height of the user's vehicle, when known: what "my vehicle fits"
/// filters with.

final class VehicleHeightProvider extends $FunctionalProvider<double?, double?, double?>
    with $Provider<double?> {
  /// The height of the user's vehicle, when known: what "my vehicle fits"
  /// filters with.
  VehicleHeightProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vehicleHeightProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vehicleHeightHash();

  @$internal
  @override
  $ProviderElement<double?> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  double? create(Ref ref) {
    return vehicleHeight(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<double?>(value));
  }
}

String _$vehicleHeightHash() => r'bcbc1a720e3ff802f00ef8cc6b6f15e7a974507f';

@ProviderFor(vehicleFuel)
final vehicleFuelProvider = VehicleFuelProvider._();

final class VehicleFuelProvider extends $FunctionalProvider<VehicleFuel, VehicleFuel, VehicleFuel>
    with $Provider<VehicleFuel> {
  VehicleFuelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vehicleFuelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vehicleFuelHash();

  @$internal
  @override
  $ProviderElement<VehicleFuel> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VehicleFuel create(Ref ref) {
    return vehicleFuel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VehicleFuel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VehicleFuel>(value),
    );
  }
}

String _$vehicleFuelHash() => r'ccbdad5b7865b3c8c46fcc498a70efd874262cad';
