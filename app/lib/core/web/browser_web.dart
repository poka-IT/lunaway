import 'dart:async';
import 'dart:js_interop';

import 'package:lunaway/core/web/browser.dart';
import 'package:web/web.dart' as web;

/// Set by `web/premap.js` before anything else on the page: whether the
/// user has pressed, touched, scrolled or typed since the page loaded.
@JS('lunawayUserActed')
external JSFunction? get _userActed;

Browser? pageBrowser() => _PageBrowser();

final class _PageBrowser implements Browser {
  new() {
    web.window.addEventListener('online', ((web.Event _) => _changes.add(true)).toJS);
    web.window.addEventListener('offline', ((web.Event _) => _changes.add(false)).toJS);
  }

  final _changes = StreamController<bool>.broadcast();

  @override
  void goInHistory(int delta) => web.window.history.go(delta);

  @override
  bool get online => web.window.navigator.onLine;

  @override
  Stream<bool> get onlineChanges => _changes.stream;

  @override
  bool get userActed {
    final acted = _userActed;
    // A page without it (premap.js did not load) keeps the view as it
    // always did.
    if (acted == null) return true;
    return (acted.callAsFunction() as JSBoolean?)?.toDart ?? true;
  }
}
