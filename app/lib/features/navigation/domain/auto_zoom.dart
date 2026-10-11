import 'dart:math' as math;

/// The guidance camera's zoom while it follows the vehicle, as a driver's
/// app frames the road: wider the faster the vehicle goes, closer as a turn
/// comes so the junction shows whole, wider again down a long straight.
///
/// Zooms are MapLibre's (tiles of 512 pixels). At 45° of latitude a level
/// halves or doubles the metres a pixel covers: 0.42 m at 17, 0.84 m at 16,
/// 1.7 m at 15. With the camera tilted as it follows and the vehicle in the
/// lower third of a phone's map, about 420 m of road lie ahead at 17.
abstract final class AutoZoom {
  /// The cruising zoom by speed, km/h to zoom, interpolated between: a
  /// street at 30 km/h shows its next junctions, a motorway at 130 shows
  /// about two kilometres.
  static const List<(double, double)> cruise = [
    (0, parkedZoom),
    (30, 17.1),
    (50, 16.6),
    (70, 16.0),
    (90, 15.5),
    (110, 15.1),
    (130, 14.8),
  ];

  /// The zoom of a vehicle standing still, or of one whose speed is not
  /// known yet.
  static const parkedZoom = 17.4;

  /// The road ahead in view at zoom 17, metres, the reference of [seeZoom].
  static const aheadAt17M = 420.0;

  /// Where a maneuver stands in the road ahead in view while the camera
  /// closes in on it: a little past the middle, its exits in sight.
  static const maneuverShare = 0.55;

  /// The closest the camera comes before a maneuver, by the speed: a
  /// street corner at 17.9, a motorway exit at 16.3, never more than
  /// [maxCloseIn] levels in from the cruising zoom.
  static const List<(double, double)> close = [(0, 17.9), (50, 17.6), (90, 16.8), (130, 16.3)];

  /// Levels in at most from the cruising zoom before a maneuver: in a
  /// town where turns come every 150 m the view breathes, it does not
  /// pump.
  static const maxCloseIn = 1.1;

  /// A straight longer than this many seconds at the speed, and
  /// [straightMinM] at least, widens the view by up to [straightWiden]
  /// levels, reached at twice that length.
  static const straightS = 120.0;
  static const straightMinM = 3000.0;
  static const straightWiden = 0.6;

  /// The speed the cruising zoom reads changes only once the vehicle's
  /// moves this far from it, km/h: a GPS speed wavers by a few km/h at a
  /// steady pace, and the view must not breathe with it.
  static const speedHysteresisKmh = 6.0;

  /// The zooms the camera never leaves while following.
  static const minZoom = 13.5;
  static const maxZoom = 18.0;
}

/// The cruising zoom for [speedMps] ([AutoZoom.cruise]); a vehicle with no
/// known speed is taken as parked.
double cruiseZoom(double? speedMps) => _along(AutoZoom.cruise, (speedMps ?? 0) * 3.6);

/// The zoom at which a point [distanceM] ahead stands at
/// [AutoZoom.maneuverShare] of the road in view.
double seeZoom(double distanceM) {
  final d = math.max(1, distanceM);
  return 17 + math.log(AutoZoom.aheadAt17M * AutoZoom.maneuverShare / d) / math.ln2;
}

/// Whether the maneuver of OSRM [type] and [modifier] is one the camera
/// closes in on: a turn, a roundabout, a fork, a ramp, the arrival. A road
/// that only changes its name, or goes straight on, is not.
bool maneuverDrawsZoom(String? type, String? modifier) => switch (type) {
  'turn' || 'end of road' || 'fork' || 'off ramp' || 'on ramp' || 'merge' => true,
  'roundabout' || 'rotary' || 'roundabout turn' || 'exit roundabout' || 'exit rotary' => true,
  'arrive' => true,
  'continue' => switch (modifier) {
    null || 'straight' => false,
    _ => true,
  },
  _ => false,
};

/// The zoom the following camera aims at: [cruiseKmh]'s cruising zoom,
/// closer as a maneuver that draws the eye ([maneuverDrawsZoom]) comes
/// within [distanceToManeuverM], wider when it is far down a straight.
/// Continuous in the distance, so the view never jumps as the vehicle
/// nears a turn; after the turn the next maneuver's distance takes over
/// and the camera eases back out (the engines ease toward this).
double autoZoom({
  required double cruiseKmh,
  required double? distanceToManeuverM,
  String? maneuverType,
  String? modifier,
}) {
  final base = _along(AutoZoom.cruise, cruiseKmh);
  final d = distanceToManeuverM;
  if (d == null || !d.isFinite) return base.clamp(AutoZoom.minZoom, AutoZoom.maxZoom);
  var zoom = base;
  if (maneuverDrawsZoom(maneuverType, modifier)) {
    final closest = math.min(_along(AutoZoom.close, cruiseKmh), base + AutoZoom.maxCloseIn);
    zoom = math.max(base, math.min(closest, seeZoom(d)));
  }
  // Down a long straight: the next maneuver far off, the view widens.
  final straight = math.max(AutoZoom.straightMinM, cruiseKmh / 3.6 * AutoZoom.straightS);
  if (d > straight) {
    final k = math.min(1, (d - straight) / straight);
    zoom -= AutoZoom.straightWiden * k;
  }
  return zoom.clamp(AutoZoom.minZoom, AutoZoom.maxZoom);
}

/// The speed the cruising zoom reads, held while the vehicle's stays
/// within [AutoZoom.speedHysteresisKmh] of it.
final class SpeedHold {
  double? _held;

  /// The speed held, km/h; 0 before any.
  double get kmh => _held ?? 0;

  /// A new speed, metres per second; an unknown one keeps the speed held.
  double update(double? speedMps) {
    if (speedMps == null || !speedMps.isFinite) return kmh;
    final now = math.max<double>(0, speedMps) * 3.6;
    final held = _held;
    if (held == null || (now - held).abs() >= AutoZoom.speedHysteresisKmh) _held = now;
    return kmh;
  }
}

/// [table]'s value at [x], linear between its points, held beyond its ends.
double _along(List<(double, double)> table, double x) {
  if (x <= table.first.$1) return table.first.$2;
  for (var i = 1; i < table.length; i++) {
    final (x1, y1) = table[i];
    if (x <= x1) {
      final (x0, y0) = table[i - 1];
      return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
  }
  return table.last.$2;
}
