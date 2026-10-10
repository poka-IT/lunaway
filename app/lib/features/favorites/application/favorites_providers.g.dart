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
    extends
        $FunctionalProvider<
          FavoritesRepository,
          FavoritesRepository,
          FavoritesRepository
        >
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
  $ProviderElement<FavoritesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

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

String _$favoritesRepositoryHash() =>
    r'269d91e7ef905e27a471fb0d2ea027ee8e0f19b6';

@ProviderFor(favoriteLists)
final favoriteListsProvider = FavoriteListsProvider._();

final class FavoriteListsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FavoriteList>>,
          List<FavoriteList>,
          Stream<List<FavoriteList>>
        >
    with
        $FutureModifier<List<FavoriteList>>,
        $StreamProvider<List<FavoriteList>> {
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
  $StreamProviderElement<List<FavoriteList>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

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
    with
        $FutureModifier<List<FavoriteEntry>>,
        $StreamProvider<List<FavoriteEntry>> {
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
  $StreamProviderElement<List<FavoriteEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

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

/// The places and the saved points of a list, newest first.

@ProviderFor(favoriteItems)
final favoriteItemsProvider = FavoriteItemsFamily._();

/// The places and the saved points of a list, newest first.

final class FavoriteItemsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Favorite>>,
          List<Favorite>,
          Stream<List<Favorite>>
        >
    with $FutureModifier<List<Favorite>>, $StreamProvider<List<Favorite>> {
  /// The places and the saved points of a list, newest first.
  FavoriteItemsProvider._({
    required FavoriteItemsFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'favoriteItemsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$favoriteItemsHash();

  @override
  String toString() {
    return r'favoriteItemsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Favorite>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Favorite>> create(Ref ref) {
    final argument = this.argument as int;
    return favoriteItems(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FavoriteItemsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$favoriteItemsHash() => r'8768e667232f01f3fc890dcee16417b11dee5313';

/// The places and the saved points of a list, newest first.

final class FavoriteItemsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Favorite>>, int> {
  FavoriteItemsFamily._()
    : super(
        retry: null,
        name: r'favoriteItemsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The places and the saved points of a list, newest first.

  FavoriteItemsProvider call(int listId) =>
      FavoriteItemsProvider._(argument: listId, from: this);

  @override
  String toString() => r'favoriteItemsProvider';
}

/// Gives the places saved before the app kept their street the street of
/// the copy of the place on the device, once a run, so that a place
/// without a name is titled by it in the lists as everywhere else (an
/// unnamed car park of Viviers reads "Car park · Rue de la Gare", not
/// "Car park · Viviers"). Returns how many got one; a place the device
/// could not read keeps its town and the provider fails, which the lists
/// leave aside; Riverpod then runs it again after growing delays (its
/// default retry), which reads only the places still without a street.
// keepAlive: once a run; a place saved since carries its street.

@ProviderFor(favoriteStreetsFilled)
final favoriteStreetsFilledProvider = FavoriteStreetsFilledProvider._();

/// Gives the places saved before the app kept their street the street of
/// the copy of the place on the device, once a run, so that a place
/// without a name is titled by it in the lists as everywhere else (an
/// unnamed car park of Viviers reads "Car park · Rue de la Gare", not
/// "Car park · Viviers"). Returns how many got one; a place the device
/// could not read keeps its town and the provider fails, which the lists
/// leave aside; Riverpod then runs it again after growing delays (its
/// default retry), which reads only the places still without a street.
// keepAlive: once a run; a place saved since carries its street.

final class FavoriteStreetsFilledProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Gives the places saved before the app kept their street the street of
  /// the copy of the place on the device, once a run, so that a place
  /// without a name is titled by it in the lists as everywhere else (an
  /// unnamed car park of Viviers reads "Car park · Rue de la Gare", not
  /// "Car park · Viviers"). Returns how many got one; a place the device
  /// could not read keeps its town and the provider fails, which the lists
  /// leave aside; Riverpod then runs it again after growing delays (its
  /// default retry), which reads only the places still without a street.
  // keepAlive: once a run; a place saved since carries its street.
  FavoriteStreetsFilledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoriteStreetsFilledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoriteStreetsFilledHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return favoriteStreetsFilled(ref);
  }
}

String _$favoriteStreetsFilledHash() =>
    r'5344a6dc56b254979e0c5a33b7e566996d090b42';

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

String _$defaultFavoriteListHash() =>
    r'3e4943719c1b3ab47691da16cbb9e3a5fe35eadb';

/// The lists holding a place or a saved point: empty means not saved.

@ProviderFor(placeLists)
final placeListsProvider = PlaceListsFamily._();

/// The lists holding a place or a saved point: empty means not saved.

final class PlaceListsProvider
    extends
        $FunctionalProvider<AsyncValue<Set<int>>, Set<int>, Stream<Set<int>>>
    with $FutureModifier<Set<int>>, $StreamProvider<Set<int>> {
  /// The lists holding a place or a saved point: empty means not saved.
  PlaceListsProvider._({
    required PlaceListsFamily super.from,
    required String super.argument,
  }) : super(
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

/// The lists holding a place or a saved point: empty means not saved.

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

  /// The lists holding a place or a saved point: empty means not saved.

  PlaceListsProvider call(String placeId) =>
      PlaceListsProvider._(argument: placeId, from: this);

  @override
  String toString() => r'placeListsProvider';
}

/// The point saved as [id], with the name and note the user gave it; null
/// when no list holds it.

@ProviderFor(savedPoint)
final savedPointProvider = SavedPointFamily._();

/// The point saved as [id], with the name and note the user gave it; null
/// when no list holds it.

final class SavedPointProvider
    extends
        $FunctionalProvider<
          AsyncValue<SavedPoint?>,
          SavedPoint?,
          Stream<SavedPoint?>
        >
    with $FutureModifier<SavedPoint?>, $StreamProvider<SavedPoint?> {
  /// The point saved as [id], with the name and note the user gave it; null
  /// when no list holds it.
  SavedPointProvider._({
    required SavedPointFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'savedPointProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$savedPointHash();

  @override
  String toString() {
    return r'savedPointProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<SavedPoint?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<SavedPoint?> create(Ref ref) {
    final argument = this.argument as String;
    return savedPoint(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SavedPointProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$savedPointHash() => r'00c7e2b85442b2c4101a615a9baaad87614c5439';

/// The point saved as [id], with the name and note the user gave it; null
/// when no list holds it.

final class SavedPointFamily extends $Family
    with $FunctionalFamilyOverride<Stream<SavedPoint?>, String> {
  SavedPointFamily._()
    : super(
        retry: null,
        name: r'savedPointProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The point saved as [id], with the name and note the user gave it; null
  /// when no list holds it.

  SavedPointProvider call(String id) =>
      SavedPointProvider._(argument: id, from: this);

  @override
  String toString() => r'savedPointProvider';
}

/// The list the favourites screen shows; null shows the default list.

@ProviderFor(SelectedFavoriteList)
final selectedFavoriteListProvider = SelectedFavoriteListProvider._();

/// The list the favourites screen shows; null shows the default list.
final class SelectedFavoriteListProvider
    extends $NotifierProvider<SelectedFavoriteList, int?> {
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
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$selectedFavoriteListHash() =>
    r'c1ef1c7ff45a757f09bfd204ba916748e73f0427';

/// The list the favourites screen shows; null shows the default list.

abstract class _$SelectedFavoriteList extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The saved points of the list the favourites show (the default list
/// until another is chosen): the map marks them, as it marks the places of
/// the data.

@ProviderFor(shownListPoints)
final shownListPointsProvider = ShownListPointsProvider._();

/// The saved points of the list the favourites show (the default list
/// until another is chosen): the map marks them, as it marks the places of
/// the data.

final class ShownListPointsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FavoritePointEntry>>,
          List<FavoritePointEntry>,
          Stream<List<FavoritePointEntry>>
        >
    with
        $FutureModifier<List<FavoritePointEntry>>,
        $StreamProvider<List<FavoritePointEntry>> {
  /// The saved points of the list the favourites show (the default list
  /// until another is chosen): the map marks them, as it marks the places of
  /// the data.
  ShownListPointsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shownListPointsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shownListPointsHash();

  @$internal
  @override
  $StreamProviderElement<List<FavoritePointEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<FavoritePointEntry>> create(Ref ref) {
    return shownListPoints(ref);
  }
}

String _$shownListPointsHash() => r'594ebef3dec81f03fcb75c0e6e85309256f29e93';

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

String _$favoritesSyncControllerHash() =>
    r'39c52608c9607ac0918314c0cbbffbd7d8adf718';

/// Keeps the favourites in step with the account: once it exists, after
/// each change of the lists (a few seconds later, so a burst of taps makes
/// one sync), at launch and when the app comes back. Without an account
/// the lists stay on the device; [syncNow] makes the account when the user
/// asks to sync them.
// keepAlive: the sync outlives the favourites screen.

abstract class _$FavoritesSyncController
    extends $Notifier<FavoritesSyncStatus> {
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
