import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// A spot to stop at, as the API describes it (`Place` in the contract).
@immutable
final class Place {
  const new({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lon,
    required this.overnight,
    required this.updatedAt,
    this.name,
    this.services = const {},
    this.activities = const {},
    this.description,
    this.address,
    this.priceParkingEur,
    this.priceServicesEur,
    this.priceServicesIncluded = false,
    this.priceParkingIncludes = const {},
    this.maxHeightM,
    this.capacity,
    this.stars,
    this.openingHours,
    this.openingHoursParsed = false,
    this.openingIntervals,
    this.openingValidUntil,
    this.openingSeason,
    this.website,
    this.phone,
    this.lastConfirmedAt,
    this.sources = const [],
    this.provenance = const [],
    this.descriptions = const [],
    this.ratings = const [],
    this.ratingForFilters,
    this.externalLinks = const [],
    this.verification = Verification.verified,
    this.reviewCount = 0,
    this.photoCount = 0,
    this.coverPhotos = const [],
    this.reportedIssues = const [],
  });

  final String id;

  /// Missing for many car parks; the UI then shows the kind and the town.
  final String? name;
  final PlaceKind kind;
  final double lat;
  final double lon;
  final OvernightStatus overnight;
  final Set<Service> services;
  final Set<Activity> activities;
  final String? description;
  final Address? address;

  /// Per night; 0 is free, null is unknown.
  final double? priceParkingEur;
  final double? priceServicesEur;

  /// A source says the services come with the night ([priceServicesEur]
  /// is then null).
  final bool priceServicesIncluded;

  /// What [priceParkingEur] includes besides the pitch, as its source
  /// says.
  final Set<PriceInclusion> priceParkingIncludes;
  final double? maxHeightM;
  final int? capacity;

  /// Official classification, 1 to 5 stars (Atout France for French
  /// campsites); null when unclassified or unknown.
  final int? stars;

  /// OSM `opening_hours` syntax, shown as written when no interval answers.
  final String? openingHours;

  /// Whether the server could read [openingHours].
  final bool openingHoursParsed;

  /// Open spans for the 14 days after the sync, computed by the server.
  final List<OpeningInterval>? openingIntervals;

  /// End of the window [openingIntervals] cover, sent by the server: from it
  /// on, nothing is known until the next sync.
  final DateTime? openingValidUntil;

  /// The days of the year the place is open when its hours are dates
  /// without times (`Apr 01-Oct 31`, `24/7`): one or two ranges, sorted.
  /// [openingIntervals] are then null, the season answering for every day
  /// of every year. Null when the hours are absent or are not a season.
  final List<DayRange>? openingSeason;
  final String? website;
  final String? phone;

  /// The last time someone confirmed the place is as described.
  final DateTime? lastConfirmedAt;
  final DateTime updatedAt;
  final List<PlaceSource> sources;
  final List<FieldProvenance> provenance;

  /// One per language a source wrote, the user's own shown first.
  final List<LocalizedText> descriptions;

  /// Average rating and review count, per source.
  final List<SourceRating> ratings;

  /// The rating the filters keep or leave the place by, 1 to 5 with one
  /// decimal: Lunaway users' average when they rated it, else the other
  /// sources' average weighted by their counts; null when nobody rated it.
  /// The server computes it (`Place.ratingForFilters`), so the map's tiles,
  /// the API's lists and this device filter by the same value.
  final double? ratingForFilters;

  /// The pages of the place on its sources' sites.
  final List<ExternalLink> externalLinks;

  /// [Verification.toVerify] while a place only the community describes
  /// waits for two confirmations.
  final Verification verification;

  /// Published reviews with text, and published photos.
  final int reviewCount;
  final int photoCount;

  /// The latest published photos (three at most), kept offline; each names
  /// its author so the device hides a muted author's.
  final List<Photo> coverPhotos;

  /// Issues visitors reported over the last 30 days, by kind.
  final List<IssueSummary> reportedIssues;

  /// Whether the services cost nothing beyond the night: a source says
  /// they are included, or they are free where the night is paid (a
  /// campsite at 60 euros whose services cost 0 includes them; "free"
  /// would read as a free stop).
  bool get servicesIncluded =>
      priceServicesIncluded || (priceServicesEur == 0 && (priceParkingEur ?? 0) > 0);

  LatLng get position => LatLng(lat, lon);

  PlaceSummary get summary => PlaceSummary(
    id: id,
    name: name,
    city: address?.city,
    street: address?.street,
    kind: kind,
    lat: lat,
    lon: lon,
    overnight: overnight,
    services: services,
    priceParkingEur: priceParkingEur,
    ratingAverage: combinedRating(ratings)?.average,
    ratingCount: combinedRating(ratings)?.count ?? 0,
    ratingForFilters: ratingForFilters,
    openingSeason: openingSeason,
    verification: verification,
    maxHeightM: maxHeightM,
  );

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.lat == lat &&
      other.lon == lon &&
      other.overnight == overnight &&
      const SetEquality<Service>().equals(other.services, services) &&
      const SetEquality<Activity>().equals(other.activities, activities) &&
      other.description == description &&
      other.address == address &&
      other.priceParkingEur == priceParkingEur &&
      other.priceServicesEur == priceServicesEur &&
      other.priceServicesIncluded == priceServicesIncluded &&
      const SetEquality<PriceInclusion>().equals(
        other.priceParkingIncludes,
        priceParkingIncludes,
      ) &&
      other.maxHeightM == maxHeightM &&
      other.capacity == capacity &&
      other.stars == stars &&
      other.openingHours == openingHours &&
      other.openingHoursParsed == openingHoursParsed &&
      const ListEquality<OpeningInterval>().equals(other.openingIntervals, openingIntervals) &&
      other.openingValidUntil == openingValidUntil &&
      const ListEquality<DayRange>().equals(other.openingSeason, openingSeason) &&
      other.website == website &&
      other.phone == phone &&
      other.lastConfirmedAt == lastConfirmedAt &&
      other.updatedAt == updatedAt &&
      const ListEquality<PlaceSource>().equals(other.sources, sources) &&
      const ListEquality<FieldProvenance>().equals(other.provenance, provenance) &&
      const ListEquality<LocalizedText>().equals(other.descriptions, descriptions) &&
      const ListEquality<SourceRating>().equals(other.ratings, ratings) &&
      other.ratingForFilters == ratingForFilters &&
      const ListEquality<ExternalLink>().equals(other.externalLinks, externalLinks) &&
      other.verification == verification &&
      other.reviewCount == reviewCount &&
      other.photoCount == photoCount &&
      const ListEquality<Photo>().equals(other.coverPhotos, coverPhotos) &&
      const ListEquality<IssueSummary>().equals(other.reportedIssues, reportedIssues);

  @override
  int get hashCode => Object.hash(id, updatedAt, lat, lon);

  @override
  String toString() => 'Place($id, $name, ${kind.wire})';
}

@immutable
final class Address {
  const new({this.street, this.postcode, this.city, this.countryCode});

  final String? street;
  final String? postcode;
  final String? city;
  final String? countryCode;

  bool get isEmpty => street == null && postcode == null && city == null;

  @override
  bool operator ==(Object other) =>
      other is Address &&
      other.street == street &&
      other.postcode == postcode &&
      other.city == city &&
      other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(street, postcode, city, countryCode);
}

/// A data source and the terms its data is shown under.
@immutable
final class Source {
  const new({
    required this.id,
    required this.name,
    required this.licence,
    required this.attribution,
    required this.url,
  });

  final String id;
  final String name;
  final String licence;
  final String attribution;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is Source &&
      other.id == id &&
      other.name == name &&
      other.licence == licence &&
      other.attribution == attribution &&
      other.url == url;

  @override
  int get hashCode => Object.hash(id, name, licence, attribution, url);
}

/// What one source says about the place, and how well it matched.
@immutable
final class PlaceSource {
  const new({
    required this.source,
    required this.externalId,
    required this.fetchedAt,
    this.externalUrl,
    this.matchScore,
  });

  final Source source;
  final String externalId;
  final String? externalUrl;
  final DateTime fetchedAt;
  final double? matchScore;

  @override
  bool operator ==(Object other) =>
      other is PlaceSource &&
      other.source == source &&
      other.externalId == externalId &&
      other.externalUrl == externalUrl &&
      other.fetchedAt == fetchedAt &&
      other.matchScore == matchScore;

  @override
  int get hashCode => Object.hash(source, externalId, externalUrl, fetchedAt, matchScore);
}

/// Which source supplied a field, and the values other sources proposed.
@immutable
final class FieldProvenance {
  const new({required this.field, required this.sourceId, this.alternatives = const []});

  final String field;
  final String sourceId;
  final List<AlternativeValue> alternatives;

  @override
  bool operator ==(Object other) =>
      other is FieldProvenance &&
      other.field == field &&
      other.sourceId == sourceId &&
      const ListEquality<AlternativeValue>().equals(other.alternatives, alternatives);

  @override
  int get hashCode => Object.hash(field, sourceId, Object.hashAll(alternatives));
}

@immutable
final class AlternativeValue {
  const new({required this.sourceId, required this.value});

  final String sourceId;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AlternativeValue && other.sourceId == sourceId && other.value == value;

  @override
  int get hashCode => Object.hash(sourceId, value);
}

/// The light projection of a place the map and the list need: enough to draw
/// a pin, sort by distance and label a row, without the sources.
@immutable
final class PlaceSummary {
  const new({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lon,
    required this.overnight,
    this.name,
    this.city,
    this.street,
    this.services = const {},
    this.priceParkingEur,
    this.ratingAverage,
    this.ratingCount = 0,
    this.ratingForFilters,
    this.openingSeason,
    this.verification = Verification.verified,
    this.maxHeightM,
  });

  final String id;
  final String? name;
  final String? city;

  /// The street of its address, its house number first when it has one
  /// ([Address.street]): a place without a name is titled by it. Null for
  /// a private host, whose title is its town, and when unknown.
  final String? street;
  final PlaceKind kind;
  final double lat;
  final double lon;
  final OvernightStatus overnight;
  final Set<Service> services;
  final double? priceParkingEur;

  /// The height limit in metres, when what made the summary knows it (the
  /// map's tiles carry it): a filter on the vehicle's height then decides
  /// on the device (`PlaceFilter.matches`). Null when unknown, which is no
  /// limit.
  final double? maxHeightM;

  /// Across sources, weighted by review count; null without reviews.
  final double? ratingAverage;
  final int ratingCount;

  /// What the minimum rating filter compares ([Place.ratingForFilters]);
  /// null when nobody rated the place.
  final double? ratingForFilters;

  /// What the filter on opening compares ([Place.openingSeason]); null
  /// when the place's opening is not a season.
  final List<DayRange>? openingSeason;

  /// Whether the place still waits for confirmations.
  final Verification verification;

  LatLng get position => LatLng(lat, lon);

  @override
  bool operator ==(Object other) =>
      other is PlaceSummary &&
      other.id == id &&
      other.name == name &&
      other.city == city &&
      other.street == street &&
      other.kind == kind &&
      other.lat == lat &&
      other.lon == lon &&
      other.overnight == overnight &&
      const SetEquality<Service>().equals(other.services, services) &&
      other.priceParkingEur == priceParkingEur &&
      other.ratingAverage == ratingAverage &&
      other.ratingCount == ratingCount &&
      other.ratingForFilters == ratingForFilters &&
      const ListEquality<DayRange>().equals(other.openingSeason, openingSeason) &&
      other.verification == verification &&
      other.maxHeightM == maxHeightM;

  @override
  int get hashCode => Object.hash(id, lat, lon, kind, overnight);
}
