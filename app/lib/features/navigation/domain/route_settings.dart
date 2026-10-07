import 'dart:convert';

import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:meta/meta.dart';

/// What a route avoids. Tolls, motorways and ferries are avoided when
/// another way exists; unpaved roads are never used (API semantics).
@immutable
final class AvoidOptions {
  const new({
    this.tolls = false,
    this.motorways = false,
    this.ferries = false,
    this.unpaved = false,
  });

  factory fromJson(Map<String, dynamic> json) => AvoidOptions(
    tolls: json['avoidTolls'] == true,
    motorways: json['avoidMotorways'] == true,
    ferries: json['avoidFerries'] == true,
    unpaved: json['avoidUnpaved'] == true,
  );

  final bool tolls;
  final bool motorways;
  final bool ferries;
  final bool unpaved;

  bool get any => tolls || motorways || ferries || unpaved;

  AvoidOptions copyWith({bool? tolls, bool? motorways, bool? ferries, bool? unpaved}) =>
      AvoidOptions(
        tolls: tolls ?? this.tolls,
        motorways: motorways ?? this.motorways,
        ferries: ferries ?? this.ferries,
        unpaved: unpaved ?? this.unpaved,
      );

  Map<String, Object?> toJson() => {
    'avoidTolls': tolls,
    'avoidMotorways': motorways,
    'avoidFerries': ferries,
    'avoidUnpaved': unpaved,
  };

  @override
  bool operator ==(Object other) =>
      other is AvoidOptions &&
      other.tolls == tolls &&
      other.motorways == motorways &&
      other.ferries == ferries &&
      other.unpaved == unpaved;

  @override
  int get hashCode => Object.hash(tolls, motorways, ferries, unpaved);
}

/// How distances and speeds read.
enum DistanceUnits {
  /// Metres, kilometres, km/h.
  metric,

  /// Feet, miles, mph.
  imperial,
}

/// The language of the router's instructions.
enum RouteLanguage {
  fr,
  en;

  /// The language of the app's locale, French for anything else (the
  /// router writes these two).
  static RouteLanguage of(String languageCode) => languageCode == 'en' ? en : fr;

  /// The tag the speech engine takes.
  String get speechTag => this == fr ? 'fr-FR' : 'en-GB';
}

/// The user's route settings, kept on the device.
@immutable
final class NavigationSettings {
  const new({
    this.avoid = const AvoidOptions(),
    this.voice = true,
    this.units = DistanceUnits.metric,
    this.acceptedDisclaimer,
  });

  /// Unknown or corrupt values fall back to the defaults, never fatal: the
  /// stored text may come from an older or newer app.
  factory decode(String? raw) {
    if (raw == null) return const NavigationSettings();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const NavigationSettings();
      final avoid = json['avoid'];
      final accepted = json['acceptedDisclaimer'];
      return NavigationSettings(
        avoid: avoid is Map<String, dynamic> ? AvoidOptions.fromJson(avoid) : const AvoidOptions(),
        voice: json['voice'] != false,
        units: DistanceUnits.values.asNameMap()['${json['units']}'] ?? DistanceUnits.metric,
        acceptedDisclaimer: accepted is String ? accepted : null,
      );
    } on FormatException {
      return const NavigationSettings();
    }
  }

  final AvoidOptions avoid;

  /// Spoken instructions during guidance.
  final bool voice;
  final DistanceUnits units;

  /// The disclaimer the user read before a first guidance (its key,
  /// `routing.disclaimer.v1`): a new version is shown again.
  final String? acceptedDisclaimer;

  NavigationSettings copyWith({
    AvoidOptions? avoid,
    bool? voice,
    DistanceUnits? units,
    String? acceptedDisclaimer,
  }) => NavigationSettings(
    avoid: avoid ?? this.avoid,
    voice: voice ?? this.voice,
    units: units ?? this.units,
    acceptedDisclaimer: acceptedDisclaimer ?? this.acceptedDisclaimer,
  );

  String encode() => jsonEncode({
    'avoid': avoid.toJson(),
    'voice': voice,
    'units': units.name,
    'acceptedDisclaimer': ?acceptedDisclaimer,
  });

  @override
  bool operator ==(Object other) =>
      other is NavigationSettings &&
      other.avoid == avoid &&
      other.voice == voice &&
      other.units == units &&
      other.acceptedDisclaimer == acceptedDisclaimer;

  @override
  int get hashCode => Object.hash(avoid, voice, units, acceptedDisclaimer);
}

/// The kinds of vehicle of the router (`VehicleType` of the API).
enum RouterVehicleType {
  van('VAN'),
  panelVan('PANEL_VAN'),
  lowProfile('LOW_PROFILE'),
  overcab('OVERCAB'),
  integrated('INTEGRATED'),
  other('OTHER');

  new(this.wire);

  final String wire;

  static RouterVehicleType of(VehicleType type) => switch (type) {
    VehicleType.van => van,
    VehicleType.campervan => panelVan,
    VehicleType.lowProfile => lowProfile,
    VehicleType.overcab => overcab,
    VehicleType.integrated => integrated,
  };

  static RouterVehicleType fromWire(String? wire) =>
      values.where((v) => v.wire == wire).firstOrNull ?? other;
}

/// A trailer, as the router takes it.
@immutable
final class TrailerProfile {
  const new({required this.lengthM, required this.weightT, this.heightM, this.widthM});

  final double lengthM;
  final double weightT;
  final double? heightM;
  final double? widthM;

  Map<String, Object?> toJson() => {
    'lengthM': lengthM,
    'weightT': weightT,
    if (heightM != null) 'heightM': heightM,
    if (widthM != null) 'widthM': widthM,
  };
}

/// The vehicle as the router takes it: every figure the route depends on.
@immutable
final class VehicleProfile {
  const new({
    required this.type,
    required this.heightM,
    required this.widthM,
    required this.lengthM,
    required this.weightT,
    this.trailer,
    this.cruiseSpeedKph,
  });

  final RouterVehicleType type;
  final double heightM;
  final double widthM;

  /// The vehicle alone, bike rack included; a trailer counts apart.
  final double lengthM;
  final double weightT;
  final TrailerProfile? trailer;

  /// The highest speed the driver keeps to, km/h: the server times the
  /// route at it, never above the vehicle's legal ceiling.
  final int? cruiseSpeedKph;

  Map<String, Object?> toJson() => {
    'kind': type.wire,
    'heightM': heightM,
    'widthM': widthM,
    'lengthM': lengthM,
    'weightT': weightT,
    if (trailer != null) 'trailer': trailer!.toJson(),
    'cruiseSpeedKph': ?cruiseSpeedKph,
  };

  @override
  bool operator ==(Object other) =>
      other is VehicleProfile &&
      other.type == type &&
      other.heightM == heightM &&
      other.widthM == widthM &&
      other.lengthM == lengthM &&
      other.weightT == weightT &&
      other.trailer?.lengthM == trailer?.lengthM &&
      other.trailer?.weightT == trailer?.weightT &&
      other.trailer?.heightM == trailer?.heightM &&
      other.trailer?.widthM == trailer?.widthM &&
      other.cruiseSpeedKph == cruiseSpeedKph;

  @override
  int get hashCode => Object.hash(
    type,
    heightM,
    widthM,
    lengthM,
    weightT,
    trailer?.lengthM,
    trailer?.weightT,
    cruiseSpeedKph,
  );
}

/// Which figure of the vehicle a route cannot go without.
enum MissingDimension { height, width, length, weight }

/// Why a vehicle cannot be routed yet.
@immutable
final class VehicleCheck {
  const new({this.profile, this.missing = const {}, this.outOfBounds = const {}});

  /// The profile to send; null when [missing] or [outOfBounds] is not empty.
  final VehicleProfile? profile;

  /// Figures the user has not given.
  final Set<MissingDimension> missing;

  /// Figures outside what the router accepts (a length over 15 m for the
  /// vehicle alone).
  final Set<MissingDimension> outOfBounds;

  bool get ready => profile != null;
}

/// The bounds the router accepts (`RoutingInfo.vehicleBounds`), with the
/// values the API served on 2026-10-06 as the default.
@immutable
final class VehicleBounds {
  const new({
    this.height = (min: 1.5, max: 4.5),
    this.width = (min: 1.5, max: 2.6),
    this.length = (min: 3.0, max: 15.0),
    this.weight = (min: 0.5, max: 40.0),
  });

  final ({double min, double max}) height;
  final ({double min, double max}) width;
  final ({double min, double max}) length;
  final ({double min, double max}) weight;
}

/// The trailer assumed behind a vehicle that tows, when the app knows only
/// the total length: the API's `car-trailer` preset (Debon Roadster Auto,
/// 4.78 m, 1.5 t), the commonest thing a motorhome tows in France.
const assumedTrailer = TrailerProfile(lengthM: 4.78, weightT: 1.5, widthM: 2.1);

/// The profile of [vehicle] for the router, or what is missing.
///
/// Every figure is required: a route computed on a guessed height could
/// send a vehicle under a bridge it does not clear. The app stores the
/// length of the whole combination when the vehicle tows; the router wants
/// the trailer apart, so the [assumedTrailer] is taken off the total (the
/// trailer and caravan bans then apply, and the combination keeps its
/// length).
VehicleCheck checkVehicle(Vehicle? vehicle, {VehicleBounds bounds = const VehicleBounds()}) {
  if (vehicle == null) {
    return const VehicleCheck(missing: {...MissingDimension.values});
  }
  final missing = {
    if (vehicle.heightM == null) MissingDimension.height,
    if (vehicle.widthM == null) MissingDimension.width,
    if (vehicle.lengthM == null) MissingDimension.length,
    if (vehicle.weightT == null) MissingDimension.weight,
  };
  if (missing.isNotEmpty) return VehicleCheck(missing: missing);
  final towing = vehicle.towing != Towing.none;
  final total = vehicle.lengthM!;
  final trailer = towing ? assumedTrailer : null;
  // A total too short to hold the trailer is the vehicle's own length.
  final own = towing && total - assumedTrailer.lengthM >= bounds.length.min
      ? total - assumedTrailer.lengthM
      : total;
  bool outside(double v, ({double min, double max}) r) => v < r.min || v > r.max;
  final out = {
    if (outside(vehicle.heightM!, bounds.height)) MissingDimension.height,
    if (outside(vehicle.widthM!, bounds.width)) MissingDimension.width,
    if (outside(own, bounds.length)) MissingDimension.length,
    if (outside(vehicle.weightT!, bounds.weight)) MissingDimension.weight,
  };
  if (out.isNotEmpty) return VehicleCheck(outOfBounds: out);
  return VehicleCheck(
    profile: VehicleProfile(
      type: RouterVehicleType.of(vehicle.type),
      heightM: vehicle.heightM!,
      widthM: vehicle.widthM!,
      lengthM: own,
      weightT: vehicle.weightT!,
      trailer: trailer,
      cruiseSpeedKph: vehicle.cruiseSpeedKph,
    ),
  );
}
