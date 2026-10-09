import 'package:meta/meta.dart';

/// Where a speed limit along a route comes from (`SpeedLimitSource`).
enum SpeedLimitSource {
  /// The sign, as OpenStreetMap maps it.
  posted,

  /// The road's default in France where no sign is mapped: an estimate.
  estimated,

  /// The vehicle's own ceiling, lower than the road's (a motorhome over
  /// 3.5 t, a heavy train).
  vehicle;

  static SpeedLimitSource? fromWire(Object? wire) => switch (wire) {
    'POSTED' => posted,
    'DEFAULT' => estimated,
    'VEHICLE' => vehicle,
    _ => null,
  };
}

/// The limit for the vehicle over a stretch of a route (`SpeedLimitSpan`).
@immutable
final class SpeedLimitSpan {
  const new({required this.fromM, required this.toM, required this.kmh, required this.source});

  /// Metres from the start of the route.
  final double fromM;
  final double toM;
  final int kmh;
  final SpeedLimitSource source;

  @override
  bool operator ==(Object other) =>
      other is SpeedLimitSpan &&
      other.fromM == fromM &&
      other.toM == toM &&
      other.kmh == kmh &&
      other.source == source;

  @override
  int get hashCode => Object.hash(fromM, toM, kmh, source);
}

/// The limit shown beside the speed.
@immutable
final class ShownLimit {
  const new({required this.kmh, required this.source});

  final int kmh;
  final SpeedLimitSource source;

  /// An estimate shows apart and never warns.
  bool get estimated => source == SpeedLimitSource.estimated;

  @override
  bool operator ==(Object other) =>
      other is ShownLimit && other.kmh == kmh && other.source == source;

  @override
  int get hashCode => Object.hash(kmh, source);
}

/// The limit [spans] give at [alongM] from a sign or the vehicle's
/// ceiling; null where only an estimate, or nothing, is known.
int? knownLimitAt(List<SpeedLimitSpan>? spans, double alongM) {
  final span = spans == null ? null : spanAt(spans, alongM);
  return span == null || span.source == SpeedLimitSource.estimated ? null : span.kmh;
}

/// The span of [spans] (sorted, as the server sends them) covering
/// [alongM]; null where none does.
SpeedLimitSpan? spanAt(List<SpeedLimitSpan> spans, double alongM) {
  var low = 0;
  var high = spans.length - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    final s = spans[mid];
    if (alongM < s.fromM) {
      high = mid - 1;
    } else if (alongM > s.toM) {
      low = mid + 1;
    } else {
      return s;
    }
  }
  return null;
}

/// The heaviest vehicle whose ceiling is the road's own: above it, the
/// sign alone may say more than the vehicle may drive.
const lightVehicleT = 3.5;

/// The limit at [alongM]: the server's span for the vehicle when the route
/// came with them ([spans] not null), else the sign the map gives
/// ([postedKmh]) only for a vehicle whose ceiling is the road's (3.5 t or
/// less with its trailer); null where nothing is known.
ShownLimit? limitAt({
  required List<SpeedLimitSpan>? spans,
  required double alongM,
  required double? postedKmh,
  required double totalWeightT,
}) {
  if (spans != null) {
    final span = spanAt(spans, alongM);
    return span == null ? null : ShownLimit(kmh: span.kmh, source: span.source);
  }
  if (postedKmh == null || totalWeightT > lightVehicleT) return null;
  return ShownLimit(kmh: postedKmh.round(), source: SpeedLimitSource.posted);
}

/// Whether the vehicle drives over its limit, and when to say so: over
/// when the speed passes the limit plus [toleranceKmh] for [confirm]; a
/// word after [soundAfter] over, then every [repeat] while it lasts; back
/// under the limit for [rearm], the next excess starts over (OsmAnd's
/// rhythm). An estimated limit never warns.
final class OverSpeedWatch {
  new({
    this.toleranceKmh = 3,
    this.confirm = const Duration(seconds: 2),
    this.soundAfter = const Duration(seconds: 5),
    this.repeat = const Duration(minutes: 2),
    this.rearm = const Duration(seconds: 30),
  });

  final double toleranceKmh;
  final Duration confirm;
  final Duration soundAfter;
  final Duration repeat;
  final Duration rearm;

  DateTime? _overSince;
  DateTime? _underSince;
  DateTime? _lastSound;

  /// The state after a fix at [at]: `over` for the sign, `sound` true once
  /// when the word is due.
  ({bool over, bool sound}) update({
    required double? speedKmh,
    required ShownLimit? limit,
    required DateTime at,
  }) {
    final over =
        speedKmh != null &&
        limit != null &&
        !limit.estimated &&
        speedKmh > limit.kmh + toleranceKmh;
    if (!over) {
      _underSince ??= at;
      if (!at.isBefore(_underSince!.add(rearm))) {
        _overSince = null;
        _lastSound = null;
      }
      return (over: false, sound: false);
    }
    _underSince = null;
    final since = _overSince ??= at;
    final last = _lastSound;
    final sound = last == null
        ? !at.isBefore(since.add(soundAfter))
        : !at.isBefore(last.add(repeat));
    if (sound) _lastSound = at;
    return (over: !at.isBefore(since.add(confirm)), sound: sound);
  }
}
