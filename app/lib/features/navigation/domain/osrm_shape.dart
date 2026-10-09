import 'dart:convert';
import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';

/// Decodes a polyline with [precision] decimals (Valhalla writes six), the
/// format of Google's encoded polylines. A truncated string ends the line
/// where the last whole point ends.
List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
  final factor = _pow10(precision);
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lon = 0;
  // Arithmetic rather than bit operators: compiled to JavaScript, `~` and
  // `<<` give unsigned 32-bit results, and every step west or south came
  // out about four billion units east or north on the web.
  int? next() {
    var result = 0;
    var unit = 1;
    while (index < encoded.length) {
      final byte = encoded.codeUnitAt(index++) - 63;
      result += (byte % 32) * unit;
      unit *= 32;
      if (byte < 32) return result.isOdd ? -(result ~/ 2) - 1 : result ~/ 2;
    }
    return null;
  }

  while (index < encoded.length) {
    final dLat = next();
    final dLon = next();
    if (dLat == null || dLon == null) break;
    lat += dLat;
    lon += dLon;
    points.add(LatLng(lat / factor, lon / factor));
  }
  return points;
}

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// The shapes and steps of every route of an OSRM answer (`osrmJson`), in
/// its order: what the preview draws and lists. Runs in an isolate for long
/// trips (`Isolate.run` at the call site): a 90 km answer is 200 KB.
List<({List<LatLng> line, List<RouteStep> steps})> readOsrmShapes(String osrmJson) {
  final decoded = jsonDecode(osrmJson);
  if (decoded is! Map<String, dynamic>) return const [];
  final routes = decoded['routes'];
  if (routes is! List) return const [];
  return [
    for (final route in routes)
      if (route is Map<String, dynamic>)
        (line: decodePolyline('${route['geometry'] ?? ''}'), steps: _steps(route)),
  ];
}

List<RouteStep> _steps(Map<String, dynamic> route) {
  final legs = route['legs'];
  if (legs is! List) return const [];
  final raw = [
    for (final leg in legs)
      if (leg is Map<String, dynamic> && leg['steps'] is List)
        for (final step in leg['steps'] as List)
          if (step is Map<String, dynamic>) step,
  ];
  return [
    for (var i = 0; i < raw.length; i++)
      _step(
        raw[i],
        previous: i > 0 ? raw[i - 1] : null,
        next: i + 1 < raw.length ? raw[i + 1] : null,
      ),
  ];
}

RouteStep _step(
  Map<String, dynamic> s, {
  Map<String, dynamic>? previous,
  Map<String, dynamic>? next,
}) {
  final maneuver = s['maneuver'] is Map<String, dynamic>
      ? s['maneuver'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final location = maneuver['location'];
  final position = location is List && location.length >= 2
      ? LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble())
      : const LatLng(0, 0);
  final banners = s['bannerInstructions'];
  final primary = banners is List && banners.isNotEmpty && banners.first is Map<String, dynamic>
      ? (banners.first as Map<String, dynamic>)['primary']
      : null;
  final name = '${s['name'] ?? ''}'.trim();
  final type = '${maneuver['type'] ?? 'turn'}';
  final leftHand = s['driving_side'] == 'left';
  final leaving = type == 'exit roundabout' || type == 'exit rotary';
  final entered = leaving ? _maneuverOf(previous) : maneuver;
  return RouteStep(
    instruction: '${maneuver['instruction'] ?? ''}',
    distanceM: (s['distance'] as num?)?.toDouble() ?? 0,
    durationS: (s['duration'] as num?)?.toDouble() ?? 0,
    position: position,
    maneuverType: type,
    modifier: maneuver['modifier'] as String?,
    roadName: name.isEmpty ? null : name,
    banner: primary is Map<String, dynamic> ? primary['text'] as String? : null,
    exit: ((leaving ? entered['exit'] : maneuver['exit']) as num?)?.toInt(),
    exitDegrees: Maneuver(type: type).isRoundabout
        ? _bannerDegrees(previous, type) ??
              _exitDegrees(
                headingIn: entered['bearing_before'],
                headingOut: leaving
                    ? maneuver['bearing_after']
                    : _maneuverOf(next)['bearing_after'],
                leftHandTraffic: leftHand,
                exitsHere: leaving || _exits(next),
              )
        : null,
    leftHandTraffic: leftHand,
    ferry: s['mode'] == 'ferry',
    lanes: _lanesBefore(s, next),
  );
}

Map<String, dynamic> _maneuverOf(Map<String, dynamic>? step) =>
    step?['maneuver'] is Map<String, dynamic>
    ? step!['maneuver'] as Map<String, dynamic>
    : const <String, dynamic>{};

bool _exits(Map<String, dynamic>? step) {
  final type = _maneuverOf(step)['type'];
  return type == 'exit roundabout' || type == 'exit rotary';
}

/// The router's own `degrees` for the roundabout maneuver of type [type]:
/// Valhalla writes them in the banner of the step before, which shows
/// that maneuver.
int? _bannerDegrees(Map<String, dynamic>? previous, String type) {
  final banners = previous?['bannerInstructions'];
  if (banners is! List) return null;
  for (final b in banners.reversed) {
    final primary = b is Map<String, dynamic> ? b['primary'] : null;
    if (primary is Map<String, dynamic> && primary['type'] == type) {
      return (primary['degrees'] as num?)?.toInt();
    }
  }
  return null;
}

/// The exit of a roundabout from the headings around it, when the router
/// gave no banner: the heading into the ring, and the heading on the road
/// out, which only the step leaving the ring knows ([exitsHere]).
int? _exitDegrees({
  required Object? headingIn,
  required Object? headingOut,
  required bool leftHandTraffic,
  required bool exitsHere,
}) => headingIn is num && headingOut is num && exitsHere
    ? roundaboutExitDegrees(
        headingIn: headingIn,
        headingOut: headingOut,
        leftHandTraffic: leftHandTraffic,
      )
    : null;

/// The lanes the vehicle sees as it nears the maneuver that ends [step]:
/// those of the intersection where [next] starts, else those of the last
/// intersection of [step] that has some within [_lanesReachM] of the
/// maneuver (Valhalla puts lanes on the intersections, not in a
/// sub-banner, and splits one junction into nodes a few metres apart).
List<LaneHint> _lanesBefore(Map<String, dynamic> step, Map<String, dynamic>? next) {
  List<LaneHint>? lanesOf(Object? intersection) {
    if (intersection is! Map<String, dynamic>) return null;
    final lanes = intersection['lanes'];
    if (lanes is! List || lanes.isEmpty) return null;
    return [
      for (final l in lanes)
        if (l is Map<String, dynamic>)
          LaneHint(
            directions: [for (final d in (l['indications'] as List? ?? const [])) '$d'],
            active: l['valid'] == true,
            follows: l['valid_indication'] as String?,
          ),
    ];
  }

  final nextIntersections = next?['intersections'];
  if (nextIntersections is List && nextIntersections.isNotEmpty) {
    final atManeuver = lanesOf(nextIntersections.first);
    if (atManeuver != null) return atManeuver;
  }
  final maneuver = _location(next?['maneuver']);
  final own = step['intersections'];
  if (maneuver == null || own is! List) return const [];
  for (final i in own.reversed) {
    final lanes = lanesOf(i);
    final at = _location(i is Map<String, dynamic> ? i : null);
    if (lanes != null && at != null && at.distanceTo(maneuver) <= _lanesReachM) return lanes;
  }
  return const [];
}

/// How far before a maneuver the lanes of a junction are still those of
/// the maneuver. Further back they belong to another junction, and under
/// the next turn's arrow they read as a contradiction: on Avenue des
/// Bénédictins, a junction 160 m before a slight left showed its left lane
/// faint, the lane of a street the route does not take.
const _lanesReachM = 60.0;

LatLng? _location(Object? node) {
  if (node is! Map<String, dynamic>) return null;
  final l = node['location'];
  return l is List && l.length >= 2
      ? LatLng((l[1] as num).toDouble(), (l[0] as num).toDouble())
      : null;
}

/// Encodes [points] as a polyline with [precision] decimals, the inverse of
/// [decodePolyline]. Arithmetic rather than bit operators, as there.
String encodePolyline(List<LatLng> points, {int precision = 6}) {
  final factor = _pow10(precision);
  final out = StringBuffer();
  void put(int value) {
    var v = value < 0 ? -value * 2 - 1 : value * 2;
    while (v >= 32) {
      out.writeCharCode((v % 32 + 32) + 63);
      v ~/= 32;
    }
    out.writeCharCode(v + 63);
  }

  var lat = 0;
  var lon = 0;
  for (final p in points) {
    final nextLat = (p.lat * factor).round();
    final nextLon = (p.lon * factor).round();
    put(nextLat - lat);
    put(nextLon - lon);
    lat = nextLat;
    lon = nextLon;
  }
  return out.toString();
}

/// [line] without the points that stray less than [toleranceM] metres from
/// the line through their neighbours (Douglas-Peucker), the ends kept.
List<LatLng> simplifyLine(List<LatLng> line, {required double toleranceM}) {
  if (line.length < 3) return line;
  final keep = List<bool>.filled(line.length, false)
    ..[0] = true
    ..[line.length - 1] = true;
  final stack = <(int, int)>[(0, line.length - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    var worst = 0.0;
    var index = -1;
    final chord = [line[first], line[last]];
    for (var i = first + 1; i < last; i++) {
      final off = _offChord(line[i], chord);
      if (off > worst) {
        worst = off;
        index = i;
      }
    }
    if (index >= 0 && worst > toleranceM) {
      keep[index] = true;
      stack
        ..add((first, index))
        ..add((index, last));
    }
  }
  return [
    for (var i = 0; i < line.length; i++)
      if (keep[i]) line[i],
  ];
}

/// Metres from [p] to the segment [chord], on a plane tangent at [p].
double _offChord(LatLng p, List<LatLng> chord) {
  const metresPerDegree = 111195.0;
  final cosLat = math.cos(p.lat * math.pi / 180);
  final ax = (chord[0].lon - p.lon) * metresPerDegree * cosLat;
  final ay = (chord[0].lat - p.lat) * metresPerDegree;
  final bx = (chord[1].lon - p.lon) * metresPerDegree * cosLat;
  final by = (chord[1].lat - p.lat) * metresPerDegree;
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
  final x = ax + t * dx;
  final y = ay + t * dy;
  return math.sqrt(x * x + y * y);
}
