import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:lunaway/core/geo/geo.dart';

/// How the guidance map behaves once the user moves it: free to pan, zoom,
/// turn and tilt, and back behind the vehicle on "Recentrer", when the user
/// brings the view back near it, or after a while without a touch.
abstract final class FreeMap {
  /// The magnet's reach: the vehicle within this share of the map's shorter
  /// side from where following puts it. 15 % of a phone's 400 px is 60 px,
  /// about a fingertip and a half: near enough that the user plainly
  /// brought the view back, far enough not to need a precise drop.
  static const magnetShare = 0.15;

  /// The magnet's zoom: within one level of the following camera's.
  static const magnetZoomLevels = 1.0;

  /// A view turned or tilted further than this from the driver's was
  /// turned or tilted on purpose: the magnet leaves it, or a two-finger
  /// turn around the vehicle would be undone the moment the fingers lift.
  static const magnetBearingDeg = 20.0;
  static const magnetTiltDeg = 15.0;

  /// Back to following after this long without a touch on the map while
  /// driving. Long enough to look at a junction ahead or read the pins of
  /// a town (a glance takes one to two seconds, choosing among a few pins
  /// five to ten); short enough that a map moved by a slip of the hand
  /// comes back before the next turn: 12 s are 170 m at 50 km/h and 300 m
  /// at 90 km/h, the distance at which the voice announces a turn.
  static const idleReturn = Duration(seconds: 12);

  /// Faster than this the vehicle drives: parked, the user may look around
  /// the map as long as they like.
  static const drivingMps = 2.8;

  /// How long the magnet's return takes: short, the view is already close.
  static const snapEase = Duration(milliseconds: 450);

  /// How long "Recentrer" and the return after a while take, from wherever
  /// the view was.
  static const recenterEase = Duration(milliseconds: 900);

  /// Where following puts the vehicle down the free part of the map: the
  /// centre of the camera sits this far down it, so the road ahead shows.
  static const followLift = 0.45;
}

/// The content insets of the following camera on a map of [size] with
/// panels over [padding]: the camera's centre, where the vehicle is drawn,
/// low in the free part of the map (under the banner, above the bar).
EdgeInsets followInsets(Size size, EdgeInsets padding) {
  final free = math.max<double>(0, size.height - padding.top - padding.bottom);
  return EdgeInsets.fromLTRB(
    padding.left,
    padding.top + free * FreeMap.followLift,
    padding.right,
    padding.bottom,
  );
}

/// Where following draws the vehicle on a map of [size]: the centre of
/// what [followInsets] leave.
Offset followAnchor(Size size, EdgeInsets padding) {
  final insets = followInsets(size, padding);
  return Offset(
    insets.left + math.max<double>(0, size.width - insets.horizontal) / 2,
    insets.top + math.max<double>(0, size.height - insets.vertical) / 2,
  );
}

/// The camera of a map the user moved, once it rests: what the magnet
/// compares with the driver's view.
final class FreeView {
  const new({
    required this.size,
    required this.vehicle,
    required this.zoom,
    required this.bearing,
    required this.tilt,
    this.center,
  });

  /// The map's size, logical pixels.
  final Size size;

  /// Where the camera looks; a map made again in the other layout (the
  /// phone turned) opens there.
  final LatLng? center;

  /// Where the vehicle is drawn, logical pixels from the map's top left;
  /// null when it is not known (no fix yet).
  final Offset? vehicle;
  final double zoom;
  final double bearing;
  final double tilt;
}

/// Whether [view] is close enough to the driver's to snap back to it: the
/// vehicle near where following draws it, the zoom near following's, the
/// map neither turned nor tilted away on purpose.
bool magnetHolds(
  FreeView view, {
  required EdgeInsets padding,
  required double followZoom,
  required double? course,
  required double followTilt,
}) {
  final vehicle = view.vehicle;
  if (vehicle == null) return false;
  final reach = FreeMap.magnetShare * view.size.shortestSide;
  if ((vehicle - followAnchor(view.size, padding)).distance > reach) return false;
  if ((view.zoom - followZoom).abs() > FreeMap.magnetZoomLevels) return false;
  if ((view.tilt - followTilt).abs() > FreeMap.magnetTiltDeg) return false;
  if (course != null) {
    final turned = (((view.bearing - course) % 360) + 360) % 360;
    if (math.min(turned, 360 - turned) > FreeMap.magnetBearingDeg) return false;
  }
  return true;
}
