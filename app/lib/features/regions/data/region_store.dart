import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/regions/data/region_operations.dart';
import 'package:lunaway/features/regions/domain/regions.dart';

final _log = Logger('sync');

/// Where the places of the regions go, a region at a time: its pack, then
/// the pages of its feed. Each region keeps its own cursor and generation
/// in `region_syncs`; its places carry its code, so its full sync sweeps
/// only them and removing it removes only them.
abstract interface class RegionStore {
  Future<SyncState> stateOf(String region);

  /// Starts a full sync of [region] from the feed: a new generation, no
  /// cursor. The places stay until the sync ends.
  Future<void> beginFullSync(String region);

  /// Starts a delta run from the stored cursor.
  Future<void> beginDeltaSync(String region);

  /// Writes [page] and its cursor: its places tagged with [region], the
  /// deleted ones removed, and those that left [region] removed unless the
  /// device already holds them under another region it keeps.
  Future<void> applyPage(String region, RegionChangeSet page);

  /// Replaces the places of [region] with those of the pack at [path] (an
  /// SQLite file in the `sqlite-gzip-1` layout), and leaves the region's
  /// feed to continue from [cursor]. Answers how many places it holds.
  Future<int> importPack(String region, String path, {required String cursor});

  /// Ends the run at its last page: a full sync removes the places of
  /// [region] it did not write. Answers how many.
  Future<int> completeRun(String region, DateTime at);

  /// Forgets [region]: its state and its places.
  Future<void> forget(String region);

  /// The regions the store holds a state for.
  Future<Set<String>> regions();

  /// Removes the places synced by box before regions existed, once every
  /// region kept has synced on its own; answers how many.
  Future<int> dropUnregioned();

  /// The size of each region on the device: its places.
  Stream<Map<String, int>> watchCounts();

  /// The state of each region held.
  Stream<Map<String, SyncState>> watchStates();
}

/// [RegionStore] over the place cache.
final class DriftRegionStore implements RegionStore {
  new(this._db, this._places);

  final CacheDatabase _db;
  final DriftPlacesRepository _places;

  /// The id of the sync by box of the versions before regions.
  static const legacyRegion = 'fr-metro';

  @override
  Future<SyncState> stateOf(String region) => _places.stateOf(region);

  @override
  Future<void> beginFullSync(String region) => _places.beginFullSync(region);

  @override
  Future<void> beginDeltaSync(String region) => _places.beginDeltaSync(region);

  @override
  Future<void> applyPage(String region, RegionChangeSet page) => _db.transaction(() async {
    final generation = (await stateOf(region)).generation;
    await _db.batch((batch) {
      for (final p in page.places) {
        final row = _places.placeCompanion(p, generation, region: region);
        batch.insert(
          _db.places,
          row,
          onConflict: DoUpdate<Places, PlaceRow>(
            (_) => row,
            target: [_db.places.id],
            where: (old) => _replaces(old, region, p.updatedAt),
          ),
        );
      }
      if (page.deleted.isNotEmpty) {
        batch.deleteWhere(_db.places, (p) => p.id.isIn(page.deleted));
      }
      if (page.left.isNotEmpty) {
        // A place the device already took from the region it moved to
        // carries that region now, and stays.
        batch.deleteWhere(_db.places, (p) => p.id.isIn(page.left) & p.region.equals(region));
      }
    });
    await (_db.update(_db.regionSyncs)..where((s) => s.region.equals(region))).write(
      RegionSyncsCompanion(cursor: Value(page.cursor)),
    );
  });

  /// Whether a place of [region] changed at [updatedAt] replaces the row
  /// [old]: always within its region, whose pack and feed are the truth of
  /// it; from another region (or from the sync by box) only when not older.
  /// A pack built before a place moved still lists it, while the device may
  /// hold its newer self from the region it moved to.
  static Expression<bool> _replaces(Places old, String region, DateTime updatedAt) =>
      old.region.equals(region) |
      old.updatedAt.isSmallerOrEqualValue(updatedAt.millisecondsSinceEpoch);

  /// Refuses an attached pack that is not a pack of [region] in the format
  /// this app reads: its digest only says the server sent it, not that the
  /// server built it right.
  Future<void> _checkPack(String region) async {
    final tables = await _db
        .customSelect(
          "SELECT name FROM pack.sqlite_schema WHERE type = 'table' AND name IN ('pack', 'places')",
        )
        .map((r) => r.read<String>('name'))
        .get();
    final meta = tables.length < 2
        ? const <String, String>{}
        : {
            for (final r
                in await _db
                    .customSelect(
                      "SELECT key, value FROM pack.pack WHERE key IN ('format', 'region')",
                    )
                    .get())
              r.read<String>('key'): r.read<String>('value'),
          };
    if (meta['format'] != RegionPack.supportedFormat || meta['region'] != region) {
      throw PackDownloadException(
        PackDownloadFailure.corrupt,
        'not a ${RegionPack.supportedFormat} pack of $region',
      );
    }
  }

  @override
  Future<int> importPack(String region, String path, {required String cursor}) async {
    final generation = (await stateOf(region)).generation + 1;
    // The pack comes from the network: its schema must not run functions
    // or triggers with the privileges of the app's database.
    await _db.customStatement('PRAGMA trusted_schema = OFF');
    await _db.customStatement('ATTACH DATABASE ? AS pack', [path]);
    try {
      await _checkPack(region);
      return await _db.transaction(() async {
        await _mappings();
        await _db.customStatement(_importSql, [generation, region]);
        final count = await _db
            .customSelect('SELECT count(*) AS n FROM pack.places')
            .map((r) => r.read<int>('n'))
            .getSingle();
        // The pack is the whole region: what it does not hold is gone.
        await (_db.delete(
          _db.places,
        )..where((p) => p.region.equals(region) & p.syncGen.isSmallerThanValue(generation))).go();
        final previous = await stateOf(region);
        await _db
            .into(_db.regionSyncs)
            .insertOnConflictUpdate(
              RegionSyncsCompanion.insert(
                region: region,
                cursor: Value(cursor),
                generation: Value(generation),
                fullSync: const Value(false),
                // The feed after the pack is still to read: the run ends
                // with its last page.
                running: const Value(true),
                completedAt: Value(previous.completedAt?.millisecondsSinceEpoch),
              ),
            );
        return count;
      });
    } finally {
      await _db.customStatement('DETACH DATABASE pack');
      // The rows came in through SQL drift does not watch: the count of
      // places, the map and the list read again (a first download over an
      // empty device otherwise kept "no place here" over a full map).
      _db.notifyUpdates({TableUpdate.onTable(_db.places)});
    }
  }

  /// The app's own readings of the API's values, as temporary tables the
  /// import joins: the kind's family, the bits of the services and
  /// activities, and what an unknown value is read as. The same reading as
  /// `placeFromJson`, so a place from a pack is the place the feed gives.
  Future<void> _mappings() async {
    await _db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS lw_kind (wire TEXT PRIMARY KEY, stored TEXT, family INTEGER)',
    );
    await _db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS lw_bit (domain TEXT, wire TEXT, bit INTEGER, '
      'PRIMARY KEY (domain, wire))',
    );
    await _db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS lw_value (domain TEXT, wire TEXT, stored TEXT, '
      'PRIMARY KEY (domain, wire))',
    );
    for (final table in ['lw_kind', 'lw_bit', 'lw_value']) {
      await _db.customStatement('DELETE FROM temp.$table');
    }
    final unknownKind = PlaceKind.fromWire('');
    // The row with a NULL wire is what an unknown value reads as.
    await _db.customStatement('INSERT INTO temp.lw_kind VALUES (NULL, ?, ?)', [
      unknownKind.wire,
      unknownKind.family.index,
    ]);
    for (final k in PlaceKind.values) {
      await _db.customStatement('INSERT INTO temp.lw_kind VALUES (?, ?, ?)', [
        k.wire,
        k.wire,
        k.family.index,
      ]);
    }
    for (final s in Service.values) {
      await _db.customStatement("INSERT INTO temp.lw_bit VALUES ('service', ?, ?)", [
        s.wire,
        s.bit,
      ]);
    }
    for (final a in Activity.values) {
      await _db.customStatement("INSERT INTO temp.lw_bit VALUES ('activity', ?, ?)", [
        a.wire,
        a.bit,
      ]);
    }
    final values = <(String, String?, String)>[
      ('overnight', null, OvernightStatus.fromWire('').wire),
      for (final o in OvernightStatus.values) ('overnight', o.wire, o.wire),
      ('verification', null, Verification.fromWire(null).wire),
      for (final v in Verification.values) ('verification', v.wire, v.wire),
    ];
    for (final (domain, wire, stored) in values) {
      await _db.customStatement('INSERT INTO temp.lw_value VALUES (?, ?, ?)', [
        domain,
        wire,
        stored,
      ]);
    }
  }

  @override
  Future<int> completeRun(String region, DateTime at) => _db.transaction(() async {
    final state = await stateOf(region);
    var swept = 0;
    if (state.fullSync) {
      swept =
          await (_db.delete(_db.places)..where(
                (p) => p.region.equals(region) & p.syncGen.isSmallerThanValue(state.generation),
              ))
              .go();
    }
    await (_db.update(_db.regionSyncs)..where((s) => s.region.equals(region))).write(
      RegionSyncsCompanion(
        fullSync: const Value(false),
        running: const Value(false),
        completedAt: Value(at.millisecondsSinceEpoch),
      ),
    );
    return swept;
  });

  @override
  Future<void> forget(String region) => _db.transaction(() async {
    await (_db.delete(_db.regionSyncs)..where((s) => s.region.equals(region))).go();
    await (_db.delete(_db.places)..where((p) => p.region.equals(region))).go();
  });

  @override
  Future<Set<String>> regions() async =>
      {for (final row in await _db.select(_db.regionSyncs).get()) row.region}..remove(legacyRegion);

  @override
  Future<int> dropUnregioned() => _db.transaction(() async {
    await (_db.delete(_db.regionSyncs)..where((s) => s.region.equals(legacyRegion))).go();
    return await (_db.delete(_db.places)..where((p) => p.region.isNull())).go();
  });

  @override
  Stream<Map<String, int>> watchCounts() => _db
      .customSelect(
        'SELECT region, count(*) AS n FROM places WHERE region IS NOT NULL GROUP BY region',
        readsFrom: {_db.places},
      )
      .watch()
      .map((rows) => {for (final r in rows) r.read<String>('region'): r.read<int>('n')});

  @override
  Stream<Map<String, SyncState>> watchStates() => _db
      .select(_db.regionSyncs)
      .watch()
      .map(
        (rows) => {
          for (final r in rows)
            r.region: SyncState(
              cursor: r.cursor,
              generation: r.generation,
              fullSync: r.fullSync,
              running: r.running,
              completedAt: r.completedAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(r.completedAt!, isUtc: true),
            ),
        },
      );
}

/// The instant of an RFC 3339 [column] in milliseconds since the epoch,
/// the fraction of a second cut after the milliseconds as Dart's
/// `DateTime.parse` cuts it (SQLite's own reading rounds it); NULL for a
/// value that is not a date.
String _epochMs(String column) =>
    "(CAST(round((julianday(substr($column, 1, 19) || ltrim(substr($column, 20), '.0123456789'))"
    ' - 2440587.5) * 86400) AS INTEGER) * 1000'
    " + CAST(CASE WHEN substr($column, 20, 1) = '.'"
    " THEN substr(rtrim(substr($column, 21, 3), 'Z+-:') || '000', 1, 3) ELSE '000' END AS INTEGER))";

/// A pack's places copied into the cache in one statement (the fastest
/// import the backend measured, docs/region-packs.md): every column read
/// the way `placeFromJson` and the place row read the API's JSON, the
/// enumerations through the temporary tables of the app's own values.
/// Arguments: the generation, the region.
final _importSql =
    '''
INSERT INTO places (
  id, name, kind, family, lat, lon, overnight, services, activities, description,
  street, postcode, city, country_code, price_parking, price_services, max_height, capacity,
  opening_hours, opening_hours_parsed, opening_intervals_json, opening_valid_until, stars,
  sync_gen, website, phone, last_confirmed_at, updated_at, sources_json, provenance_json,
  descriptions_json, ratings_json, links_json, rating_avg, rating_count, verification,
  review_count, photo_count, cover_photos_json, issues_json, region
)
SELECT
  p.id,
  nullif(trim(p.name), ''),
  coalesce(k.stored, ku.stored),
  coalesce(k.family, ku.family),
  p.lat,
  p.lon,
  coalesce(o.stored, ou.stored),
  (SELECT coalesce(sum(bit), 0) FROM (SELECT DISTINCT b.bit FROM json_each(p.services) j
     JOIN temp.lw_bit b ON b.domain = 'service' AND b.wire = j.value)),
  (SELECT coalesce(sum(bit), 0) FROM (SELECT DISTINCT b.bit FROM json_each(p.activities) j
     JOIN temp.lw_bit b ON b.domain = 'activity' AND b.wire = j.value)),
  nullif(trim(p.description), ''),
  nullif(trim(p.street), ''),
  nullif(trim(p.postcode), ''),
  -- A place mapped without a town takes the commune it lies in.
  coalesce(nullif(trim(p.city), ''), nullif(trim(p.municipality), '')),
  nullif(trim(p.country_code), ''),
  p.price_parking_eur,
  p.price_services_eur,
  p.max_height_m,
  p.capacity,
  nullif(trim(p.opening_hours), ''),
  coalesce(p.opening_hours_parsed, 0) = 1,
  -- The intervals mean nothing without the end of their window.
  CASE WHEN json_type(p.opening_intervals) = 'array'
        AND julianday(p.opening_intervals_until) IS NOT NULL
       THEN p.opening_intervals END,
  CASE WHEN json_type(p.opening_intervals) = 'array'
        AND julianday(p.opening_intervals_until) IS NOT NULL
       THEN ${_epochMs('p.opening_intervals_until')}
       END,
  CASE WHEN p.stars BETWEEN 1 AND 5 THEN CAST(p.stars AS INTEGER) END,
  ?1,
  nullif(trim(p.website), ''),
  nullif(trim(p.phone), ''),
  ${_epochMs('p.last_confirmed_at')},
  coalesce(${_epochMs('p.updated_at')}, 0),
  coalesce(p.sources, '[]'),
  coalesce(p.provenance, '[]'),
  coalesce(p.descriptions, '[]'),
  coalesce(p.ratings, '[]'),
  coalesce(p.external_links, '[]'),
  (SELECT sum(json_extract(j.value, '\$.average') * json_extract(j.value, '\$.count'))
          / sum(json_extract(j.value, '\$.count'))
     FROM json_each(p.ratings) j
    WHERE json_type(j.value, '\$.count') IN ('integer', 'real')
      AND json_extract(j.value, '\$.count') >= 1
      AND json_type(j.value, '\$.sourceId') = 'text'
      AND json_type(j.value, '\$.average') IN ('integer', 'real')),
  coalesce((SELECT sum(CAST(json_extract(j.value, '\$.count') AS INTEGER))
     FROM json_each(p.ratings) j
    WHERE json_type(j.value, '\$.count') IN ('integer', 'real')
      AND json_extract(j.value, '\$.count') >= 1
      AND json_type(j.value, '\$.sourceId') = 'text'
      AND json_type(j.value, '\$.average') IN ('integer', 'real')), 0),
  coalesce(v.stored, vu.stored),
  coalesce(p.review_count, 0),
  coalesce(p.photo_count, 0),
  coalesce(p.cover_photos, '[]'),
  coalesce(p.reported_issues, '[]'),
  ?2
FROM pack.places p
LEFT JOIN temp.lw_kind k ON k.wire = p.kind
JOIN temp.lw_kind ku ON ku.wire IS NULL
LEFT JOIN temp.lw_value o ON o.domain = 'overnight' AND o.wire = p.overnight
JOIN temp.lw_value ou ON ou.domain = 'overnight' AND ou.wire IS NULL
LEFT JOIN temp.lw_value v ON v.domain = 'verification' AND v.wire = p.verification
JOIN temp.lw_value vu ON vu.domain = 'verification' AND vu.wire IS NULL
WHERE true
ON CONFLICT (id) DO UPDATE SET
  name = excluded.name, kind = excluded.kind, family = excluded.family, lat = excluded.lat,
  lon = excluded.lon, overnight = excluded.overnight, services = excluded.services,
  activities = excluded.activities, description = excluded.description,
  street = excluded.street, postcode = excluded.postcode, city = excluded.city,
  country_code = excluded.country_code, price_parking = excluded.price_parking,
  price_services = excluded.price_services, max_height = excluded.max_height,
  capacity = excluded.capacity, opening_hours = excluded.opening_hours,
  opening_hours_parsed = excluded.opening_hours_parsed,
  opening_intervals_json = excluded.opening_intervals_json,
  opening_valid_until = excluded.opening_valid_until, stars = excluded.stars,
  sync_gen = excluded.sync_gen, website = excluded.website, phone = excluded.phone,
  last_confirmed_at = excluded.last_confirmed_at, updated_at = excluded.updated_at,
  sources_json = excluded.sources_json, provenance_json = excluded.provenance_json,
  descriptions_json = excluded.descriptions_json, ratings_json = excluded.ratings_json,
  links_json = excluded.links_json, rating_avg = excluded.rating_avg,
  rating_count = excluded.rating_count, verification = excluded.verification,
  review_count = excluded.review_count, photo_count = excluded.photo_count,
  cover_photos_json = excluded.cover_photos_json, issues_json = excluded.issues_json,
  region = excluded.region
-- Within its region the pack is the truth; a row another region holds is
-- replaced only by data not older (`_replaces`).
WHERE places.region IS excluded.region OR places.updated_at <= excluded.updated_at
''';

/// The regions the user keeps, in the user's own database: a choice made
/// once stays made, backups included, while the places themselves can be
/// downloaded again.
final class KeptRegionsStore {
  new(this._db);

  final UserDatabase _db;

  static const _key = 'sync_regions';

  /// The regions kept; null until a first choice (the first launch).
  Future<Set<String>?> load() async {
    final row = await (_db.select(_db.settings)..where((s) => s.id.equals(_key))).getSingleOrNull();
    if (row == null) return null;
    try {
      final json = jsonDecode(row.value);
      if (json is! List<dynamic>) return null;
      return {for (final c in json) '$c'};
    } on FormatException {
      return null;
    }
  }

  Future<void> save(Set<String> regions) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(id: _key, value: jsonEncode(regions.toList()..sort())),
      );
}

/// The last manifest read, beside the places, for the screens offline.
final class RegionCatalogCopy {
  new(this._db);

  final CacheDatabase _db;

  static const _key = 'regions_manifest';

  Future<RegionCatalog?> load() async {
    final row = await (_db.select(
      _db.deviceState,
    )..where((s) => s.id.equals(_key))).getSingleOrNull();
    if (row == null) return null;
    try {
      final json = jsonDecode(row.value);
      if (json is! List<dynamic>) return null;
      return RegionCatalog([
        for (final r in json)
          if (r is Map<String, dynamic>) ?regionFromJson(r),
      ], fromCopy: true);
    } on Object catch (e) {
      // A copy written by another version of the app: the manifest is
      // asked again.
      _log.info('regions manifest copy unreadable: $e');
      return null;
    }
  }

  Future<void> save(RegionCatalog catalog) => _db
      .into(_db.deviceState)
      .insertOnConflictUpdate(
        DeviceStateCompanion.insert(
          id: _key,
          value: jsonEncode([for (final r in catalog.regions) regionToJson(r)]),
        ),
      );
}
