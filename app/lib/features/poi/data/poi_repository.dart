import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

final _log = Logger('poi');

/// Where the points of interest come from: the API, online. The map reads
/// its tiles directly; this answers the lists and the pages.
abstract interface class PoiSource {
  /// The raw `data` of the operations, so the cache keeps what the server
  /// said and reads it back with the same parser.
  Future<Map<String, dynamic>> nearby(String placeId);

  Future<Map<String, dynamic>> page(String poiId);

  /// The reviews of a point, the account's own among them; null when the
  /// point is gone.
  Future<PoiReviews?> reviews(String poiId, {int first = 20});

  /// A page of the fuel stations of [box] with their prices, from [after].
  Future<FuelStationsPage> fuelStations(GeoBounds box, {String? after});
}

final class GraphQLPoiSource implements PoiSource {
  new(this.client, {this.headers});

  final GraphQLClient client;

  /// The session of the account, when the device has one: the server then
  /// adds the reader's own review and leaves out the authors it muted. A
  /// read never signs in.
  final Future<Map<String, String>> Function()? headers;

  @override
  Future<Map<String, dynamic>> nearby(String placeId) =>
      client.execute(_raw(nearbyPoisOperation), nearbyPoisVariables(placeId: placeId));

  @override
  Future<Map<String, dynamic>> page(String poiId) =>
      client.execute(_raw(poiOperation), {'id': poiId});

  @override
  Future<PoiReviews?> reviews(String poiId, {int first = 20}) async => await client.execute(
    poiReviewsOperation,
    {'id': poiId, 'first': first},
    await headers?.call() ?? const {},
  );

  @override
  Future<FuelStationsPage> fuelStations(GeoBounds box, {String? after}) =>
      client.execute(fuelStationsOperation, fuelStationsVariables(box, after: after));

  /// The same document, answering its `data` untouched.
  static GraphQLOperation<Map<String, dynamic>> _raw(GraphQLOperation<Object?> op) =>
      GraphQLOperation(name: op.name, document: op.document, parse: (data) => data);
}

/// What was read about points, with when, and whether it is a copy kept
/// from an earlier read because the network did not answer now.
@immutable
final class Read<T> {
  const new(this.value, {required this.fetchedAt, this.offline = false});

  final T value;
  final DateTime fetchedAt;
  final bool offline;
}

/// "Around this place" and the pages of points: the copy kept on the
/// device at once, then a fresh read when the copy is missing or older than
/// [maxAge]. Offline with a copy, the copy stays (marked [Read.offline]);
/// offline without one, the error reaches the screen.
final class PoiRepository {
  new({
    required this.db,
    required this.source,
    this.clock = DateTime.now,
    this.maxAge = const Duration(hours: 6),
    this.keep = 400,
  });

  final CacheDatabase db;
  final PoiSource source;
  final DateTime Function() clock;
  final Duration maxAge;

  /// How many reads the device keeps; the oldest go first.
  final int keep;

  Stream<Read<List<NearbyPois>>> watchNearby(String placeId) => _watch(
    'nearby:$placeId',
    () => source.nearby(placeId),
    (data) => nearbyPoisFromJson(data['nearbyPois']),
  );

  /// Null inside when the point is gone or hidden.
  Stream<Read<PoiPage?>> watchPage(String poiId) =>
      _watch('poi:$poiId', () => source.page(poiId), poiPageFromJson);

  /// The reviews of a point, online: they follow what the account just
  /// sent, a copy would not.
  Future<PoiReviews?> reviews(String poiId) => source.reviews(poiId);

  /// The fuel stations of [box] with their prices, online: prices change
  /// every quarter of an hour, a copy would mislead. Null when the area
  /// holds more fuel points than [fuelPages] pages: a part of the stations
  /// would rank as the cheapest without being so.
  Future<List<Poi>?> fuelStations(GeoBounds box) async {
    final stations = <Poi>[];
    String? after;
    for (var page = 0; page < fuelPages; page++) {
      final read = await source.fuelStations(box, after: after);
      stations.addAll(read.stations);
      if (!read.hasNextPage) return stations;
      after = read.endCursor;
      // More, and no way to ask for them: as many as too many.
      if (after == null) return null;
    }
    return null;
  }

  /// The pages of a thousand fuel points read for one area at most: a
  /// large town and its suburbs at the zoom the stations show from.
  static const fuelPages = 3;

  /// Forgets the page of a point: after a "still there?", the next read
  /// asks the server.
  Future<void> forgetPage(String poiId) =>
      (db.delete(db.poiCache)..where((e) => e.cacheKey.equals('poi:$poiId'))).go();

  Stream<Read<T>> _watch<T>(
    String key,
    Future<Map<String, dynamic>> Function() fetch,
    T Function(Map<String, dynamic>) parse,
  ) async* {
    final cached = await _read(key, parse);
    if (cached != null) yield cached;
    if (cached != null && clock().difference(cached.fetchedAt) < maxAge) return;
    try {
      final data = await fetch();
      final at = clock().toUtc();
      await _write(key, data, at);
      yield Read(parse(data), fetchedAt: at);
    } on Object catch (e) {
      if (cached == null) rethrow;
      // Only a failure to reach the server leaves the copy as it is; a
      // refusal is an answer the screen must see.
      if (e is! GraphQLNetworkException) rethrow;
      _log.info('$key: kept the copy read ${cached.fetchedAt} ($e)');
      yield Read(cached.value, fetchedAt: cached.fetchedAt, offline: true);
    }
  }

  Future<Read<T>?> _read<T>(String key, T Function(Map<String, dynamic>) parse) async {
    final row = await (db.select(
      db.poiCache,
    )..where((e) => e.cacheKey.equals(key))).getSingleOrNull();
    if (row == null) return null;
    try {
      final data = jsonDecode(row.json);
      if (data is! Map<String, dynamic>) return null;
      return Read(
        parse(data),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.fetchedAt, isUtc: true),
      );
    } on Object catch (e) {
      // A copy written by another version that no longer reads: read again.
      _log.info('$key: copy unreadable ($e)');
      return null;
    }
  }

  Future<void> _write(String key, Map<String, dynamic> data, DateTime at) async {
    await db
        .into(db.poiCache)
        .insertOnConflictUpdate(
          PoiCacheCompanion.insert(
            cacheKey: key,
            json: jsonEncode(data),
            fetchedAt: at.millisecondsSinceEpoch,
          ),
        );
    await db.customStatement(
      'DELETE FROM poi_cache WHERE cache_key NOT IN '
      '(SELECT cache_key FROM poi_cache ORDER BY fetched_at DESC LIMIT ?)',
      [keep],
    );
  }
}
