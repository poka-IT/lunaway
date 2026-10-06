import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

final _log = Logger('extras');

/// Where photos and reviews come from: the API, online.
abstract interface class PlaceExtrasSource {
  /// Null when the place no longer exists.
  Future<({List<Photo> photos, ReviewPage reviews})?> fetch(String placeId, {required int first});

  Future<ReviewPage> moreReviews(String placeId, {required String after, required int first});
}

final class GraphQLPlaceExtrasSource implements PlaceExtrasSource {
  new(this.client);

  final GraphQLClient client;

  @override
  Future<({List<Photo> photos, ReviewPage reviews})?> fetch(String placeId, {required int first}) =>
      client.execute(extrasOperation, {'id': placeId, 'first': first});

  @override
  Future<ReviewPage> moreReviews(String placeId, {required String after, required int first}) =>
      client.execute(reviewsOperation, {'id': placeId, 'first': first, 'after': after});
}

/// Photos and reviews of a place: the cached copy at once, then a fresh one
/// when the copy is missing or older than [maxAge]. Offline with a copy, the
/// copy stays; offline without one, the error reaches the screen.
final class PlaceExtrasRepository {
  new({
    required this.db,
    required this.source,
    this.clock = DateTime.now,
    this.maxAge = const Duration(hours: 12),
    this.pageSize = 20,
  });

  final CacheDatabase db;
  final PlaceExtrasSource source;
  final DateTime Function() clock;
  final Duration maxAge;
  final int pageSize;

  Stream<PlaceExtras?> watch(String placeId) async* {
    final cached = await _read(placeId);
    if (cached != null) yield cached;
    if (cached != null && clock().difference(cached.fetchedAt) < maxAge) return;
    try {
      final fresh = await source.fetch(placeId, first: pageSize);
      if (fresh == null) {
        yield null;
        return;
      }
      final extras = PlaceExtras(
        photos: fresh.photos,
        reviews: fresh.reviews,
        fetchedAt: clock().toUtc(),
      );
      await _write(placeId, extras);
      yield extras;
    } on Object catch (e) {
      if (cached == null) rethrow;
      _log.info('$placeId: kept the cached photos and reviews ($e)');
    }
  }

  /// The page after [page], online only; it is not cached (the first page
  /// is what a place shows offline).
  Future<ReviewPage> more(String placeId, ReviewPage page) async {
    final after = page.endCursor;
    if (!page.hasNextPage || after == null) return page;
    return page.append(await source.moreReviews(placeId, after: after, first: pageSize));
  }

  Future<PlaceExtras?> _read(String placeId) async {
    final row = await (db.select(
      db.placeExtrasCache,
    )..where((e) => e.placeId.equals(placeId))).getSingleOrNull();
    if (row == null) return null;
    try {
      final json = jsonDecode(row.json) as Map<String, dynamic>;
      return PlaceExtras(
        photos: photosFromJson(json['photos']),
        reviews: reviewPageFromJson(json['reviews']),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.fetchedAt, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String placeId, PlaceExtras extras) => db
      .into(db.placeExtrasCache)
      .insertOnConflictUpdate(
        PlaceExtrasCacheCompanion.insert(
          placeId: placeId,
          json: jsonEncode({
            'photos': photosToJson(extras.photos),
            'reviews': reviewPageToJson(extras.reviews),
          }),
          fetchedAt: extras.fetchedAt.millisecondsSinceEpoch,
        ),
      );
}
