import 'package:meta/meta.dart';

/// The kind of vehicle, as motorhome owners name them. The type sets the
/// dimensions offered by default; the user corrects them.
enum VehicleType {
  /// A small van, raised roof or not.
  van('van', heightM: 2, widthM: 1.95, lengthM: 5, weightT: 3),

  /// A panel van fitted out as a camper (fourgon aménagé).
  campervan('campervan', heightM: 2.65, widthM: 2.05, lengthM: 6, weightT: 3.5),

  /// A low-profile motorhome (profilé).
  lowProfile('low_profile', heightM: 2.9, widthM: 2.3, lengthM: 7, weightT: 3.5),

  /// A motorhome with a bed over the cab (capucine).
  overcab('overcab', heightM: 3.15, widthM: 2.3, lengthM: 7, weightT: 3.5),

  /// An A-class motorhome (intégral).
  integrated('integrated', heightM: 2.95, widthM: 2.35, lengthM: 7.4, weightT: 3.5);

  new(
    this.wire, {
    required this.heightM,
    required this.widthM,
    required this.lengthM,
    required this.weightT,
  });

  /// The stored name; stable across renames of the enum value.
  final String wire;

  /// Typical dimensions, offered when the user picks the type.
  final double heightM;
  final double widthM;
  final double lengthM;
  final double weightT;

  static VehicleType fromWire(String wire) =>
      values.firstWhere((t) => t.wire == wire, orElse: () => campervan);
}

/// What the vehicle tows, which changes its length on the road and in a
/// parking space.
enum Towing {
  none('none'),
  car('car'),
  trailer('trailer');

  new(this.wire);

  final String wire;

  static Towing fromWire(String wire) =>
      values.firstWhere((t) => t.wire == wire, orElse: () => none);
}

/// The user's vehicle. Dimensions are in metres and tonnes; any may be
/// unknown. The height filters places now; every dimension will constrain
/// routes when the in-app navigation arrives.
@immutable
final class Vehicle {
  const new({
    required this.type,
    this.towing = Towing.none,
    this.heightM,
    this.widthM,
    this.lengthM,
    this.weightT,
  });

  /// A vehicle of [type] with its typical dimensions.
  factory typical(VehicleType type) => Vehicle(
    type: type,
    heightM: type.heightM,
    widthM: type.widthM,
    lengthM: type.lengthM,
    weightT: type.weightT,
  );

  final VehicleType type;
  final Towing towing;
  final double? heightM;
  final double? widthM;

  /// Total length on the road, including what is towed.
  final double? lengthM;

  /// Total permitted weight.
  final double? weightT;

  /// The limits the forms accept: wide enough for every motorhome on the
  /// road, narrow enough to catch a typo (29 for 2.9).
  static const ({double max, double min}) heightRange = (min: 1.5, max: 4.5);
  static const ({double max, double min}) widthRange = (min: 1.5, max: 2.6);
  static const ({double max, double min}) lengthRange = (min: 3.0, max: 20.0);
  static const ({double max, double min}) weightRange = (min: 1.0, max: 26.0);

  Vehicle copyWith({
    VehicleType? type,
    Towing? towing,
    double? Function()? heightM,
    double? Function()? widthM,
    double? Function()? lengthM,
    double? Function()? weightT,
  }) => Vehicle(
    type: type ?? this.type,
    towing: towing ?? this.towing,
    heightM: heightM == null ? this.heightM : heightM(),
    widthM: widthM == null ? this.widthM : widthM(),
    lengthM: lengthM == null ? this.lengthM : lengthM(),
    weightT: weightT == null ? this.weightT : weightT(),
  );

  @override
  bool operator ==(Object other) =>
      other is Vehicle &&
      other.type == type &&
      other.towing == towing &&
      other.heightM == heightM &&
      other.widthM == widthM &&
      other.lengthM == lengthM &&
      other.weightT == weightT;

  @override
  int get hashCode => Object.hash(type, towing, heightM, widthM, lengthM, weightT);
}
