import 'package:collection/collection.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// A visitor's answer to "still there?".
enum ConfirmationStatus {
  stillOk('STILL_OK'),
  closed('CLOSED'),
  changed('CHANGED');

  new(this.wire);

  final String wire;

  static ConfirmationStatus? fromWire(Object? wire) =>
      values.where((v) => v.wire == wire).firstOrNull;
}

/// A problem met at a place.
enum IssueKind {
  nightBan('NIGHT_BAN'),
  serviceBroken('SERVICE_BROKEN'),
  noAccess('NO_ACCESS'),
  danger('DANGER');

  new(this.wire);

  final String wire;

  static IssueKind? fromWire(Object? wire) => values.where((v) => v.wire == wire).firstOrNull;
}

/// What a user may report to the moderators.
enum ReportTarget {
  review('REVIEW'),
  photo('PHOTO'),
  place('PLACE');

  new(this.wire);

  final String wire;
}

/// Why a user reports something.
enum ReportReason {
  spam('SPAM'),
  offensive('OFFENSIVE'),
  wrong('WRONG'),
  privacy('PRIVACY'),
  other('OTHER');

  new(this.wire);

  final String wire;
}

/// Whether a place can be trusted to exist as described.
enum Verification {
  verified('VERIFIED'),

  /// Added by a contributor and not yet confirmed by two others.
  toVerify('TO_VERIFY');

  new(this.wire);

  final String wire;

  static Verification fromWire(Object? wire) =>
      values.where((v) => v.wire == wire).firstOrNull ?? verified;
}

/// Recent reports of one kind of issue at a place.
@immutable
final class IssueSummary {
  const new({required this.kind, required this.count, required this.lastReportedAt});

  final IssueKind kind;

  /// Reports over the last 30 days, each account counted once.
  final int count;
  final DateTime lastReportedAt;

  @override
  bool operator ==(Object other) =>
      other is IssueSummary &&
      other.kind == kind &&
      other.count == count &&
      other.lastReportedAt == lastReportedAt;

  @override
  int get hashCode => Object.hash(kind, count, lastReportedAt);
}

/// A confirmation the account gave.
@immutable
final class Confirmation {
  const new({
    required this.id,
    required this.placeId,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String placeId;
  final ConfirmationStatus status;
  final DateTime createdAt;
}

/// A "still there?" answer of the account about a point of interest, with
/// what the point is while it is still served.
@immutable
final class PoiConfirmation {
  const new({
    required this.id,
    required this.poiId,
    required this.stillThere,
    required this.createdAt,
    this.name,
    this.kind,
  });

  final String id;
  final String poiId;
  final bool stillThere;
  final DateTime createdAt;

  /// The point's name; null when it has none, or is gone or hidden.
  final String? name;

  /// The point's kind code (`bakery`); null once it is gone or hidden.
  final String? kind;
}

/// An issue the account reported.
@immutable
final class IssueReport {
  const new({required this.id, required this.placeId, required this.kind, required this.createdAt});

  final String id;
  final String placeId;
  final IssueKind kind;
  final DateTime createdAt;
}

enum SubmissionKind {
  create('CREATE'),
  edit('EDIT'),

  /// A vending machine added as a point of interest.
  poi('POI');

  new(this.wire);

  final String wire;

  static SubmissionKind fromWire(Object? wire) =>
      values.where((v) => v.wire == wire).firstOrNull ?? edit;
}

/// Where a new place or an edit stands.
enum SubmissionStatus {
  proposed('PROPOSED'),
  accepted('ACCEPTED'),
  applied('APPLIED'),
  rejected('REJECTED'),
  withdrawn('WITHDRAWN');

  new(this.wire);

  final String wire;

  static SubmissionStatus fromWire(Object? wire) =>
      values.where((v) => v.wire == wire).firstOrNull ?? proposed;
}

/// A new place or a place edit the account sent.
@immutable
final class PlaceSubmission {
  const new({
    required this.id,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.placeId,
    this.poiId,
    this.appliedAt,
  });

  final String id;
  final SubmissionKind kind;

  /// The place edited, or the place a new one became; null until the
  /// server placed it.
  final String? placeId;

  /// The point of interest a new vending machine became; null until the
  /// server wrote it.
  final String? poiId;
  final SubmissionStatus status;
  final DateTime createdAt;
  final DateTime? appliedAt;
}

/// A field of a place an edit can clear (`PlaceField`): the community
/// stops stating it (a wrong phone, a closed website), and the value shown
/// comes from the next source that has one.
enum PlaceField {
  priceParking('PRICE_PARKING'),
  priceServices('PRICE_SERVICES'),
  maxHeight('MAX_HEIGHT'),
  capacity('CAPACITY'),
  website('WEBSITE'),
  phone('PHONE');

  new(this.wire);

  final String wire;
}

/// What a contributor states of a place: an absent field says nothing
/// (`PlaceDetailsInput`). A new place needs a name.
@immutable
final class PlaceDetails {
  const new({
    this.name,
    this.kind,
    this.overnight,
    this.services,
    this.description,
    this.descriptionLang,
    this.priceParkingEur,
    this.priceServicesEur,
    this.maxHeightM,
    this.capacity,
    this.website,
    this.phone,
    this.clear = const {},
  });

  final String? name;
  final PlaceKind? kind;
  final OvernightStatus? overnight;

  /// The whole set of services when given.
  final Set<Service>? services;
  final String? description;
  final String? descriptionLang;
  final double? priceParkingEur;
  final double? priceServicesEur;
  final double? maxHeightM;
  final int? capacity;
  final String? website;
  final String? phone;

  /// What an edit takes out: a field the place had and the form emptied.
  final Set<PlaceField> clear;

  bool get isEmpty =>
      name == null &&
      kind == null &&
      overnight == null &&
      services == null &&
      description == null &&
      priceParkingEur == null &&
      priceServicesEur == null &&
      maxHeightM == null &&
      capacity == null &&
      website == null &&
      phone == null &&
      clear.isEmpty;

  /// The GraphQL input: only the fields stated, and those cleared.
  Map<String, Object?> toInput() => {
    'name': ?name,
    if (kind != null) 'kind': kind!.wire,
    if (overnight != null) 'overnight': overnight!.wire,
    if (services != null)
      'services': [for (final s in Service.values.where(services!.contains)) s.wire],
    if (description != null) 'description': {'lang': descriptionLang ?? 'und', 'text': description},
    'priceParkingEur': ?priceParkingEur,
    'priceServicesEur': ?priceServicesEur,
    'maxHeightM': ?maxHeightM,
    'capacity': ?capacity,
    'website': ?website,
    'phone': ?phone,
    if (clear.isNotEmpty)
      'clear': [for (final f in PlaceField.values.where(clear.contains)) f.wire],
  };

  @override
  bool operator ==(Object other) =>
      other is PlaceDetails &&
      other.name == name &&
      other.kind == kind &&
      other.overnight == overnight &&
      const SetEquality<Service>().equals(other.services, services) &&
      other.description == description &&
      other.descriptionLang == descriptionLang &&
      other.priceParkingEur == priceParkingEur &&
      other.priceServicesEur == priceServicesEur &&
      other.maxHeightM == maxHeightM &&
      other.capacity == capacity &&
      other.website == website &&
      other.phone == phone &&
      const SetEquality<PlaceField>().equals(other.clear, clear);

  @override
  int get hashCode => Object.hash(name, kind, overnight, description, priceParkingEur, maxHeightM);
}

/// The bounds the API checks, so a form says what is wrong before sending.
abstract final class ContributionLimits {
  static const reviewMin = 10;
  static const reviewMax = 2000;
  static const placeNameMin = 2;
  static const placeNameMax = 120;
  static const noteMax = 500;
  static const listNameMax = 60;
}
