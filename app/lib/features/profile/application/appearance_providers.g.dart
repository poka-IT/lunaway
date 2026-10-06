// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The device's UTC offset without summer time: the fallback the automatic
/// theme uses before any position is known.
// keepAlive: a constant of the run (the time zone does not change under a
// running app often enough to matter for a theme).

@ProviderFor(standardOffset)
final standardOffsetProvider = StandardOffsetProvider._();

/// The device's UTC offset without summer time: the fallback the automatic
/// theme uses before any position is known.
// keepAlive: a constant of the run (the time zone does not change under a
// running app often enough to matter for a theme).

final class StandardOffsetProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// The device's UTC offset without summer time: the fallback the automatic
  /// theme uses before any position is known.
  // keepAlive: a constant of the run (the time zone does not change under a
  // running app often enough to matter for a theme).
  StandardOffsetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'standardOffsetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$standardOffsetHash();

  @$internal
  @override
  $ProviderElement<Duration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration create(Ref ref) {
    return standardOffset(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$standardOffsetHash() => r'f92f218c291c8414c403c415db954d46902914db';

/// Light or dark, now: the user's choice, or the sun at the last known
/// position. Re-evaluated every minute, so the map darkens at sunset.

@ProviderFor(appBrightness)
final appBrightnessProvider = AppBrightnessProvider._();

/// Light or dark, now: the user's choice, or the sun at the last known
/// position. Re-evaluated every minute, so the map darkens at sunset.

final class AppBrightnessProvider
    extends $FunctionalProvider<Brightness, Brightness, Brightness>
    with $Provider<Brightness> {
  /// Light or dark, now: the user's choice, or the sun at the last known
  /// position. Re-evaluated every minute, so the map darkens at sunset.
  AppBrightnessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appBrightnessProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appBrightnessHash();

  @$internal
  @override
  $ProviderElement<Brightness> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Brightness create(Ref ref) {
    return appBrightness(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Brightness value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Brightness>(value),
    );
  }
}

String _$appBrightnessHash() => r'2b05d3fe1424553320e4737ca29def6a7bb497e3';
