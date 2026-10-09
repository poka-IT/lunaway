import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/centred_clear.dart';

/// Shows [text] at the foot of the screen in place of the messages shown
/// or waiting.
///
/// A message with an [action] (undo, choose the lists) leaves by itself
/// like any other, a little later. With a screen reader or switch access it
/// stays until closed, with a close button, so the action can be reached.
void showMessage(ScaffoldMessengerState? messenger, String text, {SnackBarAction? action}) {
  if (messenger == null) return;
  final assisted = MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false;
  final stays = action != null && assisted;
  // Queued messages go too: after several quick taps only the last one,
  // the current state, shows.
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        persist: stays,
        showCloseIcon: stays,
        duration: action == null ? const Duration(seconds: 4) : const Duration(seconds: 8),
      ),
    );
}

/// The margins of a floating message ([SnackBarThemeData.insetPadding])
/// that centre it on the part of the window from [left] to [right] (the
/// map beside a fixed panel, the page beside the rail), at most [maxWidth]
/// wide (the whole of that part without one), [side] in from its edges,
/// and pushed aside only by [clear], the room a column of buttons takes at
/// an edge of that part, gap included ([centredSpan]); [bottom] below it.
///
/// A floating message adds the window's side insets to its margins by
/// itself: they are taken off here, so that a camera cut-out on one side
/// does not push it off centre. A part too narrow for a message (a small
/// window beside the guidance's panel) gives way to the whole window.
EdgeInsets messageInsets(
  BuildContext context, {
  required double left,
  required double right,
  double? maxWidth,
  EdgeInsets clear = EdgeInsets.zero,
  double side = Space.l,
  double bottom = Space.l,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final safe = MediaQuery.paddingOf(context);
  var (centre, lo, hi) = (
    (left + right) / 2,
    math.max(math.max(left + side, left + clear.left), safe.left),
    math.min(math.min(right - side, right - clear.right), width - safe.right),
  );
  if (hi - lo < _narrowestMessage) {
    (centre, lo, hi) = (width / 2, math.max(side, safe.left), width - math.max(side, safe.right));
  }
  final span = centredSpan(centre: centre, width: maxWidth ?? double.infinity, lo: lo, hi: hi);
  return EdgeInsets.fromLTRB(
    span.left - safe.left,
    0,
    math.max(0, width - span.left - span.width - safe.right),
    bottom,
  );
}

/// Under this width a message wraps at nearly every word.
const double _narrowestMessage = 160;

/// The height of a message of one line: a column of buttons within that
/// band above its foot stands level with it.
const double _messageHeight = kMinInteractiveDimension;

/// The horizontal extent of a [MessageStage] in the window.
typedef MessageStageSpan = ({double left, double right});

/// How far up from the bottom of the window the bars of actions reach (a
/// place's "Itinéraire" bar), where the stage of the screen shown stands
/// ([MessageStage]) and where the columns of buttons over the map stand
/// ([PushesMessagesAside]): the shell floats its messages above the bars,
/// centred on the stage, aside from a column they would cover.
final class MessageClearance extends ChangeNotifier {
  final _bars = <Object, double>{};
  final _stages = <Object, ({MessageStageSpan span, int depth})>{};
  final _aside = <Object, Rect>{};
  (double, MessageStageSpan?) _told = (0, null);
  List<Rect> _toldAside = const [];
  bool _pending = false;
  bool _disposed = false;

  /// The highest reach of the bars shown, 0 without any.
  double get value => _bars.values.fold(0, math.max);

  /// The innermost stage on screen (the map inside the page beside the
  /// rail), null without one.
  MessageStageSpan? get stage {
    ({MessageStageSpan span, int depth})? inner;
    for (final s in _stages.values) {
      if (inner == null || s.depth > inner.depth) inner = s;
    }
    return inner?.span;
  }

  /// The room the columns of buttons on screen ([PushesMessagesAside])
  /// take at either edge of [stage], gap included: those level with a
  /// message whose foot stands [foot] above the bottom of a window [height]
  /// tall.
  EdgeInsets clearOf(MessageStageSpan stage, {required double height, required double foot}) {
    var (left, right) = (0.0, 0.0);
    for (final r in _aside.values) {
      if (r.bottom <= height - foot - _messageHeight || r.top >= height - foot) continue;
      if (r.right <= stage.left || r.left >= stage.right) continue;
      if (r.center.dx >= (stage.left + stage.right) / 2) {
        right = math.max(right, stage.right - r.left + Space.s);
      } else {
        left = math.max(left, r.right - stage.left + Space.s);
      }
    }
    return EdgeInsets.only(left: left, right: right);
  }

  void _report(Object bar, double reach) {
    _bars[bar] = reach;
    _changed();
  }

  void _remove(Object bar) {
    if (_bars.remove(bar) != null) _changed();
  }

  void _reportStage(Object stage, MessageStageSpan span, int depth) {
    _stages[stage] = (span: span, depth: depth);
    _changed();
  }

  void _removeStage(Object stage) {
    if (_stages.remove(stage) != null) _changed();
  }

  void _reportAside(Object column, Rect rect) {
    _aside[column] = rect;
    _changed();
  }

  void _removeAside(Object column) {
    if (_aside.remove(column) != null) _changed();
  }

  // A bar leaves while the tree is being built: the shell hears of it once
  // the frame is done.
  void _changed() {
    if (_pending) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _pending = true;
      scheduler.addPostFrameCallback((_) {
        _pending = false;
        _tell();
      });
    } else {
      _tell();
    }
  }

  void _tell() {
    final now = (value, stage);
    final aside = _aside.values.toList();
    if (_disposed || (now == _told && listEquals(aside, _toldAside))) return;
    _told = now;
    _toldAside = aside;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Gives the bars below it the [MessageClearance] they report to.
class MessageClearanceScope extends InheritedNotifier<MessageClearance> {
  const new({required MessageClearance clearance, required super.child, super.key})
    : super(notifier: clearance);

  /// The clearance of the nearest scope, without listening to it.
  static MessageClearance? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MessageClearanceScope>()?.notifier;
}

/// A bar of actions at the bottom of the window: the app's messages float
/// above it rather than over its buttons. A bar on a tab the user is not on
/// (kept alive, its tickers off) does not count.
class LiftsMessages extends SingleChildRenderObjectWidget {
  const new({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLiftsMessages(
    TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderLiftsMessages).reportTo(
        TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null,
      );
}

class _RenderLiftsMessages extends RenderProxyBox {
  new(this._clearance);

  MessageClearance? _clearance;
  bool _scheduled = false;

  void reportTo(MessageClearance? clearance) {
    if (identical(clearance, _clearance)) return;
    _clearance?._remove(this);
    _clearance = clearance;
    _schedule();
  }

  @override
  void performLayout() {
    super.performLayout();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _measure();
    });
  }

  /// Reports the distance from the top of the bar to the bottom of the
  /// window. Layout offsets only: a bar sliding in is measured where it
  /// comes to rest, not where its first frame draws it.
  void _measure() {
    final clearance = _clearance;
    if (clearance == null || !attached || !hasSize) return;
    RenderObject root = this;
    for (var up = root.parent; up != null; up = up.parent) {
      root = up;
    }
    if (root is! RenderView) return;
    clearance._report(this, math.max(0, root.size.height - _layoutOrigin(this).dy));
  }

  @override
  void detach() {
    _clearance?._remove(this);
    super.detach();
  }
}

/// Where [box] stands in the window, from the offsets the parents gave
/// their children: a box sliding in is measured where it comes to rest, not
/// where its first frame draws it. A parent that keeps a plain [ParentData]
/// (a proxy, the view itself) lays its child at its own origin. Under a
/// parent that places children some other way (a sliver), the painted
/// position stands in.
Offset _layoutOrigin(RenderBox box) {
  var origin = Offset.zero;
  for (RenderObject node = box; node.parent != null; node = node.parent!) {
    final data = node.parentData;
    if (data is BoxParentData) {
      origin += data.offset;
    } else if (data.runtimeType != ParentData) {
      return box.localToGlobal(Offset.zero);
    }
  }
  return origin;
}

/// The part of the window a message centres on while this is on screen:
/// the map beside the fixed panels of a wide window, the page beside the
/// rail ([messageInsets]). The innermost stage on screen wins; one on a tab
/// the user is not on (kept alive, its tickers off) does not count. As
/// large as it is allowed without a child, and transparent to taps.
class MessageStage extends SingleChildRenderObjectWidget {
  const new({super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMessageStage(
    TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMessageStage).reportTo(
        TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null,
      );
}

class _RenderMessageStage extends RenderProxyBox {
  new(this._clearance);

  MessageClearance? _clearance;
  bool _scheduled = false;

  void reportTo(MessageClearance? clearance) {
    if (identical(clearance, _clearance)) return;
    _clearance?._removeStage(this);
    _clearance = clearance;
    _schedule();
  }

  @override
  Size computeSizeForNoChild(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    super.performLayout();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final clearance = _clearance;
      if (clearance == null || !attached || !hasSize) return;
      final left = _layoutOrigin(this).dx;
      clearance._reportStage(this, (left: left, right: left + size.width), depth);
    });
  }

  @override
  void detach() {
    _clearance?._removeStage(this);
    super.detach();
  }
}

/// A column of buttons over the map at the foot of the window (the zoom,
/// the position): a message level with it moves aside by what it would
/// cover of it ([MessageClearance.clearOf]). One on a tab the user is not
/// on (kept alive, its tickers off) does not count.
class PushesMessagesAside extends SingleChildRenderObjectWidget {
  const new({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPushesMessagesAside(
    TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderPushesMessagesAside).reportTo(
        TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null,
      );
}

class _RenderPushesMessagesAside extends RenderProxyBox {
  new(this._clearance);

  MessageClearance? _clearance;
  bool _scheduled = false;

  void reportTo(MessageClearance? clearance) {
    if (identical(clearance, _clearance)) return;
    _clearance?._removeAside(this);
    _clearance = clearance;
    _schedule();
  }

  @override
  void performLayout() {
    super.performLayout();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final clearance = _clearance;
      if (clearance == null || !attached || !hasSize) return;
      clearance._reportAside(this, _layoutOrigin(this) & size);
    });
  }

  @override
  void detach() {
    _clearance?._removeAside(this);
    super.detach();
  }
}
