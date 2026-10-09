import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:meta/meta.dart';

/// The user's choices about the limit and the alerts of the guidance.
@immutable
final class DrivingAidsSettings {
  const new({this.showSpeedLimit = true, this.speedSound = false});

  /// Unknown or corrupt values fall back to the defaults.
  factory decode(String? raw) {
    if (raw == null) return const DrivingAidsSettings();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const DrivingAidsSettings();
      return DrivingAidsSettings(
        showSpeedLimit: json['showSpeedLimit'] != false,
        speedSound: json['speedSound'] == true,
      );
    } on FormatException {
      return const DrivingAidsSettings();
    }
  }

  /// The limit beside the speed during guidance.
  final bool showSpeedLimit;

  /// A word when the vehicle drives over the limit, and when a danger zone
  /// or a camera comes; off by default: the banners alone.
  final bool speedSound;

  DrivingAidsSettings copyWith({bool? showSpeedLimit, bool? speedSound}) => DrivingAidsSettings(
    showSpeedLimit: showSpeedLimit ?? this.showSpeedLimit,
    speedSound: speedSound ?? this.speedSound,
  );

  String encode() => jsonEncode({'showSpeedLimit': showSpeedLimit, 'speedSound': speedSound});

  @override
  bool operator ==(Object other) =>
      other is DrivingAidsSettings &&
      other.showSpeedLimit == showSpeedLimit &&
      other.speedSound == speedSound;

  @override
  int get hashCode => Object.hash(showSpeedLimit, speedSound);
}

/// A danger zone or a camera ahead of the vehicle or around it.
@immutable
final class EnforcementAlert {
  const new({
    required this.id,
    required this.kind,
    required this.aheadM,
    required this.remainingM,
    this.limitKmh,
    this.sources = const [],
  });

  final String id;
  final EnforcementKind kind;

  /// Metres to its start; 0 inside it.
  final double aheadM;

  /// Metres to its end, inside it; 0 ahead of it.
  final double remainingM;

  /// A camera's limit, when known (only where points may be shown).
  final int? limitKmh;

  /// The lists it comes from, cited with their date (the French list asks
  /// for its source and date, Catalonia's for its own).
  final List<EnforcementSource> sources;

  bool get inside => aheadM <= 0;

  @override
  bool operator ==(Object other) =>
      other is EnforcementAlert &&
      other.id == id &&
      other.kind == kind &&
      other.aheadM == aheadM &&
      other.remainingM == remainingM &&
      other.limitKmh == limitKmh &&
      const ListEquality<EnforcementSource>().equals(other.sources, sources);

  @override
  int get hashCode => Object.hash(id, kind, aheadM, remainingM, limitKmh);
}

/// What the guidance shows beside the speed and over the map, after a fix.
@immutable
final class DrivingAids {
  const new({
    this.limit,
    this.overSpeed = false,
    this.alert,
    this.mode = EnforcementMode.off,
    this.country,
    this.calls = const [],
    this.zones = const [],
  });

  static const none = DrivingAids();

  /// The same aids with other [zones]: none while a new route waits for
  /// its first fix, as those were measured on the old one.
  DrivingAids withZones(List<RouteSpan> zones) => DrivingAids(
    limit: limit,
    overSpeed: overSpeed,
    alert: alert,
    mode: mode,
    country: country,
    calls: calls,
    zones: zones,
  );

  /// The limit to show; null where none is known or the user turned it
  /// off.
  final ShownLimit? limit;

  /// The vehicle drives over [limit].
  final bool overSpeed;

  /// The zone or camera to show; never where the rule of the country does
  /// not allow it.
  final EnforcementAlert? alert;

  /// The rule the vehicle drives under, the stricter one near a border.
  final EnforcementMode mode;

  /// The country the vehicle is in, when known.
  final String? country;

  /// The words due at this fix, in the order they came (over the limit,
  /// an alert coming): the guidance says each once, in the app's language.
  final List<AidCall> calls;

  /// The stretches of the route its danger zones cover, for the map: only
  /// where the rule of the country the vehicle is in, and the zone's own,
  /// allow zones.
  final List<RouteSpan> zones;

  @override
  bool operator ==(Object other) =>
      other is DrivingAids &&
      other.limit == limit &&
      other.overSpeed == overSpeed &&
      other.alert == alert &&
      other.mode == mode &&
      other.country == country &&
      const ListEquality<AidCall>().equals(other.calls, calls) &&
      const ListEquality<RouteSpan>().equals(other.zones, zones);

  @override
  int get hashCode => Object.hash(
    limit,
    overSpeed,
    alert,
    mode,
    country,
    Object.hashAll(calls),
    Object.hashAll(zones),
  );
}

/// What a word of the aids says.
enum AidWord {
  /// The vehicle drives over the road's limit: a reminder, not an alert.
  overSpeed,

  /// A danger zone comes, or the vehicle is in one.
  zone,

  /// A camera comes.
  camera;

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
