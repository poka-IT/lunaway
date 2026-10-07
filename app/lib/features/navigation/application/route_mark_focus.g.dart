// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route_mark_focus.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The focus of the marks of the preview of [target].

@ProviderFor(RouteMarkFocus)
final routeMarkFocusProvider = RouteMarkFocusFamily._();

/// The focus of the marks of the preview of [target].
final class RouteMarkFocusProvider extends $NotifierProvider<RouteMarkFocus, MarkFocus> {
  /// The focus of the marks of the preview of [target].
  RouteMarkFocusProvider._({
    required RouteMarkFocusFamily super.from,
    required RouteTarget super.argument,
  }) : super(
         retry: null,
         name: r'routeMarkFocusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$routeMarkFocusHash();

  @override
  String toString() {
    return r'routeMarkFocusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RouteMarkFocus create() => RouteMarkFocus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MarkFocus value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<MarkFocus>(value));
  }

  @override
  bool operator ==(Object other) {
    return other is RouteMarkFocusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$routeMarkFocusHash() => r'811220afc60dd4c49eaa64a330c09235fafa24f1';

/// The focus of the marks of the preview of [target].

final class RouteMarkFocusFamily extends $Family
    with $ClassFamilyOverride<RouteMarkFocus, MarkFocus, MarkFocus, MarkFocus, RouteTarget> {
  RouteMarkFocusFamily._()
    : super(
        retry: null,
        name: r'routeMarkFocusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The focus of the marks of the preview of [target].

  RouteMarkFocusProvider call(RouteTarget target) =>
      RouteMarkFocusProvider._(argument: target, from: this);

  @override
  String toString() => r'routeMarkFocusProvider';
}

/// The focus of the marks of the preview of [target].

abstract class _$RouteMarkFocus extends $Notifier<MarkFocus> {
  late final _$args = ref.$arg as RouteTarget;
  RouteTarget get target => _$args;

  MarkFocus build(RouteTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MarkFocus, MarkFocus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MarkFocus, MarkFocus>,
              MarkFocus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
