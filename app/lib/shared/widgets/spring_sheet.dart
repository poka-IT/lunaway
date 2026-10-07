import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// Drives a [SpringSheet] from outside: where it rests and how to move it.
class SpringSheetController extends ChangeNotifier {
  _SpringSheetState? _state;

  /// The visible height of the sheet, in logical pixels.
  double get extent => _state?._extent.value ?? 0;

  bool get isAttached => _state != null;

  /// Moves the sheet to [pixels] on the sheet's spring.
  Future<void> animateTo(double pixels) async => _state?._springTo(pixels, 0);

  void _changed() => notifyListeners();
}

/// A bottom sheet over the map that rests at [snaps] and moves on a spring:
/// a fling carries its speed into the settle instead of snapping on a fixed
/// curve. The content scrolls once the sheet is at its highest snap, and
/// dragging the content down from its top moves the sheet down again, as
/// users expect from map apps. With [onDismiss], a fling down from the
/// lowest snap closes it.
class SpringSheet extends StatefulWidget {
  const new({
    required this.snaps,
    required this.initial,
    required this.builder,
    this.controller,
    this.onDismiss,
    this.onSettle,
    super.key,
  });

  /// Heights the sheet rests at, in logical pixels, ascending.
  final List<double> snaps;
  final double initial;
  final Widget Function(BuildContext context, ScrollController scroll) builder;
  final SpringSheetController? controller;
  final VoidCallback? onDismiss;

  /// Called with the height once the sheet comes to rest: what the map
  /// needs to keep its camera centred on the uncovered part, without a
  /// change at every frame of a drag.
  final ValueChanged<double>? onSettle;

  @override
  State<SpringSheet> createState() => _SpringSheetState();
}

class _SpringSheetState extends State<SpringSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _extent = AnimationController.unbounded(
    vsync: this,
    value: widget.initial,
  )..addListener(() => widget.controller?._changed());
  late final _SheetScrollController _scroll = _SheetScrollController(this);

  double get _min => widget.snaps.first;
  double get _max => widget.snaps.last;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(SpringSheet old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    // New snaps (another content): settle on the nearest one that still
    // exists, unless the owner moves the sheet itself.
    if (!_sameSnaps(old.snaps, widget.snaps) && !_extent.isAnimating) {
      final value = _extent.value;
      if (value < _min || value > _max) _springTo(_nearest(value), 0);
    }
  }

  static bool _sameSnaps(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _scroll.dispose();
    _extent.dispose();
    super.dispose();
  }

  double _nearest(double value) =>
      widget.snaps.reduce((a, b) => (a - value).abs() <= (b - value).abs() ? a : b);

  /// Moves the sheet by a drag of [delta] pixels (positive: up). Below the
  /// lowest snap a dismissible sheet follows with resistance.
  void _dragBy(double delta) {
    var next = _extent.value + delta;
    if (next < _min) {
      next = widget.onDismiss == null ? _min : _extent.value + delta * 0.45;
    }
    _extent.value = next.clamp(0, _max);
  }

  /// Ends a drag at [velocity] (pixels per second, positive: up): the sheet
  /// springs to the snap the fling points at, or closes.
  void _release(double velocity) {
    final value = _extent.value;
    if (widget.onDismiss != null && (value < _min - 48 || (value <= _min + 1 && velocity < -900))) {
      widget.onDismiss!();
      return;
    }
    // Where the fling would carry the sheet, then the snap nearest that.
    final projected = value + velocity * 0.18;
    var target = _nearest(projected);
    // A deliberate fling always moves at least one snap.
    if (velocity.abs() > 700 && (target - value).abs() < 1) {
      final up = velocity > 0;
      target = up
          ? widget.snaps.firstWhere((s) => s > value + 1, orElse: () => _max)
          : widget.snaps.lastWhere((s) => s < value - 1, orElse: () => _min);
    }
    _springTo(target, velocity);
  }

  void _springTo(double target, double velocity) {
    if (Motion.reduced(context)) {
      _extent.value = target;
      widget.onSettle?.call(target);
      return;
    }
    _extent
        .animateWith(SpringSimulation(Motion.sheetSpring, _extent.value, target, velocity))
        .whenCompleteOrCancel(() {
          if (mounted && !_extent.isAnimating) widget.onSettle?.call(_extent.value);
        });
  }

  bool get _atMax => _extent.value >= _max - 0.5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    return AnimatedBuilder(
      animation: _extent,
      builder: (context, child) => Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(height: math.max(0, _extent.value), child: child),
      ),
      child: OverMap(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
            boxShadow: tokens.sheetShadow,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  // The handle drags the sheet even where the content does not
                  // scroll. It moves the sheet's top edge up and down only,
                  // so the mouse shows the vertical resize arrows: a grabbing
                  // hand would promise the sheet moves freely.
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => _extent.stop(),
                      onVerticalDragUpdate: (d) => _dragBy(-d.delta.dy),
                      onVerticalDragEnd: (d) => _release(-(d.primaryVelocity ?? 0)),
                      child: SizedBox(
                        height: 22,
                        width: double.infinity,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: scheme.outline.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: widget.builder(context, _scroll)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetScrollController extends ScrollController {
  new(this.sheet);

  final _SpringSheetState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet: sheet,
    physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
    context: context,
    oldPosition: oldPosition,
  );
}

/// The content's scroll position, which hands drags to the sheet while the
/// sheet can still move: up until the highest snap, down while the content
/// is at its top.
class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  new({required this.sheet, required super.physics, required super.context, super.oldPosition});

  final _SpringSheetState sheet;
  VoidCallback? _dragCancel;
  var _sheetMoved = false;

  bool get _contentAtTop => pixels <= minScrollExtent;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _dragCancel = dragCancelCallback;
    _sheetMoved = false;
    sheet._extent.stop();
    return super.drag(details, dragCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    // delta > 0: the finger moves down. From the top of the content, a drag
    // up grows the sheet until its highest snap, a drag down lowers it.
    final growing = delta < 0;
    if (_contentAtTop && (!growing || !sheet._atMax)) {
      _sheetMoved = true;
      sheet._dragBy(-delta);
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    // velocity > 0: the content would scroll up, the sheet grow.
    final sheetOwnsFling =
        _sheetMoved ||
        (_contentAtTop && velocity < 0) ||
        (_contentAtTop && velocity > 0 && !sheet._atMax);
    if (!sheetOwnsFling) {
      super.goBallistic(velocity);
      return;
    }
    _dragCancel?.call();
    _dragCancel = null;
    _sheetMoved = false;
    sheet._release(velocity);
    super.goBallistic(0);
  }
}
