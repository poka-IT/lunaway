import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/centred_clear.dart';

/// Shows [text] at the foot of the screen in place of the messages shown
/// or waiting: a passing notice of the app's rule (`notices.dart`).
///
/// It leaves by itself after [NoticeTimes.passing], one with an [action]
/// (undo, choose the lists) after [NoticeTimes.withAction]; a tap or a
/// swipe down closes it at once. With a screen reader or switch access a
/// message with an action stays until closed, with a close button, so the
/// action can be reached.
///
/// While a screen that shows its notices its own way is up (the guidance,
/// [redirectMessages]), the message goes there instead.
void showMessage(ScaffoldMessengerState? messenger, String text, {SnackBarAction? action}) {
  if (messenger == null) return;
  if (_sinks[messenger]?.lastOrNull case final sink?) {
    sink.tell(text, action: action);
    return;
  }
  final assisted = MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false;
  final stays = action != null && assisted;
  // Queued messages go too: after several quick taps only the last one,
  // the current state, shows.
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A screen reader closes it by its own gesture, or by the close
            // button when it stays.
            excludeFromSemantics: true,
            onTap: messenger.hideCurrentSnackBar,
            child: Text(text),
          ),
        ),
        action: action,
        persist: stays,
        showCloseIcon: stays,
        duration: action == null ? NoticeTimes.passing : NoticeTimes.withAction,
      ),
    );
}

/// A screen that shows the app's messages its own way while it is up.
abstract interface class MessageSink {
  /// Shows [text], with its [action], as [showMessage] would.
  void tell(String text, {SnackBarAction? action});
}

final _sinks = Expando<List<MessageSink>>('message sinks');

/// Sends what [showMessage] is asked to show through [messenger] to [sink]
/// until the returned function is called; the last screen to ask has them.
/// The guidance does this: a message at the foot of its screen would cover
/// the driver's bar, so it shows them under the maneuver with its own
/// notices.
void Function() redirectMessages(ScaffoldMessengerState messenger, MessageSink sink) {
  final sinks = (_sinks[messenger] ??= [])..add(sink);
  return () => sinks.remove(sink);
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

  /// The room the buttons on screen ([PushesMessagesAside]) take at either
  /// edge of [stage], gap included: those level with a message standing
  /// between [top] and [bottom] in the window.
  EdgeInsets clearOf(MessageStageSpan stage, {required double top, required double bottom}) {
    var (left, right) = (0.0, 0.0);
    for (final r in _aside.values) {
      if (r.bottom <= top || r.top >= bottom) continue;
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

/// The clearance a reporter built in [context] reports to: none on a tab
/// the user is not on (kept alive, its tickers off).
MessageClearance? _scopeOf(BuildContext context) =>
    TickerMode.valuesOf(context).enabled ? MessageClearanceScope.maybeOf(context) : null;

/// What the reporters below share: the clearance they report to, and a
/// measure after each frame that laid them out or built them again. A
/// rebuild counts too: a box its parent moves (a button riding a sheet, a
/// window grown taller) keeps its constraints and is not laid out again.
abstract class _RenderReports extends RenderProxyBox {
  new(this._clearance);

  MessageClearance? _clearance;
  bool _scheduled = false;

  /// Reports to [clearance] (none: withdrawn) after this frame.
  void reportTo(MessageClearance? clearance) {
    if (!identical(clearance, _clearance)) {
      if (_clearance case final old?) _withdrawFrom(old);
      _clearance = clearance;
    }
    _schedule();
  }

  @override
  void performLayout() {
    super.performLayout();
    _schedule();
  }

  // Moved elsewhere in the tree (a global key), it is measured again there.
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_clearance case final clearance? when attached && hasSize) _measureInto(clearance);
    });
  }

  void _measureInto(MessageClearance clearance);

  void _withdrawFrom(MessageClearance clearance);

  @override
  void detach() {
    if (_clearance case final clearance?) _withdrawFrom(clearance);
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

/// A bar of actions at the bottom of the window: the app's messages float
/// above it rather than over its buttons. A bar on a tab the user is not on
/// (kept alive, its tickers off) does not count.
class LiftsMessages extends SingleChildRenderObjectWidget {
  const new({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLiftsMessages(_scopeOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderLiftsMessages).reportTo(_scopeOf(context));
}

class _RenderLiftsMessages extends _RenderReports {
  new(super._clearance);

  /// Reports the distance from the top of the bar to the bottom of the
  /// window.
  @override
  void _measureInto(MessageClearance clearance) {
    RenderObject root = this;
    for (var up = root.parent; up != null; up = up.parent) {
      root = up;
    }
    if (root is! RenderView) return;
    clearance._report(this, math.max(0, root.size.height - _layoutOrigin(this).dy));
  }

  @override
  void _withdrawFrom(MessageClearance clearance) => clearance._remove(this);
}

/// The part of the window a message centres on while this is on screen:
/// the map beside the fixed panels of a wide window, the page beside the
/// rail ([messageInsets]). The innermost stage on screen wins; one on a tab
/// the user is not on (kept alive, its tickers off) does not count. Without
/// a child, as large as its bounded constraints allow; transparent to taps.
class MessageStage extends SingleChildRenderObjectWidget {
  const new({super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMessageStage(_scopeOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMessageStage).reportTo(_scopeOf(context));
}

class _RenderMessageStage extends _RenderReports {
  new(super._clearance);

  @override
  Size computeSizeForNoChild(BoxConstraints constraints) {
    assert(
      constraints.isTight || constraints.hasBoundedWidth && constraints.hasBoundedHeight,
      'A MessageStage without a child takes the room it is given: it needs bounds.',
    );
    return constraints.biggest;
  }

  @override
  void _measureInto(MessageClearance clearance) {
    final left = _layoutOrigin(this).dx;
    clearance._reportStage(this, (left: left, right: left + size.width), depth);
  }

  @override
  void _withdrawFrom(MessageClearance clearance) => clearance._removeStage(this);
}

/// A button over the map at the foot of the window (the zoom, the
/// position): a message level with it moves aside by what it would cover of
/// it ([MessageClearance.clearOf]). Not [active] (faded out), or on a tab
/// the user is not on, it does not count.
class PushesMessagesAside extends SingleChildRenderObjectWidget {
  const new({required Widget super.child, this.active = true, super.key});

  final bool active;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPushesMessagesAside(active ? _scopeOf(context) : null);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderPushesMessagesAside).reportTo(active ? _scopeOf(context) : null);
}

class _RenderPushesMessagesAside extends _RenderReports {
  new(super._clearance);

  @override
  void _measureInto(MessageClearance clearance) =>
      clearance._reportAside(this, _layoutOrigin(this) & size);

  @override
  void _withdrawFrom(MessageClearance clearance) => clearance._removeAside(this);
}
