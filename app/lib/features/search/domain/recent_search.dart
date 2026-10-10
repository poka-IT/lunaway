import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/french_departments.dart';
import 'package:lunaway/features/places/domain/locality.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/domain/town_names.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// The most entries the search's history keeps and shows.
const recentSearchLimit = 15;

/// One entry of the search's history, on this device only: a result the
/// user opened (a place, a point of interest, a town, an address) or a text
/// they searched without opening anything. It keeps what its row shows and
/// what opens it again without a search: an id for a place or a point, a
/// position for a town or an address.
@immutable
sealed class RecentSearch {
  const new();

  /// One entry per result: the same result opened again moves up, it is
  /// not listed twice.
  String get key;

  /// The kind stored with the entry.
  String get kind;

  /// What the row says first: the name, the address, the text.
  String get title;

  /// The words a typed text is matched against ([matches]).
  String get matchedText => title;

  Map<String, Object?> toJson();

  /// Whether every word typed in [query] starts a word of the entry: "lac
  /// ann" finds "Camping du Lac d'Annecy". Accents and case aside.
  bool matches(String query) {
    final typed = _words(query);
    if (typed.isEmpty) return false;
    final own = _words(matchedText);
    return typed.every((w) => own.any((o) => o.startsWith(w)));
  }

  /// The entry stored as [kind] with [json]; null for one this version
  /// cannot read (written by a later one, or damaged).
  static RecentSearch? fromStored(String kind, Map<String, dynamic> json) {
    try {
      return switch (kind) {
        RecentPlace.wire => RecentPlace.fromJson(json),
        RecentPoi.wire => RecentPoi.fromJson(json),
        RecentTown.wire => RecentTown.fromJson(json),
        RecentAddress.wire => RecentAddress.fromJson(json),
        RecentText.wire => RecentText.fromJson(json),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

/// A place for motorhomes, opened again by its id.
final class RecentPlace extends RecentSearch {
  const new(this.place);

  static const wire = 'place';

  final PlaceSummary place;

  static RecentPlace? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = json['kind'];
    final lat = json['lat'];
    final lon = json['lon'];
    if (id is! String || kind is! String || lat is! num || lon is! num) return null;
    return RecentPlace(
      PlaceSummary(
        id: id,
        name: json['name'] as String?,
        kind: PlaceKind.fromWire(kind),
        overnight: OvernightStatus.fromWire(json['overnight'] as String? ?? ''),
        street: json['street'] as String?,
        city: json['city'] as String?,
        postcode: json['postcode'] as String?,
        countryCode: json['countryCode'] as String?,
        lat: lat.toDouble(),
        lon: lon.toDouble(),
      ),
    );
  }

  @override
  String get key => 'place:${place.id}';

  @override
  String get kind => wire;

  @override
  String get title => place.name ?? place.street ?? place.city ?? '';

  @override
  String get matchedText => [?place.name, ?place.street, ?place.city].join(' ');

  @override
  Map<String, Object?> toJson() => {
    'id': place.id,
    'name': ?place.name,
    'kind': place.kind.wire,
    'overnight': place.overnight.wire,
    'street': ?place.street,
    'city': ?place.city,
    'postcode': ?place.postcode,
    'countryCode': ?place.countryCode,
    'lat': place.lat,
    'lon': place.lon,
  };
}

/// A point of interest or an establishment, opened again by its id.
final class RecentPoi extends RecentSearch {
  const new({
    required this.id,
    required this.poiKind,
    required this.position,
    this.name,
    this.locality,
  });

  factory of(Poi poi) => RecentPoi(
    id: poi.id,
    poiKind: poi.kind,
    position: poi.position,
    name: poi.name ?? poi.brand,
    locality: poi.locality,
  );

  static const wire = 'poi';

  final String id;
  final PoiKind poiKind;
  final LatLng position;
  final String? name;
  final Locality? locality;

  /// What its page opens with before the point is read again.
  PoiFeature get feature =>
      PoiFeature(id: id, kind: poiKind, position: position, name: name, locality: locality);

  static RecentPoi? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = PoiKind.fromCode(json['kind']);
    final lat = json['lat'];
    final lon = json['lon'];
    if (id is! String || kind == null || lat is! num || lon is! num) return null;
    return RecentPoi(
      id: id,
      poiKind: kind,
      position: LatLng(lat.toDouble(), lon.toDouble()),
      name: json['name'] as String?,
      locality: Locality.fromStored(json['locality']),
    );
  }

  @override
  String get key => 'poi:$id';

  @override
  String get kind => wire;

  @override
  String get title => name ?? '';

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': poiKind.code,
    'lat': position.lat,
    'lon': position.lon,
    'name': ?name,
    'locality': ?locality?.toJson(),
  };
}

/// A town of the search, shown again where it lies.
final class RecentTown extends RecentSearch {
  const new(this.town);

  static const wire = 'town';

  final Municipality town;

  static RecentTown? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final lat = json['lat'];
    final lon = json['lon'];
    if (name is! String || lat is! num || lon is! num) return null;
    return RecentTown(
      Municipality(
        name: name,
        postcode: json['postcode'] as String?,
        department: json['department'] as String?,
        countryCode: json['countryCode'] as String?,
        center: LatLng(lat.toDouble(), lon.toDouble()),
        placeCount: (json['places'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// One town by its name, its area (the department in France, however it
  /// came: by the API, or by the postcode the device's places carry) and
  /// its country.
  @override
  String get key {
    final area = town.department ?? departmentOfPostcode(town.postcode) ?? town.postcode ?? '';
    return 'town:${townKey(town.name)}:$area:${town.countryCode ?? ''}';
  }

  @override
  String get kind => wire;

  @override
  String get title => town.name;

  @override
  Map<String, Object?> toJson() => {
    'name': town.name,
    'postcode': ?town.postcode,
    'department': ?town.department,
    'countryCode': ?town.countryCode,
    'lat': town.center.lat,
    'lon': town.center.lon,
    'places': town.placeCount,
  };
}

/// An address, a street or an area the geocoders found, opened again at
/// its position with its source.
final class RecentAddress extends RecentSearch {
  const new(this.address);

  static const wire = 'address';

  final AddressMatch address;

  static RecentAddress? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final lat = json['lat'];
    final lon = json['lon'];
    final source = json['sourceId'];
    if (name is! String || lat is! num || lon is! num || source is! String) return null;
    return RecentAddress(
      AddressMatch(
        kind: AddressKind.fromWire(json['kind'] as String?),
        name: name,
        postcode: json['postcode'] as String?,
        city: json['city'] as String?,
        context: json['context'] as String?,
        region: json['region'] as String?,
        countryCode: json['countryCode'] as String?,
        position: LatLng(lat.toDouble(), lon.toDouble()),
        sourceId: source,
        attribution: json['attribution'] as String? ?? '',
      ),
    );
  }

  @override
  String get key {
    final p = address.position;
    return 'address:${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}:'
        '${foldForSearch(address.name)}';
  }

  @override
  String get kind => wire;

  @override
  String get title => address.name;

  @override
  String get matchedText => [address.name, ?address.city].join(' ');

  @override
  Map<String, Object?> toJson() => {
    'kind': switch (address.kind) {
      AddressKind.houseNumber => 'HOUSE_NUMBER',
      AddressKind.street => 'STREET',
      AddressKind.locality => 'LOCALITY',
      AddressKind.town => 'TOWN',
      AddressKind.postcode => 'POSTCODE',
      AddressKind.region => 'REGION',
    },
    'name': address.name,
    'postcode': ?address.postcode,
    'city': ?address.city,
    'context': ?address.context,
    'region': ?address.region,
    'countryCode': ?address.countryCode,
    'lat': address.position.lat,
    'lon': address.position.lon,
    'sourceId': address.sourceId,
    'attribution': address.attribution,
  };
}

/// A text the user searched without opening a result: touched, it is
/// searched again.
final class RecentText extends RecentSearch {
  const new(this.text);

  static const wire = 'text';

  final String text;

  static RecentText? fromJson(Map<String, dynamic> json) {
    final text = json['text'];
    if (text is! String || text.trim().isEmpty) return null;
    return RecentText(text);
  }

  @override
  String get key => 'text:${townKey(text)}';

  @override
  String get kind => wire;

  @override
  String get title => text;

  @override
  Map<String, Object?> toJson() => {'text': text};
}

/// The words of [text], folded as the search folds them.
List<String> _words(String text) => [
  for (final w in townKey(text).split(' '))
    if (w.isNotEmpty) w,
];
