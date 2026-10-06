import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
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
