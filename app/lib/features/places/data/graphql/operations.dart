import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:meta/meta.dart';

/// One GraphQL operation the app sends: its document and how to read its
/// `data`. Every instance is listed in [allOperations], which the contract
/// test validates against `schema/lunaway.graphql`.
@immutable
final class GraphQLOperation<T> {
  const new({required this.name, required this.document, required this.parse});

  final String name;
  final String document;
  final T Function(Map<String, dynamic> data) parse;
}

/// Everything the offline store keeps of a place. Photos and reviews are
/// left out: they are read online on demand ([extrasOperation]).
const _placeFields = '''
fragment PlaceFields on Place {
  id
  name
  kind
  lat
  lon
  overnight
  services
  activities
  description
  address { street postcode city countryCode }
  municipality
  priceParkingEur
  priceServicesEur
  maxHeightM
  capacity
  stars
  openingHours
  openingHoursParsed
  openingIntervals { start end }
  openingIntervalsUntil
  website
  phone
  lastConfirmedAt
  updatedAt
  sources {
    source { id name licence attribution url }
    externalId
    externalUrl
    fetchedAt
    matchScore
  }
  provenance { field sourceId alternatives { sourceId value } }
  descriptions { lang text sourceId }
  ratings { sourceId average count }
  externalLinks { sourceId url label }
  verification
  reviewCount
  photoCount
  coverPhotos { id sourceId thumbUrl largeUrl width height thumbhash authorId }
  reportedIssues { kind count lastReportedAt }
}
''';

const _reviewFields = '''
fragment ReviewFields on ReviewConnection {
  nodes { id sourceId rating text lang authorName authorId authorVehicle visitedAt createdAt }
  endCursor
  hasNextPage
  totalCount
}
''';

/// The reader's own review of a place: every status, with the place.
const myReviewFields = '''
fragment MyReviewFields on Review {
  id
  sourceId
  placeId
  rating
  text
  lang
  authorName
  authorId
  authorVehicle
  visitedAt
  createdAt
  status
}
''';

/// A page of the delta sync.
@immutable
final class ChangeSet {
  const new({
    required this.places,
    required this.deleted,
    required this.cursor,
    required this.hasMore,
  });

  final List<Place> places;
  final List<String> deleted;
  final String cursor;
  final bool hasMore;
}

final changesOperation = GraphQLOperation<ChangeSet>(
  name: 'Changes',
  document: '''
query Changes(\$bbox: BBoxInput!, \$since: String, \$first: Int) {
  changes(bbox: \$bbox, since: \$since, first: \$first) {
    places { ...PlaceFields }
    deleted
    cursor
    hasMore
  }
}
$_placeFields''',
  parse: (data) {
    final set = data['changes'] as Map<String, dynamic>;
    return ChangeSet(
      places: [
        for (final p in set['places'] as List<dynamic>)
          placeFromJson(p as Map<String, dynamic>),
      ],
      deleted: [for (final d in set['deleted'] as List<dynamic>) d as String],
      cursor: set['cursor'] as String,
      hasMore: set['hasMore'] as bool,
    );
  },
);

Map<String, Object?> changesVariables({
  required GeoBounds bbox,
  String? since,
  int first = 1000,
}) => {
  'bbox': {
    'south': bbox.south,
    'west': bbox.west,
    'north': bbox.north,
    'east': bbox.east,
  },
  'since': since,
  'first': first,
};

/// What a place shows online: its photos, the first page of reviews, and
/// the reader's own review (null when anonymous); null when the place no
/// longer exists.
typedef PlaceExtrasRead = ({
  List<Photo> photos,
  ReviewPage reviews,
  Review? myReview,
});

final extrasOperation = GraphQLOperation<PlaceExtrasRead?>(
  name: 'PlaceExtras',
  document: '''
query PlaceExtras(\$id: UUID!, \$first: Int) {
  place(id: \$id) {
    id
    photos { id sourceId thumbUrl largeUrl width height thumbhash authorId authorName createdAt }
    reviews(first: \$first) { ...ReviewFields }
    myReview { ...MyReviewFields }
  }
}
$_reviewFields$myReviewFields''',
  parse: (data) {
    final place = data['place'];
    if (place is! Map<String, dynamic>) return null;
    return (
      photos: photosFromJson(place['photos']),
      reviews: reviewPageFromJson(place['reviews']),
      myReview: reviewFromJson(place['myReview']),
    );
  },
);

/// The next page of reviews after a cursor.
final reviewsOperation = GraphQLOperation<ReviewPage>(
  name: 'PlaceReviews',
  document: '''
query PlaceReviews(\$id: UUID!, \$first: Int, \$after: String) {
  place(id: \$id) {
    id
    reviews(first: \$first, after: \$after) { ...ReviewFields }
  }
}
$_reviewFields''',
  parse: (data) {
    final place = data['place'];
    return place is Map<String, dynamic>
        ? reviewPageFromJson(place['reviews'])
        : ReviewPage.empty;
  },
);

/// Every operation the app can send, for the contract test.
final allOperations = <GraphQLOperation<Object?>>[
  changesOperation,
  extrasOperation,
  reviewsOperation,
];
