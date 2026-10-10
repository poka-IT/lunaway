// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_credit_fold.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the maps' credit has folded into its mark this run.
///
/// The OpenStreetMap Foundation's attribution guidelines (adopted
/// 2021-06-25) let an interactive map's credit collapse "automatically on
/// map interaction such as panning, clicking, or zooming" or "automatically
/// after five seconds", the licence then found from "an '(i)' button in the
/// corner of the map"; and "if attribution is presented to the user upon
/// application startup, it does not need to be presented to the user every
/// time". So the first map shows "© OpenStreetMap" in full, and once it has
/// folded every map after it (the preview, the guidance, the placement)
/// shows the mark alone (`MapCredit`).
// keepAlive: the credit shown once in the run stands for every map opened
// after it, whichever screen holds it.

@ProviderFor(MapCreditFolded)
final mapCreditFoldedProvider = MapCreditFoldedProvider._();

/// Whether the maps' credit has folded into its mark this run.
///
/// The OpenStreetMap Foundation's attribution guidelines (adopted
/// 2021-06-25) let an interactive map's credit collapse "automatically on
/// map interaction such as panning, clicking, or zooming" or "automatically
/// after five seconds", the licence then found from "an '(i)' button in the
/// corner of the map"; and "if attribution is presented to the user upon
/// application startup, it does not need to be presented to the user every
/// time". So the first map shows "© OpenStreetMap" in full, and once it has
/// folded every map after it (the preview, the guidance, the placement)
/// shows the mark alone (`MapCredit`).
// keepAlive: the credit shown once in the run stands for every map opened
// after it, whichever screen holds it.
final class MapCreditFoldedProvider
    extends $NotifierProvider<MapCreditFolded, bool> {
  /// Whether the maps' credit has folded into its mark this run.
  ///
  /// The OpenStreetMap Foundation's attribution guidelines (adopted
  /// 2021-06-25) let an interactive map's credit collapse "automatically on
  /// map interaction such as panning, clicking, or zooming" or "automatically
  /// after five seconds", the licence then found from "an '(i)' button in the
  /// corner of the map"; and "if attribution is presented to the user upon
  /// application startup, it does not need to be presented to the user every
  /// time". So the first map shows "© OpenStreetMap" in full, and once it has
  /// folded every map after it (the preview, the guidance, the placement)
  /// shows the mark alone (`MapCredit`).
  // keepAlive: the credit shown once in the run stands for every map opened
  // after it, whichever screen holds it.
  MapCreditFoldedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapCreditFoldedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapCreditFoldedHash();

  @$internal
  @override
  MapCreditFolded create() => MapCreditFolded();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$mapCreditFoldedHash() => r'80611153df17a8d224b7838c88b83ae7e4dbf80b';

/// Whether the maps' credit has folded into its mark this run.
///
/// The OpenStreetMap Foundation's attribution guidelines (adopted
/// 2021-06-25) let an interactive map's credit collapse "automatically on
/// map interaction such as panning, clicking, or zooming" or "automatically
/// after five seconds", the licence then found from "an '(i)' button in the
/// corner of the map"; and "if attribution is presented to the user upon
/// application startup, it does not need to be presented to the user every
/// time". So the first map shows "© OpenStreetMap" in full, and once it has
/// folded every map after it (the preview, the guidance, the placement)
/// shows the mark alone (`MapCredit`).
// keepAlive: the credit shown once in the run stands for every map opened
// after it, whichever screen holds it.

abstract class _$MapCreditFolded extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
