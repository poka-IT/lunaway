import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// Hand-written decoding of the API's `Place` (and of the same shape stored as
/// JSON in drift). Lenient on what can be absent, strict on the identity: a
/// place without id, kind or position is a server bug and throws.
Place placeFromJson(Map<String, dynamic> json) {
  final address = json['address'];
  final municipality = _nonEmpty(json['municipality']);
  return Place(
    id: json['id'] as String,
    name: _nonEmpty(json['name']),
    kind: PlaceKind.fromWire(json['kind'] as String),
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    overnight: OvernightStatus.fromWire(json['overnight'] as String? ?? 'UNKNOWN'),
    services: {
      for (final s in (json['services'] as List<dynamic>? ?? const []))
        ?Service.fromWire(s as String),
    },
    activities: {
      for (final a in (json['activities'] as List<dynamic>? ?? const []))
        ?Activity.fromWire(a as String),
    },
    description: _nonEmpty(json['description']),
    address: _withCommune(
      address is Map<String, dynamic> ? addressFromJson(address) : null,
      municipality,
    ),
    priceParkingEur: (json['priceParkingEur'] as num?)?.toDouble(),
    priceServicesEur: (json['priceServicesEur'] as num?)?.toDouble(),
    maxHeightM: (json['maxHeightM'] as num?)?.toDouble(),
    capacity: (json['capacity'] as num?)?.toInt(),
    stars: switch (json['stars']) {
      final num n when n >= 1 && n <= 5 => n.toInt(),
      _ => null,
    },
    openingHours: _nonEmpty(json['openingHours']),
    openingHoursParsed: json['openingHoursParsed'] == true,
    openingIntervals: openingIntervalsFromJson(json['openingIntervals']),
    openingValidUntil: _date(json['openingIntervalsUntil']),
    website: _nonEmpty(json['website']),
    phone: _nonEmpty(json['phone']),
    lastConfirmedAt: _date(json['lastConfirmedAt']),
    updatedAt: _date(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    sources: [
      for (final s in (json['sources'] as List<dynamic>? ?? const []))
        placeSourceFromJson(s as Map<String, dynamic>),
    ],
    provenance: [
      for (final p in (json['provenance'] as List<dynamic>? ?? const []))
        fieldProvenanceFromJson(p as Map<String, dynamic>),
    ],
    descriptions: localizedTextsFromJson(json['descriptions']),
    ratings: ratingsFromJson(json['ratings']),
    externalLinks: externalLinksFromJson(json['externalLinks']),
    verification: Verification.fromWire(json['verification']),
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    photoCount: (json['photoCount'] as num?)?.toInt() ?? 0,
    coverPhotos: photosFromJson(json['coverPhotos']),
    reportedIssues: issuesFromJson(json['reportedIssues']),
  );
}

List<IssueSummary> issuesFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((IssueKind.fromWire(m['kind']), m['count'], _date(m['lastReportedAt'])) case (
      final kind?,
      final num count,
      final at?,
    ))
      IssueSummary(kind: kind, count: count.toInt(), lastReportedAt: at),
];

List<Map<String, Object?>> issuesToJson(List<IssueSummary> issues) => [
  for (final i in issues)
    {
      'kind': i.kind.wire,
      'count': i.count,
      'lastReportedAt': i.lastReportedAt.toUtc().toIso8601String(),
    },
];

List<Map<String, dynamic>> _maps(Object? json) => [
  if (json is List<dynamic>)
    for (final e in json)
      if (e is Map<String, dynamic>) e,
];

List<LocalizedText> localizedTextsFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['lang'], _nonEmpty(m['text']), m['sourceId']) case (
      final String lang,
      final String text,
      final String source,
    ))
      LocalizedText(lang: lang, text: text, sourceId: source),
];

List<Map<String, Object?>> localizedTextsToJson(List<LocalizedText> texts) => [
  for (final t in texts) {'lang': t.lang, 'text': t.text, 'sourceId': t.sourceId},
];

List<SourceRating> ratingsFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['sourceId'], m['average'], m['count']) case (
      final String source,
      final num average,
      final num count,
    ))
      SourceRating(sourceId: source, average: average.toDouble(), count: count.toInt()),
];

/// The digests of `Query.placeDigests`; an entry without a place id or a
/// readable date is left out.
List<PlaceDigest> placeDigestsFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['placeId'], DateTime.tryParse('${m['addedAt']}')) case (
      final String id,
      final DateTime added?,
    ))
      PlaceDigest(
        placeId: id,
        addedAt: added,
        ratings: ratingsFromJson(m['ratings']),
        excerpt: localizedTextsFromJson([?m['excerpt']]).firstOrNull,
      ),
];

List<Map<String, Object?>> ratingsToJson(List<SourceRating> ratings) => [
  for (final r in ratings) {'sourceId': r.sourceId, 'average': r.average, 'count': r.count},
];

List<ExternalLink> externalLinksFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['sourceId'], m['url'], m['label']) case (
      final String source,
      final String url,
      final String label,
    ))
      ExternalLink(sourceId: source, url: url, label: label),
];

List<Map<String, Object?>> externalLinksToJson(List<ExternalLink> links) => [
  for (final l in links) {'sourceId': l.sourceId, 'url': l.url, 'label': l.label},
];

List<Photo> photosFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['id'], m['sourceId'], m['thumbUrl'], m['largeUrl']) case (
      final Object id,
      final String source,
      final String thumb,
      final String large,
    ))
      photoFromJson(m, id: '$id', source: source, thumb: thumb, large: large),
];

Photo photoFromJson(
  Map<String, dynamic> m, {
  required String id,
  required String source,
  required String thumb,
  required String large,
}) => Photo(
  id: id,
  sourceId: source,
  thumbUrl: thumb,
  largeUrl: large,
  thumbhash: _nonEmpty(m['thumbhash']),
  width: (m['width'] as num?)?.toInt(),
  height: (m['height'] as num?)?.toInt(),
  authorId: _nonEmpty(m['authorId']),
  authorName: _nonEmpty(m['authorName']),
  createdAt: _date(m['createdAt']),
  status: ContributionStatus.fromWire(m['status']),
);

List<Map<String, Object?>> photosToJson(List<Photo> photos) => [
  for (final p in photos)
    {
      'id': p.id,
      'sourceId': p.sourceId,
      'thumbUrl': p.thumbUrl,
      'largeUrl': p.largeUrl,
      'thumbhash': p.thumbhash,
      'width': p.width,
      'height': p.height,
      'authorId': p.authorId,
      'authorName': p.authorName,
      'createdAt': p.createdAt?.toUtc().toIso8601String(),
      'status': p.status?.wire,
    },
];

/// A review; null when it lacks its identity.
Review? reviewFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  if ((json['id'], json['sourceId'], _date(json['createdAt'])) case (
    final Object id,
    final String source,
    final created?,
  )) {
    return Review(
      id: '$id',
      sourceId: source,
      rating: (json['rating'] as num?)?.toInt(),
      text: _nonEmpty(json['text']),
      lang: _nonEmpty(json['lang']),
      authorName: _nonEmpty(json['authorName']),
      authorId: _nonEmpty(json['authorId']),
      authorVehicle: ReviewVehicle.fromWire(json['authorVehicle']),
      visitedAt: _day(json['visitedAt']),
      createdAt: created,
      placeId: _nonEmpty(json['placeId']),
      status: ContributionStatus.fromWire(json['status']),
    );
  }
  return null;
}

Map<String, Object?> reviewToJson(Review r) => {
  'id': r.id,
  'sourceId': r.sourceId,
  'rating': r.rating,
  'text': r.text,
  'lang': r.lang,
  'authorName': r.authorName,
  'authorId': r.authorId,
  'authorVehicle': r.authorVehicle?.wire,
  'visitedAt': switch (r.visitedAt) {
    final d? => naiveDate(d),
    null => null,
  },
  'createdAt': r.createdAt.toUtc().toIso8601String(),
  'placeId': r.placeId,
  'status': r.status?.wire,
};

/// A calendar day as the API's `NaiveDate` (`2026-09-20`).
String naiveDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

ReviewPage reviewPageFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return ReviewPage.empty;
  return ReviewPage(
    nodes: [for (final m in _maps(json['nodes'])) ?reviewFromJson(m)],
    endCursor: json['endCursor'] as String?,
    hasNextPage: json['hasNextPage'] == true,
    totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
  );
}

Map<String, Object?> reviewPageToJson(ReviewPage page) => {
  'nodes': [for (final r in page.nodes) reviewToJson(r)],
  'endCursor': page.endCursor,
  'hasNextPage': page.hasNextPage,
  'totalCount': page.totalCount,
};

/// Null when the server sent none (not computed), an empty list when the
/// place is closed for the whole window.
List<OpeningInterval>? openingIntervalsFromJson(Object? json) {
  if (json is! List<dynamic>) return null;
  return [
    for (final i in json)
      if (i is Map<String, dynamic>)
        if ((_date(i['start']), _date(i['end'])) case (final start?, final end?))
          OpeningInterval(start, end),
  ];
}

List<Map<String, String>>? openingIntervalsToJson(List<OpeningInterval>? intervals) =>
    intervals == null
    ? null
    : [
        for (final i in intervals)
          {'start': i.start.toUtc().toIso8601String(), 'end': i.end.toUtc().toIso8601String()},
      ];

Address addressFromJson(Map<String, dynamic> json) => Address(
  street: _nonEmpty(json['street']),
  postcode: _nonEmpty(json['postcode']),
  city: _nonEmpty(json['city']),
  countryCode: _nonEmpty(json['countryCode']),
);

Source sourceFromJson(Map<String, dynamic> json) => Source(
  id: json['id'] as String,
  name: json['name'] as String,
  licence: json['licence'] as String,
  attribution: json['attribution'] as String,
  url: json['url'] as String,
);

PlaceSource placeSourceFromJson(Map<String, dynamic> json) => PlaceSource(
  source: sourceFromJson(json['source'] as Map<String, dynamic>),
  externalId: json['externalId'] as String,
  externalUrl: _nonEmpty(json['externalUrl']),
  fetchedAt: _date(json['fetchedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  matchScore: (json['matchScore'] as num?)?.toDouble(),
);

FieldProvenance fieldProvenanceFromJson(Map<String, dynamic> json) => FieldProvenance(
  field: json['field'] as String,
  sourceId: json['sourceId'] as String,
  alternatives: [
    for (final a in (json['alternatives'] as List<dynamic>? ?? const []))
      AlternativeValue(
        sourceId: (a as Map<String, dynamic>)['sourceId'] as String,
        value: a['value'] as String,
      ),
  ],
);

Map<String, Object?> placeSourceToJson(PlaceSource s) => {
  'source': sourceToJson(s.source),
  'externalId': s.externalId,
  'externalUrl': s.externalUrl,
  'fetchedAt': s.fetchedAt.toUtc().toIso8601String(),
  'matchScore': s.matchScore,
};

Map<String, Object?> sourceToJson(Source s) => {
  'id': s.id,
  'name': s.name,
  'licence': s.licence,
  'attribution': s.attribution,
  'url': s.url,
};

Map<String, Object?> fieldProvenanceToJson(FieldProvenance p) => {
  'field': p.field,
  'sourceId': p.sourceId,
  'alternatives': [
    for (final a in p.alternatives) {'sourceId': a.sourceId, 'value': a.value},
  ],
};

/// The inverse of [placeFromJson], used by the demo server and the tests to
/// speak exactly what the API speaks.
Map<String, Object?> placeToJson(Place p) => {
  'id': p.id,
  'name': p.name,
  'kind': p.kind.wire,
  'lat': p.lat,
  'lon': p.lon,
  'overnight': p.overnight.wire,
  'services': [for (final s in p.services) s.wire],
  'activities': [for (final a in p.activities) a.wire],
  'description': p.description,
  'address': p.address == null
      ? null
      : {
          'street': p.address!.street,
          'postcode': p.address!.postcode,
          'city': p.address!.city,
          'countryCode': p.address!.countryCode,
        },
  // The server's commune; the places written here are all French towns.
  'municipality': p.address?.city,
  'priceParkingEur': p.priceParkingEur,
  'priceServicesEur': p.priceServicesEur,
  'maxHeightM': p.maxHeightM,
  'capacity': p.capacity,
  'stars': p.stars,
  'openingHours': p.openingHours,
  'openingHoursParsed': p.openingHoursParsed,
  'openingIntervals': openingIntervalsToJson(p.openingIntervals),
  'openingIntervalsUntil': p.openingValidUntil?.toUtc().toIso8601String(),
  'website': p.website,
  'phone': p.phone,
  'lastConfirmedAt': p.lastConfirmedAt?.toUtc().toIso8601String(),
  'updatedAt': p.updatedAt.toUtc().toIso8601String(),
  'sources': [for (final s in p.sources) placeSourceToJson(s)],
  'provenance': [for (final f in p.provenance) fieldProvenanceToJson(f)],
  'descriptions': localizedTextsToJson(p.descriptions),
  'ratings': ratingsToJson(p.ratings),
  'externalLinks': externalLinksToJson(p.externalLinks),
  'verification': p.verification.wire,
  'reviewCount': p.reviewCount,
  'photoCount': p.photoCount,
  'coverPhotos': photosToJson(p.coverPhotos),
  'reportedIssues': issuesToJson(p.reportedIssues),
};

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// A `NaiveDate` (`2026-09-20`) as local midnight of that day, so formatting
/// it never moves it to the day before or after.
DateTime? _day(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The address, its town taken from the commune the server found for the
/// place when the source gave none: rows and the offline search by town
/// then cover places mapped without an address.
Address? _withCommune(Address? address, String? municipality) {
  if (municipality == null || address?.city != null) return address;
  return Address(
    street: address?.street,
    postcode: address?.postcode,
    city: municipality,
    countryCode: address?.countryCode,
  );
}

/// The terms an item of another source carries; null when it carries none
/// (an API older than the open sources).
ItemTerms? _termsFromJson(Map<String, dynamic> m) {
  final terms = ItemTerms(
    licence: _nonEmpty(m['licence']),
    licenceUrl: _https(m['licenceUrl']),
    pageUrl: _https(m['pageUrl']),
    publisher: _nonEmpty(m['publisher']),
    updatedOn: _day(m['sourceUpdatedOn']),
  );
  return terms == const ItemTerms() ? null : terms;
}

/// An `https` address the API gave; anything else is no link.
String? _https(Object? value) =>
    value is String && Uri.tryParse(value)?.scheme == 'https' ? value : null;

/// The texts of the open sources: each in its language, with its source,
/// licence and page.
List<ExternalDescription> externalDescriptionsFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['sourceId'], _nonEmpty(m['lang']), _nonEmpty(m['text'])) case (
      final String source,
      final String lang,
      final String text,
    ))
      ExternalDescription(
        text: LocalizedText(lang: lang, text: text, sourceId: source),
        terms: _termsFromJson(m) ?? const ItemTerms(),
        title: _nonEmpty(m['title']),
      ),
];

/// The photos of the other sources: `takenAt` stands where a Lunaway photo
/// has its upload date, and no author id ever comes (the pseudonym or
/// credit is all the API serves of another source's authors).
List<Photo> externalPhotosFromJson(Object? json) => [
  for (final m in _maps(json))
    if ((m['id'], m['sourceId'], m['thumbUrl'], m['largeUrl']) case (
      final Object id,
      final String source,
      final String thumb,
      final String large,
    ))
      Photo(
        id: '$id',
        sourceId: source,
        thumbUrl: thumb,
        largeUrl: large,
        thumbhash: _nonEmpty(m['thumbhash']),
        width: (m['width'] as num?)?.toInt(),
        height: (m['height'] as num?)?.toInt(),
        authorName: _nonEmpty(m['authorName']),
        createdAt: _date(m['takenAt']),
        kind: PhotoKind.fromWire(m['kind']),
        terms: _termsFromJson(m),
      ),
];

/// A page of the external community source's reviews: `writtenAt` is
/// their writing time, as `createdAt` is a Lunaway review's.
ReviewPage externalReviewPageFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return ReviewPage.empty;
  return ReviewPage(
    nodes: [
      for (final m in _maps(json['nodes']))
        if ((m['id'], m['sourceId'], _nonEmpty(m['text']), _date(m['writtenAt'])) case (
          final Object id,
          final String source,
          final String text,
          final written?,
        ))
          Review(
            id: '$id',
            sourceId: source,
            rating: (m['rating'] as num?)?.toInt(),
            text: text,
            lang: _nonEmpty(m['lang']),
            authorName: _nonEmpty(m['authorName']),
            authorVehicle: ReviewVehicle.fromWire(m['authorVehicle']),
            createdAt: written,
            terms: _termsFromJson(m),
          ),
    ],
    endCursor: json['endCursor'] as String?,
    hasNextPage: json['hasNextPage'] == true,
    totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
  );
}
