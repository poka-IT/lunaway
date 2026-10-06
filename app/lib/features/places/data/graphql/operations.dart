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
}
''';

const _reviewFields = '''
fragment ReviewFields on ReviewConnection {
  nodes { id sourceId rating text lang authorName authorVehicle visitedAt createdAt }
  endCursor
  hasNextPage
  totalCount
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
        for (final p in set['places'] as List<dynamic>) placeFromJson(p as Map<String, dynamic>),
      ],
      deleted: [for (final d in set['deleted'] as List<dynamic>) d as String],
      cursor: set['cursor'] as String,
      hasMore: set['hasMore'] as bool,
    );
  },
);

Map<String, Object?> changesVariables({required GeoBounds bbox, String? since, int first = 1000}) =>
    {
      'bbox': {'south': bbox.south, 'west': bbox.west, 'north': bbox.north, 'east': bbox.east},
      'since': since,
      'first': first,
    };

/// The photos and the first page of reviews of a place; null when the place
/// no longer exists.
final extrasOperation = GraphQLOperation<({List<Photo> photos, ReviewPage reviews})?>(
  name: 'PlaceExtras',
  document: '''
query PlaceExtras(\$id: UUID!, \$first: Int) {
  place(id: \$id) {
    id
    photos { id sourceId thumbUrl largeUrl }
    reviews(first: \$first) { ...ReviewFields }
  }
}
$_reviewFields''',
  parse: (data) {
    final place = data['place'];
    if (place is! Map<String, dynamic>) return null;
    return (photos: photosFromJson(place['photos']), reviews: reviewPageFromJson(place['reviews']));
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
    return place is Map<String, dynamic> ? reviewPageFromJson(place['reviews']) : ReviewPage.empty;
  },
);

/// Every operation the app can send, for the contract test.
final allOperations = <GraphQLOperation<Object?>>[
  changesOperation,
  extrasOperation,
  reviewsOperation,
];
