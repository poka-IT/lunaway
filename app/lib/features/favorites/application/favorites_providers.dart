import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorites_providers.g.dart';

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
FavoritesRepository favoritesRepository(Ref ref) =>
    DriftFavoritesRepository(ref.watch(appDatabaseProvider), clock: ref.watch(clockProvider));

@riverpod
Stream<List<FavoriteList>> favoriteLists(Ref ref) =>
    ref.watch(favoritesRepositoryProvider).watchLists();

@riverpod
Stream<List<FavoriteEntry>> favoriteEntries(Ref ref, int listId) =>
    ref.watch(favoritesRepositoryProvider).watchEntries(listId);

/// The lists holding a place: empty means not saved.
@riverpod
Stream<Set<int>> placeLists(Ref ref, String placeId) =>
    ref.watch(favoritesRepositoryProvider).watchListsOf(placeId);

/// The list the favourites screen shows; null shows the default list.
@riverpod
class SelectedFavoriteList extends _$SelectedFavoriteList {
  @override
  int? build() => null;

  void show(int? listId) => state = listId;
}
