import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vehicle_providers.g.dart';

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
VehicleRepository vehicleRepository(Ref ref) =>
    DriftVehicleRepository(ref.watch(userDatabaseProvider), clock: ref.watch(clockProvider));

/// The user's vehicle; null until described.
// keepAlive: the map filter reads it on every query; reopening the stream
// each time the filter screen closes would flash the unfiltered map.
@Riverpod(keepAlive: true)
Stream<Vehicle?> vehicle(Ref ref) => ref.watch(vehicleRepositoryProvider).watch();

/// The height of the user's vehicle, when known: what "my vehicle fits"
/// filters with.
@riverpod
double? vehicleHeight(Ref ref) => ref.watch(vehicleProvider).value?.heightM;

/// The fuel of the user's vehicle and what it burns, read wherever a price
/// of fuel is shown: the map's labels and the cheapest stations around, and
/// the cheapest fuel along a route of the navigation.
@immutable
final class VehicleFuel {
  const new({this.fuel, this.consumptionL100, this.lpgHeating = false});

  /// The engine's fuel; null until the user says.
  final FuelType? fuel;

  /// Litres per 100 km, when known.
  final double? consumptionL100;

  /// The living area heats on LPG: its price matters too.
  final bool lpgHeating;

  @override
  bool operator ==(Object other) =>
      other is VehicleFuel &&
      other.fuel == fuel &&
      other.consumptionL100 == consumptionL100 &&
      other.lpgHeating == lpgHeating;

  @override
  int get hashCode => Object.hash(fuel, consumptionL100, lpgHeating);
}

// keepAlive: the fuel chosen for the prices follows it, and keeps the
// user's switch while the map tab is away.
@Riverpod(keepAlive: true)
VehicleFuel vehicleFuel(Ref ref) {
  final v = ref.watch(vehicleProvider).value;
  return VehicleFuel(
    fuel: v?.fuel,
    consumptionL100: v?.consumptionL100,
    lpgHeating: v?.lpgHeating ?? false,
  );
}
