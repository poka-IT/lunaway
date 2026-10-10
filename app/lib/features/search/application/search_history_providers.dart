import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/search/data/search_history_store.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_history_providers.g.dart';

// keepAlive: a stateless store over the app-wide database.
@Riverpod(keepAlive: true)
SearchHistoryStore searchHistoryStore(Ref ref) =>
    SearchHistoryStore(ref.watch(cacheDatabaseProvider), clock: ref.watch(clockProvider));

/// The search's history, the most recent first ([recentSearchLimit] at
/// most).
@riverpod
Stream<List<RecentSearch>> recentSearches(Ref ref) => ref.watch(searchHistoryStoreProvider).watch();

/// Whether the history shows under the map's search field: the field has
/// the focus and holds no text. The system back and Escape close it before
/// anything else, and the layouts give it the room of the results.
// keepAlive: part of what the map screen shows, as the search's text
// (SearchQuery), which the system back closes too.
@Riverpod(keepAlive: true)
class SearchHistoryOpen extends _$SearchHistoryOpen {
  @override
  bool build() => false;

  void set({required bool open}) {
    // A field left as the app closes tells a scope already gone.
    if (!ref.mounted) return;
    if (state != open) state = open;
  }
}

/// Whether the history lies under the search field now, open and not
/// empty: what the map shows under the field (the chips, the notices, the
/// list of a pane) gives way to it, as to the results.
@riverpod
bool searchHistoryShown(Ref ref) =>
    ref.watch(searchHistoryOpenProvider) &&
    (ref.watch(recentSearchesProvider).value?.isNotEmpty ?? false);
