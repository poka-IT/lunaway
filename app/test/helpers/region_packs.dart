import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:sqlite3/sqlite3.dart';

/// The columns of a pack's `places` table and the field of the API's JSON
/// each holds, as the server writes them (`lunaway_api::packs::COLUMNS`):
/// a scalar, a scalar of `address`, or JSON text.
const packColumns = <(String, String, String)>[
  ('id', 'scalar', 'id'),
  ('name', 'scalar', 'name'),
  ('kind', 'scalar', 'kind'),
  ('lat', 'scalar', 'lat'),
  ('lon', 'scalar', 'lon'),
  ('overnight', 'scalar', 'overnight'),
  ('services', 'json', 'services'),
  ('activities', 'json', 'activities'),
  ('description', 'scalar', 'description'),
  ('street', 'address', 'street'),
  ('postcode', 'address', 'postcode'),
  ('city', 'address', 'city'),
  ('country_code', 'address', 'countryCode'),
  ('municipality', 'scalar', 'municipality'),
  ('region', 'scalar', 'region'),
  ('price_parking_eur', 'scalar', 'priceParkingEur'),
  ('price_services_eur', 'scalar', 'priceServicesEur'),
  ('max_height_m', 'scalar', 'maxHeightM'),
  ('max_length_m', 'scalar', 'maxLengthM'),
  ('max_width_m', 'scalar', 'maxWidthM'),
  ('max_weight_t', 'scalar', 'maxWeightT'),
  ('capacity', 'scalar', 'capacity'),
  ('stars', 'scalar', 'stars'),
  ('opening_hours', 'scalar', 'openingHours'),
  ('opening_hours_parsed', 'scalar', 'openingHoursParsed'),
  ('opening_intervals', 'json', 'openingIntervals'),
  ('opening_intervals_until', 'scalar', 'openingIntervalsUntil'),
  ('website', 'scalar', 'website'),
  ('phone', 'scalar', 'phone'),
  ('last_confirmed_at', 'scalar', 'lastConfirmedAt'),
  ('updated_at', 'scalar', 'updatedAt'),
  ('sources', 'json', 'sources'),
  ('provenance', 'json', 'provenance'),
  ('descriptions', 'json', 'descriptions'),
  ('ratings', 'json', 'ratings'),
  ('external_links', 'json', 'externalLinks'),
  ('verification', 'scalar', 'verification'),
  ('review_count', 'scalar', 'reviewCount'),
  ('photo_count', 'scalar', 'photoCount'),
  ('cover_photos', 'json', 'coverPhotos'),
  ('reported_issues', 'json', 'reportedIssues'),
  // Added at the end of the same format: a pack built before has none.
  ('rating_for_filters', 'scalar', 'ratingForFilters'),
  ('price_services_included', 'scalar', 'priceServicesIncluded'),
  ('price_parking_includes', 'json', 'priceParkingIncludes'),
  ('opening_season', 'json', 'openingSeason'),
];

/// The columns of the price inclusions, the last ones of the format.
const _inclusionColumns = {'price_services_included', 'price_parking_includes'};

/// Writes the SQLite file of a pack of [region] holding [places] (the
/// API's JSON of each) at [path], as `lunaway packs build` does; without
/// [withRating], as it did before the rating of the filters; without
/// [withInclusions], as it did before the price inclusions; without
/// [withSeason], as it did before the seasons.
void writePackDatabase(
  String path,
  List<Map<String, dynamic>> places, {
  required String region,
  required String cursor,
  bool withRating = true,
  bool withInclusions = true,
  bool withSeason = true,
}) {
  final columns = [
    for (final c in packColumns)
      if ((withRating || c.$1 != 'rating_for_filters') &&
          (withInclusions || !_inclusionColumns.contains(c.$1)) &&
          (withSeason || c.$1 != 'opening_season'))
        c,
  ];
  final db = sqlite3.open(path);
  try {
    db
      ..execute('CREATE TABLE pack (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID')
      ..execute('CREATE TABLE places (${columns.map((c) => c.$1).join(', ')})');
    for (final (key, value) in [
      ('format', RegionPack.supportedFormat),
      ('region', region),
      ('cursor', cursor),
      ('places', '${places.length}'),
    ]) {
      db.execute('INSERT INTO pack VALUES (?, ?)', [key, value]);
    }
    final insert = db.prepare(
      'INSERT INTO places VALUES (${List.filled(columns.length, '?').join(', ')})',
    );
    for (final p in places) {
      insert.execute([
        for (final (_, how, field) in columns)
          switch (how) {
            'address' => _scalar((p['address'] as Map<String, dynamic>?)?[field]),
            'json' => p[field] == null ? null : jsonEncode(p[field]),
            _ => _scalar(p[field]),
          },
      ]);
    }
    insert.close();
  } finally {
    db.close();
  }
}

Object? _scalar(Object? v) => switch (v) {
  null => null,
  final bool b => b ? 1 : 0,
  final num n => n,
  final String s => s,
  final other => jsonEncode(other),
};

/// A pack file as the server serves it: [places] gzipped at [path], and
/// the manifest's description of it.
RegionPack writePackFile(
  String path,
  List<Map<String, dynamic>> places, {
  required String region,
  required String cursor,
  String version = '1',
}) {
  final raw = '$path.raw';
  writePackDatabase(raw, places, region: region, cursor: cursor);
  final bytes = File(raw).readAsBytesSync();
  final packed = gzip.encode(bytes);
  File(path).writeAsBytesSync(packed);
  File(raw).deleteSync();
  return RegionPack(
    url: '/packs/places/$region-$version-0123456789ab.sqlite.gz',
    format: RegionPack.supportedFormat,
    bytes: packed.length,
    rawBytes: bytes.length,
    sha256: sha256.convert(packed).toString(),
    version: version,
    cursor: cursor,
    places: places.length,
    bounds: const GeoBounds(south: 41, west: -5, north: 51, east: 9),
    generatedAt: DateTime.utc(2026, 10, 6, 5, 30),
  );
}
