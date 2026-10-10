import 'package:lunaway/core/geo/geo.dart';

/// The cells of a grid of [cellDeg] degrees that a route passes through,
/// widened by two cells all round: where a road event may lie for the
/// engine to find it on the route.
///
/// The guidance hands the engine the road events of a whole country or
/// more (some 6 000 in Europe in October 2026), and the engine measures
/// each against every point of the route: 60 to 120 ms on the thread that
/// draws the app, at the start and every 10 s while driving
/// (`plan/research/112-perf-android.md`). The events far from the route
/// are left out here, at the cost of a few grid lookups each.
///
/// Why it never leaves out an event the engine would find: the engine
/// finds an event within 15 m of the route (`eventPointToleranceM`, the
/// larger tolerance), under 0.001 degree of longitude below 82 degrees of
/// latitude. The route and the events are sampled at most [_stepDeg]
/// apart on each axis. A sample of an event that comes that close lies
/// within half a step of the close point, which lies within 0.001 degree
/// of a point of the route, itself within half a step of a sample of the
/// route: 0.005 degree on each axis, half a cell. One cell around the
/// route's would do; two are kept.
final class RouteCorridor {
  RouteCorridor._(this._cells);

  /// The corridor of [line].
  factory RouteCorridor.of(List<LatLng> line) {
    final marked = <int>{};
    void mark(LatLng p) => marked.add(_key(_cell(p.lat), _cell(p.lon)));
    if (line.isNotEmpty) mark(line.first);
    for (var i = 1; i < line.length; i++) {
      _walk(line[i - 1], line[i], mark);
    }
    final cells = <int>{};
    for (final key in marked) {
      final (y, x) = _unkey(key);
      for (var dy = -_widen; dy <= _widen; dy++) {
        for (var dx = -_widen; dx <= _widen; dx++) {
          cells.add(_key(y + dy, x + dx));
        }
      }
    }
    return RouteCorridor._(cells);
  }

  static const cellDeg = 0.01;
  static const _stepDeg = 0.004;
  static const _widen = 2;

  final Set<int> _cells;

  /// Whether a road event of [points] (a line, or one point) may lie on
  /// the route.
  bool reaches(List<LatLng> points) {
    if (points.isEmpty) return false;
    var hit = false;
    void test(LatLng p) {
      if (!hit && _cells.contains(_key(_cell(p.lat), _cell(p.lon)))) hit = true;
    }

    test(points.first);
    for (var i = 1; i < points.length && !hit; i++) {
      _walk(points[i - 1], points[i], test);
    }
    return hit;
  }

  /// Calls [visit] at [b] and at points every [_stepDeg] or less from [a]
  /// to it.
  static void _walk(LatLng a, LatLng b, void Function(LatLng) visit) {
    final dLat = b.lat - a.lat;
    final dLon = b.lon - a.lon;
    final span = dLat.abs() > dLon.abs() ? dLat.abs() : dLon.abs();
    final steps = (span / _stepDeg).ceil();
    for (var k = 1; k < steps; k++) {
      final t = k / steps;
      visit(LatLng(a.lat + dLat * t, a.lon + dLon * t));
    }
    visit(b);
  }

  static int _cell(double deg) => (deg / cellDeg).floor();

  // A row and a column in one integer: rows from -9 000 to 9 000 and
  // columns from -18 000 to 18 000 fit with room to spare.
  static int _key(int y, int x) => (y + 20000) * 100000 + (x + 50000);

  static (int, int) _unkey(int key) => (key ~/ 100000 - 20000, key % 100000 - 50000);
}
