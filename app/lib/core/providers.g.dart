// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appConfig)
final appConfigProvider = AppConfigProvider._();

final class AppConfigProvider extends $FunctionalProvider<AppConfig, AppConfig, AppConfig>
    with $Provider<AppConfig> {
  AppConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appConfigHash();

  @$internal
  @override
  $ProviderElement<AppConfig> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  AppConfig create(Ref ref) {
    return appConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppConfig value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<AppConfig>(value));
  }
}

String _$appConfigHash() => r'87f9d20a2d92252672162b2ce97547b7b2479239';

/// The version string of the running app, overridden in `main` from the
/// platform; the default serves tests.
// keepAlive: a constant of the run, read by every outbound request.

@ProviderFor(appVersion)
final appVersionProvider = AppVersionProvider._();

/// The version string of the running app, overridden in `main` from the
/// platform; the default serves tests.
// keepAlive: a constant of the run, read by every outbound request.

final class AppVersionProvider extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The version string of the running app, overridden in `main` from the
  /// platform; the default serves tests.
  // keepAlive: a constant of the run, read by every outbound request.
  AppVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appVersionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appVersionHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return appVersion(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<String>(value));
  }
}

String _$appVersionHash() => r'c67afb04e42493484a674ffaa09eeb0e35add300';

@ProviderFor(cacheDatabase)
final cacheDatabaseProvider = CacheDatabaseProvider._();

final class CacheDatabaseProvider
    extends $FunctionalProvider<CacheDatabase, CacheDatabase, CacheDatabase>
    with $Provider<CacheDatabase> {
  CacheDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cacheDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cacheDatabaseHash();

  @$internal
  @override
  $ProviderElement<CacheDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CacheDatabase create(Ref ref) {
    return cacheDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CacheDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CacheDatabase>(value),
    );
  }
}

String _$cacheDatabaseHash() => r'bfee7ee9b7fa9c33709b0b88e0d8324412e30f00';

@ProviderFor(userDatabase)
final userDatabaseProvider = UserDatabaseProvider._();

final class UserDatabaseProvider
    extends $FunctionalProvider<UserDatabase, UserDatabase, UserDatabase>
    with $Provider<UserDatabase> {
  UserDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userDatabaseHash();

  @$internal
  @override
  $ProviderElement<UserDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UserDatabase create(Ref ref) {
    return userDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserDatabase>(value),
    );
  }
}

String _$userDatabaseHash() => r'03f4ae5f178a9345e97fc48ffdc852a1adcbc1e7';

@ProviderFor(httpClient)
final httpClientProvider = HttpClientProvider._();

final class HttpClientProvider extends $FunctionalProvider<http.Client, http.Client, http.Client>
    with $Provider<http.Client> {
  HttpClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'httpClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$httpClientHash();

  @$internal
  @override
  $ProviderElement<http.Client> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  http.Client create(Ref ref) {
    return httpClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(http.Client value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<http.Client>(value),
    );
  }
}

String _$httpClientHash() => r'7ec49beae0f15115de79f9aa98dbd250130e26d8';

@ProviderFor(userAgent)
final userAgentProvider = UserAgentProvider._();

final class UserAgentProvider extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  UserAgentProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userAgentProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userAgentHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return userAgent(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<String>(value));
  }
}

String _$userAgentHash() => r'cd5d351cc762fa1b7d16fa007dcdad9ebe9c01b8';

/// Downloads the photos of the API's image proxy.
// keepAlive: a stateless service over the shared client.

@ProviderFor(imageFetcher)
final imageFetcherProvider = ImageFetcherProvider._();

/// Downloads the photos of the API's image proxy.
// keepAlive: a stateless service over the shared client.

final class ImageFetcherProvider
    extends $FunctionalProvider<ImageFetcher, ImageFetcher, ImageFetcher>
    with $Provider<ImageFetcher> {
  /// Downloads the photos of the API's image proxy.
  // keepAlive: a stateless service over the shared client.
  ImageFetcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'imageFetcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$imageFetcherHash();

  @$internal
  @override
  $ProviderElement<ImageFetcher> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ImageFetcher create(Ref ref) {
    return imageFetcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImageFetcher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImageFetcher>(value),
    );
  }
}

String _$imageFetcherHash() => r'ffd7fa49c64a0acf7cf81764cc33bca2ff064653';

/// The clock, injectable so freshness and "open now" are testable.
// keepAlive: a pure function with no state to release.

@ProviderFor(clock)
final clockProvider = ClockProvider._();

/// The clock, injectable so freshness and "open now" are testable.
// keepAlive: a pure function with no state to release.

final class ClockProvider
    extends $FunctionalProvider<DateTime Function(), DateTime Function(), DateTime Function()>
    with $Provider<DateTime Function()> {
  /// The clock, injectable so freshness and "open now" are testable.
  // keepAlive: a pure function with no state to release.
  ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$clockHash() => r'3f65ad34ac6fcd532de9004042bdf2ed2bd85b13';

/// The current time, emitted again at the start of every minute: what a
/// screen showing "open now" or "updated 3 days ago" watches, so the text
/// turns over without a rebuild from elsewhere.

@ProviderFor(minuteClock)
final minuteClockProvider = MinuteClockProvider._();

/// The current time, emitted again at the start of every minute: what a
/// screen showing "open now" or "updated 3 days ago" watches, so the text
/// turns over without a rebuild from elsewhere.

final class MinuteClockProvider
    extends $FunctionalProvider<AsyncValue<DateTime>, DateTime, Stream<DateTime>>
    with $FutureModifier<DateTime>, $StreamProvider<DateTime> {
  /// The current time, emitted again at the start of every minute: what a
  /// screen showing "open now" or "updated 3 days ago" watches, so the text
  /// turns over without a rebuild from elsewhere.
  MinuteClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'minuteClockProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$minuteClockHash();

  @$internal
  @override
  $StreamProviderElement<DateTime> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<DateTime> create(Ref ref) {
    return minuteClock(ref);
  }
}

String _$minuteClockHash() => r'b9558187e9778bf64fc9526ff4efb62b0e11e28d';

@ProviderFor(minuteTicker)
final minuteTickerProvider = MinuteTickerProvider._();

final class MinuteTickerProvider
    extends $FunctionalProvider<MinuteTicker, MinuteTicker, MinuteTicker>
    with $Provider<MinuteTicker> {
  MinuteTickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'minuteTickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$minuteTickerHash();

  @$internal
  @override
  $ProviderElement<MinuteTicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MinuteTicker create(Ref ref) {
    return minuteTicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MinuteTicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MinuteTicker>(value),
    );
  }
}

String _$minuteTickerHash() => r'74a97970bd2bc28580ef6f6caf167ec4e571cd81';
