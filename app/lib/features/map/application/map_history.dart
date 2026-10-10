import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/popup_routes.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_history.g.dart';

/// The one writer of the router and of the tab's history for the map and
/// the pages over it (the route preview, the guidance). `MapFlow` decides
/// each change of what the map screen shows; this writes it, in order.
///
/// In a browser each selection of the map has an entry of its own
/// (`/map?place=<id>`), and a page over the map holds the entry above the
/// map's. A move back through the history lands a moment later (the
/// page's `popstate`): until it has, the writes asked after it wait, so
/// that none lands before it and is undone by it, and the address the
/// browser shows meanwhile is judged only once every write has landed
/// ([whenSettled]). The map's own address is written only while the map
/// is the page shown: under a page, it is that page's way back, and
/// writing it would replace the page (the guidance, stopped).
abstract interface class MapHistory implements PopupHistory {
  /// Whether the map is the page shown: its tab, nothing over it.
  bool get mapShown;

  /// Whether the map writes its address: in a browser, while it is shown.
  bool get writesAddresses;

  /// What the address of the map names.
  MapLink get address;

  /// Whether the way back from what the map shows starts at the bare map:
  /// always in the apps; in a browser, when the map is shown at its bare
  /// address, or on its way back to it (a close whose move has not landed
  /// yet: the next pin tapped goes on top of the bare map's entry).
  bool get onBareMap;

  /// Whether the entry shown is one the map wrote in this load of the page
  /// ([TrailMarks]): only from such an entry does the way back walk the
  /// history.
  bool get onOwnEntry;

  /// Runs [then] once every move and write asked of the history has
  /// landed, and never while the router builds: what the browser shows
  /// meanwhile is on its way somewhere else.
  void whenSettled(VoidCallback then);

  /// [link] on a new entry, the map shown.
  void pushMap(MapLink link);

  /// [link] in place of the map's address, without a new entry.
  void replaceMap(MapLink link);

  /// Back [steps] entries of the tab's history.
  void back(int steps);

  /// The map at [link], from another tab.
  void goToMap(MapLink link);

  /// [location] over the map, on the entry above the map's.
  void pushPage(String location, {Object? extra});

  /// [location] in place of the page over the map, on its entry.
  void replacePage(String location, {Object? extra});

  /// The page over the map left for the map under it: back one entry in a
  /// browser, as the browser's own back does; popped in the apps. A page
  /// opened on its own (a link typed or reloaded) has no map under it: the
  /// map takes its place.
  void leavePage();

  /// [popup] (a dialog, a sheet, a menu) opened over the map shown. In a
  /// browser it takes an entry of the tab's history, at the map's address,
  /// so the browser's back closes it: without one, the back closed the
  /// place under the photo viewer, or left the app from the filters.
  @override
  void popupOpened(Route<dynamic> popup);

  /// [popup] closed or taken away: in a browser, its entry goes too, unless
  /// the browser's back closed it and took it already.
  @override
  void popupClosed(Route<dynamic> popup);
}

// keepAlive: one writer for the whole run, which holds the order of the
// moves it was asked.
@Riverpod(keepAlive: true)
MapHistory mapHistory(Ref ref) {
  final history = RouterMapHistory(
    router: ref.watch(routerProvider),
    browser: ref.watch(browserProvider),
  );
  final popups = ref.watch(popupObserverProvider)..history = history;
  ref.onDispose(() {
    history.dispose();
    if (identical(popups.history, history)) popups.history = null;
  });
  return history;
}

/// [MapHistory] over the app's router, and in a browser over the tab's
/// history.
final class RouterMapHistory implements MapHistory {
  new({required this.router, required this.browser}) {
    router.routerDelegate.addListener(_routed);
    router.routeInformationProvider.addListener(_informed);
  }

  final GoRouter router;

  /// The browser, on the web; null in the apps.
  final Browser? browser;

  /// How long a move or a write may take to land before the rest go on: a
  /// move that leaves the app never does.
  static const landing = Duration(milliseconds: 600);

  /// A move back sent to the browser that has not landed.
  Timer? _moving;

  /// Writes sent to the router whose change it has not reported yet.
  int _unseen = 0;
  Timer? _giveUp;

  /// Whether a write is being sent: what the router hears meanwhile is
  /// this writer's, not the browser's.
  bool _writing = false;

  /// The writes asked while a move back lands, in order.
  final _waiting = <VoidCallback>[];

  /// What waits for every move and write to land.
  final _whenSettled = <VoidCallback>[];

  /// The popups over the map that hold an entry of the tab's history,
  /// oldest first.
  final _popups = <Route<dynamic>>[];

  /// The popups the browser's back is closing: their entry is gone.
  final _closedByBack = <Route<dynamic>>{};

  RouteMatchList get _config => router.routerDelegate.currentConfiguration;

  void dispose() {
    router.routerDelegate.removeListener(_routed);
    router.routeInformationProvider.removeListener(_informed);
    _moving?.cancel();
    _giveUp?.cancel();
  }

  @override
  bool get mapShown => _config.lastOrNull?.matchedLocation == AppRoutes.map;

  @override
  bool get writesAddresses => browser != null && mapShown;

  @override
  MapLink get address => MapLink.of(_config.uri);

  @override
  bool get onBareMap => browser == null || _moving != null || (mapShown && address.isNone);

  @override
  bool get onOwnEntry => TrailMarks.ours(_config.extra);

  bool get _settled => _moving == null && _unseen == 0;

  @override
  void whenSettled(VoidCallback then) {
    if (_settled) {
      scheduleMicrotask(then);
    } else {
      _whenSettled.add(then);
    }
  }

  void _maybeSettled() {
    if (!_settled || _whenSettled.isEmpty) return;
    final waiting = [..._whenSettled];
    _whenSettled.clear();
    // After the router's own work for this change: never while it builds.
    waiting.forEach(scheduleMicrotask);
  }

  /// Runs [write] now, or once the move back under way has landed.
  void _run(VoidCallback write) {
    if (_moving != null) {
      _waiting.add(write);
    } else {
      write();
    }
  }

  /// Sends [write] to the router, which reports its change a moment later.
  void _send(VoidCallback write) {
    _unseen++;
    _giveUp?.cancel();
    _giveUp = Timer(landing, () {
      _unseen = 0;
      _maybeSettled();
    });
    _writing = true;
    try {
      write();
    } finally {
      _writing = false;
    }
  }

  /// The router changed its pages.
  void _routed() {
    if (_unseen > 0) _unseen--;
    _maybeSettled();
  }

  /// The router heard of an address: this writer's own, or the browser's
  /// when it moved (back, forward, a move asked here landing).
  void _informed() {
    if (_writing) return;
    if (_moving != null) {
      _landed();
      _maybeSettled();
      return;
    }
    // The browser left the entry of the popup on top: the popup closes, as
    // the system's back closes it in the apps.
    if (_popups.isEmpty) return;
    final popup = _popups.last;
    _closedByBack.add(popup);
    final navigator = popup.navigator;
    if (popup.isCurrent) {
      navigator?.pop();
    } else if (popup.isActive) {
      navigator?.removeRoute(popup);
    }
  }

  void _landed() {
    _moving?.cancel();
    _moving = null;
    final writes = [..._waiting];
    _waiting.clear();
    for (final (i, write) in writes.indexed) {
      write();
      // A write that moved back again holds the rest until it lands.
      if (_moving != null) {
        _waiting.addAll(writes.skip(i + 1));
        return;
      }
    }
  }

  void _goBack(int steps) {
    final browser = this.browser;
    if (browser == null) return;
    _moving = Timer(landing, () {
      _landed();
      _maybeSettled();
    });
    browser.goInHistory(-steps);
  }

  /// [write] as a change that takes no new entry of the tab's history.
  void _neglect(VoidCallback write) {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return write();
    Router.neglect(context, write);
  }

  @override
  void pushMap(MapLink link) => _run(() {
    if (!mapShown || address == link) return;
    _send(() => router.go(link.location, extra: TrailMarks.next()));
  });

  @override
  void replaceMap(MapLink link) => _run(() {
    if (!mapShown || address == link) return;
    _send(() => _neglect(() => router.go(link.location, extra: TrailMarks.next())));
  });

  @override
  void back(int steps) => _run(() => _goBack(steps));

  @override
  void goToMap(MapLink link) => _run(() => _send(() => router.go(link.location)));

  @override
  void pushPage(String location, {Object? extra}) =>
      _run(() => _send(() => unawaited(router.push<void>(location, extra: extra))));

  @override
  void replacePage(String location, {Object? extra}) => _run(
    () => _send(
      () => _neglect(() => unawaited(router.pushReplacement<void>(location, extra: extra))),
    ),
  );

  @override
  void leavePage() => _run(() {
    if (router.canPop()) {
      if (browser != null) {
        _goBack(1);
      } else {
        _send(router.pop);
      }
    } else if (browser != null) {
      _send(() => _neglect(() => router.go(AppRoutes.map)));
    } else {
      _send(() => router.go(AppRoutes.map));
    }
  });

  @override
  void popupOpened(Route<dynamic> popup) {
    if (browser == null || !mapShown) return;
    _run(() {
      // Closed before its turn came, or the map covered meanwhile.
      if (!popup.isActive || !mapShown) return;
      final here = router.routeInformationParser.restoreRouteInformation(_config);
      if (here == null) return;
      _popups.add(popup);
      // The map's own address and state again, on a new entry: the router
      // finds the same pages there when the browser comes back to it.
      unawaited(SystemNavigator.routeInformationUpdated(uri: here.uri, state: here.state));
    });
  }

  @override
  void popupClosed(Route<dynamic> popup) {
    // One that took no entry (over another page, or closed before its
    // entry's turn came) leaves the history as it is.
    if (!_popups.remove(popup)) return;
    if (_closedByBack.remove(popup)) return;
    back(1);
  }
}
