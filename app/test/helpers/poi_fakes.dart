import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/data/pack_files.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

import 'samples.dart';

String _iso(DateTime t) => t.toUtc().toIso8601String();

/// Open from [from] to [to] UTC every day around [testNow] (08:30 UTC).
List<Map<String, String>> _dayHours({int from = 5, int to = 17}) => [
  for (var d = -1; d < 13; d++)
    {
      'start': _iso(DateTime.utc(2026, 10, 6 + d, from)),
      'end': _iso(DateTime.utc(2026, 10, 6 + d, to)),
    },
];

/// Open from 14:00 to 19:00 UTC: closed now, opening this afternoon.
List<Map<String, String>> _afternoonHours() => [
  for (var d = 0; d < 13; d++)
    {
      'start': _iso(DateTime.utc(2026, 10, 6 + d, 14)),
      'end': _iso(DateTime.utc(2026, 10, 6 + d, 19)),
    },
];

/// Points around the sample lake area (`test-lake`), as the API sends them.
Map<String, Object?> poiJson(
  String id,
  String kind, {
  String? name,
  double lat = 45.9002,
  double lon = 6.1300,
  double? distanceM,
  bool alwaysOpen = false,
  List<Map<String, String>>? intervals,
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'kind': kind,
  'name': name,
  'brand': null,
  'lat': lat,
  'lon': lon,
  'distanceM': distanceM,
  'alwaysOpen': alwaysOpen,
  'openingHoursParsed': intervals != null,
  'openingIntervals': intervals,
  'openingIntervalsUntil': intervals == null ? null : _iso(DateTime.utc(2026, 10, 19, 22)),
  'lpg': null,
  ...extra,
};

final Map<String, Object?> bakeryJson = poiJson(
  '00000000-0000-7000-8000-00000000b001',
  'BAKERY',
  name: 'Boulangerie du Lac',
  distanceM: 230,
  intervals: _dayHours(),
);

final Map<String, Object?> pizzaJson = poiJson(
  '00000000-0000-7000-8000-00000000b002',
  'VENDING_PIZZA',
  distanceM: 640,
  alwaysOpen: true,
);

final Map<String, Object?> dumpJson = poiJson(
  '00000000-0000-7000-8000-00000000b003',
  'DUMP_STATION',
  distanceM: 20,
);

final Map<String, Object?> pharmacyJson = poiJson(
  '00000000-0000-7000-8000-00000000b004',
  'PHARMACY',
  name: 'Pharmacie des Marquisats',
  distanceM: 2100,
  intervals: _afternoonHours(),
);

final Map<String, Object?> stationJson = poiJson(
  '00000000-0000-7000-8000-00000000b005',
  'FUEL_STATION',
  name: 'Station du Semnoz',
  distanceM: 1800,
  intervals: _dayHours(from: 4, to: 19),
  extra: {
    'lpg': true,
    'operator': null,
    'address': {
      'street': '4 chemin des Alluèges',
      'postcode': '74000',
      'city': 'Annecy',
      'countryCode': 'FR',
    },
    'phone': null,
    'website': 'https://www.example.org/station',
    'openingHours': 'Mo-Sa 07:00-19:30',
    'products': <String>[],
    'payment': ['cards'],
    'fuel': {
      'prices': [
        {'fuel': 'DIESEL', 'priceEur': 1.789, 'updatedAt': _iso(DateTime.utc(2026, 10, 6, 6))},
        {'fuel': 'LPG', 'priceEur': 1.029, 'updatedAt': _iso(DateTime.utc(2026, 10, 6, 6))},
        {'fuel': 'E10', 'priceEur': 1.759, 'updatedAt': _iso(DateTime.utc(2026, 10, 5, 6))},
      ],
      'shortages': [
        {'fuel': 'E85', 'kind': 'TEMPORARY', 'since': _iso(DateTime.utc(2026, 10, 3))},
      ],
      'sellsLpg': true,
      'selfService24h': true,
      'highway': false,
      'fetchedAt': _iso(DateTime.utc(2026, 10, 6, 8, 20)),
    },
    'reportedClosed': null,
    'seasonal': null,
    'fee': null,
    'selfService': null,
    'wheelchair': null,
    'checkedOn': null,
    'lastConfirmedAt': _iso(DateTime.utc(2026, 10, 3, 12)),
    'sources': [
      {
        'sourceId': 'osm',
        'externalId': 'node/25179237',
        'externalUrl': 'https://www.openstreetmap.org/node/25179237',
        'fetchedAt': _iso(DateTime.utc(2026, 10, 6, 3)),
      },
      {
        'sourceId': 'prix-carburants',
        'externalId': '74000020',
        'externalUrl': null,
        'fetchedAt': _iso(DateTime.utc(2026, 10, 6, 8, 20)),
      },
    ],
  },
);

/// A station with only [prices] (fuel, euros), around the lake.
Map<String, Object?> stationWith(
  String id,
  String name,
  Map<String, double> prices, {
  double lat = 45.905,
  double lon = 6.12,
  List<Map<String, Object?>> shortages = const [],
}) => poiJson(
  id,
  'FUEL_STATION',
  name: name,
  lat: lat,
  lon: lon,
  intervals: _dayHours(from: 4, to: 19),
  extra: {
    'fuel': {
      'prices': [
        for (final MapEntry(:key, :value) in prices.entries)
          {'fuel': key, 'priceEur': value, 'updatedAt': _iso(DateTime.utc(2026, 10, 6, 6))},
      ],
      'shortages': shortages,
      'sellsLpg': prices.containsKey('LPG'),
      'selfService24h': false,
      'highway': false,
      'fetchedAt': _iso(DateTime.utc(2026, 10, 6, 8, 20)),
    },
  },
);

const _sources = [
  {
    'id': 'osm',
    'name': 'OpenStreetMap',
    'licence': 'ODbL 1.0',
    'attribution': '© OpenStreetMap contributors',
    'url': 'https://www.openstreetmap.org/copyright',
  },
  {
    'id': 'prix-carburants',
    'name': 'Prix des carburants',
    'licence': 'Licence Ouverte 2.0',
    'attribution': "Ministère de l'Économie, prix des carburants",
    'url': 'https://www.data.gouv.fr/',
  },
];

/// The API's points in memory: "around this place" and the pages.
final class FakePoiSource implements PoiSource {
  /// By default none is closed at [testNow]: the place pages of other tests
  /// read their own hours without a point's in the way.
  new({List<Map<String, Object?>>? pois})
    : pois = pois ?? [bakeryJson, pizzaJson, dumpJson, stationJson];

  final List<Map<String, Object?>> pois;
  bool online = true;
  int nearbyReads = 0;

  /// The server answers with an error instead of the data.
  bool refuse = false;

  void _check() {
    if (!online) throw GraphQLNetworkException('offline', null);
    if (refuse) throw GraphQLResponseException([const GraphQLError('down', code: 'INTERNAL')]);
  }

  @override
  Future<Map<String, dynamic>> nearby(String placeId) async {
    nearbyReads++;
    _check();
    return jsonDecode(
      jsonEncode({
        'nearbyPois': [
          // The families the tiles carry, as the server's default.
          for (final c in PoiCategory.values.where((c) => c.tiled))
            {
              'category': c.wire,
              'radiusM': c == PoiCategory.fuel || c == PoiCategory.health ? 10000.0 : 5000.0,
              'pois': [
                for (final p in pois)
                  if (PoiKind.fromCode(p['kind'])?.category == c) p,
              ],
            },
        ],
      }),
    ) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> page(String poiId) async {
    _check();
    final poi = pois.where((p) => p['id'] == poiId).firstOrNull;
    return jsonDecode(jsonEncode({'poi': poi, 'sources': _sources})) as Map<String, dynamic>;
  }

  int fuelReads = 0;

  /// The reviews of each point, as `PoiReviews` answers them.
  final Map<String, PoiReviews> reviewsOf = {};

  /// How many times the reviews of a point were read.
  int reviewReads = 0;

  /// The reviews' request fails as a lost network would.
  bool reviewsOffline = false;

  /// The server refuses the reviews' request.
  bool reviewsRefused = false;

  /// Holds the answers of the reviews until it completes.
  Completer<void>? holdReviews;

  @override
  Future<PoiReviews?> reviews(String poiId, {int first = 20}) async {
    reviewReads++;
    await holdReviews?.future;
    if (reviewsOffline) throw GraphQLNetworkException('offline', null);
    if (reviewsRefused) {
      throw GraphQLResponseException([const GraphQLError('down', code: 'INTERNAL')]);
    }
    _check();
    return reviewsOf[poiId] ?? (mine: null, ours: ReviewPage.empty, external: ReviewPage.empty);
  }

  /// The fuel points a page holds, as the API's `first`.
  int fuelPageSize = 1000;

  @override
  Future<FuelStationsPage> fuelStations(GeoBounds box, {String? after}) async {
    fuelReads++;
    _check();
    final all = [
      for (final p in pois)
        if (poiFromJson(p) case final poi? when poi.fuel != null && box.contains(poi.position)) poi,
    ];
    final start = after == null ? 0 : int.parse(after);
    final end = (start + fuelPageSize).clamp(0, all.length);
    return (stations: all.sublist(start, end), endCursor: '$end', hasNextPage: end < all.length);
  }
}

/// The offline maps' folder in memory.
final class MemoryPackFiles implements PackFiles {
  new({this.supported = true});

  @override
  final bool supported;

  final files = <String, List<int>>{};
  String? index;
  String? manifestCopy;

  @override
  Future<String> directory() async => '/mem/offline_maps';

  @override
  Future<String?> readIndex() async => index;

  @override
  Future<void> writeIndex(String json) async => index = json;

  @override
  Future<String?> readManifestCopy() async => manifestCopy;

  @override
  Future<void> writeManifestCopy(String text) async => manifestCopy = text;

  @override
  PackSink partSink(String fileName) =>
      MemorySink(files.putIfAbsent('$fileName.part', () => []), room: room);

  /// What a part may hold before the disk is full; null, no limit.
  int? room;

  @override
  Future<String> partSha256(String fileName) async =>
      sha256.convert(files['$fileName.part'] ?? const []).toString();

  @override
  Future<void> install(String fileName) async {
    files[fileName] = files.remove('$fileName.part')!;
  }

  @override
  Future<void> delete(String fileName) async {
    files
      ..remove(fileName)
      ..remove('$fileName.part');
  }

  @override
  Future<bool> exists(String fileName) async => files.containsKey(fileName);

  /// What the device says it has free; null, it does not say.
  int? free;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<int> usedBytes() async => files.values.fold<int>(0, (n, f) => n + f.length);

  @override
  Future<String> installStyleAssets(AssetBundle bundle, {required String version}) async =>
      '/mem/offline_maps/style';
}

/// A part in memory.
final class MemorySink implements PackSink {
  new(this.bytes, {this.room});

  final List<int> bytes;

  /// The bytes the device can still take; past them, a write fails as a
  /// full disk does.
  final int? room;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<void> truncate() async => bytes.clear();

  @override
  Future<void> append(List<int> chunk) async {
    if (room case final room? when bytes.length + chunk.length > room) {
      throw const FileSystemException('No space left on device', '', OSError('', 28));
    }
    bytes.addAll(chunk);
  }

  @override
  Future<void> close() async {}
}

/// The basemap's host answers, or not, as the test says; nothing is asked.
final class FixedReachability extends BasemapReachability {
  new({required this.reachable});

  final bool? reachable;

  @override
  bool? build() => reachable;

  /// Each time the map, at rest, asked whether the answer was still fresh.
  final List<void> restChecks = [];

  @override
  Future<void> probe() async {}

  @override
  Future<void> probeIfStale() async => restChecks.add(null);
}
