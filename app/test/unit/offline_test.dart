import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/domain/packs.dart';

import '../helpers/poi_fakes.dart';

final String _manifestText = File('test/fixtures/packs_manifest.json').readAsStringSync();
const _template = '{"sources":{"protomaps":{"type":"vector","url":"__LUNAWAY_TILES__"}}}';
final _outlines = PackOutlines.parse(File('assets/map/offline/regions.json').readAsStringSync());

/// A small pack for the downloads: its bytes, and the manifest entry that
/// names them.
final _bytes = List<int>.generate(10000, (i) => (i * 7) % 251);
final _pack = PackInfo(
  id: 'fr-20r',
  names: const {'fr': 'Corse', 'en': 'Corsica'},
  country: 'fr',
  bounds: const GeoBounds(south: 41.3, west: 8.5, north: 43.1, east: 9.6),
  url: 'fr-20r-20261005-78b49820.pmtiles',
  size: _bytes.length,
  sha256: sha256.convert(_bytes).toString(),
  build: '20261005',
);

/// A pack host: the whole file, or the rest of it from a `Range`, unless
/// `If-Range` names another version; it records each request.
MockClient _host(List<http.BaseRequest> seen, {String etag = '"v1"', int chunk = 1000}) =>
    MockClient.streaming(_serve(seen, etag: etag, chunk: chunk));

/// The answers of [_host], for a test that wraps them.
MockClientStreamHandler _serve(
  List<http.BaseRequest> seen, {
  String etag = '"v1"',
  int chunk = 1000,
}) => (request, _) async {
  seen.add(request);
  final range = RegExp(r'bytes=(\d+)-').firstMatch(request.headers['range'] ?? '');
  final ifRange = request.headers['if-range'];
  final start = range != null && (ifRange == null || ifRange == etag) ? int.parse(range[1]!) : 0;
  final body = _bytes.sublist(start);
  Stream<List<int>> chunks() async* {
    for (var i = 0; i < body.length; i += chunk) {
      yield body.sublist(i, (i + chunk).clamp(0, body.length));
    }
  }

  return http.StreamedResponse(
    chunks(),
    start > 0 ? 206 : 200,
    contentLength: body.length,
    headers: {
      'etag': etag,
      if (start > 0) 'content-range': 'bytes $start-${_bytes.length - 1}/${_bytes.length}',
    },
  );
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the manifest', () {
    test('reads the packs of version 1, with their names, groups and sizes', () {
      final m = PackManifest.parse(_manifestText);
      expect(m.build, '20261005');
      final bre = m.byId('fr-bre')!;
      expect(bre.name('fr'), 'Bretagne');
      expect(bre.name('de'), 'Brittany', reason: 'English when the language is missing');
      expect(bre.size, 162863132);
      expect(bre.group, PackGroup.france);
      expect(m.byId('fr-974')!.group, PackGroup.overseas);
      expect(m.byId('es')!.group, PackGroup.countries);
      expect(bre.fileName, 'fr-bre-20261005.pmtiles');
    });

    test('refuses another version, and drops a pack whose file name could leave its folder', () {
      final json = jsonDecode(_manifestText) as Map<String, dynamic>;
      expect(() => PackManifest.parse(jsonEncode({...json, 'version': 2})), throwsFormatException);
      final packs = (json['packs'] as List<dynamic>).cast<Map<String, dynamic>>();
      final tampered = {
        ...json,
        'packs': [
          {...packs[0], 'url': '../index.json.pmtiles'},
          {...packs[1], 'url': 'sub/dir.pmtiles'},
          {...packs[2], 'sha256': 'abc'},
          packs[3],
        ],
      };
      expect(PackManifest.parse(jsonEncode(tampered)).packs.map((p) => p.id), [packs[3]['id']]);
      expect(safeFileName('fr-bre-20261005-e4fa3cea.pmtiles'), isTrue);
      expect(safeFileName('..pmtiles'), isFalse);
    });
  });

  group('which pack covers a point', () {
    final m = PackManifest.parse(_manifestText);
    PackInfo? at(double lat, double lon) => packAt(
      m.packs,
      LatLng(lat, lon),
      outlines: _outlines,
      id: (p) => p.id,
      bounds: (p) => p.bounds,
    );

    test(
      'reads the outline, not the box: Châteaubriant is in the Bretagne box, not in Bretagne',
      () {
        final bre = m.byId('fr-bre')!;
        const chateaubriant = LatLng(47.717, -1.376);
        expect(bre.bounds.contains(chateaubriant), isTrue);
        expect(at(chateaubriant.lat, chateaubriant.lon)?.id, 'fr-pdl');
        expect(at(48.117, -1.677)?.id, 'fr-bre', reason: 'Rennes');
        expect(at(47.218, -1.554)?.id, 'fr-pdl', reason: 'Nantes');
        expect(at(41.919, 8.738)?.id, 'fr-20r', reason: 'Ajaccio');
      },
    );

    test('prefers the smaller pack where two cover a point', () {
      expect(at(42.507, 1.521)?.id, 'ad', reason: 'Andorra la Vella, inside the Spain box too');
      expect(at(48.857, 2.352), isNull, reason: 'Paris: no pack of this sample');
    });
  });

  test('the offline style reads the pack and the bundled glyphs and sprites from files', () {
    const template =
        '{"sources":{"protomaps":{"type":"vector","url":"__LUNAWAY_TILES__"}},'
        '"sprite":"__LUNAWAY_SPRITE__/light","glyphs":"__LUNAWAY_GLYPHS__/{fontstack}/{range}.pbf",'
        '"layers":[{"id":"x","layout":{"text-field":"name:__LUNAWAY_LANG__"}}]}';
    final style = fillOfflineBasemapStyle(
      template,
      pack: '/var/mobile/Library/Application Support/offline_maps/fr-20r-20261005.pmtiles',
      assets: '/var/mobile/Library/Application Support/offline_maps/style',
      language: 'fr-FR',
    );
    final json = jsonDecode(style) as Map<String, dynamic>;
    expect(
      ((json['sources'] as Map<String, dynamic>)['protomaps'] as Map<String, dynamic>)['url'],
      'pmtiles://file:///var/mobile/Library/Application%20Support/offline_maps/fr-20r-20261005.pmtiles',
    );
    expect(json['glyphs'], startsWith('file:///var/mobile/Library/Application%20Support/'));
    expect(json['glyphs'], endsWith('/style/glyphs/{fontstack}/{range}.pbf'));
    expect(json['sprite'], endsWith('/style/sprites/light'));
    expect(style, contains('name:fr'));
  });

  group('a download', () {
    test('writes the whole file on a first request', () async {
      final seen = <http.BaseRequest>[];
      final sink = MemorySink([]);
      final result = await PackDownloader(client: _host(seen), userAgent: 'Lunaway/test').download(
        Uri.parse('https://tiles.example/packs/x.pmtiles'),
        size: _bytes.length,
        sink: sink,
        token: PackDownloadToken(),
      );
      expect(result.complete, isTrue);
      expect(result.etag, '"v1"');
      expect(sink.bytes, _bytes);
      expect(seen.single.headers.containsKey('range'), isFalse);
    });

    test('resumes from the bytes it has, with Range and If-Range', () async {
      final seen = <http.BaseRequest>[];
      final sink = MemorySink(_bytes.sublist(0, 4000).toList());
      final result = await PackDownloader(client: _host(seen), userAgent: null).download(
        Uri.parse('https://tiles.example/packs/x.pmtiles'),
        size: _bytes.length,
        sink: sink,
        token: PackDownloadToken(),
        etag: '"v1"',
      );
      expect(result.complete, isTrue);
      expect(seen.single.headers['range'], 'bytes=4000-');
      expect(seen.single.headers['if-range'], '"v1"');
      expect(sink.bytes, _bytes);
    });

    test('starts over when the file changed on the server (a 200 to a Range)', () async {
      final seen = <http.BaseRequest>[];
      final sink = MemorySink(List.filled(4000, 0, growable: true));
      await PackDownloader(client: _host(seen, etag: '"v2"'), userAgent: null).download(
        Uri.parse('https://tiles.example/packs/x.pmtiles'),
        size: _bytes.length,
        sink: sink,
        token: PackDownloadToken(),
        etag: '"v1"',
      );
      expect(sink.bytes, _bytes, reason: 'the stale part is gone, not spliced');
    });

    test('keeps its part when a resume gets a whole answer of another size', () async {
      // A captive portal's page, sent whole to a request for the rest.
      final portal = MockClient(
        (_) async => http.Response('<html>Connectez-vous</html>', 200, headers: {'etag': '"p"'}),
      );
      final part = List<int>.of(_bytes.sublist(0, 4000));
      final sink = MemorySink(part);
      await expectLater(
        PackDownloader(client: portal, userAgent: null).download(
          Uri.parse('https://tiles.example/packs/x.pmtiles'),
          size: _bytes.length,
          sink: sink,
          token: PackDownloadToken(),
          etag: '"v1"',
        ),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.failure,
            'failure',
            PackDownloadFailure.server,
          ),
        ),
      );
      expect(sink.bytes, _bytes.sublist(0, 4000), reason: 'what came stays');
    });

    test('pauses between two chunks when asked, keeping what came', () async {
      final token = PackDownloadToken();
      final sink = MemorySink([]);
      final result = await PackDownloader(client: _host([]), userAgent: null).download(
        Uri.parse('https://tiles.example/packs/x.pmtiles'),
        size: _bytes.length,
        sink: sink,
        token: token,
        onProgress: (received) {
          if (received >= 3000) token.cancel();
        },
      );
      expect(result.complete, isFalse);
      expect(result.received, 3000);
      expect(sink.bytes, _bytes.sublist(0, 3000));
    });

    test('refuses an error page and a body longer than the manifest says', () async {
      final error = MockClient((_) async => http.Response('nope', 500));
      expect(
        PackDownloader(client: error, userAgent: null).download(
          Uri.parse('https://tiles.example/x'),
          size: 10,
          sink: MemorySink([]),
          token: PackDownloadToken(),
        ),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.failure,
            'failure',
            PackDownloadFailure.server,
          ),
        ),
      );
      expect(
        PackDownloader(client: _host([]), userAgent: null).download(
          Uri.parse('https://tiles.example/x'),
          size: 100,
          sink: MemorySink([]),
          token: PackDownloadToken(),
        ),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.failure,
            'failure',
            PackDownloadFailure.server,
          ),
        ),
      );
    });
  });

  group('the offline maps of the device', () {
    late MemoryPackFiles files;
    late ProviderContainer container;
    final catalog = PackCatalog(
      manifest: PackManifest(build: '20261005', packs: [_pack]),
      url: Uri.parse('https://tiles.example/packs/manifest.json'),
    );

    ProviderContainer make({http.Client? client, bool? reachable = true}) => ProviderContainer.test(
      overrides: [
        packFilesProvider.overrideWithValue(files),
        httpClientProvider.overrideWithValue(client ?? _host([])),
        basemapReachabilityProvider.overrideWith(() => FixedReachability(reachable: reachable)),
        basemapTemplatesProvider.overrideWithValue(
          const BasemapTemplates(aube: _template, minuit: _template),
        ),
      ],
    );

    setUp(() => files = MemoryPackFiles());

    Future<OfflineMaps> settled() async {
      for (var i = 0; i < 50; i++) {
        final value = await container.read(offlinePacksProvider.future);
        if (value.transfers.values.every((t) => t.state == TransferState.failed)) return value;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return await container.read(offlinePacksProvider.future);
    }

    Future<OfflineMaps> installed() async {
      for (var i = 0; i < 100; i++) {
        final value = await container.read(offlinePacksProvider.future);
        if (value.installed.isNotEmpty) return value;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return await container.read(offlinePacksProvider.future);
    }

    test('a pack downloads, is checked against its SHA-256, and stays after a restart', () async {
      container = make();
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      final maps = await settled();
      expect(maps.installed.keys, ['fr-20r']);
      expect(files.files['fr-20r-20261005.pmtiles'], _bytes);
      expect(maps.usedBytes, _bytes.length);

      final again = make();
      final restored = await again.read(offlinePacksProvider.future);
      expect(restored.installed['fr-20r']!.sha256, _pack.sha256);
    });

    test('a damaged file is removed and the download says so', () async {
      container = make();
      final wrong = PackInfo(
        id: _pack.id,
        names: _pack.names,
        country: 'fr',
        bounds: _pack.bounds,
        url: _pack.url,
        size: _pack.size,
        sha256: '0' * 64,
        build: _pack.build,
      );
      await container.read(offlinePacksProvider.notifier).download(wrong, catalog);
      final maps = await settled();
      expect(maps.installed, isEmpty);
      expect(maps.transfers['fr-20r']!.failure, PackDownloadFailure.corrupt);
      expect(files.files.keys.where((k) => k.contains('fr-20r')), isEmpty);
    });

    test('a pack is deleted with its file', () async {
      container = make();
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      await settled();
      await container.read(offlinePacksProvider.notifier).delete('fr-20r');
      final maps = await container.read(offlinePacksProvider.future);
      expect(maps.installed, isEmpty);
      expect(files.files, isEmpty);
    });

    test(
      'offline, the map reads the pack under the view, and keeps it when the view leaves it',
      () async {
        container = make(reachable: false);
        await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
        await settled();
        await container.read(packOutlinesProvider.future);
        container
            .read(viewportProvider.notifier)
            .update(
              const MapViewport(
                bounds: GeoBounds(south: 41.8, west: 8.6, north: 42, east: 8.9),
                center: LatLng(41.919, 8.738),
                zoom: 12,
              ),
            );
        expect(container.read(activeOfflinePackProvider)?.id, 'fr-20r');
        container
            .read(viewportProvider.notifier)
            .update(
              const MapViewport(
                bounds: GeoBounds(south: 43, west: 7, north: 44, east: 8),
                center: LatLng(43.7, 7.26),
                zoom: 12,
              ),
            );
        expect(container.read(activeOfflinePackProvider)?.id, 'fr-20r', reason: 'Nice, at sea');
        final style = container.read(basemapStyleProvider(dark: false, language: 'fr'));
        expect(style, contains('"pmtiles://file:///mem/offline_maps/fr-20r-20261005.pmtiles"'));
      },
    );

    test(
      'a download the end of the app cut goes on at the next start, from where it stopped',
      () async {
        files
          ..index = jsonEncode({
            'installed': <Object>[],
            'transfers': [
              PackTransfer(
                pack: _pack,
                url: catalog.urlOf(_pack),
                state: TransferState.running,
                received: 4000,
                etag: '"v1"',
              ).toJson(),
            ],
          })
          ..files['fr-20r-20261005.pmtiles.part'] = _bytes.sublist(0, 4000);
        final seen = <http.BaseRequest>[];
        container = make(client: _host(seen));
        await container.read(offlinePacksProvider.future);
        final maps = await installed();
        expect(maps.installed.keys, ['fr-20r']);
        expect(seen.single.headers['range'], 'bytes=4000-');
      },
    );

    test('one stopped for want of network goes on once the host answers again', () async {
      var up = false;
      final seen = <http.BaseRequest>[];
      final serve = _serve(seen);
      container = make(
        client: MockClient.streaming((request, body) async {
          if (!up) throw http.ClientException('no route to host', request.url);
          return await serve(request, body);
        }),
      );
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      final failed = await settled();
      expect(failed.transfers['fr-20r']!.failure, PackDownloadFailure.network);

      container.read(basemapReachabilityProvider.notifier).assume(reachable: false);
      up = true;
      container.read(basemapReachabilityProvider.notifier).assume(reachable: true);
      expect((await installed()).installed.keys, ['fr-20r']);
    });

    test('one stopped for want of network tries again a minute later', () {
      fakeAsync((async) {
        var up = false;
        final serve = _serve([]);
        container = make(
          client: MockClient.streaming((request, body) async {
            if (!up) throw http.ClientException('no route to host', request.url);
            return await serve(request, body);
          }),
        );
        unawaited(container.read(offlinePacksProvider.notifier).download(_pack, catalog));
        async.elapse(const Duration(seconds: 1));
        PackTransfer? transfer() => container.read(offlinePacksProvider).value?.transfers['fr-20r'];
        expect(transfer()?.failure, PackDownloadFailure.network);

        up = true;
        async.elapse(const Duration(seconds: 58));
        expect(transfer()?.state, TransferState.failed, reason: 'not before the minute');
        async.elapse(const Duration(seconds: 3));
        expect(container.read(offlinePacksProvider).value?.installed.keys, ['fr-20r']);
      });
    });

    test('the app leaving the screen stops a download, which goes on when it comes back', () async {
      final gate = Completer<void>();
      final seen = <http.BaseRequest>[];
      final serve = _serve(seen);
      container = make(
        client: MockClient.streaming((request, body) async {
          final response = await serve(request, body);
          if (seen.length > 1) return response;
          // The first answer gives a chunk, then waits.
          Stream<List<int>> held() async* {
            var first = true;
            await for (final chunk in response.stream) {
              if (!first) await gate.future;
              first = false;
              yield chunk;
            }
          }

          return http.StreamedResponse(held(), response.statusCode, headers: response.headers);
        }),
      );
      final binding = TestWidgetsFlutterBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      while (container.read(offlinePacksProvider).value?.transfers['fr-20r']?.state !=
          TransferState.running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // The platform's own order of states, as AppLifecycleListener checks it.
      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ].forEach(binding.handleAppLifecycleStateChanged);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final away = await container.read(offlinePacksProvider.future);
      expect(away.transfers['fr-20r']!.state, TransferState.waiting);
      expect(away.installed, isEmpty);
      expect(seen, hasLength(1));

      [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(binding.handleAppLifecycleStateChanged);
      expect((await installed()).installed.keys, ['fr-20r']);
      expect(seen.last.headers['range'], startsWith('bytes='));
    });

    test('a pack that would fill the device is not asked for', () async {
      final seen = <http.BaseRequest>[];
      files.free = _bytes.length + OfflinePacks.spareBytes - 1;
      container = make(client: _host(seen));
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      final maps = await settled();
      expect(maps.transfers['fr-20r']!.failure, PackDownloadFailure.storage);
      expect(seen, isEmpty);
    });

    test('a disk that fills up during a download gets its room back', () async {
      files.room = 3000;
      container = make();
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      final maps = await settled();
      expect(maps.transfers['fr-20r']!.failure, PackDownloadFailure.storage);
      expect(maps.transfers['fr-20r']!.received, 0);
      expect(files.files.keys.where((k) => k.startsWith('fr-20r')), isEmpty);
    });

    test('online, no pack is read', () async {
      container = make();
      await container.read(offlinePacksProvider.notifier).download(_pack, catalog);
      await settled();
      expect(container.read(activeOfflinePackProvider), isNull);
      final style = container.read(basemapStyleProvider(dark: false, language: 'fr'));
      expect(style, contains('/planet.json'));
    });
  });
}
