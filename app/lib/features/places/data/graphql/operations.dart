import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// One GraphQL operation the app sends: its document and how to read its
/// `data`. Every instance is listed in [allOperations], which the contract
/// test validates against `schema/lunaway.graphql`.
@immutable
final class GraphQLOperation<T> {
  const new({required this.name, required this.document, required this.parse, this.older});

  final String name;
  final String document;
  final T Function(Map<String, dynamic> data) parse;

  /// The same request for an API that predates an argument or an input
  /// field this one sends: the client sends it when the server answers that
  /// it does not know one (an app published before the API it was built
  /// against).
  final OlderForm? older;
}

/// An operation as an older API reads it: [document] without the arguments
/// it does not know, and [variables] that drops what they carried.
@immutable
final class OlderForm {
  const new({
    required this.document,
    required this.variables,
    this.usable = _always,
    this.withoutFields = false,
    this.older,
  });

  /// [document] for an API that lacks fields it selects (`speedLimits` on
  /// a route): sent when the server answers that it does not know a field.
  /// [older] is the form for an API older still, tried when this one is
  /// refused in turn.
  factory selecting(String document, {OlderForm? older}) =>
      OlderForm(document: document, variables: _same, withoutFields: true, older: older);

  /// The form of [document] without [arguments]: their variables and their
  /// uses, wherever they stand on a line. [usable] says which requests may
  /// go in it: one whose meaning needs an argument the older API lacks
  /// waits for the API instead.
  factory without(
    String document,
    Set<String> arguments, {
    bool Function(Map<String, Object?> variables) usable = _always,
  }) {
    var older = document;
    for (final a in arguments) {
      older = older
          .replaceAll(RegExp(r',?\s*\$' + a + r':\s*[A-Za-z_!\[\]]+'), '')
          .replaceAll(RegExp(r',?\s*\b' + a + r':\s*\$' + a + r'\b'), '');
    }
    return OlderForm(
      document: older,
      variables: (v) => {
        for (final MapEntry(:key, :value) in v.entries)
          if (!arguments.contains(key)) key: value,
      },
      usable: usable,
    );
  }

  final String document;
  final Map<String, Object?> Function(Map<String, Object?> variables) variables;
  final bool Function(Map<String, Object?> variables) usable;

  /// The older form leaves out fields, not only arguments: an unknown
  /// field also calls for it.
  final bool withoutFields;

  /// The form for an API older than the one this form is for: fields
  /// added over two releases fall back one release at a time, so an API
  /// that knows the first keeps it.
  final OlderForm? older;

  static bool _always(Map<String, Object?> _) => true;

  static Map<String, Object?> _same(Map<String, Object?> variables) => variables;
}

/// Everything the offline store keeps of a place. Photos and reviews are
/// left out: they are read online on demand ([extrasOperation]).
const placeFieldsFragment = '''
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
  priceServicesIncluded
  priceParkingIncludes
  maxHeightM
  capacity
  stars
  openingHours
  openingHoursParsed
  openingIntervals { start end }
  openingIntervalsUntil
  openingSeason { from to }
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
  ratingForFilters
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
$placeFieldsFragment''',
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

/// What a place shows online: its photos, the first page of reviews, and
/// the reader's own review (null when anonymous); null when the place no
/// longer exists.
typedef PlaceExtrasRead = ({List<Photo> photos, ReviewPage reviews, Review? myReview});

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
    return place is Map<String, dynamic> ? reviewPageFromJson(place['reviews']) : ReviewPage.empty;
  },
);

/// One place for its page, read when it is opened and the device holds no
/// copy of its region (the web, or a region not kept); null when it is
/// gone. A place merged into another answers with that one.
final placeOperation = GraphQLOperation<Place?>(
  name: 'Place',
  document: '''
query Place(\$id: UUID!) {
  place(id: \$id) { ...PlaceFields }
}
$placeFieldsFragment''',
  parse: (data) => switch (data['place']) {
    final Map<String, dynamic> place => placeFromJson(place),
    _ => null,
  },
);

/// What a row of a list shows of a place.
const placeSummaryFragment = '''
fragment PlaceSummaryFields on Place {
  id
  name
  kind
  lat
  lon
  overnight
  services
  priceParkingEur
  address { city }
  municipality
  ratings { sourceId average count }
  ratingForFilters
  openingSeason { from to }
  verification
}
''';

/// A page of the places of a viewport, the total they make, and the cursor
/// of the next page.
@immutable
final class PlacePage {
  const new({required this.places, required this.total, required this.hasNextPage, this.endCursor});

  static const empty = PlacePage(places: [], total: 0, hasNextPage: false);

  final List<PlaceSummary> places;

  /// Every place of the viewport the filter keeps, beyond this page.
  final int total;
  final bool hasNextPage;
  final String? endCursor;
}

/// The places of a viewport passing a filter, nearest to `near` first: the
/// list beside the map when the places come from the tiles.
final nearbyPlacesOperation = GraphQLOperation<PlacePage>(
  name: 'NearbyPlaces',
  document: '''
query NearbyPlaces(\$bbox: BBoxInput!, \$filter: PlaceFilter, \$near: LatLonInput, \$first: Int, \$after: String) {
  places(bbox: \$bbox, filter: \$filter, near: \$near, first: \$first, after: \$after) {
    nodes { ...PlaceSummaryFields }
    endCursor
    hasNextPage
    totalCount
  }
}
$placeSummaryFragment''',
  parse: (data) {
    final page = data['places'] as Map<String, dynamic>;
    return PlacePage(
      places: [
        for (final p in page['nodes'] as List<dynamic>)
          placeFromJson(p as Map<String, dynamic>).summary,
      ],
      total: (page['totalCount'] as num?)?.toInt() ?? 0,
      hasNextPage: page['hasNextPage'] == true,
      endCursor: page['endCursor'] as String?,
    );
  },
);

const _externalReviewFields = '''
fragment ExternalReviewFields on ExternalReviewConnection {
  nodes {
    id sourceId authorName rating text lang authorVehicle writtenAt licence licenceUrl pageUrl
  }
  endCursor
  hasNextPage
  totalCount
}
''';

/// What other sources than Lunaway's community say of a place (the partner's
/// community, Commons, Panoramax, Wikipedia, the tourist offices,
/// Mangrove), read when its card opens and kept in memory only: the change
/// feed, the packs and the device's stores never carry it. Null when the
/// place no longer exists.
final externalOperation = GraphQLOperation<ExternalContent?>(
  name: 'PlaceExternal',
  document: '''
query PlaceExternal(\$id: UUID!, \$first: Int) {
  place(id: \$id) {
    id
    externalPhotos {
      id sourceId kind authorName publisher sourceUpdatedOn licence licenceUrl pageUrl takenAt
      thumbUrl largeUrl width height thumbhash
    }
    externalRatings { sourceId average count }
    externalReviews(first: \$first) { ...ExternalReviewFields }
    externalDescriptions {
      sourceId lang text title publisher sourceUpdatedOn licence licenceUrl pageUrl
    }
  }
}
$_externalReviewFields''',
  parse: (data) {
    final place = data['place'];
    if (place is! Map<String, dynamic>) return null;
    return ExternalContent(
      photos: externalPhotosFromJson(place['externalPhotos']),
      ratings: ratingsFromJson(place['externalRatings']),
      reviews: externalReviewPageFromJson(place['externalReviews']),
      descriptions: externalDescriptionsFromJson(place['externalDescriptions']),
    );
  },
);

/// The places whose name or town matches what the user typed, online.
final searchPlacesOperation = GraphQLOperation<List<PlaceSummary>>(
  name: 'SearchPlaces',
  document: '''
query SearchPlaces(\$text: String!, \$near: LatLonInput, \$first: Int) {
  search(text: \$text, near: \$near, first: \$first) { ...PlaceSummaryFields }
}
$placeSummaryFragment''',
  parse: (data) => [
    for (final p in data['search'] as List<dynamic>)
      placeFromJson(p as Map<String, dynamic>).summary,
  ],
);

/// The fields of an address the search shows.
const _addressFields = '''
addresses { kind name postcode city context countryCode lat lon source { id attribution } }''';

/// The map's search online: the places as [searchPlacesOperation] finds
/// them, the towns whose name starts like the text with every place they
/// hold, then the addresses of the server's geocoders, in one request.
final searchAllOperation = GraphQLOperation<SearchAnswer>(
  name: 'SearchAll',
  document:
      '''
query SearchAll(\$text: String!, \$near: LatLonInput, \$first: Int, \$language: String) {
  searchAll(text: \$text, near: \$near, first: \$first, language: \$language) {
    places { ...PlaceSummaryFields }
    towns { name postcode department countryCode placeCount lat lon }
    $_addressFields
  }
}
$placeSummaryFragment''',
  parse: (data) => searchAnswerFromJson(data['searchAll'] as Map<String, dynamic>),
);

/// The addresses alone, for a device that searches its own places.
final searchAddressesOperation = GraphQLOperation<SearchAnswer>(
  name: 'SearchAddresses',
  document:
      '''
query SearchAddresses(\$text: String!, \$near: LatLonInput, \$language: String) {
  searchAll(text: \$text, near: \$near, language: \$language) {
    $_addressFields
  }
}''',
  parse: (data) => searchAnswerFromJson(data['searchAll'] as Map<String, dynamic>),
);

/// What `searchAll` answered: the places and the towns (none when not
/// asked) and the addresses.
@immutable
final class SearchAnswer {
  const new({this.places = const [], this.towns = const [], this.addresses = const []});

  final List<PlaceSummary> places;
  final List<Municipality> towns;
  final List<AddressMatch> addresses;
}

SearchAnswer searchAnswerFromJson(Map<String, dynamic> json) => SearchAnswer(
  places: [
    for (final p in (json['places'] as List<dynamic>?) ?? const [])
      placeFromJson(p as Map<String, dynamic>).summary,
  ],
  towns: [
    for (final t in (json['towns'] as List<dynamic>?) ?? const [])
      ?townFromJson(t as Map<String, dynamic>),
  ],
  addresses: [
    for (final a in (json['addresses'] as List<dynamic>?) ?? const [])
      ?addressMatchFromJson(a as Map<String, dynamic>),
  ],
);

/// One town of the API; null when it lacks its name or its middle.
Municipality? townFromJson(Map<String, dynamic> json) {
  final name = json['name'];
  final lat = json['lat'];
  final lon = json['lon'];
  final count = json['placeCount'];
  if (name is! String || name.isEmpty || lat is! num || lon is! num || count is! num) return null;
  return Municipality(
    name: name,
    postcode: json['postcode'] as String?,
    department: json['department'] as String?,
    countryCode: (json['countryCode'] as String?)?.toUpperCase(),
    center: LatLng(lat.toDouble(), lon.toDouble()),
    placeCount: count.toInt(),
  );
}

/// One address of the API; null when it lacks what the list needs.
AddressMatch? addressMatchFromJson(Map<String, dynamic> json) {
  final name = json['name'];
  final lat = json['lat'];
  final lon = json['lon'];
  final source = json['source'];
  if (name is! String || lat is! num || lon is! num || source is! Map<String, dynamic>) {
    return null;
  }
  return AddressMatch(
    kind: AddressKind.fromWire(json['kind'] as String?),
    name: name,
    postcode: json['postcode'] as String?,
    city: json['city'] as String?,
    context: json['context'] as String?,
    countryCode: json['countryCode'] as String?,
    position: LatLng(lat.toDouble(), lon.toDouble()),
    sourceId: source['id'] as String? ?? '',
    attribution: source['attribution'] as String? ?? '',
  );
}

/// The box the places of [view] are asked for: the view widened to a grid
/// of [placesGrid] degree (about 5 km), so the request says no more of where
/// the map looks than a point rounded to that grid. Without it, the centre
/// of a map the user brought to their position is that position.
GeoBounds placesQueryBox(GeoBounds view) {
  // A hair inside the cell, so that an edge already on the grid (a box
  // snapped once, 0.15000000000000002) stays where it is.
  const hair = 1e-9;
  double down(double v) => _onGrid((v / placesGrid + hair).floorToDouble() * placesGrid);
  double up(double v) => _onGrid((v / placesGrid - hair).ceilToDouble() * placesGrid);
  return GeoBounds(
    south: down(view.south).clamp(-90, 90),
    west: down(view.west).clamp(-180, 180),
    north: up(view.north).clamp(-90, 90),
    east: up(view.east).clamp(-180, 180),
  );
}

/// The grid of [placesQueryBox], the same as the search's (`searchGrid`).
const placesGrid = 0.05;

/// [v] written with two decimals, so the floating point of the grid leaves
/// no trace (0.15000000000000002) in the request.
double _onGrid(double v) => double.parse(v.toStringAsFixed(2));

Map<String, Object?> bboxInput(GeoBounds b) => {
  'south': b.south,
  'west': b.west,
  'north': b.north,
  'east': b.east,
};

/// [filter] as the API's `PlaceFilter`, with the same meaning as
/// [PlaceFilter.matches]; null for the empty filter.
Map<String, Object?>? placeFilterInput(PlaceFilter filter) {
  final input = <String, Object?>{
    if (filter.families.isNotEmpty)
      'kinds': [
        for (final k in PlaceKind.values)
          if (filter.families.contains(k.family)) k.wire,
      ],
    if (filter.overnight.isNotEmpty)
      'overnight': [
        for (final o in OvernightStatus.values)
          if (filter.overnight.contains(o)) o.wire,
      ],
    if (filter.amenities.isNotEmpty)
      'serviceGroups': [
        for (final a in Amenity.values)
          if (filter.amenities.contains(a)) [for (final s in a.services) s.wire],
      ],
    if (filter.freeOnly) 'freeOnly': true,
    'vehicleHeightM': ?filter.vehicleHeightM,
    'minRating': ?filter.minRating,
    if (filter.openDays case final days?)
      'openDays': [
        for (final d in days) {'from': d.from, 'to': d.to},
      ],
  };
  return input.isEmpty ? null : input;
}

/// The next page of the external community source's reviews.
final externalReviewsOperation = GraphQLOperation<ReviewPage>(
  name: 'PlaceExternalReviews',
  document: '''
query PlaceExternalReviews(\$id: UUID!, \$first: Int, \$after: String) {
  place(id: \$id) {
    id
    externalReviews(first: \$first, after: \$after) { ...ExternalReviewFields }
  }
}
$_externalReviewFields''',
  parse: (data) {
    final place = data['place'];
    return place is Map<String, dynamic>
        ? externalReviewPageFromJson(place['externalReviews'])
        : ReviewPage.empty;
  },
);

/// What the rows of a list show beyond their places' summaries: their
/// ratings by source, an excerpt in `language`, the day each was added.
/// Either `ids` (those a list just received) or `bbox` (an area the list
/// read from the map's tiles, widened to the grid), never both. Kept in
/// memory only.
final placeDigestsOperation = GraphQLOperation<List<PlaceDigest>>(
  name: 'PlaceDigests',
  document: r'''
query PlaceDigests($ids: [UUID!], $bbox: BBoxInput, $language: String) {
  placeDigests(ids: $ids, bbox: $bbox, language: $language) {
    placeId
    ratings { sourceId average count }
    excerpt { lang text sourceId }
    addedAt
  }
}''',
  parse: (data) => placeDigestsFromJson(data['placeDigests']),
);

/// Every operation the app can send, for the contract test.
final allOperations = <GraphQLOperation<Object?>>[
  changesOperation,
  extrasOperation,
  reviewsOperation,
  placeOperation,
  nearbyPlacesOperation,
  searchPlacesOperation,
  searchAllOperation,
  searchAddressesOperation,
  externalOperation,
  externalReviewsOperation,
  placeDigestsOperation,
];
