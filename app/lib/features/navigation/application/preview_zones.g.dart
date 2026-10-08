// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preview_zones.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The danger zones the preview draws on [route], read from [origin], where
/// the device is: under the strictest rule of the countries around it, at
/// rest (a preview is read before setting off), only zones, only where the
/// zone's own country allows them. None where no country is known at the
/// device, the strictest reading. While a guidance runs, the vehicle's rule
/// while driving, which follows it across a border at once; before its
/// first fix and once arrived, that rule reads off, the strict side. The route's
/// countries leave the device, as at the start of a guidance; a position
/// never does (docs/speed-cameras.md).

@ProviderFor(previewZones)
final previewZonesProvider = PreviewZonesFamily._();

/// The danger zones the preview draws on [route], read from [origin], where
/// the device is: under the strictest rule of the countries around it, at
/// rest (a preview is read before setting off), only zones, only where the
/// zone's own country allows them. None where no country is known at the
/// device, the strictest reading. While a guidance runs, the vehicle's rule
/// while driving, which follows it across a border at once; before its
/// first fix and once arrived, that rule reads off, the strict side. The route's
/// countries leave the device, as at the start of a guidance; a position
/// never does (docs/speed-cameras.md).

final class PreviewZonesProvider
    extends
        $FunctionalProvider<
          AsyncValue<PreviewZones>,
          PreviewZones,
          FutureOr<PreviewZones>
        >
    with $FutureModifier<PreviewZones>, $FutureProvider<PreviewZones> {
  /// The danger zones the preview draws on [route], read from [origin], where
  /// the device is: under the strictest rule of the countries around it, at
  /// rest (a preview is read before setting off), only zones, only where the
  /// zone's own country allows them. None where no country is known at the
  /// device, the strictest reading. While a guidance runs, the vehicle's rule
  /// while driving, which follows it across a border at once; before its
  /// first fix and once arrived, that rule reads off, the strict side. The route's
  /// countries leave the device, as at the start of a guidance; a position
  /// never does (docs/speed-cameras.md).
  PreviewZonesProvider._({
    required PreviewZonesFamily super.from,
    required (RouteOption, LatLng) super.argument,
  }) : super(
         retry: null,
         name: r'previewZonesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$previewZonesHash();

  @override
  String toString() {
    return r'previewZonesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<PreviewZones> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PreviewZones> create(Ref ref) {
    final argument = this.argument as (RouteOption, LatLng);
    return previewZones(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is PreviewZonesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$previewZonesHash() => r'15f07059fe949f3b3589d7ea0b95bc65cd3269f3';

/// The danger zones the preview draws on [route], read from [origin], where
/// the device is: under the strictest rule of the countries around it, at
/// rest (a preview is read before setting off), only zones, only where the
/// zone's own country allows them. None where no country is known at the
/// device, the strictest reading. While a guidance runs, the vehicle's rule
/// while driving, which follows it across a border at once; before its
/// first fix and once arrived, that rule reads off, the strict side. The route's
/// countries leave the device, as at the start of a guidance; a position
/// never does (docs/speed-cameras.md).

final class PreviewZonesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<PreviewZones>,
          (RouteOption, LatLng)
        > {
  PreviewZonesFamily._()
    : super(
        retry: null,
        name: r'previewZonesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The danger zones the preview draws on [route], read from [origin], where
  /// the device is: under the strictest rule of the countries around it, at
  /// rest (a preview is read before setting off), only zones, only where the
  /// zone's own country allows them. None where no country is known at the
  /// device, the strictest reading. While a guidance runs, the vehicle's rule
  /// while driving, which follows it across a border at once; before its
  /// first fix and once arrived, that rule reads off, the strict side. The route's
  /// countries leave the device, as at the start of a guidance; a position
  /// never does (docs/speed-cameras.md).

  PreviewZonesProvider call(RouteOption route, LatLng origin) =>
      PreviewZonesProvider._(argument: (route, origin), from: this);

  @override
  String toString() => r'previewZonesProvider';
}
