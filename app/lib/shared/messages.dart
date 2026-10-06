import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

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

/// How far up from the bottom of the window the bars of actions reach (a
/// place's "Itinéraire" bar): the shell floats its messages above that.
final class MessageClearance extends ChangeNotifier {
  final _bars = <Object, double>{};
  double _told = 0;
  bool _pending = false;
  bool _disposed = false;

  /// The highest reach of the bars shown, 0 without any.
  double get value => _bars.values.fold(0, math.max);

  void _report(Object bar, double reach) {
    _bars[bar] = reach;
    _changed();
  }

  void _remove(Object bar) {
    if (_bars.remove(bar) != null) _changed();
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
    if (_disposed || value == _told) return;
    _told = value;
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
    clearance._report(this, math.max(0, root.size.height - _layoutTop()));
  }

  /// The top of the bar in the window, from the offsets the parents gave
  /// their children. A parent that keeps a plain [ParentData] (a proxy, the
  /// view itself) lays its child at its own origin. Under a parent that
  /// places children some other way (a sliver), the painted position stands
  /// in.
  double _layoutTop() {
    var top = 0.0;
    for (RenderObject node = this; node.parent != null; node = node.parent!) {
      final data = node.parentData;
      if (data is BoxParentData) {
        top += data.offset.dy;
      } else if (data.runtimeType != ParentData) {
        return localToGlobal(Offset.zero).dy;
      }
    }
    return top;
  }

  @override
  void detach() {
    _clearance?._remove(this);
    super.detach();
  }
}
