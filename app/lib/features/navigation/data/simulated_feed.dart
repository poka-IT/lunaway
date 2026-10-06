import 'dart:async';
import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

/// A drive along a line at a steady speed: the location feed of the tests,
/// the integration test on the emulator and the captures, where no GPS
/// moves.
final class SimulatedFeed implements LocationFeed {
  new({
    required this.path,
    this.speedMps = 12,
    this.tick = const Duration(seconds: 1),
    this.realTick,
    DateTime? start,
    this.accuracyM = 5,
  }) : start = start ?? DateTime.utc(2026, 10, 6, 9);

  /// The points driven through, in order.
  final List<LatLng> path;
  final double speedMps;

  /// Simulated time between two fixes.
  final Duration tick;

  /// Real time between two fixes; [tick] when null. A test runs the drive
  /// faster than real time this way.
  final Duration? realTick;
  final DateTime start;
  final double accuracyM;

  @override
  Future<Fix?> current() async =>
      path.isEmpty ? null : Fix(position: path.first, accuracyM: accuracyM, at: start);

  @override
  Stream<Fix> guidance(BackgroundNotice notice) async* {
    final fixes = drive(
      path,
      stepM: speedMps * tick.inMilliseconds / 1000,
      start: start,
      tick: tick,
      speedMps: speedMps,
      accuracyM: accuracyM,
    );
    for (final f in fixes) {
      await Future<void>.delayed(realTick ?? tick);
      yield f;
    }
  }
}

/// The fixes of a drive along [path], one every [stepM] metres and [tick].
List<Fix> drive(
  List<LatLng> path, {
  required double stepM,
  required DateTime start,
  required Duration tick,
  required double speedMps,
  double accuracyM = 5,
}) {
  final out = <Fix>[];
  var carry = 0.0;
  var at = start;
  for (var i = 0; i + 1 < path.length; i++) {
    final a = path[i];
    final b = path[i + 1];
    final d = a.distanceTo(b);
    if (d == 0) continue;
    final course = bearing(a, b);
    var s = carry;
    while (s < d) {
      final t = s / d;
      out.add(
        Fix(
          position: LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t),
          accuracyM: accuracyM,
          at: at,
          courseDeg: course,
          speedMps: speedMps,
        ),
      );
      at = at.add(tick);
      s += stepM;
    }
    carry = s - d;
  }
  if (path.isNotEmpty) {
    // Parked at the end: the arrival needs a fix there.
    for (var k = 0; k < 3; k++) {
      out.add(Fix(position: path.last, accuracyM: accuracyM, at: at, speedMps: 0));
      at = at.add(tick);
    }
  }
  return out;
}

/// Initial bearing from [a] to [b], degrees from north.
double bearing(LatLng a, LatLng b) {
  final la = a.lat * math.pi / 180;
  final lb = b.lat * math.pi / 180;
  final dl = (b.lon - a.lon) * math.pi / 180;
  final y = math.sin(dl) * math.cos(lb);
  final x = math.cos(la) * math.sin(lb) - math.sin(la) * math.cos(lb) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
