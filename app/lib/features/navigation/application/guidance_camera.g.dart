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
/// route (the distance driven plus the distance to it, read to 5 m) holds
/// while the vehicle drives toward it.

@ProviderFor(guidanceArrow)
final guidanceArrowProvider = GuidanceArrowProvider._();

/// The arrow the guidance map draws on the route at the next maneuver
/// ([arrowForManeuver]); none off the route, while a new one is sought or
/// at the arrival. Worked out once per maneuver: where it lies along the
/// route (the distance driven plus the distance to it, read to 5 m) holds
/// while the vehicle drives toward it.

final class GuidanceArrowProvider
    extends $FunctionalProvider<ManeuverArrow?, ManeuverArrow?, ManeuverArrow?>
    with $Provider<ManeuverArrow?> {
  /// The arrow the guidance map draws on the route at the next maneuver
  /// ([arrowForManeuver]); none off the route, while a new one is sought or
  /// at the arrival. Worked out once per maneuver: where it lies along the
  /// route (the distance driven plus the distance to it, read to 5 m) holds
  /// while the vehicle drives toward it.
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

String _$guidanceArrowHash() => r'6c35c80d08241f841c0126aeaf63f1d7e352edb7';

/// The zoom the guidance map aims at while it follows ([autoZoom]): the
/// speed held through [SpeedHold], so a GPS speed that wavers does not make
/// the view breathe, and the next maneuver's distance and kind, so the
/// camera closes in before a turn and widens down a long straight. The
/// engines ease toward it at each frame of the glide.

@ProviderFor(GuidanceZoom)
final guidanceZoomProvider = GuidanceZoomProvider._();

/// The zoom the guidance map aims at while it follows ([autoZoom]): the
/// speed held through [SpeedHold], so a GPS speed that wavers does not make
/// the view breathe, and the next maneuver's distance and kind, so the
/// camera closes in before a turn and widens down a long straight. The
/// engines ease toward it at each frame of the glide.
final class GuidanceZoomProvider
    extends $NotifierProvider<GuidanceZoom, double> {
  /// The zoom the guidance map aims at while it follows ([autoZoom]): the
  /// speed held through [SpeedHold], so a GPS speed that wavers does not make
  /// the view breathe, and the next maneuver's distance and kind, so the
  /// camera closes in before a turn and widens down a long straight. The
  /// engines ease toward it at each frame of the glide.
  GuidanceZoomProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceZoomProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceZoomHash();

  @$internal
  @override
  GuidanceZoom create() => GuidanceZoom();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$guidanceZoomHash() => r'd519c8153123cf804683e8a1eebcfeef88ebf069';

/// The zoom the guidance map aims at while it follows ([autoZoom]): the
/// speed held through [SpeedHold], so a GPS speed that wavers does not make
/// the view breathe, and the next maneuver's distance and kind, so the
/// camera closes in before a turn and widens down a long straight. The
/// engines ease toward it at each frame of the glide.

abstract class _$GuidanceZoom extends $Notifier<double> {
  double build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<double, double>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<double, double>,
              double,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
