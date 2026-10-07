import 'package:drift/drift.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

/// Where the user's vehicle lives between runs.
abstract interface class VehicleRepository {
  /// The vehicle, or null before the user described one.
  Stream<Vehicle?> watch();

  Future<void> save(Vehicle vehicle);

  Future<void> clear();
}

/// The vehicle as the single row of the `vehicle` table.
final class DriftVehicleRepository implements VehicleRepository {
  new(this._db, {this.clock = DateTime.now});

  final UserDatabase _db;
  final DateTime Function() clock;

  @override
  Stream<Vehicle?> watch() =>
      _db.select(_db.vehicles).watchSingleOrNull().map((row) => row == null ? null : _vehicle(row));

  @override
  Future<void> save(Vehicle v) => _db
      .into(_db.vehicles)
      .insertOnConflictUpdate(
        VehiclesCompanion.insert(
          id: const Value(1),
          type: v.type.wire,
          towing: Value(v.towing.wire),
          heightM: Value(v.heightM),
          widthM: Value(v.widthM),
          lengthM: Value(v.lengthM),
          weightT: Value(v.weightT),
          updatedAt: clock().millisecondsSinceEpoch,
          fuel: Value(v.fuel?.wire),
          consumptionL100: Value(v.consumptionL100),
          lpgHeating: Value(v.lpgHeating),
          cruiseSpeedKph: Value(v.cruiseSpeedKph),
        ),
      );

  @override
  Future<void> clear() => _db.delete(_db.vehicles).go();

  static Vehicle _vehicle(VehicleRow r) => Vehicle(
    type: VehicleType.fromWire(r.type),
    towing: Towing.fromWire(r.towing),
    heightM: r.heightM,
    widthM: r.widthM,
    lengthM: r.lengthM,
    weightT: r.weightT,
    fuel: FuelType.fromWire(r.fuel),
    consumptionL100: r.consumptionL100,
    lpgHeating: r.lpgHeating,
    cruiseSpeedKph: r.cruiseSpeedKph,
  );
}
