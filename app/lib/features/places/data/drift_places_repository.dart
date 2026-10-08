import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// [PlacesRepository] and [SyncStore] over the drift database: the R*Tree
/// answers the viewport, FTS5 the search, and filters are SQL predicates.
final class DriftPlacesRepository implements PlacesRepository, SyncStore {
  new(this._db);

  final CacheDatabase _db;

  static const _summaryColumns =
      'p.id, p.name, p.kind, p.lat, p.lon, p.overnight, p.services, p.price_parking, p.city, '
      'p.rating_avg, p.rating_count, p.verification';

  @override
  Stream<List<PlaceSummary>> watchAll(PlaceFilter filter) {
    final where = _filterSql(filter);
    return _db
        .customSelect(
          'SELECT $_summaryColumns FROM places p WHERE ${where.sql}',
          variables: where.variables,
          readsFrom: {_db.places},
        )
        .watch()
        .map((rows) => rows.map(_summary).toList());
  }

  @override
  Stream<List<PlaceSummary>> watchInBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng center,
    int limit = 200,
  }) {
    final where = _filterSql(filter);
    // Squared equirectangular distance: the order it gives matches the true
    // distance at the scale of a screen, without math functions in SQL.
    final k = math.cos(center.lat * math.pi / 180);
    return _db
        .customSelect(
          'SELECT $_summaryColumns FROM places p '
          'JOIN place_bounds b ON b.rid = p.rid '
          'WHERE b.min_lat >= ? AND b.max_lat <= ? AND b.min_lon >= ? AND b.max_lon <= ? '
          'AND ${where.sql} '
          'ORDER BY (p.lat - ?) * (p.lat - ?) + (p.lon - ?) * (p.lon - ?) * ? '
          'LIMIT ?',
          variables: [
            Variable.withReal(bounds.south),
            Variable.withReal(bounds.north),
            Variable.withReal(bounds.west),
            Variable.withReal(bounds.east),
            ...where.variables,
            Variable.withReal(center.lat),
            Variable.withReal(center.lat),
            Variable.withReal(center.lon),
            Variable.withReal(center.lon),
            Variable.withReal(k * k),
            Variable.withInt(limit),
          ],
          readsFrom: {_db.places},
        )
        .watch()
        .map((rows) => rows.map(_summary).toList());
  }

  @override
  Stream<Place?> watchPlace(String id) => (_db.select(_db.places)..where((p) => p.id.equals(id)))
      .watchSingleOrNull()
      .map((row) => row == null ? null : _place(row));

  @override
  Future<SearchResults> search(String text, {LatLng? near, int limit = 20}) async {
    final match = ftsPrefixQuery(text);
    if (match == null) return SearchResults.empty;
    final placeRows = await _db
        .customSelect(
          'SELECT $_summaryColumns FROM place_search s JOIN places p ON p.rid = s.rowid '
          'WHERE place_search MATCH ? ORDER BY bm25(place_search, 10.0, 2.0, 1.0) LIMIT ?',
          variables: [Variable.withString(match), Variable.withInt(limit * 3)],
          readsFrom: {_db.places},
        )
        .get();
    var places = placeRows.map(_summary).toList();
    if (near != null) {
      // Among matches, the nearest is the likeliest intent ("aire" near me).
      places.sort((a, b) => a.position.distanceTo(near).compareTo(b.position.distanceTo(near)));
    }
    places = places.take(limit).toList();

    final townRows = await _db
        .customSelect(
          'SELECT p.city AS city, MIN(p.postcode) AS postcode, AVG(p.lat) AS lat, AVG(p.lon) AS lon, '
          'COUNT(*) AS n FROM place_search s JOIN places p ON p.rid = s.rowid '
          'WHERE place_search MATCH ? AND p.city IS NOT NULL '
          'GROUP BY p.city ORDER BY n DESC LIMIT 5',
          variables: [Variable.withString('city : ($match)')],
          readsFrom: {_db.places},
        )
        .get();
    final towns = [
      for (final r in townRows)
        Municipality(
          name: r.read<String>('city'),
          postcode: r.readNullable<String>('postcode'),
          center: LatLng(r.read<double>('lat'), r.read<double>('lon')),
          placeCount: r.read<int>('n'),
        ),
    ];
    return SearchResults(places: places, municipalities: towns);
  }

  @override
  Stream<int> watchCount() => _db.places.count().watchSingle();

  @override
  Future<int> countMatching(PlaceFilter filter, {GeoBounds? bounds}) async {
    final where = _filterSql(filter);
    // The view as watchInBounds reads it, through the R-tree of positions.
    final row = await _db
        .customSelect(
          bounds == null
              ? 'SELECT COUNT(*) AS n FROM places p WHERE ${where.sql}'
              : 'SELECT COUNT(*) AS n FROM places p JOIN place_bounds b ON b.rid = p.rid '
                    'WHERE b.min_lat >= ? AND b.max_lat <= ? AND b.min_lon >= ? '
                    'AND b.max_lon <= ? AND ${where.sql}',
          variables: [
            if (bounds != null) ...[
              Variable.withReal(bounds.south),
              Variable.withReal(bounds.north),
              Variable.withReal(bounds.west),
              Variable.withReal(bounds.east),
            ],
            ...where.variables,
          ],
        )
        .getSingle();
    return row.read<int>('n');
  }

  @override
  Future<int> storageSizeBytes() => _db.sizeInBytes();

  // SyncStore

  @override
  Stream<SyncState> watchSync(String region) =>
      (_db.select(_db.regionSyncs)..where((s) => s.region.equals(region))).watchSingleOrNull().map(
        (row) => row == null ? SyncState.none : _syncState(row),
      );

  @override
  Future<SyncState> stateOf(String region) async {
    final row = await (_db.select(
      _db.regionSyncs,
    )..where((s) => s.region.equals(region))).getSingleOrNull();
    return row == null ? SyncState.none : _syncState(row);
  }

  static SyncState _syncState(SyncStateRow r) => SyncState(
    cursor: r.cursor,
    generation: r.generation,
    fullSync: r.fullSync,
    running: r.running,
    completedAt: r.completedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.completedAt!, isUtc: true),
  );

  @override
  Future<void> beginFullSync(String region) => _db.transaction(() async {
    final state = await stateOf(region);
    await _db
        .into(_db.regionSyncs)
        .insertOnConflictUpdate(
          RegionSyncsCompanion.insert(
            region: region,
            cursor: const Value(null),
            generation: Value(state.generation + 1),
            fullSync: const Value(true),
            running: const Value(true),
            completedAt: Value(state.completedAt?.millisecondsSinceEpoch),
          ),
        );
  });

  @override
  Future<void> beginDeltaSync(String region) => (_db.update(
    _db.regionSyncs,
  )..where((s) => s.region.equals(region))).write(const RegionSyncsCompanion(running: Value(true)));

  @override
  Future<void> applyPage(String region, ChangeSet page) => _db.transaction(() async {
    final generation = (await stateOf(region)).generation;
    await _db.batch((batch) {
      for (final p in page.places) {
        final row = placeCompanion(p, generation);
        batch.insert(_db.places, row, onConflict: DoUpdate((_) => row, target: [_db.places.id]));
      }
      if (page.deleted.isNotEmpty) {
        batch.deleteWhere(_db.places, (p) => p.id.isIn(page.deleted));
      }
    });
    await (_db.update(_db.regionSyncs)..where((s) => s.region.equals(region))).write(
      RegionSyncsCompanion(cursor: Value(page.cursor)),
    );
  });

  @override
  Future<int> completeRun(String region, GeoBounds bounds, DateTime at) =>
      _db.transaction(() async {
        final state = await stateOf(region);
        var swept = 0;
        if (state.fullSync) {
          swept =
              await (_db.delete(_db.places)..where(
                    (p) =>
                        p.syncGen.isSmallerThanValue(state.generation) &
                        p.lat.isBetweenValues(bounds.south, bounds.north) &
                        p.lon.isBetweenValues(bounds.west, bounds.east),
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

  /// Forgets every place and every sync: the web, which reads the places
  /// from the API now, drops the copy an earlier version of the app synced
  /// into the browser's storage.
  Future<int> forgetAll() => _db.transaction(() async {
    await _db.delete(_db.regionSyncs).go();
    return await _db.delete(_db.places).go();
  });

  @override
  Future<void> reset(String region, GeoBounds bounds) => _db.transaction(() async {
    await (_db.delete(_db.regionSyncs)..where((s) => s.region.equals(region))).go();
    await (_db.delete(_db.places)..where(
          (p) =>
              p.lat.isBetweenValues(bounds.south, bounds.north) &
              p.lon.isBetweenValues(bounds.west, bounds.east),
        ))
        .go();
  });

  /// The row of [p], written by the sync of [generation]; [region] is the
  /// sync region it came with (null for the sync by box).
  PlacesCompanion placeCompanion(Place p, int generation, {String? region}) =>
      PlacesCompanion.insert(
        id: p.id,
        region: region == null ? const Value.absent() : Value(region),
        name: Value(p.name),
        kind: p.kind.wire,
        family: p.kind.family.index,
        lat: p.lat,
        lon: p.lon,
        overnight: p.overnight.wire,
        services: Value(Service.maskOf(p.services)),
        activities: Value(Activity.maskOf(p.activities)),
        description: Value(p.description),
        street: Value(p.address?.street),
        postcode: Value(p.address?.postcode),
        city: Value(p.address?.city),
        countryCode: Value(p.address?.countryCode),
        priceParking: Value(p.priceParkingEur),
        priceServices: Value(p.priceServicesEur),
        maxHeight: Value(p.maxHeightM),
        capacity: Value(p.capacity),
        openingHours: Value(p.openingHours),
        openingHoursParsed: Value(p.openingHoursParsed),
        openingIntervalsJson: Value(
          p.openingIntervals == null || p.openingValidUntil == null
              ? null
              : jsonEncode(openingIntervalsToJson(p.openingIntervals)),
        ),
        // The server says where its window ends; the window is meaningless
        // without that end, so intervals without one are dropped.
        openingValidUntil: Value(
          p.openingIntervals == null ? null : p.openingValidUntil?.millisecondsSinceEpoch,
        ),
        stars: Value(p.stars),
        syncGen: Value(generation),
        website: Value(p.website),
        phone: Value(p.phone),
        lastConfirmedAt: Value(p.lastConfirmedAt?.millisecondsSinceEpoch),
        updatedAt: p.updatedAt.millisecondsSinceEpoch,
        sourcesJson: Value(jsonEncode([for (final s in p.sources) placeSourceToJson(s)])),
        provenanceJson: Value(jsonEncode([for (final f in p.provenance) fieldProvenanceToJson(f)])),
        descriptionsJson: Value(jsonEncode(localizedTextsToJson(p.descriptions))),
        ratingsJson: Value(jsonEncode(ratingsToJson(p.ratings))),
        linksJson: Value(jsonEncode(externalLinksToJson(p.externalLinks))),
        ratingAvg: Value(combinedRating(p.ratings)?.average),
        ratingCount: Value(combinedRating(p.ratings)?.count ?? 0),
        verification: Value(p.verification.wire),
        reviewCount: Value(p.reviewCount),
        photoCount: Value(p.photoCount),
        coverPhotosJson: Value(jsonEncode(photosToJson(p.coverPhotos))),
        issuesJson: Value(jsonEncode(issuesToJson(p.reportedIssues))),
      );

  Place _place(PlaceRow r) => Place(
    id: r.id,
    name: r.name,
    kind: PlaceKind.fromWire(r.kind),
    lat: r.lat,
    lon: r.lon,
    overnight: OvernightStatus.fromWire(r.overnight),
    services: Service.fromMask(r.services),
    activities: Activity.fromMask(r.activities),
    description: r.description,
    address: (r.street == null && r.postcode == null && r.city == null && r.countryCode == null)
        ? null
        : Address(street: r.street, postcode: r.postcode, city: r.city, countryCode: r.countryCode),
    priceParkingEur: r.priceParking,
    priceServicesEur: r.priceServices,
    maxHeightM: r.maxHeight,
    capacity: r.capacity,
    stars: r.stars,
    openingHours: r.openingHours,
    openingHoursParsed: r.openingHoursParsed,
    openingIntervals: r.openingIntervalsJson == null
        ? null
        : openingIntervalsFromJson(jsonDecode(r.openingIntervalsJson!)),
    openingValidUntil: r.openingValidUntil == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.openingValidUntil!, isUtc: true),
    website: r.website,
    phone: r.phone,
    lastConfirmedAt: r.lastConfirmedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.lastConfirmedAt!, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt, isUtc: true),
    sources: [
      for (final s in jsonDecode(r.sourcesJson) as List<dynamic>)
        placeSourceFromJson(s as Map<String, dynamic>),
    ],
    provenance: [
      for (final f in jsonDecode(r.provenanceJson) as List<dynamic>)
        fieldProvenanceFromJson(f as Map<String, dynamic>),
    ],
    descriptions: localizedTextsFromJson(jsonDecode(r.descriptionsJson)),
    ratings: ratingsFromJson(jsonDecode(r.ratingsJson)),
    externalLinks: externalLinksFromJson(jsonDecode(r.linksJson)),
    verification: Verification.fromWire(r.verification),
    reviewCount: r.reviewCount,
    photoCount: r.photoCount,
    coverPhotos: photosFromJson(jsonDecode(r.coverPhotosJson)),
    reportedIssues: issuesFromJson(jsonDecode(r.issuesJson)),
  );

  PlaceSummary _summary(QueryRow r) => PlaceSummary(
    id: r.read<String>('id'),
    name: r.readNullable<String>('name'),
    city: r.readNullable<String>('city'),
    kind: PlaceKind.fromWire(r.read<String>('kind')),
    lat: r.read<double>('lat'),
    lon: r.read<double>('lon'),
    overnight: OvernightStatus.fromWire(r.read<String>('overnight')),
    services: Service.fromMask(r.read<int>('services')),
    priceParkingEur: r.readNullable<double>('price_parking'),
    ratingAverage: r.readNullable<double>('rating_avg'),
    ratingCount: r.read<int>('rating_count'),
    verification: Verification.fromWire(r.read<String>('verification')),
  );
}

typedef _Where = ({String sql, List<Variable<Object>> variables});

/// The WHERE clause of [filter] over the `p` alias of `places`.
_Where _filterSql(PlaceFilter filter) {
  final clauses = <String>['1 = 1'];
  final variables = <Variable<Object>>[];
  if (filter.families.isNotEmpty) {
    clauses.add('p.family IN (${List.filled(filter.families.length, '?').join(', ')})');
    variables.addAll(filter.families.map((f) => Variable.withInt(f.index)));
  }
  if (filter.overnight.isNotEmpty) {
    clauses.add('p.overnight IN (${List.filled(filter.overnight.length, '?').join(', ')})');
    variables.addAll(filter.overnight.map((o) => Variable.withString(o.wire)));
  }
  for (final amenity in filter.amenities) {
    clauses.add('(p.services & ?) != 0');
    variables.add(Variable.withInt(amenity.mask));
  }
  if (filter.freeOnly) clauses.add('p.price_parking = 0');
  final height = filter.vehicleHeightM;
  if (height != null) {
    clauses.add('(p.max_height IS NULL OR p.max_height >= ?)');
    variables.add(Variable.withReal(height));
  }
  return (sql: clauses.join(' AND '), variables: variables);
}
