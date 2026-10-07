// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(settingsRepository)
final settingsRepositoryProvider = SettingsRepositoryProvider._();

final class SettingsRepositoryProvider
    extends $FunctionalProvider<SettingsStore, SettingsStore, SettingsStore>
    with $Provider<SettingsStore> {
  SettingsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsRepositoryHash();

  @$internal
  @override
  $ProviderElement<SettingsStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsStore create(Ref ref) {
    return settingsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsStore>(value),
    );
  }
}

String _$settingsRepositoryHash() => r'cc0cb4ad99601984dfe0db3bc77e2de8a0641dfe';

/// The settings as read before the first frame, overridden in `main`, so the
/// app never flashes a default language, theme or filter.
// keepAlive: a constant of the run.

@ProviderFor(initialSettings)
final initialSettingsProvider = InitialSettingsProvider._();

/// The settings as read before the first frame, overridden in `main`, so the
/// app never flashes a default language, theme or filter.
// keepAlive: a constant of the run.

final class InitialSettingsProvider
    extends $FunctionalProvider<AppSettings, AppSettings, AppSettings>
    with $Provider<AppSettings> {
  /// The settings as read before the first frame, overridden in `main`, so the
  /// app never flashes a default language, theme or filter.
  // keepAlive: a constant of the run.
  InitialSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'initialSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$initialSettingsHash();

  @$internal
  @override
  $ProviderElement<AppSettings> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppSettings create(Ref ref) {
    return initialSettings(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSettings>(value),
    );
  }
}

String _$initialSettingsHash() => r'0ee52d46bb01b76efc2bfb545a6b92daac0db17e';

/// The user's settings: the state changes at once, the write follows.
// keepAlive: the settings shape every screen for the whole run.

@ProviderFor(Settings)
final settingsProvider = SettingsProvider._();

/// The user's settings: the state changes at once, the write follows.
// keepAlive: the settings shape every screen for the whole run.
final class SettingsProvider extends $NotifierProvider<Settings, AppSettings> {
  /// The user's settings: the state changes at once, the write follows.
  // keepAlive: the settings shape every screen for the whole run.
  SettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsHash();

  @$internal
  @override
  Settings create() => Settings();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSettings>(value),
    );
  }
}

String _$settingsHash() => r'45bb3844930d5265a43fb1c3783fab97a6c3ae36';

/// The user's settings: the state changes at once, the write follows.
// keepAlive: the settings shape every screen for the whole run.

abstract class _$Settings extends $Notifier<AppSettings> {
  AppSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppSettings, AppSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppSettings, AppSettings>,
              AppSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The user's place filter, a slice of the settings. Screens query with
/// `effectiveFilterProvider`, which adds the vehicle's size.

@ProviderFor(placeFilter)
final placeFilterProvider = PlaceFilterProvider._();

/// The user's place filter, a slice of the settings. Screens query with
/// `effectiveFilterProvider`, which adds the vehicle's size.

final class PlaceFilterProvider extends $FunctionalProvider<PlaceFilter, PlaceFilter, PlaceFilter>
    with $Provider<PlaceFilter> {
  /// The user's place filter, a slice of the settings. Screens query with
  /// `effectiveFilterProvider`, which adds the vehicle's size.
  PlaceFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placeFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeFilterHash();

  @$internal
  @override
  $ProviderElement<PlaceFilter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaceFilter create(Ref ref) {
    return placeFilter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaceFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaceFilter>(value),
    );
  }
}

String _$placeFilterHash() => r'fb0dbfabe2a5d689e85096a96543b5c525ef5473';
