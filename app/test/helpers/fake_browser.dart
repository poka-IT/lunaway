import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/web/browser.dart';

/// A browser tab for widget tests: it keeps the history the router writes
/// (`routeInformationUpdated` on the navigation channel, a new entry or the
/// current one replaced), and its back and forward give the router the
/// entry they land on, as a page's `popstate` does on the web.
final class FakeBrowser implements Browser {
  /// Listens to the router's reports for the length of the test; [userActed]
  /// says whether the user has acted on the page.
  new(WidgetTester tester, {this.userActed = true, this._online = true}) {
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.navigation, (call) async {
        if (call.method != 'routeInformationUpdated') return null;
        final args = (call.arguments as Map<Object?, Object?>).cast<String, Object?>();
        final entry = (location: args['uri']! as String, state: args['state']);
        // The app's first report replaces the entry the page loaded in, its
        // own: the page before it stays.
        if (args['replace'] == true && !leftApp) {
          entries[index] = entry;
        } else {
          entries
            ..removeRange(index + 1, entries.length)
            ..add(entry);
          index = entries.length - 1;
        }
        return null;
      });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.navigation, null));
    _deliver = (entry) => messenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {'location': entry.location, 'state': entry.state}),
      ),
      (_) {},
    );
  }

  /// The tab's entries, oldest first: an entry before the app's stands for
  /// the page the tab came from.
  final entries = <({String location, Object? state})>[(location: 'about:blank', state: null)];
  int index = 0;

  /// Whether the tab left the app (its back went past the app's first entry).
  bool get leftApp => entries[index].location == 'about:blank';

  /// The address shown.
  String get location => entries[index].location;

  /// The moves asked of the history by the app.
  final moves = <int>[];

  late final Future<void> Function(({String location, Object? state})) _deliver;

  /// The user's back button.
  Future<void> back() => _move(-1);

  /// The user's forward button.
  Future<void> forward() => _move(1);

  Future<void> _move(int delta) async {
    final target = (index + delta).clamp(0, entries.length - 1);
    if (target == index) return;
    index = target;
    if (leftApp) return;
    await _deliver(entries[index]);
  }

  @override
  void goInHistory(int delta) {
    moves.add(delta);
    // The browser moves after the call returns, as a page hears `popstate`.
    scheduleMicrotask(() => unawaited(_move(delta)));
  }

  bool _online;
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get online => _online;

  set online(bool value) {
    _online = value;
    _changes.add(value);
  }

  @override
  Stream<bool> get onlineChanges => _changes.stream;

  @override
  bool userActed;
}
