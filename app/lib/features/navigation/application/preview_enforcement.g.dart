// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preview_enforcement.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// What the preview draws on [route], read from [device], where the device
/// is (never a start chosen elsewhere): under the strictest rule of the
/// countries around it, once the user's choices apply, the same at rest as
/// while driving (Germany's rule shows nothing: a stop at a light counts
/// as driving there). The zones where the zone's own country allows them;
/// the cameras where the rule at the device shows points and the camera's
/// own country does too. Nothing where no country is known at the device,
/// the strictest reading. While a guidance runs, the vehicle's rule, which
/// follows it across a border at once; before its first fix and once
/// arrived, that rule reads off, the strict side. The route's countries
/// leave the device, as at the start of a guidance; a position never does
/// (docs/speed-cameras.md).

@ProviderFor(previewEnforcement)
final previewEnforcementProvider = PreviewEnforcementFamily._();

/// What the preview draws on [route], read from [device], where the device
/// is (never a start chosen elsewhere): under the strictest rule of the
/// countries around it, once the user's choices apply, the same at rest as
/// while driving (Germany's rule shows nothing: a stop at a light counts
/// as driving there). The zones where the zone's own country allows them;
/// the cameras where the rule at the device shows points and the camera's
/// own country does too. Nothing where no country is known at the device,
/// the strictest reading. While a guidance runs, the vehicle's rule, which
/// follows it across a border at once; before its first fix and once
/// arrived, that rule reads off, the strict side. The route's countries
/// leave the device, as at the start of a guidance; a position never does
/// (docs/speed-cameras.md).

final class PreviewEnforcementProvider
    extends
        $FunctionalProvider<
          AsyncValue<PreviewEnforcement>,
          PreviewEnforcement,
          FutureOr<PreviewEnforcement>
        >
    with
        $FutureModifier<PreviewEnforcement>,
        $FutureProvider<PreviewEnforcement> {
  /// What the preview draws on [route], read from [device], where the device
  /// is (never a start chosen elsewhere): under the strictest rule of the
  /// countries around it, once the user's choices apply, the same at rest as
  /// while driving (Germany's rule shows nothing: a stop at a light counts
  /// as driving there). The zones where the zone's own country allows them;
  /// the cameras where the rule at the device shows points and the camera's
  /// own country does too. Nothing where no country is known at the device,
  /// the strictest reading. While a guidance runs, the vehicle's rule, which
  /// follows it across a border at once; before its first fix and once
  /// arrived, that rule reads off, the strict side. The route's countries
  /// leave the device, as at the start of a guidance; a position never does
  /// (docs/speed-cameras.md).
  PreviewEnforcementProvider._({
    required PreviewEnforcementFamily super.from,
    required (RouteOption, LatLng) super.argument,
  }) : super(
         retry: null,
         name: r'previewEnforcementProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$previewEnforcementHash();

  @override
  String toString() {
    return r'previewEnforcementProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<PreviewEnforcement> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PreviewEnforcement> create(Ref ref) {
    final argument = this.argument as (RouteOption, LatLng);
    return previewEnforcement(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is PreviewEnforcementProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$previewEnforcementHash() =>
    r'b62474bfaa35bf3a1ba82f679cf479ee4af57a4b';

/// What the preview draws on [route], read from [device], where the device
/// is (never a start chosen elsewhere): under the strictest rule of the
/// countries around it, once the user's choices apply, the same at rest as
/// while driving (Germany's rule shows nothing: a stop at a light counts
/// as driving there). The zones where the zone's own country allows them;
/// the cameras where the rule at the device shows points and the camera's
/// own country does too. Nothing where no country is known at the device,
/// the strictest reading. While a guidance runs, the vehicle's rule, which
/// follows it across a border at once; before its first fix and once
/// arrived, that rule reads off, the strict side. The route's countries
/// leave the device, as at the start of a guidance; a position never does
/// (docs/speed-cameras.md).

final class PreviewEnforcementFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<PreviewEnforcement>,
          (RouteOption, LatLng)
        > {
  PreviewEnforcementFamily._()
    : super(
        retry: null,
        name: r'previewEnforcementProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What the preview draws on [route], read from [device], where the device
  /// is (never a start chosen elsewhere): under the strictest rule of the
  /// countries around it, once the user's choices apply, the same at rest as
  /// while driving (Germany's rule shows nothing: a stop at a light counts
  /// as driving there). The zones where the zone's own country allows them;
  /// the cameras where the rule at the device shows points and the camera's
  /// own country does too. Nothing where no country is known at the device,
  /// the strictest reading. While a guidance runs, the vehicle's rule, which
  /// follows it across a border at once; before its first fix and once
  /// arrived, that rule reads off, the strict side. The route's countries
  /// leave the device, as at the start of a guidance; a position never does
  /// (docs/speed-cameras.md).

  PreviewEnforcementProvider call(RouteOption route, LatLng device) =>
      PreviewEnforcementProvider._(argument: (route, device), from: this);

  @override
  String toString() => r'previewEnforcementProvider';
}
