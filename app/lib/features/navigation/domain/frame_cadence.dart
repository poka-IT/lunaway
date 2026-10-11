import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/painting.dart' show EdgeInsets;

/// How often the guidance map draws, from how fast what it shows moves on
/// the screen. Each frame of the map costs the phone a full render of the
/// basemap; down a motorway seen wide the picture moves a pixel or two
/// between two frames drawn 30 times a second or more. Measured on an
/// emulator, Google Maps draws 10 to 12 frames a second while it guides
/// (`plan/research/117-voix-energie-android.md`).
///
/// The cadence aims at [stepPx] of motion a frame, between [minFps] and
/// [maxFps]: low down a motorway seen wide, full through a town's turns,
/// a roundabout, a turn of the map, a change of zoom or of tilt (the
/// approach of a maneuver brings both). Under a finger, while the map
/// eases back into following, and during an animation of the camera, the
/// cadence is full; it then comes down over a second ([releasePerS]).
///
/// The map engine keeps drawing between two moves of the camera while its
/// labels fade: measured on an emulator, MapLibre Native drew a frame every
/// 25 ms while the app moved the camera every 100 ms
/// (`plan/research/124-cadence-carte-guidage.md`). Sending fewer moves
/// draws no fewer frames. So the guidance's map places its labels without
/// fading them (`setMapLabelFades` on Android, and the pages' motion; iOS
/// keeps its fades, its display link alone holding the count), the cadence
/// is the engine's own limit of frames ([renderCap]), and the app keeps
/// sending the vehicle and the camera [sampleFps] times a second: a frame
/// shows the latest state, set by the clock (`VehicleMotion.at`, the eases
/// of the camera), never by the frame's number.
abstract final class FrameCadence {
  /// The motion a frame may show, logical pixels: the vehicle and the road
  /// glide in steps the eye reads as one motion.
  static const double stepPx = 1.5;

  /// The fewest frames a second while anything moves: a moving vehicle is
  /// never drawn in steps a tenth of a second apart or more.
  static const double minFps = 10;

  /// The full cadence. Its frames are not limited: the engine draws as it
  /// did before the cadence existed.
  static const double maxFps = 30;

  /// How often the app sends the vehicle and the camera while they move:
  /// the map takes each over a platform channel, and 30 a second keep the
  /// calls from queueing.
  static const double sampleFps = 30;

  /// How fast the cadence comes back down, frames a second per second:
  /// from the full cadence to the lowest in one second, so a cadence that
  /// falls is not seen as a change of motion.
  static const double releasePerS = 20;

  /// MapLibre's vertical field of view, degrees (Native and GL JS).
  static const double fovDeg = 36.87;

  /// The far edge of a tilted view is taken no further than this from
  /// straight down, degrees: past it the ground is under the horizon's haze.
  static const double farDeg = 85;
}

/// Metres a logical pixel covers at [zoom] (MapLibre's, tiles of 512) and
/// [latitude], across the view at the camera's centre.
double metresPerPixel(double zoom, double latitude) =>
    40075016.686 * math.cos(latitude * math.pi / 180) / (512 * math.pow(2, zoom));

/// How fast the guidance map's picture moves, logical pixels a second, at
/// the point of the view where it moves fastest: the map of [size], the
/// panels over [covered] (the banner, the bar), following the vehicle drawn
/// at [anchor], at [zoom], [tilt] (degrees from straight down) and
/// [latitude]; the vehicle drives [groundMps] over the ground; the camera
/// turns [turnDegPerS], zooms [zoomPerS] levels a second and tilts
/// [tiltDegPerS]. Not [following], the camera stands and only the vehicle
/// moves across it.
///
/// Two points are measured, each with every motion that moves it (its parts
/// across and along the screen added up with the same sign: a bound rather
/// than an average), and the faster one counts:
/// - a corner of the view under the vehicle, where the road slides by at
///   [groundMps] over [metresPerPixel] (tilted, the near road moves no
///   faster than under the vehicle) and which a turn or a zoom moves by
///   its distance from the vehicle;
/// - a corner of the top of the view, far down the road on a tilted map: a
///   turn sweeps it sideways across the far ground (a pinhole camera of
///   MapLibre's, the vehicle at its centre), a zoom moves it by its
///   distance from the vehicle, a tilt by the focal length times
///   1 + (its height over the vehicle / the focal length)², and the road
///   slides there in proportion to how much smaller the far ground is
///   drawn.
double screenSpeed({
  required Size size,
  required EdgeInsets covered,
  required Offset anchor,
  required double latitude,
  required double zoom,
  required double tilt,
  double groundMps = 0,
  double turnDegPerS = 0,
  double zoomPerS = 0,
  double tiltDegPerS = 0,
  bool following = true,
}) {
  final slide = groundMps.abs() / metresPerPixel(zoom, latitude);
  if (!following) return slide;
  const toRad = math.pi / 180;
  final turn = turnDegPerS.abs() * toRad;
  final scale = zoomPerS.abs() * math.ln2;
  final pitchRate = tiltDegPerS.abs() * toRad;
  final focal = size.height / 2 / math.tan(FrameCadence.fovDeg / 2 * toRad);
  final side = math.max(anchor.dx - covered.left, size.width - covered.right - anchor.dx);
  final above = math.max<double>(0, anchor.dy - covered.top);
  final below = math.max<double>(0, size.height - covered.bottom - anchor.dy);
  double tilting(double dy) => pitchRate * focal * (1 + (dy / focal) * (dy / focal));

  // Across and along the screen, each motion's part added up with the same
  // sign (a bound), the two then taken together.
  final under = math.sqrt(
    math.pow(turn * below + scale * side, 2) +
        math.pow(turn * side + scale * below + tilting(below) + slide, 2),
  );

  // The far ground, in heights of the camera over the vehicle's: the
  // vehicle seen at the pitch, the top of the view `up` above it.
  final pitch = tilt.clamp(0, FrameCadence.farDeg) * toRad;
  final up = math.atan(above / focal);
  final far = math.min(pitch + up, FrameCadence.farDeg * toRad);
  final depthVehicle = 1 / math.cos(pitch);
  final depthFar = math.cos(up) / math.cos(far);
  final sweep = focal * (math.tan(far) - math.tan(pitch)) / depthFar;
  final top = math.sqrt(
    math.pow(turn * sweep + scale * side, 2) +
        math.pow(turn * side + scale * above + tilting(above) + slide * depthVehicle / depthFar, 2),
  );
  return math.max(under, top);
}

/// The frames a second that show [pxPerS] of motion in steps of
/// [FrameCadence.stepPx], within [FrameCadence.minFps] and
/// [FrameCadence.maxFps].
double cadenceFor(double pxPerS) {
  if (pxPerS.isNaN) return FrameCadence.maxFps;
  return (pxPerS / FrameCadence.stepPx).clamp(FrameCadence.minFps, FrameCadence.maxFps);
}

/// The engine's limit of frames for a cadence of [fps]; null when it draws
/// freely. The app sends [FrameCadence.sampleFps] states a second: a limit
/// that draws about a whole number of them per frame (3 at 10, 2 at 15)
/// keeps the steps of the motion close to even, where a limit close under
/// the samples' rate would show one sample in a frame and two in the next.
/// On Android the limit is a sleep after each render
/// (`MapRenderer.onDrawFrame`), not set on the app's timer: a frame may
/// take one sample more or less now and then. Above 15 the engine draws
/// freely, as it did before the cadence.
int? renderCap(double fps) {
  if (fps <= 10.5) return 10;
  if (fps <= 15) return 15;
  return null;
}

/// The cadence of the map's frames over time: up at once when the picture
/// moves faster, a gesture or an animation begins; down by
/// [FrameCadence.releasePerS] when it slows, so the eye does not see the
/// steps lengthen.
final class FramePace {
  double _fps = FrameCadence.maxFps;
  Duration? _at;

  /// The cadence now, frames a second; the full one until the motion is
  /// known.
  double get fps => _fps;

  /// The cadence wanted at [now] for [pxPerS] of motion, or the full one
  /// when [full] (a finger on the map, the way into following, an
  /// animation): taken at once if higher, approached at
  /// [FrameCadence.releasePerS] if lower.
  double next(Duration now, {required double pxPerS, bool full = false}) {
    final wanted = full ? FrameCadence.maxFps : cadenceFor(pxPerS);
    final at = _at;
    _at = now;
    if (at == null || wanted >= _fps) {
      _fps = wanted;
    } else {
      final down = FrameCadence.releasePerS * (now - at).inMicroseconds / 1e6;
      _fps = math.max(wanted, _fps - down);
    }
    return _fps;
  }
}
