// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'on_the_way_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Places and points of interest along a route, through the routing client,
/// which does not wait out a rate limit: the list says at once that the
/// server asks to wait.
// keepAlive: stateless, wired once.

@ProviderFor(onTheWaySource)
final onTheWaySourceProvider = OnTheWaySourceProvider._();

/// Places and points of interest along a route, through the routing client,
/// which does not wait out a rate limit: the list says at once that the
/// server asks to wait.
// keepAlive: stateless, wired once.

final class OnTheWaySourceProvider
    extends $FunctionalProvider<OnTheWaySource, OnTheWaySource, OnTheWaySource>
    with $Provider<OnTheWaySource> {
  /// Places and points of interest along a route, through the routing client,
  /// which does not wait out a rate limit: the list says at once that the
  /// server asks to wait.
  // keepAlive: stateless, wired once.
  OnTheWaySourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onTheWaySourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onTheWaySourceHash();

  @$internal
  @override
  $ProviderElement<OnTheWaySource> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OnTheWaySource create(Ref ref) {
    return onTheWaySource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnTheWaySource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnTheWaySource>(value),
    );
  }
}

String _$onTheWaySourceHash() => r'325da58ac5fa9d75f979c6fd0e31fa31247eab82';

/// The sheet's choice on the current trip: kept from the preview to the
/// guidance and from one opening of the sheet to the next; another trip
/// starts again from fuel.
// keepAlive: the choice must outlive the sheet, closed between openings.

@ProviderFor(OnTheWayChoices)
final onTheWayChoicesProvider = OnTheWayChoicesProvider._();

/// The sheet's choice on the current trip: kept from the preview to the
/// guidance and from one opening of the sheet to the next; another trip
/// starts again from fuel.
// keepAlive: the choice must outlive the sheet, closed between openings.
final class OnTheWayChoicesProvider extends $NotifierProvider<OnTheWayChoices, OnTheWayChoice> {
  /// The sheet's choice on the current trip: kept from the preview to the
  /// guidance and from one opening of the sheet to the next; another trip
  /// starts again from fuel.
  // keepAlive: the choice must outlive the sheet, closed between openings.
  OnTheWayChoicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onTheWayChoicesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onTheWayChoicesHash();

  @$internal
  @override
  OnTheWayChoices create() => OnTheWayChoices();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnTheWayChoice value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnTheWayChoice>(value),
    );
  }
}

String _$onTheWayChoicesHash() => r'd05aaec666eee17e8ceac200b700815904422434';

/// The sheet's choice on the current trip: kept from the preview to the
/// guidance and from one opening of the sheet to the next; another trip
/// starts again from fuel.
// keepAlive: the choice must outlive the sheet, closed between openings.

abstract class _$OnTheWayChoices extends $Notifier<OnTheWayChoice> {
  OnTheWayChoice build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<OnTheWayChoice, OnTheWayChoice>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OnTheWayChoice, OnTheWayChoice>,
              OnTheWayChoice,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The list of [query], a page at a time; a failure of the first page
/// shows at once (`noRetry`), a later one under the list.

@ProviderFor(OnTheWayList)
final onTheWayListProvider = OnTheWayListFamily._();

/// The list of [query], a page at a time; a failure of the first page
/// shows at once (`noRetry`), a later one under the list.
final class OnTheWayListProvider extends $AsyncNotifierProvider<OnTheWayList, OnTheWayResults> {
  /// The list of [query], a page at a time; a failure of the first page
  /// shows at once (`noRetry`), a later one under the list.
  OnTheWayListProvider._({
    required OnTheWayListFamily super.from,
    required OnTheWayQuery super.argument,
  }) : super(
         retry: noRetry,
         name: r'onTheWayListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$onTheWayListHash();

  @override
  String toString() {
    return r'onTheWayListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OnTheWayList create() => OnTheWayList();

  @override
  bool operator ==(Object other) {
    return other is OnTheWayListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$onTheWayListHash() => r'7f92913776d2581f48e58282e52393f25277f02a';

/// The list of [query], a page at a time; a failure of the first page
/// shows at once (`noRetry`), a later one under the list.

final class OnTheWayListFamily extends $Family
    with
        $ClassFamilyOverride<
          OnTheWayList,
          AsyncValue<OnTheWayResults>,
          OnTheWayResults,
          FutureOr<OnTheWayResults>,
          OnTheWayQuery
        > {
  OnTheWayListFamily._()
    : super(
        retry: noRetry,
        name: r'onTheWayListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The list of [query], a page at a time; a failure of the first page
  /// shows at once (`noRetry`), a later one under the list.

  OnTheWayListProvider call(OnTheWayQuery query) =>
      OnTheWayListProvider._(argument: query, from: this);

  @override
  String toString() => r'onTheWayListProvider';
}

/// The list of [query], a page at a time; a failure of the first page
/// shows at once (`noRetry`), a later one under the list.

abstract class _$OnTheWayList extends $AsyncNotifier<OnTheWayResults> {
  late final _$args = ref.$arg as OnTheWayQuery;
  OnTheWayQuery get query => _$args;

  FutureOr<OnTheWayResults> build(OnTheWayQuery query);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OnTheWayResults>, OnTheWayResults>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OnTheWayResults>, OnTheWayResults>,
              AsyncValue<OnTheWayResults>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
