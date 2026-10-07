// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'popup_routes.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How many dialogs, sheets and menus are open over the screens, across the
/// app's navigators. The web map reads it: its HTML element would otherwise
/// take the clicks and the wheel meant for what lies over it.
// keepAlive: the navigators push and pop for the whole run; a count that
// reset while nothing watched it would be wrong when the map came back.

@ProviderFor(OpenPopups)
final openPopupsProvider = OpenPopupsProvider._();

/// How many dialogs, sheets and menus are open over the screens, across the
/// app's navigators. The web map reads it: its HTML element would otherwise
/// take the clicks and the wheel meant for what lies over it.
// keepAlive: the navigators push and pop for the whole run; a count that
// reset while nothing watched it would be wrong when the map came back.
final class OpenPopupsProvider extends $NotifierProvider<OpenPopups, int> {
  /// How many dialogs, sheets and menus are open over the screens, across the
  /// app's navigators. The web map reads it: its HTML element would otherwise
  /// take the clicks and the wheel meant for what lies over it.
  // keepAlive: the navigators push and pop for the whole run; a count that
  // reset while nothing watched it would be wrong when the map came back.
  OpenPopupsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'openPopupsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$openPopupsHash();

  @$internal
  @override
  OpenPopups create() => OpenPopups();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<int>(value));
  }
}

String _$openPopupsHash() => r'44dcdda692b2cdbc30738291c42f33f8c02bc7d9';

/// How many dialogs, sheets and menus are open over the screens, across the
/// app's navigators. The web map reads it: its HTML element would otherwise
/// take the clicks and the wheel meant for what lies over it.
// keepAlive: the navigators push and pop for the whole run; a count that
// reset while nothing watched it would be wrong when the map came back.

abstract class _$OpenPopups extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element as $ClassProviderElement<AnyNotifier<int, int>, int, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
