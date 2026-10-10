// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browser.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The browser the app runs in; null outside the web.
// keepAlive: the page lives as long as the app; its history and its network
// listeners are the page's own.

@ProviderFor(browser)
final browserProvider = BrowserProvider._();

/// The browser the app runs in; null outside the web.
// keepAlive: the page lives as long as the app; its history and its network
// listeners are the page's own.

final class BrowserProvider extends $FunctionalProvider<Browser?, Browser?, Browser?>
    with $Provider<Browser?> {
  /// The browser the app runs in; null outside the web.
  // keepAlive: the page lives as long as the app; its history and its network
  // listeners are the page's own.
  BrowserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserHash();

  @$internal
  @override
  $ProviderElement<Browser?> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  Browser? create(Ref ref) {
    return browser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Browser? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<Browser?>(value));
  }
}

String _$browserHash() => r'713b4976a19a3d464c6fd570f4ccea85e94b206e';
