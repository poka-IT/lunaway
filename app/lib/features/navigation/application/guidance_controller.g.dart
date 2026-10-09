// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guidance_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The guidance: the engine fed with each fix, the spoken instructions, the
/// recalculation when the vehicle leaves the route or a road event closes
/// it ahead.
// keepAlive: the guidance runs while the screen is off and the app in the
// background; it ends only through stop().

@ProviderFor(GuidanceController)
final guidanceControllerProvider = GuidanceControllerProvider._();

/// The guidance: the engine fed with each fix, the spoken instructions, the
/// recalculation when the vehicle leaves the route or a road event closes
/// it ahead.
// keepAlive: the guidance runs while the screen is off and the app in the
// background; it ends only through stop().
final class GuidanceControllerProvider
    extends $NotifierProvider<GuidanceController, GuidanceSession?> {
  /// The guidance: the engine fed with each fix, the spoken instructions, the
  /// recalculation when the vehicle leaves the route or a road event closes
  /// it ahead.
  // keepAlive: the guidance runs while the screen is off and the app in the
  // background; it ends only through stop().
  GuidanceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceControllerHash();

  @$internal
  @override
  GuidanceController create() => GuidanceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GuidanceSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GuidanceSession?>(value),
    );
  }
}

String _$guidanceControllerHash() =>
    r'648faafa9307393f3368a2729bdf7709ce516721';

/// The guidance: the engine fed with each fix, the spoken instructions, the
/// recalculation when the vehicle leaves the route or a road event closes
/// it ahead.
// keepAlive: the guidance runs while the screen is off and the app in the
// background; it ends only through stop().

abstract class _$GuidanceController extends $Notifier<GuidanceSession?> {
  GuidanceSession? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GuidanceSession?, GuidanceSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GuidanceSession?, GuidanceSession?>,
              GuidanceSession?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
