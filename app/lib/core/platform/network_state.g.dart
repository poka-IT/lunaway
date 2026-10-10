// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The platform's monitor; a fake in tests.
// keepAlive: stateless, wired once.

@ProviderFor(networkMonitor)
final networkMonitorProvider = NetworkMonitorProvider._();

/// The platform's monitor; a fake in tests.
// keepAlive: stateless, wired once.

final class NetworkMonitorProvider
    extends $FunctionalProvider<NetworkMonitor, NetworkMonitor, NetworkMonitor>
    with $Provider<NetworkMonitor> {
  /// The platform's monitor; a fake in tests.
  // keepAlive: stateless, wired once.
  NetworkMonitorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'networkMonitorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$networkMonitorHash();

  @$internal
  @override
  $ProviderElement<NetworkMonitor> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NetworkMonitor create(Ref ref) {
    return networkMonitor(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NetworkMonitor value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NetworkMonitor>(value),
    );
  }
}

String _$networkMonitorHash() => r'70f6b00266d29332a5566f3489466c1b01fc8852';

/// The network as the system last said; null until it says, and for good
/// where it never does (then nothing is held back for a metered network).
// keepAlive: the sync and the basemap's reachability read it for the run.

@ProviderFor(DeviceNetwork)
final deviceNetworkProvider = DeviceNetworkProvider._();

/// The network as the system last said; null until it says, and for good
/// where it never does (then nothing is held back for a metered network).
// keepAlive: the sync and the basemap's reachability read it for the run.
final class DeviceNetworkProvider extends $NotifierProvider<DeviceNetwork, NetworkState?> {
  /// The network as the system last said; null until it says, and for good
  /// where it never does (then nothing is held back for a metered network).
  // keepAlive: the sync and the basemap's reachability read it for the run.
  DeviceNetworkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceNetworkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceNetworkHash();

  @$internal
  @override
  DeviceNetwork create() => DeviceNetwork();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NetworkState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NetworkState?>(value),
    );
  }
}

String _$deviceNetworkHash() => r'aeb5ce0a7c081f6e6ef28e54d7379f732bf3122c';

/// The network as the system last said; null until it says, and for good
/// where it never does (then nothing is held back for a metered network).
// keepAlive: the sync and the basemap's reachability read it for the run.

abstract class _$DeviceNetwork extends $Notifier<NetworkState?> {
  NetworkState? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<NetworkState?, NetworkState?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NetworkState?, NetworkState?>,
              NetworkState?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
