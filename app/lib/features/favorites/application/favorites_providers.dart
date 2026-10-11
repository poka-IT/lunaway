import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/favorites/data/home_repository.dart';
import 'package:lunaway/features/favorites/data/home_sync.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorites_providers.g.dart';

final _log = Logger('favorites-sync');

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
FavoritesRepository favoritesRepository(Ref ref) =>
    DriftFavoritesRepository(ref.watch(userDatabaseProvider), clock: ref.watch(clockProvider));

@riverpod
Stream<List<FavoriteList>> favoriteLists(Ref ref) =>
    ref.watch(favoritesRepositoryProvider).watchLists();

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
HomeRepository homeRepository(Ref ref) =>
    DriftHomeRepository(ref.watch(userDatabaseProvider), clock: ref.watch(clockProvider));

/// The user's home: the head of the favourites and of the search, the end
/// of a route in one tap; null while there is none.
@riverpod
Stream<SavedPoint?> userHome(Ref ref) => ref.watch(homeRepositoryProvider).watch();

/// The user asked, in the favourites, to place their home on the map: the
/// card of the next point held on the map offers "Mon domicile est ici".
// keepAlive: the choice made on the favourites tab waits for the map's.
@Riverpod(keepAlive: true)
class HomePicking extends _$HomePicking {
  @override
  bool build() => false;

  void start() => state = true;

  void stop() => state = false;
}

@riverpod
Stream<List<FavoriteEntry>> favoriteEntries(Ref ref, int listId) =>
    ref.watch(favoritesRepositoryProvider).watchEntries(listId);

/// The places and the saved points of a list, newest first.
@riverpod
Stream<List<Favorite>> favoriteItems(Ref ref, int listId) =>
    ref.watch(favoritesRepositoryProvider).watchFavorites(listId);

/// Gives the places saved before the app kept their street the street of
/// the copy of the place on the device, once a run, so that a place
/// without a name is titled by it in the lists as everywhere else (an
/// unnamed car park of Viviers reads "Car park · Rue de la Gare", not
/// "Car park · Viviers"). Returns how many got one; a place the device
/// could not read keeps its town and the provider fails, which the lists
/// leave aside; Riverpod then runs it again after growing delays (its
/// default retry), which reads only the places still without a street.
// keepAlive: once a run; a place saved since carries its street.
@Riverpod(keepAlive: true)
Future<int> favoriteStreetsFilled(Ref ref) async {
  try {
    return await ref
        .read(favoritesRepositoryProvider)
        .fillStreets(
          (id) async => (await ref.read(placesRepositoryProvider).watchPlace(id).first)?.summary,
        );
  } on Object catch (e, st) {
    _log.warning('the streets of the saved places were not all filled', e, st);
    rethrow;
  }
}

/// The id of the default list, which the save button toggles.
@riverpod
Future<int> defaultFavoriteList(Ref ref) => ref.watch(favoritesRepositoryProvider).defaultListId();

/// The lists holding a place or a saved point: empty means not saved.
@riverpod
Stream<Set<int>> placeLists(Ref ref, String placeId) =>
    ref.watch(favoritesRepositoryProvider).watchListsOf(placeId);

/// The point saved as [id], with the name and note the user gave it; null
/// when no list holds it.
@riverpod
Stream<SavedPoint?> savedPoint(Ref ref, String id) =>
    ref.watch(favoritesRepositoryProvider).watchPoint(id);

/// The list the favourites screen shows; null shows the default list.
@riverpod
class SelectedFavoriteList extends _$SelectedFavoriteList {
  @override
  int? build() => null;

  void show(int? listId) => state = listId;
}

/// The saved points of the list the favourites show (the default list
/// until another is chosen): the map marks them, as it marks the places of
/// the data.
@riverpod
Stream<List<FavoritePointEntry>> shownListPoints(Ref ref) async* {
  final repo = ref.watch(favoritesRepositoryProvider);
  final selected = ref.watch(selectedFavoriteListProvider);
  yield* repo.watchPoints(selected ?? await repo.defaultListId());
}

// keepAlive: the merge of the device's lists with the account's, wired once.
@Riverpod(keepAlive: true)
FavoritesSync favoritesSync(Ref ref) => FavoritesSync(
  db: ref.watch(userDatabaseProvider),
  remote: GraphQLFavoritesRemote(ref.watch(accountServiceProvider)),
  lookup: (id) async => (await ref.read(placesRepositoryProvider).watchPlace(id).first)?.summary,
  defaultName: () => t.favorites.defaultList,
  home: HomeSync(
    db: ref.watch(userDatabaseProvider),
    home: ref.watch(homeRepositoryProvider),
    remote: GraphQLHomeRemote(ref.watch(accountServiceProvider)),
  ),
  clock: ref.watch(clockProvider),
);

/// Where the sync of the favourites with the account stands.
@immutable
sealed class FavoritesSyncStatus {
  const new();
}

/// No account: the favourites live on this device only.
final class FavoritesLocal extends FavoritesSyncStatus {
  const new();
}

final class FavoritesSyncing extends FavoritesSyncStatus {
  const new();
}

final class FavoritesSynced extends FavoritesSyncStatus {
  const new(this.at);

  final DateTime at;
}

final class FavoritesSyncFailed extends FavoritesSyncStatus {
  const new(this.failure);

  final SyncFailure failure;
}

/// Keeps the favourites in step with the account: once it exists, after
/// each change of the lists (a few seconds later, so a burst of taps makes
/// one sync), at launch and when the app comes back. Without an account
/// the lists stay on the device; [syncNow] makes the account when the user
/// asks to sync them.
// keepAlive: the sync outlives the favourites screen.
@Riverpod(keepAlive: true)
class FavoritesSyncController extends _$FavoritesSyncController {
  static const debounce = Duration(seconds: 3);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<List<FavoriteList>>? _changes;
  StreamSubscription<SavedPoint?>? _homeChanges;
  Future<void>? _running;
  bool _again = false;

  @override
  FavoritesSyncStatus build() {
    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
      unawaited(_changes?.cancel());
      unawaited(_homeChanges?.cancel());
    });
    ref.listen(accountControllerProvider, (previous, next) {
      if (next is SignedIn && previous is SignedIn && next.account.id != previous.account.id) {
        // Another account on this device: the lists stay, bound to none,
        // and join the new account at its first sync.
        unawaited(ref.read(favoritesSyncProvider).unlink().then((_) => _schedule(Duration.zero)));
      } else if (next is SignedIn && previous is! SignedIn) {
        _schedule(Duration.zero);
      } else if (next is NoAccount && previous is SignedIn) {
        // The account is gone: the lists stay, unlinked.
        unawaited(ref.read(favoritesSyncProvider).unlink());
        state = const FavoritesLocal();
      }
    });
    return const FavoritesLocal();
  }

  /// Starts following the lists; later calls do nothing.
  void start() {
    if (_lifecycle != null) return;
    _lifecycle = AppLifecycleListener(onResume: () => _schedule(Duration.zero));
    var first = true;
    _changes = ref.read(favoritesRepositoryProvider).watchLists().listen((_) {
      // The first value is the lists as they are, not a change.
      if (first) {
        first = false;
        return;
      }
      _schedule(debounce);
    });
    // The home goes with the lists: a change of it is a change to sync.
    var firstHome = true;
    _homeChanges = ref.read(homeRepositoryProvider).watch().listen((_) {
      if (firstHome) {
        firstHome = false;
        return;
      }
      _schedule(debounce);
    });
    _schedule(Duration.zero);
  }

  void _schedule(Duration wait) {
    _timer?.cancel();
    if (_holds > 0) return;
    _timer = Timer(wait, () => unawaited(_syncIfSignedIn()));
  }

  /// Held while the device changes accounts: no sync starts meanwhile, so
  /// none runs under the account left while its lists are cleared or moved.
  int _holds = 0;

  /// Runs [action] once the sync under way, if any, has ended, with no
  /// sync starting until it ends; then syncs.
  Future<T> holding<T>(Future<T> Function() action) async {
    _holds++;
    _timer?.cancel();
    try {
      await _running;
      return await action();
    } finally {
      _holds--;
      if (_holds == 0 && ref.mounted) _schedule(Duration.zero);
    }
  }

  Future<void> _syncIfSignedIn() async {
    if (ref.read(accountControllerProvider) is SignedIn) await _run();
  }

  /// Syncs now, making the account when the device has none.
  Future<void> syncNow() async {
    if (ref.read(accountControllerProvider) is! SignedIn) {
      await ref.read(accountControllerProvider.notifier).create();
    }
    await _run();
  }

  Future<void> _run() async {
    if (_running != null) {
      _again = true;
      return await _running;
    }
    state = const FavoritesSyncing();
    _running = _sync();
    try {
      await _running;
    } finally {
      _running = null;
    }
    if (_again && ref.mounted) {
      _again = false;
      // The account may have gone while the first one ran.
      await _syncIfSignedIn();
    }
  }

  Future<void> _sync() async {
    final account = ref.read(accountControllerProvider);
    if (account is! SignedIn) {
      state = const FavoritesLocal();
      return;
    }
    try {
      await ref.read(favoritesSyncProvider).sync(accountId: account.account.id);
      if (ref.mounted) state = FavoritesSynced(ref.read(clockProvider)());
    } on Object catch (e, st) {
      // The type and the kind of failure alone: a database error's text
      // holds the saved points' names, notes and coordinates.
      _log.info('favourites not synced: ${e.runtimeType} (${SyncFailure.of(e).name})', null, st);
      if (!ref.mounted) return;
      // The account went during the sync: the lists are this device's again.
      state = ref.read(accountControllerProvider) is SignedIn
          ? FavoritesSyncFailed(SyncFailure.of(e))
          : const FavoritesLocal();
    }
  }
}
