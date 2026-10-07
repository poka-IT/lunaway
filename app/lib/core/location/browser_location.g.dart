// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browser_location.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The browser's position on the web; null on the other platforms, which
/// ask the system through their own permission flow.
// keepAlive: a stateless gateway to the browser for the whole run.

@ProviderFor(browserLocation)
final browserLocationProvider = BrowserLocationProvider._();

/// The browser's position on the web; null on the other platforms, which
/// ask the system through their own permission flow.
// keepAlive: a stateless gateway to the browser for the whole run.

final class BrowserLocationProvider
    extends
        $FunctionalProvider<
          BrowserLocation?,
          BrowserLocation?,
          BrowserLocation?
        >
    with $Provider<BrowserLocation?> {
  /// The browser's position on the web; null on the other platforms, which
  /// ask the system through their own permission flow.
  // keepAlive: a stateless gateway to the browser for the whole run.
  BrowserLocationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserLocationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserLocationHash();

  @$internal
  @override
  $ProviderElement<BrowserLocation?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BrowserLocation? create(Ref ref) {
    return browserLocation(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserLocation? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserLocation?>(value),
    );
  }
}

String _$browserLocationHash() => r'cfc78bf5c3745d30d393c6b57f272912250041f0';
