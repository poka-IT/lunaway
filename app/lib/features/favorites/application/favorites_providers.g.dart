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

String _$favoritesRepositoryHash() => r'269d91e7ef905e27a471fb0d2ea027ee8e0f19b6';

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

/// The id of the default list, which the save button toggles.

@ProviderFor(defaultFavoriteList)
final defaultFavoriteListProvider = DefaultFavoriteListProvider._();

/// The id of the default list, which the save button toggles.

final class DefaultFavoriteListProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// The id of the default list, which the save button toggles.
  DefaultFavoriteListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'defaultFavoriteListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$defaultFavoriteListHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return defaultFavoriteList(ref);
  }
}

String _$defaultFavoriteListHash() => r'3e4943719c1b3ab47691da16cbb9e3a5fe35eadb';

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

@ProviderFor(favoritesSync)
final favoritesSyncProvider = FavoritesSyncProvider._();

final class FavoritesSyncProvider
    extends $FunctionalProvider<FavoritesSync, FavoritesSync, FavoritesSync>
    with $Provider<FavoritesSync> {
  FavoritesSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoritesSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritesSyncHash();

  @$internal
  @override
  $ProviderElement<FavoritesSync> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FavoritesSync create(Ref ref) {
    return favoritesSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FavoritesSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FavoritesSync>(value),
    );
  }
}

String _$favoritesSyncHash() => r'8a236f19aa5cc3e63e9e28b9007159e4cef5277f';

/// Keeps the favourites in step with the account: once it exists, after
/// each change of the lists (a few seconds later, so a burst of taps makes
/// one sync), at launch and when the app comes back. Without an account
/// the lists stay on the device; [syncNow] makes the account when the user
/// asks to sync them.
// keepAlive: the sync outlives the favourites screen.

@ProviderFor(FavoritesSyncController)
final favoritesSyncControllerProvider = FavoritesSyncControllerProvider._();

/// Keeps the favourites in step with the account: once it exists, after
/// each change of the lists (a few seconds later, so a burst of taps makes
/// one sync), at launch and when the app comes back. Without an account
/// the lists stay on the device; [syncNow] makes the account when the user
/// asks to sync them.
// keepAlive: the sync outlives the favourites screen.
final class FavoritesSyncControllerProvider
    extends $NotifierProvider<FavoritesSyncController, FavoritesSyncStatus> {
  /// Keeps the favourites in step with the account: once it exists, after
  /// each change of the lists (a few seconds later, so a burst of taps makes
  /// one sync), at launch and when the app comes back. Without an account
  /// the lists stay on the device; [syncNow] makes the account when the user
  /// asks to sync them.
  // keepAlive: the sync outlives the favourites screen.
  FavoritesSyncControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoritesSyncControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritesSyncControllerHash();

  @$internal
  @override
  FavoritesSyncController create() => FavoritesSyncController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FavoritesSyncStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FavoritesSyncStatus>(value),
    );
  }
}

String _$favoritesSyncControllerHash() => r'56fe8c3e840fce4f4ecdfa6dec12353f568c153a';

/// Keeps the favourites in step with the account: once it exists, after
/// each change of the lists (a few seconds later, so a burst of taps makes
/// one sync), at launch and when the app comes back. Without an account
/// the lists stay on the device; [syncNow] makes the account when the user
/// asks to sync them.
// keepAlive: the sync outlives the favourites screen.

abstract class _$FavoritesSyncController extends $Notifier<FavoritesSyncStatus> {
  FavoritesSyncStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FavoritesSyncStatus, FavoritesSyncStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FavoritesSyncStatus, FavoritesSyncStatus>,
              FavoritesSyncStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
