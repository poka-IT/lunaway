// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guidance_camera.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The guidance map's camera mode: following by default; free as soon as
/// the user moves the map; the whole route on demand. Back to following on
/// "Recentrer", by the magnet, or after [FreeMap.idleReturn] without a
/// touch while the vehicle drives, never while a finger, the mouse or a
/// card opened from the map holds it.
///
/// The guidance itself (instructions, voice, new routes) does not read it:
/// it runs the same whatever the map shows.

@ProviderFor(GuidanceCamera)
final guidanceCameraProvider = GuidanceCameraProvider._();

/// The guidance map's camera mode: following by default; free as soon as
/// the user moves the map; the whole route on demand. Back to following on
/// "Recentrer", by the magnet, or after [FreeMap.idleReturn] without a
/// touch while the vehicle drives, never while a finger, the mouse or a
/// card opened from the map holds it.
///
/// The guidance itself (instructions, voice, new routes) does not read it:
/// it runs the same whatever the map shows.
final class GuidanceCameraProvider extends $NotifierProvider<GuidanceCamera, GuidanceView> {
  /// The guidance map's camera mode: following by default; free as soon as
  /// the user moves the map; the whole route on demand. Back to following on
  /// "Recentrer", by the magnet, or after [FreeMap.idleReturn] without a
  /// touch while the vehicle drives, never while a finger, the mouse or a
  /// card opened from the map holds it.
  ///
  /// The guidance itself (instructions, voice, new routes) does not read it:
  /// it runs the same whatever the map shows.
  GuidanceCameraProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceCameraProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceCameraHash();

  @$internal
  @override
  GuidanceCamera create() => GuidanceCamera();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GuidanceView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GuidanceView>(value),
    );
  }
}

String _$guidanceCameraHash() => r'e167157f09141523bfaeb075798e78fb46f834dc';

/// The guidance map's camera mode: following by default; free as soon as
/// the user moves the map; the whole route on demand. Back to following on
/// "Recentrer", by the magnet, or after [FreeMap.idleReturn] without a
/// touch while the vehicle drives, never while a finger, the mouse or a
/// card opened from the map holds it.
///
/// The guidance itself (instructions, voice, new routes) does not read it:
/// it runs the same whatever the map shows.

abstract class _$GuidanceCamera extends $Notifier<GuidanceView> {
  GuidanceView build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GuidanceView, GuidanceView>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GuidanceView, GuidanceView>,
              GuidanceView,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
