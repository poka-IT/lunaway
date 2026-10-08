import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/domain/packs.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';

final Translations t = AppLocale.fr.buildSync();

final _bytes = List<int>.generate(20000, (i) => (i * 13) % 251);
final _corse = PackInfo(
  id: 'fr-20r',
  names: const {'fr': 'Corse', 'en': 'Corsica'},
  country: 'fr',
  bounds: const GeoBounds(south: 41.3, west: 8.5, north: 43.1, east: 9.6),
  url: 'fr-20r-20261005-78b49820.pmtiles',
  size: _bytes.length,
  sha256: sha256.convert(_bytes).toString(),
  build: '20261005',
);

/// The fixture's manifest with a small Corsica, so a download runs in the test.
PackCatalog _catalog() {
  final m = PackManifest.parse(File('test/fixtures/packs_manifest.json').readAsStringSync());
  return PackCatalog(
    manifest: PackManifest(
      build: m.build,
      packs: [
        for (final p in m.packs)
          if (p.id != 'fr-20r') p,
        _corse,
      ],
    ),
    url: Uri.parse('https://tiles.lunaway.net/packs/manifest.json'),
  );
}

final _host = MockClient((request) async {
  if (request.url.path.endsWith('.pmtiles')) return http.Response.bytes(_bytes, 200);
  return http.Response('', 404);
});

/// A device that already keeps Corsica.
MemoryPackFiles _withCorsica() => MemoryPackFiles()
  ..files['fr-20r-20261005.pmtiles'] = List.of(_bytes)
  ..index = jsonEncode({
    'installed': [InstalledPack.from(_corse, DateTime.utc(2026, 10, 6)).toJson()],
    'transfers': <Object>[],
  });

Future<void> _openScreen(WidgetTester tester, TestApp app) async {
  app.container(tester).read(routerProvider).go(AppRoutes.offlineMaps);
  await settleShort(tester);
}

void main() {
  testWidgets('where no map is kept, the screen says plainly that the map needs the network', (
    tester,
  ) async {
    final app = await pumpLunaway(tester, packFiles: MemoryPackFiles(supported: false));
    await _openScreen(tester, app);
    expect(find.text(t.offlineMaps.desktopTitle), findsOneWidget);
    expect(find.text(t.offlineMaps.desktop), findsOneWidget);
    expect(find.text(t.offlineMaps.france), findsNothing);
  });

  testWidgets('the regions come by group with their size, and where the traveller is first', (
    tester,
  ) async {
    final app = await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      overrides: [
        packCatalogProvider.overrideWith((ref) async => _catalog()),
        initialPositionProvider.overrideWithValue(const LatLng(41.919, 8.738)),
      ],
    );
    await _openScreen(tester, app);
    expect(find.text(t.offlineMaps.suggested), findsOneWidget);
    expect(find.text('${t.offlineMaps.here} · 20 ko'), findsOneWidget);
    expect(find.text(t.offlineMaps.france), findsOneWidget);
    expect(find.text(t.offlineMaps.overseas), findsOneWidget);
    expect(find.text(t.offlineMaps.countries), findsOneWidget);
    expect(find.text('155 Mo'), findsOneWidget, reason: 'Bretagne');
    expect(find.text(t.offlineMaps.none), findsOneWidget);
  });

  testWidgets('in German the maps read in German and in German order, though the manifest '
      'names them in French and English only', (tester) async {
    final de = AppLocale.de.buildSync();
    PackInfo country(String id, String en, String fr) => PackInfo(
      id: id,
      names: {'fr': fr, 'en': en},
      country: id,
      bounds: const GeoBounds(south: 0, west: 0, north: 1, east: 1),
      url: '$id-20261005-0123abcd.pmtiles',
      size: 1000,
      sha256: 'a' * 64,
      build: '20261005',
      region: false,
    );
    final m = _catalog().manifest;
    final app = await pumpLunaway(
      tester,
      locale: AppLocale.de,
      size: const Size(1280, 2400),
      overrides: [
        packCatalogProvider.overrideWith(
          (ref) async => PackCatalog(
            manifest: PackManifest(
              build: m.build,
              packs: [
                ...m.packs,
                country('at', 'Austria', 'Autriche'),
                country('nl', 'Netherlands', 'Pays-Bas'),
                country('pl', 'Poland', 'Pologne'),
              ],
            ),
            url: Uri.parse('https://tiles.lunaway.net/packs/manifest.json'),
          ),
        ),
      ],
    );
    await _openScreen(tester, app);
    expect(find.text(de.countries.es), findsOneWidget);
    expect(find.text(de.areas.bre), findsOneWidget);
    for (final english in ['Spain', 'Brittany', 'Austria', 'Netherlands']) {
      expect(find.text(english), findsNothing, reason: english);
    }
    // Niederlande before Österreich, where English puts Austria first;
    // Österreich among the O, before Polen.
    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y(de.countries.nl), lessThan(y(de.countries.at)));
    expect(y(de.countries.at), lessThan(y(de.countries.pl)));
  });

  testWidgets('a region downloads, is checked, then shows on the device with its size', (
    tester,
  ) async {
    final files = MemoryPackFiles();
    final app = await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      packFiles: files,
      httpClient: _host,
      overrides: [packCatalogProvider.overrideWith((ref) async => _catalog())],
    );
    await _openScreen(tester, app);
    await tester.tap(find.byTooltip(t.offlineMaps.downloadNamed(name: 'Corse', size: '20 ko')));
    await settleShort(tester, const Duration(seconds: 2));
    expect(find.text(t.offlineMaps.installed), findsOneWidget);
    expect(find.text('Corse'), findsOneWidget);
    expect(find.text(t.offlineMaps.used(size: '20 ko')), findsOneWidget);
    expect(files.files['fr-20r-20261005.pmtiles'], _bytes);
  });

  testWidgets('a region is removed after a confirmation', (tester) async {
    final files = _withCorsica();
    final app = await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      packFiles: files,
      overrides: [packCatalogProvider.overrideWith((ref) async => _catalog())],
    );
    await _openScreen(tester, app);
    await tester.tap(find.byTooltip(t.offlineMaps.deleteNamed(name: 'Corse')));
    await settleShort(tester);
    expect(find.text(t.offlineMaps.deleteTitle(name: 'Corse')), findsOneWidget);
    await tester.tap(find.text(t.common.delete));
    await settleShort(tester);
    expect(files.files, isEmpty);
    expect(find.text(t.offlineMaps.installed), findsNothing);
  });

  testWidgets('offline over a downloaded region, the map says so calmly', (tester) async {
    final map = FakeMap()
      ..viewport = const MapViewport(
        bounds: GeoBounds(south: 41.8, west: 8.6, north: 42, east: 8.9),
        center: LatLng(41.919, 8.738),
        zoom: 12,
      );
    await pumpLunaway(tester, map: map, packFiles: _withCorsica(), reachable: false);
    await settleShort(tester);
    expect(find.text(t.offlineMaps.noticePack(name: 'Corse')), findsOneWidget);
  });

  testWidgets('offline with no region kept, the map suggests one for next time', (tester) async {
    await pumpLunaway(tester, reachable: false);
    expect(find.text(t.offlineMaps.noticeNone), findsOneWidget);
  });

  testWidgets('online, the map says nothing about it', (tester) async {
    await pumpLunaway(tester, packFiles: _withCorsica());
    expect(find.textContaining('Hors ligne'), findsNothing);
  });

  testWidgets('the profile leads to the offline maps', (tester) async {
    final app = await pumpLunaway(tester, size: const Size(1280, 2400));
    app.container(tester).read(routerProvider).go(AppRoutes.profile);
    await settleShort(tester);
    await tester.tap(find.text(t.offlineMaps.title));
    await settleShort(tester);
    expect(
      GoRouter.of(tester.element(find.text(t.offlineMaps.intro))).state.uri.path,
      AppRoutes.offlineMaps,
    );
  });
}
