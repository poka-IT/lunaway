import 'package:lunaway/core/web/browser_stub.dart'
    if (dart.library.js_interop) 'package:lunaway/core/web/browser_web.dart'
    as impl;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'browser.g.dart';

/// What the app reads of, and asks of, the browser it runs in: its history,
/// whether it is online, whether the user has touched the page. Only the
/// web has one; tests stand a fake in for it.
abstract interface class Browser {
  /// Moves [delta] entries through the tab's history, as the browser's own
  /// buttons do (a negative [delta] goes back). The page hears the move
  /// later, as the address it lands on.
  void goInHistory(int delta);

  /// Whether the browser says it is online (`navigator.onLine`). False is
  /// sure (no network at all); true only means a network is there.
  bool get online;

  /// Each change of [online], as the browser announces it (its `online` and
  /// `offline` events).
  Stream<bool> get onlineChanges;

  /// Whether the user has pressed, touched, scrolled or typed anywhere in
  /// the page since it loaded, the page's first map included
  /// (`web/premap.js`): until then, what the map shows is the app's own
  /// framing, not a view the user chose.
  bool get userActed;
}

/// The browser the app runs in; null outside the web.
// keepAlive: the page lives as long as the app; its history and its network
// listeners are the page's own.
@Riverpod(keepAlive: true)
Browser? browser(Ref ref) => impl.pageBrowser();
