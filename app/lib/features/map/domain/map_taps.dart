import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';

/// How far from a tap the maps look for something to open, in logical
/// pixels each way, and what a tap on bare map does.
///
/// Kept apart from the engines so that one rule serves the phone, the web
/// and the desktop maps, and so that a shared hit resolution can replace it
/// in one place.
abstract final class FreeTap {
  /// Before a tap on bare map opens the card of a free point, the map looks
  /// this many times further than the tolerance of a selection
  /// (`hitTolerance`) for a pin, a cluster or a marker: a tap that just
  /// missed one opens it rather than the free point.
  static const double wider = 1.5;

  /// From this zoom (street level) a tap on bare map opens the card of the
  /// point. Further out a tap there is no place in particular, and the map
  /// keeps its own behaviour: a click must not open anything.
  static const double freePointMinZoom = 14;

  /// A second tap within this time makes a double tap, which zooms: the
  /// first one then opens nothing. The browsers report both clicks before
  /// the double click.
  static const Duration doubleTapWindow = Duration(milliseconds: 250);

  /// MapLibre GL JS on a touch screen counts a second tap starting within
  /// 500 ms as a double tap and keeps it for its zoom, which starts when that
  /// tap ends: the app hears the first tap alone. The engine waits this long
  /// after a bare tap (a second tap held 150 ms included) and drops it when
  /// the camera zoomed meanwhile ([touchTapStands]).
  static const Duration touchDoubleTapWait = Duration(milliseconds: 650);

  /// A camera that moved more than this many pixels during that wait was
  /// panned: the tap was the start of a drag.
  static const double dragSlop = 8;

  /// The wait of [DoubleTapGate] for [pointer] on an engine. MapLibre
  /// Native on Android and iOS reports a tap only once it knows no second
  /// one follows; MapLibre GL JS on a touch screen has its own wait
  /// ([touchDoubleTapWait]): the screen adds none there. With a mouse, the
  /// browsers and the desktop page report both clicks of a double click.
  static Duration doubleTapWindowFor({
    required bool web,
    required TargetPlatform platform,
    required PointerKind pointer,
  }) {
    if (!web && (platform == TargetPlatform.android || platform == TargetPlatform.iOS)) {
      return Duration.zero;
    }
    return web && pointer == PointerKind.touch ? Duration.zero : doubleTapWindow;
  }
}

/// Waits [wait] after a bare tap on a touch screen in the browser, then
/// tells whether it still stands: no other tap or press came meanwhile
/// ([superseded]), and the camera, read again ([camera]), neither zoomed
/// (the engine kept a second tap for its zoom) nor moved more than
/// [FreeTap.dragSlop] pixels from [center] (a pan begun at once). A camera
/// the engine cannot read counts as still.
Future<bool> touchTapStands({
  required Future<({LatLng center, double zoom})?> Function() camera,
  required LatLng center,
  required double zoom,
  required bool Function() superseded,
  Duration wait = FreeTap.touchDoubleTapWait,
}) async {
  await Future<void>.delayed(wait);
  if (superseded()) return false;
  ({LatLng center, double zoom})? now;
  try {
    now = await camera();
  } on Object {
    now = null;
  }
  if (superseded()) return false;
  if (now == null) return true;
  if ((now.zoom - zoom).abs() > 0.01) return false;
  final shift = screenOf(now.center, reference: center, referenceAt: Offset.zero, zoom: zoom);
  return shift.distance <= FreeTap.dragSlop;
}

/// What a tap at [zoom] reaches: what [pick] finds within the selection's
/// [tolerance], else, from [FreeTap.freePointMinZoom] where a bare tap opens
/// a point, what it finds within [FreeTap.wider] times that. Further out the
/// map keeps the selection's tolerance alone, so a click there does no more
/// than it did. [pick] is the shared hit resolution (`nearestHit`) at a
/// given tolerance.
T? hitAroundTap<T extends Object>(
  T? Function(double tolerance) pick, {
  required double tolerance,
  required double? zoom,
}) {
  final near = pick(tolerance);
  if (near != null || zoom == null || zoom < FreeTap.freePointMinZoom) return near;
  return pick(tolerance * FreeTap.wider);
}

/// What a tap on bare map does.
enum BareTap {
  /// Closes what is open (a place's card, a free point), as in every map
  /// app.
  close,

  /// Opens the card of the point tapped.
  freePoint,

  /// Nothing: the map is too far out for a point to mean anything.
  nothing,
}

/// The outcome of a tap on bare map at [zoom], with something already open
/// or not. A tap elsewhere closes the open card first; the next one opens a
/// point, so a tap never swaps one card for another by surprise.
BareTap bareTapAt({required double zoom, required bool open}) {
  if (open) return BareTap.close;
  return zoom >= FreeTap.freePointMinZoom ? BareTap.freePoint : BareTap.nothing;
}

/// Waits [window] after a tap on bare map before acting on it: a second tap
/// in that time is the end of a double tap (the map zooms) and cancels
/// both.
final class DoubleTapGate {
  new({this.window = FreeTap.doubleTapWindow});

  final Duration window;
  Timer? _pending;

  /// Whether a tap waits for the end of its window.
  @visibleForTesting
  bool get waiting => _pending?.isActive ?? false;

  /// A tap on bare map: [act] runs once the window (this gate's, or
  /// [window] for this tap) has passed without a second tap.
  void tap(VoidCallback act, {Duration? window}) {
    final wait = window ?? this.window;
    if (wait == Duration.zero) return act();
    if (waiting) {
      cancel();
      return;
    }
    _pending = Timer(wait, () {
      _pending = null;
      act();
    });
  }

  /// Drops the tap that waits: a pin was tapped, the map was dragged or
  /// left.
  void cancel() {
    _pending?.cancel();
    _pending = null;
  }
}
