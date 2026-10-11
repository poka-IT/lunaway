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
final class GuidanceCameraProvider
    extends $NotifierProvider<GuidanceCamera, GuidanceView> {
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

/// The arrow the guidance map draws on the route at the next maneuver
/// ([arrowForManeuver]); none off the route, while a new one is sought or
/// at the arrival. Worked out once per maneuver: where it lies along the
/// route, the distance driven plus the distance to it, is the same at
/// every fix of a step (read to the metre, so a rounding of the engine's
/// sum changes nothing unless the sum falls on a half metre), and a fix
/// that wanders, parked, neither moves it nor redraws the map.

@ProviderFor(guidanceArrow)
final guidanceArrowProvider = GuidanceArrowProvider._();

/// The arrow the guidance map draws on the route at the next maneuver
/// ([arrowForManeuver]); none off the route, while a new one is sought or
/// at the arrival. Worked out once per maneuver: where it lies along the
/// route, the distance driven plus the distance to it, is the same at
/// every fix of a step (read to the metre, so a rounding of the engine's
/// sum changes nothing unless the sum falls on a half metre), and a fix
/// that wanders, parked, neither moves it nor redraws the map.

final class GuidanceArrowProvider
    extends $FunctionalProvider<ManeuverArrow?, ManeuverArrow?, ManeuverArrow?>
    with $Provider<ManeuverArrow?> {
  /// The arrow the guidance map draws on the route at the next maneuver
  /// ([arrowForManeuver]); none off the route, while a new one is sought or
  /// at the arrival. Worked out once per maneuver: where it lies along the
  /// route, the distance driven plus the distance to it, is the same at
  /// every fix of a step (read to the metre, so a rounding of the engine's
  /// sum changes nothing unless the sum falls on a half metre), and a fix
  /// that wanders, parked, neither moves it nor redraws the map.
  GuidanceArrowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceArrowProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceArrowHash();

  @$internal
  @override
  $ProviderElement<ManeuverArrow?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ManeuverArrow? create(Ref ref) {
    return guidanceArrow(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ManeuverArrow? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ManeuverArrow?>(value),
    );
  }
}

String _$guidanceArrowHash() => r'ac3ce67473a6777e9b49636b11011277f7d69bbb';

/// The zoom and the tilt the guidance map aims at while it follows
/// ([autoAim]): the speed held through [SpeedHold], so a GPS speed that
/// wavers does not make the view breathe, and the next maneuver's distance
/// and kind, so the camera frames it, closer as it comes, flatter over a
/// junction, wider and toward the horizon down a long straight. The
/// engines ease toward it at each frame of the glide.

@ProviderFor(GuidanceAim)
final guidanceAimProvider = GuidanceAimProvider._();

/// The zoom and the tilt the guidance map aims at while it follows
/// ([autoAim]): the speed held through [SpeedHold], so a GPS speed that
/// wavers does not make the view breathe, and the next maneuver's distance
/// and kind, so the camera frames it, closer as it comes, flatter over a
/// junction, wider and toward the horizon down a long straight. The
/// engines ease toward it at each frame of the glide.
final class GuidanceAimProvider
    extends $NotifierProvider<GuidanceAim, CameraAim> {
  /// The zoom and the tilt the guidance map aims at while it follows
  /// ([autoAim]): the speed held through [SpeedHold], so a GPS speed that
  /// wavers does not make the view breathe, and the next maneuver's distance
  /// and kind, so the camera frames it, closer as it comes, flatter over a
  /// junction, wider and toward the horizon down a long straight. The
  /// engines ease toward it at each frame of the glide.
  GuidanceAimProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceAimProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceAimHash();

  @$internal
  @override
  GuidanceAim create() => GuidanceAim();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CameraAim value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CameraAim>(value),
    );
  }
}

String _$guidanceAimHash() => r'25966a2839f710d5a08d4fb5aca139528c063cab';

/// The zoom and the tilt the guidance map aims at while it follows
/// ([autoAim]): the speed held through [SpeedHold], so a GPS speed that
/// wavers does not make the view breathe, and the next maneuver's distance
/// and kind, so the camera frames it, closer as it comes, flatter over a
/// junction, wider and toward the horizon down a long straight. The
/// engines ease toward it at each frame of the glide.

abstract class _$GuidanceAim extends $Notifier<CameraAim> {
  CameraAim build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CameraAim, CameraAim>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CameraAim, CameraAim>,
              CameraAim,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
