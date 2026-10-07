import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Tells when the user starts moving a map drawn by a platform view
/// (MapLibre on Android and iOS), from the raw pointer events that reach
/// the view: the engine's own camera events do not say who moved it.
///
/// A gesture is a finger or the mouse that slides past the touch slop, a
/// second finger (a pinch, a turn, a tilt), a second tap close to the first
/// (a double tap zooms), the mouse wheel or a trackpad's pan and zoom. A
/// tap that stays put is no gesture: it opens what is under it.
class MapGestureWatch extends StatefulWidget {
  const new({required this.child, this.onGesture, this.onTouch, super.key});

  final Widget child;

  /// Once per gesture, at its start.
  final VoidCallback? onGesture;

  /// A pointer went down on the map (true), or the last one came up.
  final ValueChanged<bool>? onTouch;

  /// Two taps closer than this in time and space make a double tap.
  static const doubleTapTime = Duration(milliseconds: 300);
  static const doubleTapSlop = 48.0;

  @override
  State<MapGestureWatch> createState() => _MapGestureWatchState();
}

class _MapGestureWatchState extends State<MapGestureWatch> {
  final Map<int, Offset> _down = {};

  /// The current press already counted as a gesture.
  bool _moved = false;

  /// Where the last tap that stayed put was, while a second one there
  /// would make a double tap.
  Offset? _lastTap;
  Timer? _tapWindow;

  @override
  void dispose() {
    _tapWindow?.cancel();
    super.dispose();
  }

  void _gesture() {
    if (_moved) return;
    _moved = true;
    widget.onGesture?.call();
  }

  void _onDown(PointerDownEvent e) {
    final first = _down.isEmpty;
    _down[e.pointer] = e.position;
    if (first) {
      _moved = false;
      widget.onTouch?.call(true);
      final tap = _lastTap;
      if (tap != null && (e.position - tap).distance <= MapGestureWatch.doubleTapSlop) _gesture();
    } else {
      _gesture();
    }
  }

  void _onMove(PointerMoveEvent e) {
    final start = _down[e.pointer];
    if (start == null) return;
    if ((e.position - start).distance > _slop(e.kind)) _gesture();
  }

  /// How far a press may wander and still be a tap: a fingertip rolls, a
  /// mouse barely moves (MapLibre GL JS starts a drag after 3 px).
  static double _slop(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad ? 4 : kTouchSlop;

  void _onUp(PointerEvent e) {
    if (_down.remove(e.pointer) == null) return;
    if (_down.isNotEmpty) return;
    _tapWindow?.cancel();
    _lastTap = null;
    if (!_moved && e is! PointerCancelEvent) {
      _lastTap = e.position;
      _tapWindow = Timer(MapGestureWatch.doubleTapTime, () => _lastTap = null);
    }
    widget.onTouch?.call(false);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent && e is! PointerScaleEvent) return;
    // A wheel turn is a gesture of its own, with no press around it.
    _moved = false;
    _gesture();
    if (_down.isEmpty) _moved = false;
  }

  void _onPanZoomStart(PointerPanZoomStartEvent _) {
    _moved = false;
    _gesture();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    onPointerSignal: _onSignal,
    onPointerPanZoomStart: _onPanZoomStart,
    child: widget.child,
  );
}
