// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_flow.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every change of what the map screen shows is asked of this one model,
/// whatever asks and in whichever layout: a pin, a row of a list, a search
/// result, a card's close, Escape, the system back, the browser's back or
/// forward, a link, the favourites, a page opened over the map or left. It
/// decides the change, keeps the way back, and has the tab's history
/// written by [MapHistory], the one writer.
///
/// A change that comes late is held to what happened since it began. A
/// tap on the map acts a moment after its press (it waits to know it is
/// no double tap), and a link is read before it opens: the user may have
/// opened something else meanwhile. Such a change carries the
/// [MapFlowState.revision] it began under (`since`) and is dropped when anything changed since:
/// it never undoes a newer action of the user.
// keepAlive: what is open stays through a switch to another tab and the
// pages over the map, as the history of the tab does.

@ProviderFor(MapFlow)
final mapFlowProvider = MapFlowProvider._();

/// Every change of what the map screen shows is asked of this one model,
/// whatever asks and in whichever layout: a pin, a row of a list, a search
/// result, a card's close, Escape, the system back, the browser's back or
/// forward, a link, the favourites, a page opened over the map or left. It
/// decides the change, keeps the way back, and has the tab's history
/// written by [MapHistory], the one writer.
///
/// A change that comes late is held to what happened since it began. A
/// tap on the map acts a moment after its press (it waits to know it is
/// no double tap), and a link is read before it opens: the user may have
/// opened something else meanwhile. Such a change carries the
/// [MapFlowState.revision] it began under (`since`) and is dropped when anything changed since:
/// it never undoes a newer action of the user.
// keepAlive: what is open stays through a switch to another tab and the
// pages over the map, as the history of the tab does.
final class MapFlowProvider extends $NotifierProvider<MapFlow, MapFlowState> {
  /// Every change of what the map screen shows is asked of this one model,
  /// whatever asks and in whichever layout: a pin, a row of a list, a search
  /// result, a card's close, Escape, the system back, the browser's back or
  /// forward, a link, the favourites, a page opened over the map or left. It
  /// decides the change, keeps the way back, and has the tab's history
  /// written by [MapHistory], the one writer.
  ///
  /// A change that comes late is held to what happened since it began. A
  /// tap on the map acts a moment after its press (it waits to know it is
  /// no double tap), and a link is read before it opens: the user may have
  /// opened something else meanwhile. Such a change carries the
  /// [MapFlowState.revision] it began under (`since`) and is dropped when anything changed since:
  /// it never undoes a newer action of the user.
  // keepAlive: what is open stays through a switch to another tab and the
  // pages over the map, as the history of the tab does.
  MapFlowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapFlowProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapFlowHash();

  @$internal
  @override
  MapFlow create() => MapFlow();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapFlowState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapFlowState>(value),
    );
  }
}

String _$mapFlowHash() => r'76b1659a30308c9d5f7c9c67380232a6482a8ef2';

/// Every change of what the map screen shows is asked of this one model,
/// whatever asks and in whichever layout: a pin, a row of a list, a search
/// result, a card's close, Escape, the system back, the browser's back or
/// forward, a link, the favourites, a page opened over the map or left. It
/// decides the change, keeps the way back, and has the tab's history
/// written by [MapHistory], the one writer.
///
/// A change that comes late is held to what happened since it began. A
/// tap on the map acts a moment after its press (it waits to know it is
/// no double tap), and a link is read before it opens: the user may have
/// opened something else meanwhile. Such a change carries the
/// [MapFlowState.revision] it began under (`since`) and is dropped when anything changed since:
/// it never undoes a newer action of the user.
// keepAlive: what is open stays through a switch to another tab and the
// pages over the map, as the history of the tab does.

abstract class _$MapFlow extends $Notifier<MapFlowState> {
  MapFlowState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MapFlowState, MapFlowState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MapFlowState, MapFlowState>,
              MapFlowState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// How many times the list of the places around was asked for
/// ([MapFlow.showPlacesAround]): a layout that folds its list away opens
/// it at each.
// keepAlive: a count of the run, which a layout built later must not take
// for a new request.

@ProviderFor(PlacesAroundAsked)
final placesAroundAskedProvider = PlacesAroundAskedProvider._();

/// How many times the list of the places around was asked for
/// ([MapFlow.showPlacesAround]): a layout that folds its list away opens
/// it at each.
// keepAlive: a count of the run, which a layout built later must not take
// for a new request.
final class PlacesAroundAskedProvider
    extends $NotifierProvider<PlacesAroundAsked, int> {
  /// How many times the list of the places around was asked for
  /// ([MapFlow.showPlacesAround]): a layout that folds its list away opens
  /// it at each.
  // keepAlive: a count of the run, which a layout built later must not take
  // for a new request.
  PlacesAroundAskedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placesAroundAskedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placesAroundAskedHash();

  @$internal
  @override
  PlacesAroundAsked create() => PlacesAroundAsked();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$placesAroundAskedHash() => r'83d24548797e29bc1a32ce97ce318d408621d413';

/// How many times the list of the places around was asked for
/// ([MapFlow.showPlacesAround]): a layout that folds its list away opens
/// it at each.
// keepAlive: a count of the run, which a layout built later must not take
// for a new request.

abstract class _$PlacesAroundAsked extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// What the map points at: a place, a point the user long-pressed or an
/// address the search found, or a point of interest; null for none. Read
/// only: it changes through [MapFlow].
// keepAlive: it follows the flow, itself kept.

@ProviderFor(selection)
final selectionProvider = SelectionProvider._();

/// What the map points at: a place, a point the user long-pressed or an
/// address the search found, or a point of interest; null for none. Read
/// only: it changes through [MapFlow].
// keepAlive: it follows the flow, itself kept.

final class SelectionProvider
    extends $FunctionalProvider<MapSelection?, MapSelection?, MapSelection?>
    with $Provider<MapSelection?> {
  /// What the map points at: a place, a point the user long-pressed or an
  /// address the search found, or a point of interest; null for none. Read
  /// only: it changes through [MapFlow].
  // keepAlive: it follows the flow, itself kept.
  SelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectionHash();

  @$internal
  @override
  $ProviderElement<MapSelection?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MapSelection? create(Ref ref) {
    return selection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapSelection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapSelection?>(value),
    );
  }
}

String _$selectionHash() => r'e15ee1ec0dbfe22f0d2bacb305a00118e11d8e4d';
