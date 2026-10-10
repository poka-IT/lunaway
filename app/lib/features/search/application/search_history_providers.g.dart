// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_history_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(searchHistoryStore)
final searchHistoryStoreProvider = SearchHistoryStoreProvider._();

final class SearchHistoryStoreProvider
    extends
        $FunctionalProvider<
          SearchHistoryStore,
          SearchHistoryStore,
          SearchHistoryStore
        >
    with $Provider<SearchHistoryStore> {
  SearchHistoryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchHistoryStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchHistoryStoreHash();

  @$internal
  @override
  $ProviderElement<SearchHistoryStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SearchHistoryStore create(Ref ref) {
    return searchHistoryStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchHistoryStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchHistoryStore>(value),
    );
  }
}

String _$searchHistoryStoreHash() =>
    r'87b9a40ef7ca09463e9c9f4d0c99b5231bfd8e59';

/// The search's history, the most recent first ([recentSearchLimit] at
/// most).

@ProviderFor(recentSearches)
final recentSearchesProvider = RecentSearchesProvider._();

/// The search's history, the most recent first ([recentSearchLimit] at
/// most).

final class RecentSearchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RecentSearch>>,
          List<RecentSearch>,
          Stream<List<RecentSearch>>
        >
    with
        $FutureModifier<List<RecentSearch>>,
        $StreamProvider<List<RecentSearch>> {
  /// The search's history, the most recent first ([recentSearchLimit] at
  /// most).
  RecentSearchesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentSearchesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentSearchesHash();

  @$internal
  @override
  $StreamProviderElement<List<RecentSearch>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<RecentSearch>> create(Ref ref) {
    return recentSearches(ref);
  }
}

String _$recentSearchesHash() => r'593cee1fdfe0dc35644148efdd83091df8bef5d2';

/// Whether the history shows under the map's search field: the field has
/// the focus and holds no text. The system back and Escape close it before
/// anything else, and the layouts give it the room of the results.
// keepAlive: part of what the map screen shows, as the search's text
// (SearchQuery), which the system back closes too.

@ProviderFor(SearchHistoryOpen)
final searchHistoryOpenProvider = SearchHistoryOpenProvider._();

/// Whether the history shows under the map's search field: the field has
/// the focus and holds no text. The system back and Escape close it before
/// anything else, and the layouts give it the room of the results.
// keepAlive: part of what the map screen shows, as the search's text
// (SearchQuery), which the system back closes too.
final class SearchHistoryOpenProvider
    extends $NotifierProvider<SearchHistoryOpen, bool> {
  /// Whether the history shows under the map's search field: the field has
  /// the focus and holds no text. The system back and Escape close it before
  /// anything else, and the layouts give it the room of the results.
  // keepAlive: part of what the map screen shows, as the search's text
  // (SearchQuery), which the system back closes too.
  SearchHistoryOpenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchHistoryOpenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchHistoryOpenHash();

  @$internal
  @override
  SearchHistoryOpen create() => SearchHistoryOpen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$searchHistoryOpenHash() => r'ec8f5ccaf438c93c55deed92362333f14b02b522';

/// Whether the history shows under the map's search field: the field has
/// the focus and holds no text. The system back and Escape close it before
/// anything else, and the layouts give it the room of the results.
// keepAlive: part of what the map screen shows, as the search's text
// (SearchQuery), which the system back closes too.

abstract class _$SearchHistoryOpen extends $Notifier<bool> {
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

/// Whether the history lies under the search field now, open and not
/// empty: what the map shows under the field (the chips, the notices, the
/// list of a pane) gives way to it, as to the results.

@ProviderFor(searchHistoryShown)
final searchHistoryShownProvider = SearchHistoryShownProvider._();

/// Whether the history lies under the search field now, open and not
/// empty: what the map shows under the field (the chips, the notices, the
/// list of a pane) gives way to it, as to the results.

final class SearchHistoryShownProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the history lies under the search field now, open and not
  /// empty: what the map shows under the field (the chips, the notices, the
  /// list of a pane) gives way to it, as to the results.
  SearchHistoryShownProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchHistoryShownProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchHistoryShownHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return searchHistoryShown(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$searchHistoryShownHash() =>
    r'f127f572d5b5845952ca95e53184d38c6834e8a7';
