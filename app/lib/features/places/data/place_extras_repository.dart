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
  Future<PlaceExtrasRead?> fetch(String placeId, {required int first});

  Future<ReviewPage> moreReviews(String placeId, {required String after, required int first});
}

final class GraphQLPlaceExtrasSource implements PlaceExtrasSource {
  new(this.client, {this.headers});

  final GraphQLClient client;

  /// The session of the account, when the device has one: the server then
  /// leaves out the authors it muted and adds its own review. A read never
  /// signs in.
  final Future<Map<String, String>> Function()? headers;

  @override
  Future<PlaceExtrasRead?> fetch(String placeId, {required int first}) async => await client
      .execute(extrasOperation, {'id': placeId, 'first': first}, await headers?.call() ?? const {});

  @override
  Future<ReviewPage> moreReviews(
    String placeId, {
    required String after,
    required int first,
  }) async => await client.execute(reviewsOperation, {
    'id': placeId,
    'first': first,
    'after': after,
  }, await headers?.call() ?? const {});
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
        myReview: fresh.myReview,
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

  /// Puts the account's own review of [placeId], as the server answered a
  /// rating, a review or a deletion, into the copy: the place shows it at
  /// once, without waiting for a new read.
  Future<void> putMyReview(String placeId, Review? review) async {
    final cached = await _read(placeId);
    if (cached == null) return;
    await _write(
      placeId,
      PlaceExtras(
        photos: cached.photos,
        reviews: cached.reviews,
        fetchedAt: cached.fetchedAt,
        myReview: review,
      ),
    );
  }

  /// Forgets the copy of [placeId]: after a contribution to it, the next
  /// read asks the server.
  Future<void> forget(String placeId) =>
      (db.delete(db.placeExtrasCache)..where((e) => e.placeId.equals(placeId))).go();

  /// Forgets every copy: they carry the reviews the account saw and its own
  /// review, which another account must not see.
  Future<void> forgetAll() => db.delete(db.placeExtrasCache).go();

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
        myReview: reviewFromJson(json['myReview']),
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
            if (extras.myReview != null) 'myReview': reviewToJson(extras.myReview!),
          }),
          fetchedAt: extras.fetchedAt.millisecondsSinceEpoch,
        ),
      );
}
