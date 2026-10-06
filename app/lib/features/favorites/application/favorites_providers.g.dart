// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorites_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(favoritesRepository)
final favoritesRepositoryProvider = FavoritesRepositoryProvider._();

final class FavoritesRepositoryProvider
    extends $FunctionalProvider<FavoritesRepository, FavoritesRepository, FavoritesRepository>
    with $Provider<FavoritesRepository> {
  FavoritesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoritesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritesRepositoryHash();

  @$internal
  @override
  $ProviderElement<FavoritesRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FavoritesRepository create(Ref ref) {
    return favoritesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FavoritesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FavoritesRepository>(value),
    );
  }
}

String _$favoritesRepositoryHash() => r'40167a96fadbf7b1dc12793efbe99921369bb971';

@ProviderFor(favoriteLists)
final favoriteListsProvider = FavoriteListsProvider._();

final class FavoriteListsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FavoriteList>>,
          List<FavoriteList>,
          Stream<List<FavoriteList>>
        >
    with $FutureModifier<List<FavoriteList>>, $StreamProvider<List<FavoriteList>> {
  FavoriteListsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoriteListsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoriteListsHash();

  @$internal
  @override
  $StreamProviderElement<List<FavoriteList>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<FavoriteList>> create(Ref ref) {
    return favoriteLists(ref);
  }
}

String _$favoriteListsHash() => r'5fe3bbd716d6ce1fc63523cb6dc304e57dfb1dfd';

@ProviderFor(favoriteEntries)
final favoriteEntriesProvider = FavoriteEntriesFamily._();

final class FavoriteEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FavoriteEntry>>,
          List<FavoriteEntry>,
          Stream<List<FavoriteEntry>>
        >
    with $FutureModifier<List<FavoriteEntry>>, $StreamProvider<List<FavoriteEntry>> {
  FavoriteEntriesProvider._({
    required FavoriteEntriesFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'favoriteEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$favoriteEntriesHash();

  @override
  String toString() {
    return r'favoriteEntriesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<FavoriteEntry>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<FavoriteEntry>> create(Ref ref) {
    final argument = this.argument as int;
    return favoriteEntries(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FavoriteEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$favoriteEntriesHash() => r'62e762310e512e10551b8c71a589d12349ce4f2a';

final class FavoriteEntriesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<FavoriteEntry>>, int> {
  FavoriteEntriesFamily._()
    : super(
        retry: null,
        name: r'favoriteEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FavoriteEntriesProvider call(int listId) =>
      FavoriteEntriesProvider._(argument: listId, from: this);

  @override
  String toString() => r'favoriteEntriesProvider';
}

/// The lists holding a place: empty means not saved.

@ProviderFor(placeLists)
final placeListsProvider = PlaceListsFamily._();

/// The lists holding a place: empty means not saved.

final class PlaceListsProvider
    extends $FunctionalProvider<AsyncValue<Set<int>>, Set<int>, Stream<Set<int>>>
    with $FutureModifier<Set<int>>, $StreamProvider<Set<int>> {
  /// The lists holding a place: empty means not saved.
  PlaceListsProvider._({required PlaceListsFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'placeListsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placeListsHash();

  @override
  String toString() {
    return r'placeListsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Set<int>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Set<int>> create(Ref ref) {
    final argument = this.argument as String;
    return placeLists(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlaceListsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$placeListsHash() => r'737148786ee00c856f802e62e12326f7d1f1ac2c';

/// The lists holding a place: empty means not saved.

final class PlaceListsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Set<int>>, String> {
  PlaceListsFamily._()
    : super(
        retry: null,
        name: r'placeListsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The lists holding a place: empty means not saved.

  PlaceListsProvider call(String placeId) => PlaceListsProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeListsProvider';
}

/// The list the favourites screen shows; null shows the default list.

@ProviderFor(SelectedFavoriteList)
final selectedFavoriteListProvider = SelectedFavoriteListProvider._();

/// The list the favourites screen shows; null shows the default list.
final class SelectedFavoriteListProvider extends $NotifierProvider<SelectedFavoriteList, int?> {
  /// The list the favourites screen shows; null shows the default list.
  SelectedFavoriteListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedFavoriteListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedFavoriteListHash();

  @$internal
  @override
  SelectedFavoriteList create() => SelectedFavoriteList();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<int?>(value));
  }
}

String _$selectedFavoriteListHash() => r'c1ef1c7ff45a757f09bfd204ba916748e73f0427';

/// The list the favourites screen shows; null shows the default list.

abstract class _$SelectedFavoriteList extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element as $ClassProviderElement<AnyNotifier<int?, int?>, int?, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
