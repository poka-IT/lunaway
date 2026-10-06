import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A description in one language, from one source.
@immutable
final class LocalizedText {
  const new({required this.lang, required this.text, required this.sourceId});

  final String lang;
  final String text;
  final String sourceId;

  @override
  bool operator ==(Object other) =>
      other is LocalizedText &&
      other.lang == lang &&
      other.text == text &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(lang, text, sourceId);
}

/// The average rating a source gives a place, and over how many reviews.
@immutable
final class SourceRating {
  const new({required this.sourceId, required this.average, required this.count});

  final String sourceId;
  final double average;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SourceRating &&
      other.sourceId == sourceId &&
      other.average == average &&
      other.count == count;

  @override
  int get hashCode => Object.hash(sourceId, average, count);
}

/// The page of a place on a source's own site.
@immutable
final class ExternalLink {
  const new({required this.sourceId, required this.url, required this.label});

  final String sourceId;
  final String url;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ExternalLink &&
      other.sourceId == sourceId &&
      other.url == url &&
      other.label == label;

  @override
  int get hashCode => Object.hash(sourceId, url, label);
}

/// A photo of a place, served by the Lunaway image proxy.
@immutable
final class Photo {
  const new({
    required this.id,
    required this.sourceId,
    required this.thumbUrl,
    required this.largeUrl,
  });

  final String id;
  final String sourceId;
  final String thumbUrl;
  final String largeUrl;

  @override
  bool operator ==(Object other) =>
      other is Photo &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.thumbUrl == thumbUrl &&
      other.largeUrl == largeUrl;

  @override
  int get hashCode => Object.hash(id, sourceId, thumbUrl, largeUrl);
}

/// The source of what Lunaway users write: reviews, photos, places.
const communitySourceId = 'community';

/// The vehicle a reviewer travelled in, as the API names it.
enum ReviewVehicle {
  van('VAN'),
  campervan('CAMPERVAN'),
  motorhome('MOTORHOME'),
  caravan('CARAVAN'),
  other('OTHER');

  new(this.wire);

  final String wire;

  /// Null for a value this version does not know: a newer server may add
  /// one, and the review still shows without it.
  static ReviewVehicle? fromWire(Object? wire) => values.where((v) => v.wire == wire).firstOrNull;
}

/// What a visitor wrote about a place, on the source it was written on.
@immutable
final class Review {
  const new({
    required this.id,
    required this.sourceId,
    required this.createdAt,
    this.rating,
    this.text,
    this.lang,
    this.authorName,
    this.authorVehicle,
    this.visitedAt,
  });

  final String id;
  final String sourceId;

  /// Out of 5; null when the visitor gave none.
  final int? rating;
  final String? text;
  final String? lang;

  /// Null once the author deleted their account.
  final String? authorName;
  final ReviewVehicle? authorVehicle;

  /// The day of the stay, a calendar date (local midnight) without a time
  /// zone of its own.
  final DateTime? visitedAt;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is Review &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.rating == rating &&
      other.text == text &&
      other.lang == lang &&
      other.authorName == authorName &&
      other.authorVehicle == authorVehicle &&
      other.visitedAt == visitedAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, sourceId, rating, createdAt);
}

/// One page of reviews and where the next one starts.
@immutable
final class ReviewPage {
  const new({
    required this.nodes,
    required this.hasNextPage,
    required this.totalCount,
    this.endCursor,
  });

  static const empty = ReviewPage(nodes: [], hasNextPage: false, totalCount: 0);

  final List<Review> nodes;
  final String? endCursor;
  final bool hasNextPage;
  final int totalCount;

  ReviewPage append(ReviewPage next) => ReviewPage(
    nodes: [...nodes, ...next.nodes],
    endCursor: next.endCursor,
    hasNextPage: next.hasNextPage,
    totalCount: next.totalCount,
  );

  @override
  bool operator ==(Object other) =>
      other is ReviewPage &&
      const ListEquality<Review>().equals(other.nodes, nodes) &&
      other.endCursor == endCursor &&
      other.hasNextPage == hasNextPage &&
      other.totalCount == totalCount;

  @override
  int get hashCode => Object.hash(Object.hashAll(nodes), endCursor, hasNextPage, totalCount);
}

/// What the offline sync leaves out of a place: its photos and its reviews,
/// read online and kept in a cache.
@immutable
final class PlaceExtras {
  const new({required this.photos, required this.reviews, required this.fetchedAt});

  final List<Photo> photos;
  final ReviewPage reviews;
  final DateTime fetchedAt;

  PlaceExtras withReviews(ReviewPage reviews) =>
      PlaceExtras(photos: photos, reviews: reviews, fetchedAt: fetchedAt);

  @override
  bool operator ==(Object other) =>
      other is PlaceExtras &&
      const ListEquality<Photo>().equals(other.photos, photos) &&
      other.reviews == reviews &&
      other.fetchedAt == fetchedAt;

  @override
  int get hashCode => Object.hash(Object.hashAll(photos), reviews, fetchedAt);
}

/// The rating of a place across its sources: the mean weighted by the number
/// of reviews, and the total count. Null without any review.
({double average, int count})? combinedRating(List<SourceRating> ratings) {
  var count = 0;
  var sum = 0.0;
  for (final r in ratings) {
    if (r.count <= 0) continue;
    count += r.count;
    sum += r.average * r.count;
  }
  return count == 0 ? null : (average: sum / count, count: count);
}

/// The description to show in [lang]: that language if a source wrote one,
/// else English, else the first. `translated` is false when the text is in
/// another language than asked, so the screen can say which.
({LocalizedText text, bool inUserLanguage})? descriptionFor(
  List<LocalizedText> texts,
  String lang,
) {
  if (texts.isEmpty) return null;
  final own = texts.where((t) => t.lang == lang).firstOrNull;
  if (own != null) return (text: own, inUserLanguage: true);
  final fallback = texts.where((t) => t.lang == 'en').firstOrNull ?? texts.first;
  return (text: fallback, inUserLanguage: false);
}
