import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:meta/meta.dart';

/// A stop of the route as the user asked for it and as the route reaches
/// it: where the server moved it, when it did.
typedef LegEnd = ({LatLng asked, LatLng reached});

/// One stretch of the route ahead: from the vehicle, or the stop before,
/// to a stop or to the destination.
@immutable
final class RouteLeg {
  const new({
    required this.to,
    required this.toM,
    required this.toS,
    required this.bounds,
    this.stop,
  });

  /// What it leads to, as the user asked for it: names the leg from one
  /// route to the next, whatever the stops passed meanwhile.
  final LatLng to;

  /// Its stop's index among the stops ahead; null for the destination.
  final int? stop;

  /// Metres and seconds from the vehicle to its end: those of the whole
  /// trip left, shared out along the route by its steps.
  final double toM;
  final double toS;

  /// The box of the route from the leg's start to its end.
  final GeoBounds bounds;
}

/// The legs of [route] still ahead of the vehicle, [alongM] metres along
/// it, through [stops] (those ahead, in order) to [destination]: the
/// first from the vehicle to the first stop, then from stop to stop.
/// [leftM] and [leftS] are what the guidance says is left of the trip; the
/// last leg ends with them. Empty for a route without a shape.
List<RouteLeg> routeLegs({
  required RouteOption route,
  required List<LegEnd> stops,
  required LegEnd destination,
  required double alongM,
  required double leftM,
  required double leftS,
  LatLng? vehicle,
}) {
  final line = route.line;
  if (line.length < 2) return const [];
  final acc = List<double>.filled(line.length, 0);
  for (var i = 1; i < line.length; i++) {
    acc[i] = acc[i - 1] + line[i - 1].distanceTo(line[i]);
  }
  final total = acc.last;
  final from = alongM.clamp(0.0, total);
  final time = _TimeAlong(route, total);
  final timeLeft = time.at(total) - time.at(from);
  final ends = <(LatLng, int?, double, LatLng)>[];
  var start = from;
  for (final (i, s) in stops.indexed) {
    final along = _nearestAlongFrom(s.reached, line, acc, start);
    ends.add((s.asked, i, along, s.reached));
    start = along;
  }
  ends.add((destination.asked, null, total, destination.reached));
  final legs = <RouteLeg>[];
  start = from;
  for (final (asked, stop, along, reached) in ends) {
    legs.add(
      RouteLeg(
        to: asked,
        stop: stop,
        toM: total > from ? leftM * (along - from) / (total - from) : 0,
        toS: timeLeft > 0 ? leftS * (time.at(along) - time.at(from)) / timeLeft : 0,
        bounds: GeoBounds.around([
          _pointAt(line, acc, start),
          for (var i = 0; i < line.length; i++)
            if (acc[i] > start && acc[i] < along) line[i],
          _pointAt(line, acc, along),
          reached,
          if (legs.isEmpty) ?vehicle,
        ])!,
      ),
    );
    start = along;
  }
  return legs;
}

/// The point [along] metres along [line], whose lengths so far are [acc].
LatLng _pointAt(List<LatLng> line, List<double> acc, double along) {
  for (var i = 1; i < line.length; i++) {
    if (acc[i] >= along) {
      final seg = acc[i] - acc[i - 1];
      final t = seg <= 0 ? 0.0 : ((along - acc[i - 1]) / seg).clamp(0.0, 1.0);
      final a = line[i - 1];
      final b = line[i];
      return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
    }
  }
  return line.last;
}

/// Where [line] passes nearest [p], in metres from its start, looking only
/// from [fromM] on: a route that comes by the same place twice reaches a
/// stop on the pass after the stop before it.
double _nearestAlongFrom(LatLng p, List<LatLng> line, List<double> acc, double fromM) {
  const metresPerDegree = 111195.0;
  final cosLat = math.cos(p.lat * math.pi / 180);
  (double, double) local(LatLng q) =>
      ((q.lon - p.lon) * metresPerDegree * cosLat, (q.lat - p.lat) * metresPerDegree);
  var best = double.infinity;
  var bestAlong = fromM;
  for (var i = 1; i < line.length; i++) {
    if (acc[i] < fromM) continue;
    final (ax, ay) = local(line[i - 1]);
    final (bx, by) = local(line[i]);
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final seg = acc[i] - acc[i - 1];
    // The part of the segment before fromM is behind.
    final t0 = seg <= 0 ? 0.0 : ((fromM - acc[i - 1]) / seg).clamp(0.0, 1.0);
    final t = len2 == 0 ? t0 : (-(ax * dx + ay * dy) / len2).clamp(t0, 1.0);
    final x = ax + t * dx;
    final y = ay + t * dy;
    final d = math.sqrt(x * x + y * y);
    if (d < best) {
      best = d;
      bestAlong = acc[i - 1] + t * seg;
    }
  }
  return bestAlong;
}

/// The time the router gives to reach each point of a route, from its
/// steps: a slow street and a fast road of the same length weigh as they
/// are driven.
final class _TimeAlong {
  new(this.route, this.lineM) {
    var d = 0.0;
    var s = 0.0;
    for (final step in route.steps) {
      _d.add(d);
      _s.add(s);
      d += step.distanceM;
      s += step.durationS;
    }
    _stepsM = d;
  }

  final RouteOption route;

  /// The length of the line, which the steps' metres may differ from by a
  /// little: positions are read on the line, then scaled.
  final double lineM;
  final _d = <double>[];
  final _s = <double>[];
  double _stepsM = 0;

  /// Seconds from the start to [alongM] metres along the line.
  double at(double alongM) {
    final steps = route.steps;
    if (_stepsM <= 0 || lineM <= 0) {
      return lineM <= 0 ? 0 : route.durationS * alongM / lineM;
    }
    final m = alongM * _stepsM / lineM;
    for (var k = steps.length - 1; k >= 0; k--) {
      if (m >= _d[k]) {
        final step = steps[k];
        final into = step.distanceM <= 0 ? 0.0 : ((m - _d[k]) / step.distanceM).clamp(0.0, 1.0);
        return _s[k] + into * step.durationS;
      }
    }
    return 0;
  }
}
