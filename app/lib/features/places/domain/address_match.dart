import 'package:lunaway/core/geo/geo.dart';
import 'package:meta/meta.dart';

/// What an address the search found designates, from the most precise to
/// the widest.
enum AddressKind {
  houseNumber,
  street,
  locality,
  town,
  postcode,
  region;

  /// The kind the API names [wire]; an unknown one (an API newer than the
  /// app) reads as a locality, a named point of no particular size.
  static AddressKind fromWire(String? wire) => switch (wire) {
    'HOUSE_NUMBER' => houseNumber,
    'STREET' => street,
    'TOWN' => town,
    'POSTCODE' => postcode,
    'REGION' => region,
    _ => locality,
  };

  /// How close the map comes to show it: a house up close, a region from
  /// afar.
  double get zoom => switch (this) {
    houseNumber => 17,
    street => 16,
    locality => 14,
    town || postcode => 12,
    region => 8,
  };
}

/// A postal address, street, town or postcode the server's geocoders found
/// for the map's search, with the source to credit.
@immutable
final class AddressMatch {
  const new({
    required this.kind,
    required this.name,
    required this.position,
    required this.sourceId,
    required this.attribution,
    this.postcode,
    this.city,
    this.context,
    this.countryCode,
  });

  final AddressKind kind;

  /// The first line: house number and street, the street, or the name of
  /// the town or area (a postcode for [AddressKind.postcode]).
  final String name;
  final String? postcode;

  /// Its town, when it lies in one.
  final String? city;

  /// The wider area ("77, Seine-et-Marne, Île-de-France").
  final String? context;
  final String? countryCode;
  final LatLng position;

  /// `ban` (Base Adresse Nationale) or `osm` (OpenStreetMap).
  final String sourceId;

  /// The text the source asks to be credited with.
  final String attribution;

  /// The second line: postcode and town, then the wider area.
  String get detail => [
    [?postcode, ?city].join(' '),
    ?context,
  ].where((s) => s.isNotEmpty).join(', ');

  @override
  bool operator ==(Object other) =>
      other is AddressMatch &&
      other.kind == kind &&
      other.name == name &&
      other.postcode == postcode &&
      other.city == city &&
      other.position == position &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(kind, name, postcode, city, position, sourceId);
}
