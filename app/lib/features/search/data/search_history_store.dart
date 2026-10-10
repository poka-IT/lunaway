import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';

final _log = Logger('search_history');

/// The search's history in the device's cache database (`search_history`):
/// [recentSearchLimit] entries at most, the most recent first. Nothing of
/// it leaves the device.
final class SearchHistoryStore {
  new(this._db, {this._clock = DateTime.now});

  final CacheDatabase _db;
  final DateTime Function() _clock;

  /// The entries, the most recent first; one this version cannot read is
  /// left out.
  Stream<List<RecentSearch>> watch() {
    final query = _db.select(_db.searchHistory)
      ..orderBy([(e) => OrderingTerm.desc(e.usedAt)])
      ..limit(recentSearchLimit);
    return query.watch().map((rows) => [for (final row in rows) ?_read(row)]);
  }

  /// [entry] at the top: a result already listed moves up, and the oldest
  /// beyond [recentSearchLimit] go.
  Future<void> record(RecentSearch entry) => _db.transaction(() async {
    // After every other entry, even within the same millisecond or with a
    // clock set back: the last opened is the first listed.
    final latest = await _db
        .customSelect('SELECT MAX(used_at) AS latest FROM search_history')
        .getSingle();
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final last = latest.readNullable<int>('latest');
    await _db
        .into(_db.searchHistory)
        .insertOnConflictUpdate(
          SearchHistoryCompanion.insert(
            entryKey: entry.key,
            kind: entry.kind,
            payload: jsonEncode(entry.toJson()),
            usedAt: last != null && last >= now ? last + 1 : now,
          ),
        );
    await _db.customStatement(
      'DELETE FROM search_history WHERE entry_key NOT IN '
      '(SELECT entry_key FROM search_history ORDER BY used_at DESC LIMIT ?)',
      [recentSearchLimit],
    );
  });

  /// Takes the entry of [key] out.
  Future<void> remove(String key) =>
      (_db.delete(_db.searchHistory)..where((e) => e.entryKey.equals(key))).go();

  /// Empties the history.
  Future<void> clear() => _db.delete(_db.searchHistory).go();

  RecentSearch? _read(SearchHistoryRow row) {
    try {
      final json = jsonDecode(row.payload);
      if (json is Map<String, dynamic>) return RecentSearch.fromStored(row.kind, json);
    } on FormatException {
      // Never the entry itself in a log: it says what the user searched.
      _log.info('an entry of the history does not read');
    }
    return null;
  }
}
