import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'popup_routes.g.dart';

/// How many dialogs, sheets and menus are open over the screens, across the
/// app's navigators. The web map reads it: its HTML element would otherwise
/// take the clicks and the wheel meant for what lies over it.
// keepAlive: the navigators push and pop for the whole run; a count that
// reset while nothing watched it would be wrong when the map came back.
@Riverpod(keepAlive: true)
class OpenPopups extends _$OpenPopups {
  @override
  int build() => 0;

  void _change(int delta) {
    if (ref.mounted) state = (state + delta).clamp(0, 1 << 20);
  }
}

/// What the tab's history does with a popup: in a browser, one opened over
/// the map takes an entry, so the browser's back closes it
/// (`MapHistory.popupOpened`).
abstract interface class PopupHistory {
  void popupOpened(Route<dynamic> popup);

  void popupClosed(Route<dynamic> popup);
}

/// The router's observer of the popups, one for the run.
// keepAlive: the router holds it for the whole run.
@Riverpod(keepAlive: true)
PopupObserver popupObserver(Ref ref) => PopupObserver(ref.read(openPopupsProvider.notifier));

/// Counts the popups of a navigator into [OpenPopups], and tells the tab's
/// history of them; the router's one also hears the shell's navigators.
final class PopupObserver extends NavigatorObserver {
  new(this._popups);

  final OpenPopups _popups;

  /// The tab's history, told when a popup comes or goes: set by the
  /// history itself, which depends on the router this observer serves.
  PopupHistory? history;

  // A navigator may report a change while it builds (pages replaced by the
  // router), when no provider may change: the count and the history follow
  // just after, in the order the popups came and went.
  void _count(Route<dynamic>? route, int delta) {
    if (route is! PopupRoute) return;
    scheduleMicrotask(() {
      _popups._change(delta);
      final history = this.history;
      if (delta > 0) {
        history?.popupOpened(route);
      } else {
        history?.popupClosed(route);
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _count(route, 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _count(route, -1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _count(route, -1);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _count(oldRoute, -1);
    _count(newRoute, 1);
  }
}
