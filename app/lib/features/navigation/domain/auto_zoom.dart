import 'dart:math' as math;

/// The guidance camera's framing while it follows the vehicle, as the big
/// navigation apps frame the road: the next maneuver in view, the camera
/// closing in as it comes and easing back out past it; never wider than the
/// speed allows (a long straight shows more road the faster the vehicle
/// goes), never closer than it allows (a motorway exit is not seen at a
/// street's scale). Tilted toward the horizon down a straight, flatter over
/// a junction so it reads from above.
///
/// Measured on Google Maps on 2026-10-11
/// (`plan/research/120-guidage-facon-gmaps.md`): its zoom
/// follows the distance to the next maneuver far more than the speed (the
/// same 1.3 m a pixel on a motorway straight at 30 and at 130 km/h, the
/// maneuver 4 km off, MapLibre zoom 14.5); tilted about 52° cruising, 63°
/// down long straights, 21 to 26° as a junction comes (from about 300 m
/// in town, 150 m before a roundabout of a main road); no closer before a
/// motorway fork at 90 km/h.
///
/// Zooms are MapLibre's (tiles of 512 pixels). At 45° of latitude a level
/// halves or doubles the metres a pixel covers: 0.42 m at 17, 0.84 m at 16,
/// 1.7 m at 15. With the camera tilted as it follows and the vehicle low on
/// a phone's map, about 420 m of road lie ahead at 17.
abstract final class AutoZoom {
  /// The widest the camera goes at a speed, km/h to zoom, interpolated
  /// between: down a long straight a street at 30 km/h shows its next few
  /// hundred metres, a motorway at 130 about four kilometres.
  static const List<(double, double)> wide = [
    (0, 16.2),
    (30, 16.0),
    (50, 15.6),
    (70, 15.2),
    (90, 14.9),
    (110, 14.6),
    (130, 14.4),
  ];

  /// The closest the camera comes before a maneuver at a speed: a street
  /// corner at 17.4 (Google Maps 17.0 to 17.4 within 150 m of one), a
  /// motorway exit at 16.2.
  static const List<(double, double)> close = [(0, 17.4), (50, 17.2), (90, 16.6), (130, 16.2)];

  /// A fork, a ramp or a merge taken this fast is read from far: the camera
  /// neither closes in nor flattens for it, km/h.
  static const splitAtSpeedKmh = 70.0;

  /// The zoom of a vehicle with nothing ahead to frame: off the route, or
  /// before the first position.
  static const parkedZoom = 17.0;

  /// The road ahead in view at zoom 17, metres, the reference of [seeZoom].
  static const aheadAt17M = 420.0;

  /// Where a maneuver stands in the road ahead in view while the camera
  /// closes in on it: a little past the middle, its exits in sight.
  static const maneuverShare = 0.55;

  /// The speed the framing reads changes only once the vehicle's moves this
  /// far from it, km/h: a GPS speed wavers by a few km/h at a steady pace,
  /// and the view must not breathe with it.
  static const speedHysteresisKmh = 6.0;

  /// The zooms the camera never leaves while following.
  static const minZoom = 13.5;
  static const maxZoom = 18.0;
}

/// How the follow camera tilts, degrees from straight down.
abstract final class AutoTilt {
  /// Cruising.
  static const cruise = 52.0;

  /// Down a long straight, shown at its widest: the road toward the
  /// horizon. MapLibre draws up to 60.
  static const straight = 60.0;

  /// Over a roundabout, and over another junction, close to it: flatter,
  /// so its branches read from above.
  static const roundabout = 26.0;
  static const junction = 30.0;

  /// The camera starts flattening this far from the junction, metres, and
  /// is flat enough within [flatM].
  static const flattenFromM = 300.0;
  static const flatM = 120.0;
}

/// The zoom and the tilt the follow camera eases to.
typedef CameraAim = ({double zoom, double tilt});

/// The aim of a vehicle with nothing to frame.
const CameraAim restingAim = (zoom: AutoZoom.parkedZoom, tilt: AutoTilt.cruise);

/// The widest the camera goes at [speedKmh] ([AutoZoom.wide]).
double wideZoom(double speedKmh) => _along(AutoZoom.wide, speedKmh);

/// The closest the camera comes at [speedKmh] ([AutoZoom.close]).
double closeZoom(double speedKmh) => _along(AutoZoom.close, speedKmh);

/// The zoom at which a point [distanceM] ahead stands at
/// [AutoZoom.maneuverShare] of the road in view.
double seeZoom(double distanceM) {
  final d = math.max(1, distanceM);
  return 17 + math.log(AutoZoom.aheadAt17M * AutoZoom.maneuverShare / d) / math.ln2;
}

/// Whether the maneuver of OSRM [type] and [modifier] is one the camera
/// frames: a turn, a roundabout, a fork, a ramp, the arrival. A road that
/// only changes its name, or goes straight on, is not.
bool maneuverDrawsZoom(String? type, String? modifier) => switch (type) {
  'end of road' || 'fork' || 'off ramp' || 'on ramp' || 'merge' => true,
  'roundabout' || 'rotary' || 'roundabout turn' || 'exit roundabout' || 'exit rotary' => true,
  'arrive' => true,
  'turn' || 'continue' => modifier != null && modifier != 'straight',
  _ => false,
};

bool _roundabout(String? type) => switch (type) {
  'roundabout' || 'rotary' || 'roundabout turn' || 'exit roundabout' || 'exit rotary' => true,
  _ => false,
};

/// The zoom and the tilt the follow camera aims at, at [speedKmh] (the
/// speed held, [SpeedHold]), the next maneuver [distanceToManeuverM] ahead.
/// A maneuver the camera does not frame ([maneuverDrawsZoom]) counts as far
/// as the one after it, [afterM] further. The next maneuver framed, within
/// what the speed allows ([wideZoom], [closeZoom]): continuous in the
/// distance, so the view never jumps as the vehicle nears a turn; past it,
/// the next one takes over and the engines ease back out.
CameraAim autoAim({
  required double speedKmh,
  required double? distanceToManeuverM,
  String? maneuverType,
  String? modifier,
  double? afterM,
}) {
  final wide = wideZoom(speedKmh);
  final close = math.max(wide, closeZoom(speedKmh));
  final d = distanceToManeuverM;
  if (d == null || !d.isFinite) {
    return (
      zoom: ((wide + close) / 2).clamp(AutoZoom.minZoom, AutoZoom.maxZoom),
      tilt: AutoTilt.cruise,
    );
  }
  final split = switch (maneuverType) {
    'fork' || 'off ramp' || 'on ramp' || 'merge' => true,
    _ => false,
  };
  final framed =
      maneuverDrawsZoom(maneuverType, modifier) && !(split && speedKmh >= AutoZoom.splitAtSpeedKmh);
  final ahead = framed ? d : d + (afterM ?? double.infinity);
  final zoom = seeZoom(ahead).clamp(wide, close).clamp(AutoZoom.minZoom, AutoZoom.maxZoom);
  // Toward the horizon as the view reaches its widest, half a level in.
  var tilt =
      AutoTilt.cruise +
      (AutoTilt.straight - AutoTilt.cruise) * ((wide + 0.5 - zoom) / 0.5).clamp(0.0, 1.0);
  if (framed && maneuverType != 'arrive') {
    final flat = _roundabout(maneuverType) ? AutoTilt.roundabout : AutoTilt.junction;
    final k = ((AutoTilt.flattenFromM - d) / (AutoTilt.flattenFromM - AutoTilt.flatM)).clamp(
      0.0,
      1.0,
    );
    tilt += (flat - tilt) * k;
  }
  return (zoom: zoom, tilt: tilt);
}

/// The speed the framing reads, held while the vehicle's stays within
/// [AutoZoom.speedHysteresisKmh] of it.
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
