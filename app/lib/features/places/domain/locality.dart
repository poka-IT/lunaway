import 'package:lunaway/features/places/domain/french_departments.dart';
import 'package:meta/meta.dart';

/// Where a result of the search lies, for the short line under its name
/// ("Restaurant · Annecy (74)"): its town, its French department, its
/// region abroad when the data names one, its country. Each part null when
/// the data does not say: the line then says less, never a guess.
@immutable
final class Locality {
  const new({this.town, this.department, this.region, this.countryCode, this.postcode});

  /// A place or an address: its town, the department of its postcode in
  /// France (or a country unknown), its country.
  factory fromAddress({String? town, String? postcode, String? countryCode, String? region}) {
    final country = countryCode?.toUpperCase();
    return Locality(
      town: town,
      department: country == null || country == 'FR'
          ? departmentOfPostcode(postcode?.trim())
          : null,
      region: region,
      countryCode: country,
      postcode: postcode,
    );
  }

  /// What the API says of a point (`Poi.locality`); null for a point the
  /// API said nothing of.
  static Locality? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final locality = Locality(
      town: text(json['town']),
      department: text(json['department']),
      countryCode: text(json['countryCode'])?.toUpperCase(),
    );
    return locality.isEmpty ? null : locality;
  }

  /// The town; null when the data names none.
  final String? town;

  /// The French department (`26`, `2A`, `974`); null outside France.
  final String? department;

  /// The region, state or province abroad, as the geocoder names it
  /// (`Bayern`); null when unknown, and in France.
  final String? region;

  /// ISO 3166-1 alpha-2, upper case.
  final String? countryCode;

  /// The postcode, which tells the arrondissement of Paris, Lyon and
  /// Marseille ("Lyon 3e"); null when unknown. Not part of the identity.
  final String? postcode;

  bool get isEmpty => town == null && department == null && region == null && countryCode == null;

  Map<String, Object?> toJson() => {
    'town': ?town,
    'department': ?department,
    'region': ?region,
    'countryCode': ?countryCode,
    'postcode': ?postcode,
  };

  /// The inverse of [toJson], for the copy the search history keeps.
  static Locality? fromStored(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final locality = Locality(
      town: text(json['town']),
      department: text(json['department']),
      region: text(json['region']),
      countryCode: text(json['countryCode']),
      postcode: text(json['postcode']),
    );
    return locality.isEmpty ? null : locality;
  }

  @override
  bool operator ==(Object other) =>
      other is Locality &&
      other.town == town &&
      other.department == department &&
      other.region == region &&
      other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(town, department, region, countryCode);
}

/// The arrondissement of Paris (75001 to 75020, 75116), Lyon (69001 to
/// 69009) or Marseille (13001 to 13016) its [postcode] names in [town];
/// null elsewhere.
int? arrondissementOf(String? town, String? postcode) {
  if (town == null || postcode == null) return null;
  final code = postcode.trim();
  if (!RegExp(r'^[0-9]{5}$').hasMatch(code)) return null;
  final n = int.parse(code.substring(3));
  return switch ((town.trim().toLowerCase(), code.substring(0, 3))) {
    ('paris', '750') when n >= 1 && n <= 20 => n,
    ('paris', '751') when code == '75116' => 16,
    ('lyon', '690') when n >= 1 && n <= 9 => n,
    ('marseille', '130') when n >= 1 && n <= 16 => n,
    _ => null,
  };
}
