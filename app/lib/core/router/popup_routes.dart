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

/// Counts the popups of a navigator into [OpenPopups]; the router's one
/// also hears the shell's navigators.
final class PopupObserver extends NavigatorObserver {
  new(this._popups);

  final OpenPopups _popups;

  // A navigator may report a change while it builds (pages replaced by the
  // router), when no provider may change: the count follows just after.
  void _count(Route<dynamic>? route, int delta) {
    if (route is PopupRoute) scheduleMicrotask(() => _popups._change(delta));
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
