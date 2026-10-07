import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';

final _log = Logger('places');

/// The places as the API answers for them, online: what a screen reads
/// when the device holds no copy of the area (the web, which keeps none;
/// a phone before its regions arrive). Each call is one small request.
abstract interface class OnlinePlaces {
  /// The places of [bounds] passing [filter], nearest to [near] first, a
  /// page of [first] after the cursor [after].
  Future<PlacePage> inBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng near,
    int first = 50,
    String? after,
  });

  /// The places whose name or town matches [text].
  Future<List<PlaceSummary>> search(String text, {LatLng? near, int first = 20});

  /// One place; null when it is gone.
  Future<Place?> place(String id);
}

final class GraphQLOnlinePlaces implements OnlinePlaces {
  new(this.client);

  final GraphQLClient client;

  @override
  Future<PlacePage> inBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng near,
    int first = 50,
    String? after,
  }) => client.execute(nearbyPlacesOperation, {
    // The box and the point on a grid of about 5 km: a view brought to the
    // user is centred on them, and its exact edges would say where they
    // stand.
    'bbox': bboxInput(placesQueryBox(bounds)),
    'filter': placeFilterInput(filter),
    'near': _point(searchAnchor(near)),
    'first': first,
    'after': after,
  });

  static Map<String, Object?> _point(LatLng p) => {'lat': p.lat, 'lon': p.lon};

  @override
  Future<List<PlaceSummary>> search(String text, {LatLng? near, int first = 20}) => client.execute(
    searchPlacesOperation,
    {'text': text, 'near': near == null ? null : _point(searchAnchor(near)), 'first': first},
  );

  @override
  Future<Place?> place(String id) => client.execute(placeOperation, {'id': id});
}

/// A place for its page: the device's synced copy when its region is
/// kept (it follows the sync), else the copy kept from an earlier opening,
/// then the API's when that copy is missing or older than [maxAge] and
/// there is an API to ask ([online], null while the device is offline).
/// A failed request with a copy keeps the copy; without one, the error
/// reaches the screen.
final class PlaceReader {
  new({
    required this.db,
    required this.local,
    this.online,
    this.clock = DateTime.now,
    this.maxAge = const Duration(hours: 1),
  });

  final CacheDatabase db;
  final PlacesRepository local;
  final OnlinePlaces? online;
  final DateTime Function() clock;
  final Duration maxAge;

  Stream<Place?> watch(String id) async* {
    final synced = await local.watchPlace(id).first;
    if (synced != null) {
      yield* local.watchPlace(id);
      return;
    }
    final cached = await _read(id);
    final api = online;
    if (api == null) {
      // Offline: the copy, or nothing the device knows of.
      yield cached?.place;
      return;
    }
    if (cached != null) yield cached.place;
    if (cached != null && clock().difference(cached.fetchedAt) < maxAge) return;
    try {
      final fresh = await api.place(id);
      if (fresh == null) {
        await forget(id);
        yield null;
        return;
      }
      await _write(id, fresh);
      yield fresh;
    } on Object catch (e) {
      if (cached == null) rethrow;
      _log.info('$id: kept the copy of the place ($e)');
    }
  }

  /// The place once, as settled: the synced copy, else the API's answer,
  /// else the copy kept (a link opened offline).
  Future<Place?> read(String id) async {
    final synced = await local.watchPlace(id).first;
    if (synced != null) return synced;
    return await watch(id).last;
  }

  /// Forgets the copy of [id]: after a contribution to it, the next
  /// opening asks the server.
  Future<void> forget(String id) =>
      (db.delete(db.placeCache)..where((e) => e.placeId.equals(id))).go();

  Future<({Place place, DateTime fetchedAt})?> _read(String id) async {
    final row = await (db.select(
      db.placeCache,
    )..where((e) => e.placeId.equals(id))).getSingleOrNull();
    if (row == null) return null;
    try {
      return (
        place: placeFromJson(jsonDecode(row.json) as Map<String, dynamic>),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.fetchedAt, isUtc: true),
      );
    } on Object catch (e) {
      // A copy written by another version that this one cannot read: as if
      // there were none.
      _log.info('$id: unreadable copy of the place ($e)');
      return null;
    }
  }

  Future<void> _write(String id, Place place) => db
      .into(db.placeCache)
      .insertOnConflictUpdate(
        PlaceCacheCompanion.insert(
          // The id asked: a merged place answers with the one that absorbed
          // it, and the page asked for the first.
          placeId: id,
          json: jsonEncode(placeToJson(place)),
          fetchedAt: clock().toUtc().millisecondsSinceEpoch,
        ),
      );
}
