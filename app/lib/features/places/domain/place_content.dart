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

/// Where a contribution stands on the server.
enum ContributionStatus {
  /// Visible to everyone.
  published('PUBLISHED'),

  /// Held by the automatic rules until a moderator decides.
  pending('PENDING'),

  /// Hidden after reports, until a moderator decides.
  hidden('HIDDEN'),

  /// Removed by a moderator.
  removed('REMOVED');

  new(this.wire);

  final String wire;

  static ContributionStatus? fromWire(Object? wire) =>
      values.where((v) => v.wire == wire).firstOrNull;
}

/// A photo of a place, served by the Lunaway image proxy.
@immutable
final class Photo {
  const new({
    required this.id,
    required this.sourceId,
    required this.thumbUrl,
    required this.largeUrl,
    this.thumbhash,
    this.width,
    this.height,
    this.authorId,
    this.authorName,
    this.createdAt,
    this.status,
  });

  final String id;
  final String sourceId;
  final String thumbUrl;
  final String largeUrl;

  /// A ThumbHash (base64) of the image: the placeholder while it loads.
  final String? thumbhash;

  /// The large image's size, for the ratio of its frame before it loads.
  final int? width;
  final int? height;

  /// The author, to hide a muted author's photos; null once the account is
  /// deleted.
  final String? authorId;
  final String? authorName;
  final DateTime? createdAt;
  final ContributionStatus? status;

  @override
  bool operator ==(Object other) =>
      other is Photo &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.thumbUrl == thumbUrl &&
      other.largeUrl == largeUrl &&
      other.thumbhash == thumbhash &&
      other.width == width &&
      other.height == height &&
      other.authorId == authorId &&
      other.authorName == authorName &&
      other.createdAt == createdAt &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, sourceId, thumbUrl, largeUrl, thumbhash, authorId);
}

/// The source of what Lunaway users contribute to the places database
/// (places, edits, confirmations), under the ODbL.
const communitySourceId = 'community';

/// The source of what Lunaway users publish under their own name: reviews,
/// ratings and photos, under CC BY 4.0.
const communityCcBySourceId = 'community-cc-by';

/// Whether [sourceId] is one of Lunaway's own users: the places database's
/// (ODbL) or their reviews, ratings and photos (CC BY 4.0).
bool isLunawayCommunity(String sourceId) =>
    sourceId == communitySourceId || sourceId == communityCcBySourceId;

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
    this.authorId,
    this.authorVehicle,
    this.visitedAt,
    this.placeId,
    this.status,
  });

  final String id;
  final String sourceId;

  /// The place it was written for; set on the author's own reviews.
  final String? placeId;

  /// Where it stands; the author's own reviews may be held or hidden.
  final ContributionStatus? status;

  /// The author, to mute them; null once the account is deleted.
  final String? authorId;

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
      other.authorId == authorId &&
      other.authorVehicle == authorVehicle &&
      other.visitedAt == visitedAt &&
      other.createdAt == createdAt &&
      other.placeId == placeId &&
      other.status == status;

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

/// What the offline sync leaves out of a place: its photos, its reviews and
/// the reader's own review, read online and kept in a cache.
@immutable
final class PlaceExtras {
  const new({required this.photos, required this.reviews, required this.fetchedAt, this.myReview});

  final List<Photo> photos;
  final ReviewPage reviews;
  final DateTime fetchedAt;

  /// The reader's own rating or review, whatever its status; null when
  /// anonymous or when there is none.
  final Review? myReview;

  PlaceExtras withReviews(ReviewPage reviews) =>
      PlaceExtras(photos: photos, reviews: reviews, fetchedAt: fetchedAt, myReview: myReview);

  @override
  bool operator ==(Object other) =>
      other is PlaceExtras &&
      const ListEquality<Photo>().equals(other.photos, photos) &&
      other.reviews == reviews &&
      other.fetchedAt == fetchedAt &&
      other.myReview == myReview;

  @override
  int get hashCode => Object.hash(Object.hashAll(photos), reviews, fetchedAt, myReview);
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

/// The external community source: a partner community's reviews, ratings
/// and photos, shown under a written agreement with its own label and
/// attribution, read online when a place opens and never stored with the
/// places.
const extcomSourceId = 'extcom';

/// What the external community source says of a place: its photos, its
/// ratings as a whole (it counts more ratings than the reviews it hands
/// over) and a page of its reviews, newest first.
@immutable
final class ExternalContent {
  const new({required this.photos, required this.ratings, required this.reviews});

  /// A place the source says nothing of, or an API that does not serve it.
  static const empty = ExternalContent(photos: [], ratings: [], reviews: ReviewPage.empty);

  final List<Photo> photos;
  final List<SourceRating> ratings;
  final ReviewPage reviews;

  ExternalContent withReviews(ReviewPage reviews) =>
      ExternalContent(photos: photos, ratings: ratings, reviews: reviews);

  @override
  bool operator ==(Object other) =>
      other is ExternalContent &&
      const ListEquality<Photo>().equals(other.photos, photos) &&
      const ListEquality<SourceRating>().equals(other.ratings, ratings) &&
      other.reviews == reviews;

  @override
  int get hashCode => Object.hash(Object.hashAll(photos), Object.hashAll(ratings), reviews);
}

/// Which of the two review lists a place shows the next page should come
/// from.
enum ReviewOrigin { lunaway, external }

/// Lunaway's reviews and the external source's in one list, newest first.
/// Both arrive a page at a time: a review is shown only once no unread page
/// can hold a newer one, so the order never changes as pages come in, and
/// `next` names the list whose next page unblocks the rest (null when both
/// are read to the end). At the same instant, Lunaway's comes first.
({List<Review> reviews, ReviewOrigin? next}) mergeReviews(ReviewPage lunaway, ReviewPage external) {
  DateTime? limit(ReviewPage page) {
    if (!page.hasNextPage) return null;
    // A page that announces more but brought nothing blocks everything:
    // its next page may start with the newest review of all.
    return page.nodes.isEmpty ? _farFuture : page.nodes.last.createdAt;
  }

  final ours = limit(lunaway);
  final theirs = limit(external);
  final DateTime? boundary;
  final ReviewOrigin? next;
  if (ours == null && theirs == null) {
    boundary = null;
    next = null;
  } else if (theirs == null || (ours != null && !ours.isBefore(theirs))) {
    boundary = ours;
    next = ReviewOrigin.lunaway;
  } else {
    boundary = theirs;
    next = ReviewOrigin.external;
  }
  bool shown(Review r) => boundary == null || !r.createdAt.isBefore(boundary);
  final merged = <Review>[];
  var i = 0;
  var j = 0;
  final a = lunaway.nodes;
  final b = external.nodes;
  while (i < a.length || j < b.length) {
    final takeOurs = j >= b.length || (i < a.length && !a[i].createdAt.isBefore(b[j].createdAt));
    final r = takeOurs ? a[i++] : b[j++];
    if (!shown(r)) {
      // Both lists are newest first: everything after is older still,
      // but the other list may hold reviews on the right side of the
      // boundary.
      if (takeOurs) {
        i = a.length;
      } else {
        j = b.length;
      }
      continue;
    }
    merged.add(r);
  }
  return (reviews: merged, next: next);
}

final _farFuture = DateTime.utc(9999);
