import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  /// missed one opens it rather than the free point. Twice the tolerance:
  /// a finger aiming at a pin lands that far from it often enough, and a
  /// point dropped beside the pin is a slip (the PO's rule of 2026-10-10).
  static const double wider = 2;

  /// After the map moved under the user's hand (a drag, a fling, a pinch,
  /// the wheel, a double tap's zoom), a tap within this time opens no
  /// point ([MapTapGuard]): it was aimed at what moved, or it stopped a
  /// fling.
  static const Duration motionQuiet = Duration(milliseconds: 500);

  /// The longest a gesture that moved the map waits for the camera's rest
  /// before its motion counts as ended: the rest of a fling comes when the
  /// fling ends, about two seconds at most in MapLibre, and an engine that
  /// reports none must not hold the taps for ever.
  static const Duration restWait = Duration(seconds: 3);

  /// How far a mouse may move between press and release and still click:
  /// MapLibre GL JS's own `clickTolerance`, the engine that decides on a
  /// mouse in the browsers and the desktop page. A finger has Flutter's
  /// touch slop (`kTouchSlop`).
  static const double mouseSlop = 3;

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
  /// Takes the free point away: it was most likely dropped by mistake.
  close,

  /// Keeps what is open: on a phone its sheet goes down to its lowest, so
  /// the map shows more around it.
  keep,

  /// Opens the card of the point tapped.
  freePoint,

  /// Nothing: the map is too far out for a point to mean anything.
  nothing,
}

/// What the map screen shows when a tap lands on bare map.
enum OpenOnMap {
  /// Nothing: the list, or the bare map.
  nothing,

  /// The card "Here" of a point the map dropped (a tap or a press on bare
  /// map), with no address and no name of its own.
  freePoint,

  /// Anything else the user chose: a place, a shop, an address, a town, a
  /// point saved in the favourites.
  chosen,
}

/// The outcome of a tap on bare map at [zoom], with [open] showing. What
/// the user chose stays chosen: a tap a little off a pin is a slip, and
/// closing would lose the choice. A free point goes: it was dropped by the
/// map, often by a slip. With nothing open, from the street, the tap drops
/// a point.
BareTap bareTapAt({required double zoom, required OpenOnMap open}) => switch (open) {
  OpenOnMap.freePoint => BareTap.close,
  OpenOnMap.chosen => BareTap.keep,
  OpenOnMap.nothing => zoom >= FreeTap.freePointMinZoom ? BareTap.freePoint : BareTap.nothing,
};

/// Tells a tap the user meant on the map from a touch that only looks like
/// one, from the pointers the app's hit test gives the map and the rests
/// its camera reports. A tap stands when:
///
/// - one pointer went down and up, never further than the drag's tolerance
///   ([FreeTap.mouseSlop] with a mouse, `kTouchSlop` with a finger);
/// - it went down neither while the map still moved from a gesture (the
///   tap that stops a fling) nor within [FreeTap.motionQuiet] of the end of
///   one, or of any move of the camera (a double tap's zoom, a flight);
/// - no sheet moved over the map when it went down ([down]'s `sheetMoving`).
///
/// The engines report a tap after its release (Android and iOS once they
/// know it is no double tap, the browser a moment later): [stands] answers
/// for the last gesture that ended. Before the app has seen any, a tap
/// stands: an engine whose pointers the app does not see keeps its taps.
final class MapTapGuard {
  new({this.quiet = FreeTap.motionQuiet, this.restWait = FreeTap.restWait});

  final Duration quiet;
  final Duration restWait;

  /// The pointers down on the map, where each went down.
  final _down = <int, Offset>{};

  bool _moved = false;
  bool _many = false;
  bool _blocked = false;

  /// Whether the last gesture that ended was a tap that stands; null before
  /// any.
  bool? _last;

  /// A gesture moved the map and the camera's rest has not come.
  Timer? _awaitingRest;

  /// The camera came to rest a moment ago: a gesture ending now ended with
  /// it (the engine may report its rest before the app hears the release).
  Timer? _justRested;

  /// The time after a motion during which a press is no tap.
  Timer? _quiet;

  ({LatLng center, double zoom})? _camera;

  bool _active(Timer? t) => t?.isActive ?? false;

  /// Whether the map moves, or moved a moment ago.
  @visibleForTesting
  bool get inMotion => _active(_awaitingRest) || _active(_quiet);

  /// A pointer went down on the map; [sheetMoving]: a sheet over the map
  /// was moving then.
  void down(PointerDownEvent event, {bool sheetMoving = false}) {
    if (_down.isEmpty) {
      _moved = false;
      _many = false;
      _blocked = inMotion || sheetMoving;
    } else {
      _many = true;
    }
    _down[event.pointer] = event.position;
  }

  /// A pointer moved: past the drag's tolerance, the gesture is no tap.
  void move(PointerMoveEvent event) {
    final from = _down[event.pointer];
    if (from == null || _moved) return;
    final slop = event.kind == PointerDeviceKind.touch ? kTouchSlop : FreeTap.mouseSlop;
    if ((event.position - from).distance > slop) _moved = true;
  }

  /// A pointer came up, or was cancelled.
  void up(PointerEvent event) {
    if (_down.remove(event.pointer) == null || _down.isNotEmpty) return;
    final gesture = _moved || _many;
    _last = !gesture && !_blocked && event is! PointerCancelEvent;
    if (gesture) _moving();
  }

  /// The wheel turned, or a trackpad moved the map: the camera moves.
  void scrolled() => _moving();

  /// A gesture moved the map: until the camera rests, then for [quiet], a
  /// press is no tap.
  void _moving() {
    _awaitingRest?.cancel();
    if (_active(_justRested)) {
      _quietFromNow();
      return;
    }
    _awaitingRest = Timer(restWait, _quietFromNow);
  }

  void _quietFromNow() {
    _awaitingRest?.cancel();
    _awaitingRest = null;
    _quiet?.cancel();
    _quiet = Timer(quiet, () {});
  }

  /// The camera came to rest at [center] and [zoom]. The same camera again
  /// (a style loaded) is no motion.
  void rested(LatLng center, double zoom) {
    final before = _camera;
    _camera = (center: center, zoom: zoom);
    final moved =
        before == null ||
        (before.zoom - zoom).abs() > 0.001 ||
        (before.center.lat - center.lat).abs() > 1e-7 ||
        (before.center.lon - center.lon).abs() > 1e-7;
    if (!moved && !_active(_awaitingRest)) return;
    _justRested?.cancel();
    _justRested = Timer(const Duration(milliseconds: 100), () {});
    _quietFromNow();
  }

  /// Whether the tap the engine reports now is one the user meant.
  bool get stands => _last ?? true;

  /// Drops the timers: the map is gone.
  void dispose() {
    _awaitingRest?.cancel();
    _justRested?.cancel();
    _quiet?.cancel();
  }
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
