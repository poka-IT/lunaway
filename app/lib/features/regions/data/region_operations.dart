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
  if (json case {
    'url': final String url,
    'format': final String format,
    'bytes': final num bytes,
    'rawBytes': final num rawBytes,
    'sha256': final String sha,
    'version': final String version,
    'cursor': final String cursor,
    'places': final num places,
    'bounds': {
      'south': final num south,
      'west': final num west,
      'north': final num north,
      'east': final num east,
    },
    'generatedAt': final String generatedAt,
  }) {
    final generated = DateTime.tryParse(generatedAt);
    if (generated == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        bytes <= 0 ||
        bytes > maxPackBytes ||
        rawBytes <= 0 ||
        rawBytes > maxPackBytes) {
      return null;
    }
    return RegionPack(
      url: url,
      format: format,
      bytes: bytes.toInt(),
      rawBytes: rawBytes.toInt(),
      sha256: sha,
      version: version,
      cursor: cursor,
      places: places.toInt(),
      bounds: GeoBounds(
        south: south.toDouble(),
        west: west.toDouble(),
        north: north.toDouble(),
        east: east.toDouble(),
      ),
      generatedAt: generated.toUtc(),
    );
  }
  return null;
}

/// Largest pack accepted, downloaded or decompressed: the biggest country
/// pack is tens of megabytes, a manifest asking for more is not trusted
/// with the device's storage.
const int maxPackBytes = 1024 * 1024 * 1024;

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
