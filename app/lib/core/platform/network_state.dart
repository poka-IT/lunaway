import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_state.g.dart';

final _log = Logger('network');

/// What the phone says of its network: whether there is one, and whether
/// it is metered (a mobile network, a phone's hotspot, a Wi-Fi marked as
/// metered, or iOS's Low Data Mode).
@immutable
final class NetworkState {
  const new({required this.connected, required this.metered});

  /// [connected] is the system's word, not a proof that a server answers:
  /// a hotel's Wi-Fi before its login page is connected.
  final bool connected;
  final bool metered;

  static NetworkState? fromMap(Object? map) {
    if (map is! Map) return null;
    final connected = map['connected'];
    final metered = map['metered'];
    if (connected is! bool || metered is! bool) return null;
    return NetworkState(connected: connected, metered: metered);
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkState && other.connected == connected && other.metered == metered;

  @override
  int get hashCode => Object.hash(connected, metered);

  @override
  String toString() => 'NetworkState(connected: $connected, metered: $metered)';
}

/// The system's view of the network; Android and iOS answer, elsewhere
/// (the web, the desktops) nothing does.
abstract interface class NetworkMonitor {
  /// Null where the platform does not say.
  Future<NetworkState?> current();

  /// Each change, as the system announces it; empty where it does not.
  Stream<NetworkState> changes();
}

/// [NetworkMonitor] over the app's channels (`MainActivity.kt`,
/// `AppDelegate.swift`).
final class PlatformNetworkMonitor implements NetworkMonitor {
  const new();

  static const _channel = MethodChannel('lunaway/network');
  static const _events = EventChannel('lunaway/network/changes');

  // The system the app runs on, not the one a test poses as: a unit test on
  // a computer has no channel to answer.
  static bool get _answers => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<NetworkState?> current() async {
    if (!_answers) return null;
    try {
      return NetworkState.fromMap(await _channel.invokeMethod<Object?>('current'));
    } on PlatformException catch (e) {
      _log.info('the network state could not be read: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<NetworkState> changes() {
    if (!_answers) return const Stream.empty();
    return _events
        .receiveBroadcastStream()
        .map(NetworkState.fromMap)
        .where((s) => s != null)
        .cast<NetworkState>()
        .handleError((Object e) => _log.info('the network changes stopped: $e'));
  }
}

/// The platform's monitor; a fake in tests.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
NetworkMonitor networkMonitor(Ref ref) => const PlatformNetworkMonitor();

/// The network as the system last said; null until it says, and for good
/// where it never does (then nothing is held back for a metered network).
// keepAlive: the sync and the basemap's reachability read it for the run.
@Riverpod(keepAlive: true)
class DeviceNetwork extends _$DeviceNetwork {
  @override
  NetworkState? build() {
    final monitor = ref.watch(networkMonitorProvider);
    final changes = monitor.changes().listen((s) {
      if (s != stateOrNull) _log.info('the system says $s');
      state = s;
    });
    ref.onDispose(changes.cancel);
    unawaited(
      monitor.current().then((s) {
        // A change that came first is newer than this answer.
        if (ref.mounted && s != null && stateOrNull == null) state = s;
      }),
    );
    return null;
  }

  /// Reads the system again now: the change events of a platform can lag
  /// behind a switch the user just made.
  Future<NetworkState?> refresh() async {
    final s = await ref.read(networkMonitorProvider).current();
    if (ref.mounted && s != null) state = s;
    return s ?? stateOrNull;
  }
}
