import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/regions/data/region_operations.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/data/region_pack_files_io.dart';
import 'package:lunaway/features/regions/data/region_store.dart';
import 'package:lunaway/features/regions/data/region_sync_service.dart';
import 'package:lunaway/features/regions/domain/regions.dart';

import '../helpers/region_packs.dart';
import '../helpers/samples.dart';

/// The places of the recorded `changes` page (an unknown service, an empty
/// website, a town from the commune, a classification out of range, an
/// unknown kind) and of the samples, as the API writes them.
List<Map<String, dynamic>> apiPlaces({String region = 'FR-ARA'}) {
  final page = jsonDecode(
    File('test/fixtures/changes_page.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final recorded = [
    for (final p in ((page['data'] as Map)['changes'] as Map)['places'] as List)
      Map<String, dynamic>.from(p as Map),
  ];
  return [
    ...recorded,
    for (final p in samplePlaces) jsonDecode(jsonEncode(placeToJson(p))) as Map<String, dynamic>,
    // Blank texts, a duplicated service, an unknown overnight status and
    // verification, ratings with a count of zero, intervals without the
    // end of their window.
    {
      'id': 'edge-1',
      'name': '   ',
      'kind': 'CAMPSITE',
      'lat': 44.5,
      'lon': 4.25,
      'overnight': 'SOMETIMES',
      'services': ['TOILETS', 'TOILETS', 'SHOWERS'],
      'activities': ['FISHING', 'NOT_YET'],
      'description': '',
      'address': null,
      'municipality': 'Aubenas',
      'stars': 2.5,
      'openingHoursParsed': false,
      'openingIntervals': [
        {'start': '2026-10-06T06:00:00Z', 'end': '2026-10-06T18:00:00Z'},
      ],
      'openingIntervalsUntil': null,
      // A fraction SQLite would round up: Dart cuts it after the milliseconds.
      'updatedAt': '2026-10-05T08:00:00.123956Z',
      'lastConfirmedAt': '2026-10-01T12:00:00+02:00',
      'sources': <Object>[],
      'provenance': <Object>[],
      'descriptions': <Object>[],
      'ratings': [
        {'sourceId': 'a', 'average': 4.5, 'count': 2},
        {'sourceId': 'b', 'average': 1, 'count': 0},
        {'sourceId': 'c', 'average': 3, 'count': 6},
      ],
      'externalLinks': <Object>[],
      'verification': 'MAYBE',
      'reviewCount': 3,
      'photoCount': 0,
      'coverPhotos': <Object>[],
      'reportedIssues': <Object>[],
    },
  ];
}

/// A region's feed in memory: its pages after each cursor, and the
/// requests received.
final class _Feed implements RegionChangesSource {
  final Map<(String, String?), RegionChangeSet> pages = {};
  final List<({String region, String? since})> requests = [];
  final Set<String?> foreign = {};

  @override
  Future<RegionChangeSet> changes({
    required String region,
    required int first,
    String? since,
  }) async {
    requests.add((region: region, since: since));
    if (foreign.contains(since)) {
      throw GraphQLResponseException(const [
        GraphQLError('another copy', code: GraphQLError.resync),
      ]);
    }
    return pages[(region, since)] ??
        RegionChangeSet(
          places: const [],
          deleted: const [],
          left: const [],
          cursor: since ?? '0',
          hasMore: false,
        );
  }
}

/// Serves pack files by path with byte ranges; [cutAfter] drops the
/// connection after that many bytes of the next answer.
final class _Files {
  final Map<String, List<int>> files = {};
  final List<String?> ranges = [];
  int? cutAfter;

  http.Client get client => MockClient.streaming((request, _) async {
    final bytes = files[request.url.path];
    if (bytes == null) return http.StreamedResponse(const Stream.empty(), 404);
    final range = request.headers['range'];
    ranges.add(range);
    final start = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
    final body = bytes.sublist(start);
    final cut = cutAfter;
    cutAfter = null;
    final stream = cut == null
        ? Stream.value(body)
        : Stream<List<int>>.fromIterable([body.sublist(0, cut)])
              .followedBy(Stream.error(http.ClientException('connection reset')));
    return http.StreamedResponse(
      stream,
      range == null ? 200 : 206,
      contentLength: body.length,
      headers: {
        if (range != null) 'content-range': 'bytes $start-${bytes.length - 1}/${bytes.length}',
      },
    );
  });
}

extension<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}

RegionChangeSet _page(
  List<Place> places, {
  required String cursor,
  List<String> deleted = const [],
  List<String> left = const [],
  bool hasMore = false,
}) =>
    RegionChangeSet(places: places, deleted: deleted, left: left, cursor: cursor, hasMore: hasMore);

Place _plain(String id, {double lat = 45, String? name, DateTime? updatedAt}) => Place(
  id: id,
  name: name,
  kind: PlaceKind.parking,
  lat: lat,
  lon: 5,
  overnight: OvernightStatus.allowed,
  updatedAt: updatedAt ?? DateTime.utc(2026, 10),
);

void main() {
  late Directory dir;
  late CacheDatabase db;
  late DriftPlacesRepository places;
  late DriftRegionStore store;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('lunaway-regions');
    db = CacheDatabase(NativeDatabase.memory());
    places = DriftPlacesRepository(db);
    store = DriftRegionStore(db, places);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<List<String>> idsOf(String? region) async => [
    for (final r
        in await (db.select(db.places)
              ..where((p) => region == null ? p.region.isNull() : p.region.equals(region))
              ..orderBy([(p) => OrderingTerm(expression: p.id)]))
            .get())
      r.id,
  ];

  group('the pack import', () {
    test('a place from a pack is the place the feed gives, field for field', () async {
      final json = apiPlaces();
      final pack = '${dir.path}/fr-ara.sqlite';
      writePackDatabase(pack, json, region: 'FR-ARA', cursor: 'c9');
      expect(await store.importPack('FR-ARA', pack, cursor: 'c9'), json.length);

      final fed = CacheDatabase(NativeDatabase.memory());
      final fedPlaces = DriftPlacesRepository(fed);
      final fedStore = DriftRegionStore(fed, fedPlaces);
      await fedStore.beginFullSync('FR-ARA');
      await fedStore.applyPage(
        'FR-ARA',
        _page([for (final j in json) placeFromJson(j)], cursor: 'c9'),
      );

      for (final j in json) {
        final id = j['id'] as String;
        expect(await places.watchPlace(id).first, await fedPlaces.watchPlace(id).first, reason: id);
        // The columns the lists and the filters read without the JSON.
        const derived =
            'SELECT family, kind, services, activities, rating_avg, rating_count, city, name, '
            'stars, opening_valid_until, last_confirmed_at, updated_at, overnight, verification, '
            'region FROM places WHERE id = ?';
        final a = await db.customSelect(derived, variables: [Variable.withString(id)]).getSingle();
        final b = await fed.customSelect(derived, variables: [Variable.withString(id)]).getSingle();
        expect(a.data, b.data, reason: id);
      }
      // The indexes follow the rows: the map's box and the search find them.
      final found = await places.search('Essais');
      expect(found.places.map((p) => p.id), contains('0192f5a0-0000-7000-8000-000000000001'));
      expect(
        await places
            .watchInBounds(
              const GeoBounds(south: 45.8, west: 6, north: 46, east: 6.2),
              PlaceFilter.none,
              center: const LatLng(45.9, 6.1),
            )
            .first,
        isNotEmpty,
      );
      await fed.close();
    });

    test('a pack replaces its region: what it lacks goes, other regions stay', () async {
      await store.beginFullSync('FR-ARA');
      await store.applyPage('FR-ARA', _page([_plain('old'), _plain('kept')], cursor: 'c1'));
      await store.completeRun('FR-ARA', DateTime.utc(2026, 10));
      await store.beginFullSync('ES');
      await store.applyPage('ES', _page([_plain('madrid', lat: 40.4)], cursor: 'e1'));
      final pack = '${dir.path}/p.sqlite';
      writePackDatabase(
        pack,
        [
          {...apiPlaces().first, 'id': 'kept'},
          {...apiPlaces().first, 'id': 'new'},
        ],
        region: 'FR-ARA',
        cursor: 'c50',
      );
      await store.importPack('FR-ARA', pack, cursor: 'c50');
      expect(await idsOf('FR-ARA'), ['kept', 'new']);
      expect(await idsOf('ES'), ['madrid']);
      final state = await store.stateOf('FR-ARA');
      expect(state.cursor, 'c50', reason: 'the feed goes on after the pack');
      expect(state.running, isTrue, reason: 'the run ends with the last page of the feed');
      expect(state.fullSync, isFalse);
    });
  });

  group('one region', () {
    late _Feed feed;
    late _Files files;
    late RegionSyncService service;
    const config = AppConfig(apiBaseUrl: 'https://api.example.org', demo: false, basemapUrl: '');

    RegionSyncService build({bool packs = true}) => RegionSyncService(
      changes: feed,
      store: store,
      packs: packs ? IoRegionPackFiles(root: () async => dir) : const _NoPacks(),
      downloader: PackDownloader(client: files.client, userAgent: 'test'),
      packUrl: (url) => placesPackUrl(config, url),
    );

    setUp(() {
      feed = _Feed();
      files = _Files();
      service = build();
    });

    RegionInfo serve(String code, List<Map<String, dynamic>> placesJson, {String cursor = 'p1'}) {
      final file = '${dir.path}/$code.gz';
      final pack = writePackFile(file, placesJson, region: code, cursor: cursor);
      files.files[pack.url] = File(file).readAsBytesSync();
      return RegionInfo(
        code: code,
        country: code.substring(0, 2),
        name: code,
        nameFr: code,
        pack: pack,
      );
    }

    test('the pack first, then the feed from its cursor; left takes out its own', () async {
      final region = serve('FR-ARA', [
        {...apiPlaces().first, 'id': 'a'},
        {...apiPlaces().first, 'id': 'b'},
        {...apiPlaces().first, 'id': 'moved'},
      ]);
      // A place that moved and that the device already has from the region
      // it moved to stays.
      await store.beginFullSync('FR-PAC');
      feed.pages[('FR-ARA', 'p1')] = _page(
        [_plain('c')],
        cursor: 'p2',
        deleted: ['a'],
        left: ['b', 'moved'],
      );
      // It moved after the pack of its first region was built.
      await store.applyPage(
        'FR-PAC',
        _page([_plain('moved', updatedAt: DateTime.utc(2026, 10, 6))], cursor: 'x'),
      );

      final done = await service.sync(region);
      expect(done.complete, isTrue);
      expect(feed.requests, [(region: 'FR-ARA', since: 'p1')]);
      expect(await idsOf('FR-ARA'), ['c']);
      expect(await idsOf('FR-PAC'), ['moved']);
      expect((await store.stateOf('FR-ARA')).completedAt, isNotNull);
      expect(
        Directory('${dir.path}/region_packs').listSync(),
        isEmpty,
        reason: 'the download and its database leave once imported',
      );
    });

    test('a download cut off resumes where it stopped', () async {
      final many = [
        for (var i = 0; i < 300; i++) {...apiPlaces().first, 'id': 'p$i'},
      ];
      final region = serve('ES', many);
      files.cutAfter = 2000;
      await expectLater(
        service.sync(region),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.failure,
            'failure',
            PackDownloadFailure.network,
          ),
        ),
      );
      expect((await store.stateOf('ES')).cursor, isNull);
      final done = await service.sync(region);
      expect(done.complete, isTrue);
      expect(files.ranges, [null, 'bytes=2000-']);
      expect(await idsOf('ES'), hasLength(300));
    });

    test(
      'a pack that is not what the manifest says is refused: the feed gives the places',
      () async {
        final region = serve('FR-BRE', [
          {...apiPlaces().first, 'id': 'x'},
        ]);
        final bytes = files.files[region.pack!.url]!;
        files.files[region.pack!.url] = [...bytes]..[bytes.length ~/ 2] ^= 0xff;
        feed.pages[('FR-BRE', null)] = _page([_plain('from-feed')], cursor: 'f1');
        final done = await service.sync(region);
        expect(done.complete, isTrue);
        expect(await idsOf('FR-BRE'), ['from-feed']);
        expect(feed.requests.single.since, isNull);
      },
    );

    test('a pack inflating past the size of its manifest stops there', () async {
      final region = serve('FR-COR', [
        for (var i = 0; i < 50; i++) {...apiPlaces().first, 'id': 'c$i'},
      ]);
      final pack = region.pack!;
      // Same bytes and digest, a manifest announcing a tenth of the size:
      // what a small download inflating to gigabytes looks like.
      final small = RegionPack(
        url: pack.url,
        format: pack.format,
        bytes: pack.bytes,
        rawBytes: pack.rawBytes ~/ 10,
        sha256: pack.sha256,
        version: pack.version,
        cursor: pack.cursor,
        places: pack.places,
        bounds: pack.bounds,
        generatedAt: pack.generatedAt,
      );
      final packFiles = IoRegionPackFiles(root: () async => dir);
      await expectLater(
        packFiles.fetch(
          small,
          placesPackUrl(config, pack.url)!,
          downloader: PackDownloader(client: files.client, userAgent: 'test'),
        ),
        throwsA(
          isA<PackDownloadException>()
              .having((e) => e.failure, 'failure', PackDownloadFailure.corrupt)
              .having((e) => e.message, 'message', contains('past')),
        ),
      );
      expect(
        Directory('${dir.path}/region_packs').listSync().whereType<File>(),
        isEmpty,
        reason: 'neither the download nor its partial inflation stays',
      );
    });

    test('what an earlier pack of the region left goes; other regions keep theirs', () async {
      final packsDir = Directory('${dir.path}/region_packs')..createSync(recursive: true);
      final stale = File('${packsDir.path}/FR-COR-1-aaaaaaaaaaaa.sqlite.gz.part')
        ..writeAsBytesSync([1, 2, 3]);
      final other = File('${packsDir.path}/FR-ARA-1-bbbbbbbbbbbb.sqlite.gz.part')
        ..writeAsBytesSync([1, 2, 3]);
      final region = serve('FR-COR', [
        {...apiPlaces().first, 'id': 'ajaccio'},
      ]);
      expect((await service.sync(region)).complete, isTrue);
      expect(stale.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });

    test('a pack of another region is refused: the feed gives the places', () async {
      final other = serve('FR-PDL', [
        {...apiPlaces().first, 'id': 'nantes'},
      ]);
      // The right digest for a file that holds another region.
      final region = RegionInfo(
        code: 'FR-BRE',
        country: 'FR',
        name: 'FR-BRE',
        nameFr: 'FR-BRE',
        pack: other.pack,
      );
      feed.pages[('FR-BRE', null)] = _page([_plain('rennes')], cursor: 'f1');
      final done = await service.sync(region);
      expect(done.complete, isTrue);
      expect(await idsOf('FR-BRE'), ['rennes']);
    });

    test('without packs (the web) the feed from the start, swept at its end', () async {
      service = build(packs: false);
      final region = serve('FR-ARA', [apiPlaces().first]);
      await store.beginFullSync('FR-ARA');
      await store.applyPage('FR-ARA', _page([_plain('stale')], cursor: 'old'));
      await store.completeRun('FR-ARA', DateTime.utc(2026));
      await store.forget('FR-ARA');
      await store.beginFullSync('FR-ARA');
      await store.applyPage('FR-ARA', _page([_plain('stale')], cursor: 'old'));
      await (db.update(db.regionSyncs)..where((s) => s.region.equals('FR-ARA'))).write(
        const RegionSyncsCompanion(cursor: Value(null), running: Value(false)),
      );
      feed.pages[('FR-ARA', null)] = _page([_plain('fresh')], cursor: 'f1');
      await service.sync(region);
      expect(files.ranges, isEmpty, reason: 'no pack fetched');
      expect(await idsOf('FR-ARA'), ['fresh']);
    });

    test('a cursor of another copy of the database imports the current pack again', () async {
      final region = serve('FR-ARA', [
        {...apiPlaces().first, 'id': 'a'},
      ], cursor: 'p9');
      await store.beginFullSync('FR-ARA');
      await store.applyPage('FR-ARA', _page([_plain('gone')], cursor: 'restored'));
      await store.completeRun('FR-ARA', DateTime.utc(2026));
      feed.foreign.add('restored');
      final done = await service.sync(region);
      expect(done.complete, isTrue);
      expect(feed.requests.map((r) => r.since), ['restored', 'p9']);
      expect(await idsOf('FR-ARA'), ['a']);
    });
  });

  group('every region kept', () {
    late _Feed feed;
    late _Kept kept;

    /// The regions synced, in order.
    List<String> synced() => [
      for (final (i, r) in feed.requests.indexed)
        if (feed.requests.indexWhere((o) => o.region == r.region) == i) r.region,
    ];

    PlacesSync build(RegionCatalog? catalog, {String? here, SyncService? legacy}) {
      final service = RegionSyncService(
        changes: feed,
        store: store,
        packs: const _NoPacks(),
        downloader: PackDownloader(
          client: MockClient((_) async => http.Response('', 404)),
          userAgent: null,
        ),
        packUrl: (_) => null,
      );
      return PlacesSync(
        catalog: () async => catalog,
        kept: kept,
        regions: () => service,
        store: () => store,
        legacy: legacy ?? SyncService(source: _NoBox(), store: places),
        here: (_) async => here,
      );
    }

    setUp(() {
      feed = _Feed();
      kept = _Kept();
    });

    RegionInfo region(String code) =>
        RegionInfo(code: code, country: code.substring(0, 2), name: code, nameFr: code);
    final catalog = RegionCatalog([
      region('FR-ARA'),
      region('FR-BRE'),
      region('FR'),
      region('ES'),
      region('IT'),
    ]);

    test('a first run keeps France and where the user is, that region first', () async {
      await build(catalog, here: 'ES').run();
      expect(kept.value, {'FR-ARA', 'FR-BRE', 'FR', 'ES'});
      expect(synced().first, 'ES');
      expect(synced(), unorderedEquals(['ES', 'FR-ARA', 'FR-BRE', 'FR']));
    });

    test('a region no longer kept leaves the device; the places synced by box go '
        'once every region kept has synced', () async {
      kept.value = {'FR-ARA', 'IT'};
      await store.beginFullSync('ES');
      await store.applyPage('ES', _page([_plain('madrid')], cursor: 'e'));
      await places.beginFullSync(DriftRegionStore.legacyRegion);
      await places.applyPage(DriftRegionStore.legacyRegion, _boxPage([_plain('by-box')]));
      await build(catalog).run();
      expect(await idsOf('ES'), isEmpty);
      expect(await store.regions(), {'FR-ARA', 'IT'});
      expect(await idsOf(null), isEmpty, reason: 'every kept region synced');
      expect(await store.stateOf(DriftRegionStore.legacyRegion), SyncState.none);
    });

    test('an API without regions keeps the sync by box of France', () async {
      final box = _Box();
      await build(
        null,
        legacy: SyncService(source: box, store: places),
      ).run();
      expect(box.requests, 1);
      expect(synced(), isEmpty);
      expect(kept.value, isNull, reason: 'no choice is made against such an API');
    });
  });

  group('the address of a pack', () {
    const config = AppConfig(apiBaseUrl: 'https://api.example.org', demo: false, basemapUrl: '');

    test('a relative name resolves on the API', () {
      expect(
        placesPackUrl(config, '/packs/places/FR-BRE-12-0123456789ab.sqlite.gz').toString(),
        'https://api.example.org/packs/places/FR-BRE-12-0123456789ab.sqlite.gz',
      );
    });

    test('the public API is ours too', () {
      expect(
        placesPackUrl(config, 'https://api.lunaway.net/packs/places/ES-3-0123456789ab.sqlite.gz'),
        isNotNull,
      );
    });

    test('another host, another folder or another name is never fetched', () {
      for (final url in [
        'https://evil.example/packs/places/ES-3-0123456789ab.sqlite.gz',
        'http://api.lunaway.net/packs/places/ES-3-0123456789ab.sqlite.gz',
        'https://api.lunaway.net:8443/packs/places/ES-3-0123456789ab.sqlite.gz',
        'https://u@api.lunaway.net/packs/places/ES-3-0123456789ab.sqlite.gz',
        'https://u@api.example.org/packs/places/ES-3-0123456789ab.sqlite.gz',
        '/packs/other/ES-3-0123456789ab.sqlite.gz',
        '/packs/places/../index.html',
        '/packs/places/ES-3-0123456789ab.sqlite.gz?x=1',
        '/packs/places/es-3-0123456789ab.sqlite.gz',
      ]) {
        expect(placesPackUrl(config, url), isNull, reason: url);
      }
    });
  });

  test('the manifest reads its packs and leaves out one it cannot check', () {
    final brittany = {
      'url': '/packs/places/FR-BRE-1-0123456789ab.sqlite.gz',
      'format': 'sqlite-gzip-1',
      'bytes': 412345.0,
      'rawBytes': 2854000.0,
      'sha256': 'a' * 64,
      'version': '1',
      'cursor': 'c',
      'places': 2854,
      'bounds': {'south': 47.2, 'west': -5.1, 'north': 48.9, 'east': -1.0},
      'generatedAt': '2026-10-06T05:30:00Z',
    };
    final regions = regionsOperation.parse({
      'regions': [
        {
          'code': 'FR-BRE',
          'country': 'FR',
          'name': 'Brittany',
          'nameFr': 'Bretagne',
          'pack': brittany,
        },
        {
          'code': 'ES',
          'country': 'ES',
          'name': 'Spain',
          'nameFr': 'Espagne',
          'pack': {'sha256': 'not hex'},
        },
        {
          'code': 'IT',
          'country': 'IT',
          'pack': {...brittany, 'url': null},
        },
        {
          'code': 'PT',
          'country': 'PT',
          'pack': {...brittany, 'bytes': 64.0 * 1024 * 1024 * 1024},
        },
      ],
    });
    expect(regions.map((r) => r.code), ['FR-BRE', 'ES', 'IT', 'PT']);
    expect(regions.first.pack!.bytes, 412345);
    expect(regions.first.nameIn('fr'), 'Bretagne');
    expect(regions.skip(1).map((r) => r.pack), everyElement(isNull));
  });
}

final class _Kept implements KeptRegions {
  Set<String>? value;

  @override
  Future<Set<String>?> load() async => value;

  @override
  Future<void> save(Set<String> regions) async => value = regions;
}

final class _NoPacks implements RegionPackFiles {
  const new();

  @override
  bool get supported => false;

  @override
  Future<String> fetch(
    RegionPack pack,
    Uri url, {
    required PackDownloader downloader,
    void Function(int received)? onProgress,
  }) => throw UnsupportedError('none');

  @override
  Future<void> release(String path) async {}

  @override
  Future<int> usedBytes() async => 0;
}

final class _NoBox implements ChangesSource {
  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) =>
      throw StateError('the sync by box must not run');
}

final class _Box implements ChangesSource {
  int requests = 0;

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) async {
    requests++;
    return const ChangeSet(places: [], deleted: [], cursor: 'b1', hasMore: false);
  }
}

ChangeSet _boxPage(List<Place> places) =>
    ChangeSet(places: places, deleted: const [], cursor: 'b', hasMore: false);
