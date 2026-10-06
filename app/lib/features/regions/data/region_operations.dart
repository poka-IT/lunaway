import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:meta/meta.dart';

/// The regions a device can keep, with the pack of each
/// (docs/region-packs.md, "The manifest").
final regionsOperation = GraphQLOperation<List<RegionInfo>>(
  name: 'Regions',
  document: '''
query Regions {
  regions {
    code
    country
    name
    nameFr
    pack {
      url
      format
      bytes
      rawBytes
      sha256
      version
      cursor
      places
      bounds { south west north east }
      generatedAt
    }
  }
}''',
  parse: (data) => [
    for (final r in data['regions'] as List<dynamic>)
      if (r is Map<String, dynamic>) ?regionFromJson(r),
  ],
);

/// A region of the manifest; null without its code. A pack the app cannot
/// read is left out: the region then syncs from the feed.
RegionInfo? regionFromJson(Map<String, dynamic> json) {
  final code = json['code'];
  final country = json['country'];
  if (code is! String || country is! String) return null;
  return RegionInfo(
    code: code,
    country: country,
    name: json['name'] as String? ?? code,
    nameFr: json['nameFr'] as String? ?? json['name'] as String? ?? code,
    pack: _pack(json['pack']),
  );
}

RegionPack? _pack(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final b = json['bounds'];
  final generated = DateTime.tryParse('${json['generatedAt']}');
  final sha = json['sha256'];
  if (b is! Map<String, dynamic> ||
      generated == null ||
      sha is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
    return null;
  }
  return RegionPack(
    url: json['url'] as String,
    format: json['format'] as String,
    bytes: (json['bytes'] as num).toInt(),
    rawBytes: (json['rawBytes'] as num).toInt(),
    sha256: sha,
    version: json['version'] as String,
    cursor: json['cursor'] as String,
    places: (json['places'] as num).toInt(),
    bounds: GeoBounds(
      south: (b['south'] as num).toDouble(),
      west: (b['west'] as num).toDouble(),
      north: (b['north'] as num).toDouble(),
      east: (b['east'] as num).toDouble(),
    ),
    generatedAt: generated.toUtc(),
  );
}

/// The inverse of [regionFromJson], for the copy of the manifest kept on
/// the device.
Map<String, Object?> regionToJson(RegionInfo r) => {
  'code': r.code,
  'country': r.country,
  'name': r.name,
  'nameFr': r.nameFr,
  'pack': switch (r.pack) {
    null => null,
    final p => {
      'url': p.url,
      'format': p.format,
      'bytes': p.bytes,
      'rawBytes': p.rawBytes,
      'sha256': p.sha256,
      'version': p.version,
      'cursor': p.cursor,
      'places': p.places,
      'bounds': {
        'south': p.bounds.south,
        'west': p.bounds.west,
        'north': p.bounds.north,
        'east': p.bounds.east,
      },
      'generatedAt': p.generatedAt.toUtc().toIso8601String(),
    },
  },
};

/// A page of the feed of one region: the places changed, deleted, and
/// those that moved to another region.
@immutable
final class RegionChangeSet {
  const new({
    required this.places,
    required this.deleted,
    required this.left,
    required this.cursor,
    required this.hasMore,
  });

  final List<Place> places;
  final List<String> deleted;

  /// Places now in another region: dropped unless the device keeps it.
  final List<String> left;
  final String cursor;
  final bool hasMore;
}

/// The feed of one region: the same fields as the sync by box, and the
/// places that left the region.
final regionChangesOperation = GraphQLOperation<RegionChangeSet>(
  name: 'RegionChanges',
  document: '''
query RegionChanges(\$region: String!, \$since: String, \$first: Int) {
  changes(region: \$region, since: \$since, first: \$first) {
    places { ...PlaceFields }
    deleted
    left
    cursor
    hasMore
  }
}
$placeFieldsFragment''',
  parse: (data) {
    final set = data['changes'] as Map<String, dynamic>;
    return RegionChangeSet(
      places: [
        for (final p in set['places'] as List<dynamic>) placeFromJson(p as Map<String, dynamic>),
      ],
      deleted: [for (final d in set['deleted'] as List<dynamic>) d as String],
      left: [for (final d in set['left'] as List<dynamic>? ?? const []) d as String],
      cursor: set['cursor'] as String,
      hasMore: set['hasMore'] as bool,
    );
  },
);

/// The operations of the regions, held to the schema by the contract test.
final regionOperations = <GraphQLOperation<Object?>>[regionsOperation, regionChangesOperation];
