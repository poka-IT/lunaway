import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:meta/meta.dart';

/// The user's choices about the limit and the alerts of the guidance.
@immutable
final class DrivingAidsSettings {
  const new({this.showSpeedLimit = true, this.speedSound = false, this.exactIn = const {}});

  /// Unknown or corrupt values fall back to the defaults.
  factory decode(String? raw) {
    if (raw == null) return const DrivingAidsSettings();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const DrivingAidsSettings();
      final exactIn = json['exactIn'];
      return DrivingAidsSettings(
        showSpeedLimit: json['showSpeedLimit'] != false,
        speedSound: json['speedSound'] == true,
        exactIn: {
          if (exactIn is List)
            for (final c in exactIn)
              if (c is String && c.length == 2) c.toUpperCase(),
        },
      );
    } on FormatException {
      return const DrivingAidsSettings();
    }
  }

  /// The limit beside the speed during guidance.
  final bool showSpeedLimit;

  /// A word when the vehicle drives over the road's limit, in the full
  /// voice; off by default: the sign alone. A danger zone or a camera
  /// coming is an alert, said as the voice mode allows whatever this says.
  final bool speedSound;

  /// The countries where the user asked for the cameras' exact positions
  /// where zones are the default (`EnforcementRules.optInOf`): France
  /// only, none by default. Never logged.
  final Set<String> exactIn;

  DrivingAidsSettings copyWith({bool? showSpeedLimit, bool? speedSound, Set<String>? exactIn}) =>
      DrivingAidsSettings(
        showSpeedLimit: showSpeedLimit ?? this.showSpeedLimit,
        speedSound: speedSound ?? this.speedSound,
        exactIn: exactIn ?? this.exactIn,
      );

  String encode() => jsonEncode({
    'showSpeedLimit': showSpeedLimit,
    'speedSound': speedSound,
    'exactIn': exactIn.toList()..sort(),
  });

  @override
  bool operator ==(Object other) =>
      other is DrivingAidsSettings &&
      other.showSpeedLimit == showSpeedLimit &&
      other.speedSound == speedSound &&
      const SetEquality<String>().equals(other.exactIn, exactIn);

  @override
  int get hashCode => Object.hash(showSpeedLimit, speedSound, Object.hashAllUnordered(exactIn));
}

/// What the aids tell on screen: an alert (a standing notice), else the end of a zone or
/// a section just left, else the rule of a country just entered.
@immutable
sealed class AidsBanner {
  const new();
}

/// A danger zone, a camera or an average speed section ahead of the
/// vehicle or around it.
final class EnforcementAlert extends AidsBanner {
  const new({
    required this.id,
    required this.kind,
    required this.aheadM,
    required this.remainingM,
    this.category,
    this.limitKmh,
    this.limitEstimated = false,
    this.cameraLimit = false,
    this.sectionM,
    this.averageKmh,
    this.over = false,
    this.sources = const [],
  });

  /// The id of its first item: the same alert from fix to fix.
  final String id;

  /// A zone, or a camera (at a point, or an average speed section).
  final EnforcementKind kind;

  /// What a camera controls; null for a zone, which never says, and for a
  /// category this app does not know.
  final CameraCategory? category;

  /// Metres to its start; 0 inside it, and once a camera's point is
  /// reached.
  final double aheadM;

  /// Metres to its end, inside a zone or a section; 0 ahead of it.
  final double remainingM;

  /// The limit that matters here: the camera's own when its list gives it
  /// ([cameraLimit]), else the road's where the vehicle is; null where
  /// none is known, or the user hid the road's.
  final int? limitKmh;

  /// [limitKmh] is the road's default, an estimate: shown apart, never
  /// over.
  final bool limitEstimated;

  /// [limitKmh] is the camera's own, not the road's.
  final bool cameraLimit;

  /// An average speed section's length; null for anything else.
  final double? sectionM;

  /// Inside a section, the vehicle's average speed since it entered it,
  /// once it has driven 200 m of it; null before, or when the guidance
  /// started inside it.
  final double? averageKmh;

  /// The vehicle drives over [limitKmh] (inside a section, its average
  /// does): the banner says so.
  final bool over;

  /// The lists it comes from, cited with their date (the French list asks
  /// for its source and date, Catalonia's for its own).
  final List<EnforcementSource> sources;

  bool get inside => aheadM <= 0;

  bool get isSection => sectionM != null;

  /// The vehicle is within the stretch: a zone or a section entered. A
  /// camera's point reached is not a stretch to be in: its alert holds a
  /// few metres past it, still "ahead" in what it shows and says.
  bool get within => inside && (kind == EnforcementKind.zone || isSection);

  @override
  bool operator ==(Object other) =>
      other is EnforcementAlert &&
      other.id == id &&
      other.kind == kind &&
      other.category == category &&
      other.aheadM == aheadM &&
      other.remainingM == remainingM &&
      other.limitKmh == limitKmh &&
      other.limitEstimated == limitEstimated &&
      other.cameraLimit == cameraLimit &&
      other.sectionM == sectionM &&
      other.averageKmh == averageKmh &&
      other.over == over &&
      const ListEquality<EnforcementSource>().equals(other.sources, sources);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    category,
    aheadM,
    remainingM,
    limitKmh,
    limitEstimated,
    cameraLimit,
    sectionM,
    averageKmh,
    over,
  );
}

/// The end of a danger zone or of an average speed section the vehicle
/// just left: on screen for a few seconds, never said.
final class AlertExit extends AidsBanner {
  const new({required this.id, required this.section});

  final String id;

  /// The end of an average speed section, else of a danger zone.
  final bool section;

  @override
  bool operator ==(Object other) =>
      other is AlertExit && other.id == id && other.section == section;

  @override
  int get hashCode => Object.hash(id, section);
}

/// The rule of the country the vehicle just entered, on screen for a few
/// seconds, never said: "Suisse : pas d'alerte radar".
final class RuleChange extends AidsBanner {
  const new({required this.country, required this.mode});

  /// The country whose rule now applies (the strictest within a kilometre).
  final String country;
  final EnforcementMode mode;

  @override
  bool operator ==(Object other) =>
      other is RuleChange && other.country == country && other.mode == mode;

  @override
  int get hashCode => Object.hash(country, mode);
}

/// What the guidance shows beside the speed and over the map, after a fix.
@immutable
final class DrivingAids {
  const new({
    this.limit,
    this.overSpeed = false,
    this.alert,
    this.exit,
    this.ruleChange,
    this.mode = EnforcementMode.off,
    this.country,
    this.calls = const [],
    this.zones = const [],
    this.cameras = const [],
  });

  static const none = DrivingAids();

  /// The same aids with other [zones]: none while a new route waits for
  /// its first fix, as those were measured on the old one. The cameras
  /// stand where they stand: they stay until that fix.
  DrivingAids withZones(List<RouteSpan> zones) => DrivingAids(
    limit: limit,
    overSpeed: overSpeed,
    alert: alert,
    exit: exit,
    ruleChange: ruleChange,
    mode: mode,
    country: country,
    calls: calls,
    zones: zones,
    cameras: cameras,
  );

  /// The limit to show; null where none is known or the user turned it
  /// off.
  final ShownLimit? limit;

  /// The vehicle drives over [limit].
  final bool overSpeed;

  /// The zone or camera to show; never where the rule of the country does
  /// not allow it.
  final EnforcementAlert? alert;

  /// The zone or section just left, while it is told.
  final AlertExit? exit;

  /// The rule of the country just entered, while it is told.
  final RuleChange? ruleChange;

  /// The rule the vehicle drives under, the stricter one near a border.
  final EnforcementMode mode;

  /// The country the vehicle is in, when known.
  final String? country;

  /// The words due at this fix, in the order they came (an alert coming,
  /// over its limit, over the road's): the guidance says each once, in the
  /// app's language.
  final List<AidCall> calls;

  /// The stretches of the route its danger zones cover, for the map: only
  /// where the rule of the country the vehicle is in, and the zone's own,
  /// allow zones.
  final List<RouteSpan> zones;

  /// The cameras of the route, for the map: only where the rule of the
  /// country the vehicle is in, and the camera's own, show points.
  final List<CameraOnRoute> cameras;

  /// What the banner shows, one thing at a time: the alert, else the end
  /// just left, else the new rule.
  AidsBanner? get banner => alert ?? exit ?? ruleChange;

  @override
  bool operator ==(Object other) =>
      other is DrivingAids &&
      other.limit == limit &&
      other.overSpeed == overSpeed &&
      other.alert == alert &&
      other.exit == exit &&
      other.ruleChange == ruleChange &&
      other.mode == mode &&
      other.country == country &&
      const ListEquality<AidCall>().equals(other.calls, calls) &&
      const ListEquality<RouteSpan>().equals(other.zones, zones) &&
      const ListEquality<CameraOnRoute>().equals(other.cameras, cameras);

  @override
  int get hashCode => Object.hash(
    limit,
    overSpeed,
    alert,
    exit,
    ruleChange,
    mode,
    country,
    Object.hashAll(calls),
    Object.hashAll(zones),
    Object.hashAll(cameras),
  );
}

/// What a word of the aids says.
enum AidWord {
  /// The vehicle drives over the road's limit: a reminder, not an alert.
  overSpeed,

  /// A danger zone comes, or the vehicle is in one.
  zone,

  /// A camera comes, with its kind and its limit.
  camera,

  /// An average speed section comes, or the vehicle is in one.
  section,

  /// The vehicle drives over the limit of the alert it is under: once per
  /// zone, camera or section.
  slowDown;

  /// Whether it is a safety alert, said in every voice mode that speaks;
  /// the reminder of the road's limit is not one.
  bool get alert => this != overSpeed;
}

/// One word due: what it is about, a key that names it once (the same key
/// is never said twice), and the zone or camera it speaks of.
@immutable
final class AidCall {
  const new({required this.word, required this.key, this.alert});

  final AidWord word;
  final String key;
  final EnforcementAlert? alert;

  @override
  bool operator ==(Object other) =>
      other is AidCall && other.word == word && other.key == key && other.alert == alert;

  @override
  int get hashCode => Object.hash(word, key, alert);
}
