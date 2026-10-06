import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
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
    this.maxHeightM,
    this.capacity,
    this.stars,
    this.openingHours,
    this.openingHoursParsed = false,
    this.openingIntervals,
    this.openingValidUntil,
    this.website,
    this.phone,
    this.lastConfirmedAt,
    this.sources = const [],
    this.provenance = const [],
    this.descriptions = const [],
    this.ratings = const [],
    this.externalLinks = const [],
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

  /// The pages of the place on its sources' sites.
  final List<ExternalLink> externalLinks;

  LatLng get position => LatLng(lat, lon);

  /// The freshest date that says the data still holds.
  DateTime get freshness => lastConfirmedAt ?? updatedAt;

  PlaceSummary get summary => PlaceSummary(
    id: id,
    name: name,
    city: address?.city,
    kind: kind,
    lat: lat,
    lon: lon,
    overnight: overnight,
    services: services,
    priceParkingEur: priceParkingEur,
    ratingAverage: combinedRating(ratings)?.average,
    ratingCount: combinedRating(ratings)?.count ?? 0,
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
      other.maxHeightM == maxHeightM &&
      other.capacity == capacity &&
      other.stars == stars &&
      other.openingHours == openingHours &&
      other.openingHoursParsed == openingHoursParsed &&
      const ListEquality<OpeningInterval>().equals(other.openingIntervals, openingIntervals) &&
      other.openingValidUntil == openingValidUntil &&
      other.website == website &&
      other.phone == phone &&
      other.lastConfirmedAt == lastConfirmedAt &&
      other.updatedAt == updatedAt &&
      const ListEquality<PlaceSource>().equals(other.sources, sources) &&
      const ListEquality<FieldProvenance>().equals(other.provenance, provenance) &&
      const ListEquality<LocalizedText>().equals(other.descriptions, descriptions) &&
      const ListEquality<SourceRating>().equals(other.ratings, ratings) &&
      const ListEquality<ExternalLink>().equals(other.externalLinks, externalLinks);

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
    this.services = const {},
    this.priceParkingEur,
    this.ratingAverage,
    this.ratingCount = 0,
  });

  final String id;
  final String? name;
  final String? city;
  final PlaceKind kind;
  final double lat;
  final double lon;
  final OvernightStatus overnight;
  final Set<Service> services;
  final double? priceParkingEur;

  /// Across sources, weighted by review count; null without reviews.
  final double? ratingAverage;
  final int ratingCount;

  LatLng get position => LatLng(lat, lon);

  @override
  bool operator ==(Object other) =>
      other is PlaceSummary &&
      other.id == id &&
      other.name == name &&
      other.city == city &&
      other.kind == kind &&
      other.lat == lat &&
      other.lon == lon &&
      other.overnight == overnight &&
      const SetEquality<Service>().equals(other.services, services) &&
      other.priceParkingEur == priceParkingEur &&
      other.ratingAverage == ratingAverage &&
      other.ratingCount == ratingCount;

  @override
  int get hashCode => Object.hash(id, lat, lon, kind, overnight);
}
