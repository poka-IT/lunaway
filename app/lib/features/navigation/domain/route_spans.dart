import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:meta/meta.dart';

/// A stretch of a route, from [fromM] to [toM] metres from its start.
@immutable
final class RouteSpan {
  const new(this.fromM, this.toM);

  final double fromM;
  final double toM;

  @override
  bool operator ==(Object other) => other is RouteSpan && other.fromM == fromM && other.toM == toM;

  @override
  int get hashCode => Object.hash(fromM, toM);

  @override
  String toString() => 'RouteSpan($fromM, $toM)';
}

/// [spans] in driving order, those that overlap or touch made one.
List<RouteSpan> mergeSpans(Iterable<RouteSpan> spans) {
  final sorted = [
    for (final s in spans) RouteSpan(math.min(s.fromM, s.toM), math.max(s.fromM, s.toM)),
  ]..sort((a, b) => a.fromM.compareTo(b.fromM));
  final out = <RouteSpan>[];
  for (final s in sorted) {
    final last = out.isEmpty ? null : out.last;
    if (last != null && s.fromM <= last.toM) {
      out[out.length - 1] = RouteSpan(last.fromM, math.max(last.toM, s.toM));
    } else {
      out.add(s);
    }
  }
  return out;
}

/// The points of [line] from [span]'s start to its end, measured along it
/// as [LatLng.distanceTo] does, cut inside the segments where the stretch
/// starts and ends. Fewer than two points when the stretch misses the line.
List<LatLng> lineAlong(List<LatLng> line, RouteSpan span) {
  if (line.length < 2 || span.toM <= span.fromM) return const [];
  final out = <LatLng>[];
  var along = 0.0;
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1];
    final b = line[i];
    final length = a.distanceTo(b);
    final end = along + length;
    if (end >= span.fromM && along <= span.toM && length > 0) {
      LatLng at(double m) {
        final t = ((m - along) / length).clamp(0.0, 1.0);
        return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      }

      if (out.isEmpty) out.add(at(math.max(span.fromM, along)));
      out.add(at(math.min(span.toM, end)));
    }
    if (end >= span.toM) break;
    along = end;
  }
  return out.length < 2 ? const [] : out;
}
