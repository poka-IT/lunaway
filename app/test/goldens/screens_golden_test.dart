@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/community/presentation/place_placement.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';

import '../helpers/fonts.dart';
import '../helpers/golden_map.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The key screens per width class and theme, in French, with the real
/// typefaces, icons and pin images, reviewed as images. Rendering differs
/// between operating systems, so the references are made and compared on
/// macOS only (the `goldens` job of the CI), with a small tolerance for
/// anti-aliasing (`test/flutter_test_config.dart`).
const _phone = Size(412, 915);
const _tablet = Size(768, 1024);
const _desktop = Size(1280, 800);

const Map<String, Size> _sizes = {'compact': _phone, 'medium': _tablet, 'expanded': _desktop};

const _annecy = GeoBounds(south: 45.80, west: 5.98, north: 46.02, east: 6.30);

final List<Place> _places = [
  lakeArea,
  ...demoPlaces(count: 2400, now: testNow).where((p) => _annecy.contains(p.position)),
  dayParking,
  campsite,
];

Future<TestApp> _pump(WidgetTester tester, Size size, Brightness brightness) async {
  final app = await pumpLunaway(
    tester,
    size: size,
    brightness: brightness,
    places: _places,
    map: GoldenMap(_annecy),
    // A new user's filters, in the theme of the image.
    settings: AppSettings(
      theme: brightness == Brightness.dark ? ThemePreference.dark : ThemePreference.light,
    ),
  );
  // Images decode on the real event loop, before the frame is compared.
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    final fetcher = app.container(tester).read(imageFetcherProvider);
    for (final p in samplePhotos) {
      await precacheImage(
        ResizeImage(CachedImage(p.thumbUrl, fetcher: fetcher), width: 480),
        context,
      );
    }
    for (final id in allPinImageIds()) {
      await precacheImage(AssetImage('assets/map/pins/2x/$id.png'), context);
    }
  });
  await settleShort(tester);
  return app;
}

/// Real shadows, not the black outlines tests draw by default; restored
/// before the test ends, as the binding checks.
Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settleShort(tester);
}

void main() {
  setUpAll(loadRealFonts);
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));
  final skip = !Platform.isMacOS;

  for (final MapEntry(key: name, value: size) in _sizes.entries) {
    for (final brightness in Brightness.values) {
      final theme = brightness.name;

      testWidgets(
        'map with a place open, $name, $theme',
        skip: skip,
        (tester) => _withShadows(() async {
          final app = await _pump(tester, size, brightness);
          app
              .container(tester)
              .read(selectionProvider.notifier)
              .select(PlaceSelection(lakeArea.id));
          await settleShort(tester, const Duration(seconds: 2));
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('images/map_place_${name}_$theme.png'),
          );
        }),
      );
    }

    testWidgets(
      'map with the list, $name',
      skip: skip,
      (tester) => _withShadows(() async {
        await _pump(tester, size, Brightness.light);
        if (name == 'medium') {
          await tester.tap(find.textContaining('Liste ('));
          await settleShort(tester);
        }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('images/map_list_$name.png'));
      }),
    );

    testWidgets(
      'filters, $name',
      skip: skip,
      (tester) => _withShadows(() async {
        await _pump(tester, size, Brightness.light);
        await tester.tap(find.text('Filtres'));
        await settleShort(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('images/filters_$name.png'));
      }),
    );

    testWidgets(
      'favourites, $name',
      skip: skip,
      (tester) => _withShadows(() async {
        final app = await _pump(tester, size, Brightness.light);
        for (final p in [lakeArea, campsite, dayParking]) {
          await app.favorites.addToDefault(p.summary);
        }
        await app.favorites.createList('Bretagne 2027');
        await _openTab(tester, 'Favoris');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('images/favorites_$name.png'),
        );
      }),
    );

    testWidgets(
      'profile, $name',
      skip: skip,
      (tester) => _withShadows(() async {
        await _pump(tester, size, Brightness.light);
        await _openTab(tester, 'Profil');
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('images/profile_$name.png'));
      }),
    );
  }

  testWidgets(
    'profile, compact, dark',
    skip: skip,
    (tester) => _withShadows(() async {
      await _pump(tester, _phone, Brightness.dark);
      await _openTab(tester, 'Profil');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/profile_compact_dark.png'),
      );
    }),
  );

  // With a mouse: the denser desktop look, a place open beside the list.
  testWidgets(
    'map with a place open, expanded, with a mouse',
    skip: skip,
    (tester) => _withShadows(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final app = await _pump(tester, _desktop, Brightness.light);
        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester, const Duration(seconds: 2));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('images/map_place_expanded_pointer.png'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }),
  );

  testWidgets(
    'a long press gives the coordinates, compact',
    skip: skip,
    (tester) => _withShadows(() async {
      final app = await _pump(tester, _phone, Brightness.light);
      app
          .container(tester)
          .read(selectionProvider.notifier)
          .select(const PointSelection(LatLng(45.7629, 4.831697)));
      await settleShort(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/map_point_compact.png'),
      );
    }),
  );

  testWidgets(
    'a new place is set under the crosshair, compact',
    skip: skip,
    (tester) => _withShadows(() async {
      await _pump(tester, _phone, Brightness.light);
      unawaited(pickPlacement(tester.element(find.byType(Scaffold).first), lakeArea.position));
      await settleShort(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/placement_compact.png'),
      );
    }),
  );

  testWidgets(
    'a place within 50 m is asked about before the form, compact',
    skip: skip,
    (tester) => _withShadows(() async {
      await _pump(tester, _phone, Brightness.light);
      unawaited(askSamePlace(tester.element(find.byType(Scaffold).first), lakeArea.summary, 30));
      await settleShort(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/placement_duplicate_compact.png'),
      );
    }),
  );
}
