import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorites_providers.g.dart';

final _log = Logger('favorites-sync');

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
FavoritesRepository favoritesRepository(Ref ref) => DriftFavoritesRepository(
  ref.watch(userDatabaseProvider),
  clock: ref.watch(clockProvider),
);

@riverpod
Stream<List<FavoriteList>> favoriteLists(Ref ref) =>
    ref.watch(favoritesRepositoryProvider).watchLists();

@riverpod
Stream<List<FavoriteEntry>> favoriteEntries(Ref ref, int listId) =>
    ref.watch(favoritesRepositoryProvider).watchEntries(listId);

/// The places and the saved points of a list, newest first.
@riverpod
Stream<List<Favorite>> favoriteItems(Ref ref, int listId) =>
    ref.watch(favoritesRepositoryProvider).watchFavorites(listId);

/// The id of the default list, which the save button toggles.
@riverpod
Future<int> defaultFavoriteList(Ref ref) =>
    ref.watch(favoritesRepositoryProvider).defaultListId();

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
  lookup: (id) async =>
      (await ref.read(placesRepositoryProvider).watchPlace(id).first)?.summary,
  defaultName: () => t.favorites.defaultList,
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
  Future<void>? _running;
  bool _again = false;

  @override
  FavoritesSyncStatus build() {
    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
      unawaited(_changes?.cancel());
    });
    ref.listen(accountControllerProvider, (previous, next) {
      if (next is SignedIn &&
          previous is SignedIn &&
          next.account.id != previous.account.id) {
        // Another account on this device: the lists stay, bound to none,
        // and join the new account at its first sync.
        unawaited(
          ref
              .read(favoritesSyncProvider)
              .unlink()
              .then((_) => _schedule(Duration.zero)),
        );
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
    _schedule(Duration.zero);
  }

  void _schedule(Duration wait) {
    _timer?.cancel();
    _timer = Timer(wait, () => unawaited(_syncIfSignedIn()));
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
      _log.info(
        'favourites not synced: ${e.runtimeType} (${SyncFailure.of(e).name})',
        null,
        st,
      );
      if (!ref.mounted) return;
      // The account went during the sync: the lists are this device's again.
      state = ref.read(accountControllerProvider) is SignedIn
          ? FavoritesSyncFailed(SyncFailure.of(e))
          : const FavoritesLocal();
    }
  }
}
