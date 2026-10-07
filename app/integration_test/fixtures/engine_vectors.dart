import 'dart:convert';

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

import 'drive_routes.dart';

/// The shared vectors of the guidance engine: what it answers, fix by fix,
/// along three recorded routes (a drive to the end, a closure ahead, a
/// turn missed then a fix 230 m off the route). The same lines must come
/// out of every build of the crate: the macOS library in
/// `test/unit/navigation/engine_vectors_test.dart`, the phones' and the
/// WebAssembly one in `integration_test/engine_vectors_test.dart`. Numbers
/// are rounded to the decimetre, below anything a screen or a voice shows.
Future<List<String>> engineTrace(GuidanceEngine engine) async {
  final out = <String>[];
  for (final (name, json) in [
    ('limoges_drive', limogesDrive),
    ('closure_detour', closureDetour),
    ('missed_turn', missedTurn),
  ]) {
    final data = (jsonDecode(json) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final plan = await withShapes(routePlanFromJson(data['route'] as Map<String, dynamic>));
    final line = plan.routes.first.line;
    final track = engine.start(plan.osrmJson!, 0);
    final fixes = drive(
      line,
      stepM: 10,
      start: DateTime.utc(2026, 10, 6, 9),
      tick: const Duration(seconds: 1),
      speedMps: 10,
    );
    for (final (i, f) in fixes.indexed) {
      final s = track.update(f);
      out.add(
        [
          name,
          i,
          s.status.name,
          s.stepIndex,
          _m(s.distanceToManeuverM),
          _m(s.distanceRemainingM),
          _m(s.distanceAlongM),
          s.durationRemainingS.round(),
          if (s.offRoute) 'off' else 'on',
          s.instruction?.text ?? '-',
          s.speedLimitKmh?.round() ?? '-',
          s.banner?.maneuverType ?? '-',
          s.banner?.modifier ?? '-',
        ].join(' '),
      );
      if (s.status == GuidanceStatus.arrived) break;
    }
    // A closure 1.5 km to 1.9 km along the route, checked from the start.
    final ahead = [
      for (
        var i = 0, along = 0.0;
        i + 1 < line.length;
        along += line[i].distanceTo(line[i + 1]), i++
      )
        if (along >= 1500 && along <= 1900) line[i],
    ];
    if (ahead.length >= 2) {
      final fresh = engine.start(plan.osrmJson!, 0);
      for (final h in fresh.eventsAhead(0, [EventShape(id: 'closure', points: ahead)])) {
        out.add('$name event ${h.id} ${_m(h.startM)} ${_m(h.endM)}');
      }
      fresh.dispose();
    }
    // 0.003 degrees east of the line, about 230 m, after 30 fixes on it.
    if (fixes.length > 31) {
      final away = engine.start(plan.osrmJson!, 0);
      fixes.take(30).forEach(away.update);
      final p = fixes[30].position;
      final off = Fix(position: LatLng(p.lat, p.lon + 0.003), accuracyM: 5, at: fixes[30].at);
      final first = away.update(off);
      final second = away.update(
        Fix(position: off.position, accuracyM: 5, at: off.at.add(const Duration(seconds: 1))),
      );
      out.add('$name away ${first.offRoute} ${second.offRoute} ${_m(second.offRouteM ?? -1)}');
      away.dispose();
    }
    track.dispose();
  }
  return out;
}

String _m(double v) => v.toStringAsFixed(1);
