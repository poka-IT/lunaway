import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';

/// How far the guidance camera tilts, degrees from straight down: the road
/// ahead reads as a driver sees it, and MapLibre still draws the horizon
/// sharp (its limit is 60).
const followTiltDeg = 55.0;

/// The zoom of the guidance camera for a speed: close in town, where the
/// next turn is near; further out on a fast road, where it is far.
double followZoom(double? speedMps) {
  final kmh = (speedMps ?? 0) * 3.6;
  if (kmh <= 40) return 17;
  if (kmh >= 110) return 15.2;
  return 17 - (kmh - 40) / 70 * 1.8;
}

/// The angle from [a] to [b] the short way round, degrees in (-180, 180].
double angleDelta(double a, double b) {
  final d = (b - a) % 360;
  return d > 180 ? d - 360 : d;
}

/// Where the vehicle is drawn between two fixes. A fix comes about once a
/// second; drawn as it comes, the arrow and the map would jump a car length
/// at each. Instead the drawn vehicle glides from where it was drawn to the
/// new fix over the time the last fix took to come, so it reaches each
/// fix as the next one arrives, and turns the short way round.
final class VehicleMotion {
  LatLng? _from;
  double? _fromCourse;
  LatLng? _to;
  double? _toCourse;
  Duration _start = Duration.zero;
  Duration _length = Duration.zero;
  Duration? _lastTarget;

  /// The glide never takes longer than this: a fix that comes late (a
  /// tunnel) is not reached at a crawl.
  static const maxGlide = Duration(milliseconds: 1500);

  /// The fix the vehicle glides to.
  LatLng? get target => _to;

  /// Whether the drawn vehicle is still on its way to [target] at [now].
  bool movingAt(Duration now) => _to != null && now - _start < _length;

  /// A new fix at [now], the time of the frame clock. The first fix is
  /// drawn where it is; a [jump] (a new route, the vehicle far away)
  /// too.
  void retarget(LatLng position, double? course, Duration now, {bool jump = false}) {
    // The same fix again (a map rebuilt for another reason) changes
    // nothing: restarting would cut the glide short and lurch.
    if (!jump && position == _to && (course ?? _toCourse) == _toCourse) return;
    final (shown, shownCourse) = at(now);
    final last = _lastTarget;
    _lastTarget = now;
    if (shown == null || jump) {
      _from = _to = position;
      _fromCourse = _toCourse = course;
      _start = now;
      _length = Duration.zero;
      return;
    }
    _from = shown;
    _fromCourse = shownCourse;
    _to = position;
    _toCourse = course ?? shownCourse;
    _start = now;
    final gap = last == null ? const Duration(seconds: 1) : now - last;
    _length = gap > maxGlide ? maxGlide : gap;
  }

  /// The drawn position and course at [now]; nulls before the first fix.
  (LatLng?, double?) at(Duration now) {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return (null, null);
    final t = _length <= Duration.zero
        ? 1.0
        : ((now - _start).inMicroseconds / _length.inMicroseconds).clamp(0.0, 1.0);
    final position = LatLng(from.lat + (to.lat - from.lat) * t, from.lon + (to.lon - from.lon) * t);
    final a = _fromCourse;
    final b = _toCourse;
    final course = a == null || b == null ? (b ?? a) : (a + angleDelta(a, b) * t) % 360;
    return (position, course);
  }
}

/// The zoom moving toward the one the speed asks for, a little each frame:
/// the view widens as the vehicle speeds up without a visible step.
double easeZoom(double shown, double wanted, Duration frame) {
  const settle = Duration(seconds: 2);
  final k = math.min(1, frame.inMicroseconds / settle.inMicroseconds);
  return shown + (wanted - shown) * k;
}
