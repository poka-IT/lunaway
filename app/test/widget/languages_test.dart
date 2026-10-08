import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/presentation/contribution_sheets.dart';
import 'package:lunaway/features/community/presentation/place_form.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

import '../helpers/fake_api.dart';
import '../helpers/fonts.dart';
import '../helpers/golden_map.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'navigation_test.dart' show driveFixes, utrillo;

/// The screens the app opens most, in each of its six languages, in the
/// three layouts and with the large text an older reader sets: no text
/// overflows its box (an overflow is an error that fails the test), and
/// each screen speaks the language asked. Measured in the app's own
/// typefaces: the test font draws every glyph as a square and would decide
/// nothing about the widths; kept in its own file, as the fonts stay loaded
/// for the rest of the file.
///
/// `fvm flutter test test/widget/languages_test.dart --update-goldens`
/// also writes every screen as an image to `data/tmp/langues/` (gitignored),
/// for a reader of each language to look at; a plain run writes nothing.
const _layouts = <(String, Size, double)>[
  ('compact', Size(412, 915), 1),
  ('compact-large-text', Size(360, 780), 1.3),
  ('medium', Size(768, 1024), 1),
  ('expanded', Size(1280, 800), 1),
];

/// German, the longest of the six, also at the largest text the audience
/// sets on a small phone.
const _germanLargest = ('compact-largest-text', Size(360, 780), 1.5);

/// The layouts [locale] is checked in.
List<(String, Size, double)> _layoutsOf(AppLocale locale) => [
  ..._layouts,
  if (locale == AppLocale.de) _germanLargest,
];

const _annecy = GeoBounds(south: 45.80, west: 5.98, north: 46.02, east: 6.30);

final List<Place> _places = [
  lakeArea,
  ...demoPlaces(count: 2400, now: testNow).where((p) => _annecy.contains(p.position)),
  dayParking,
  campsite,
];

final _letter = RegExp(r'[\p{L}]', unicode: true);

/// The words of the frame cut across two lines: a compound too long for
/// its box ("Wohnmobilste" over "llplatz"), which no overflow reports.
List<String> _brokenWords(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if (element.renderObject case final RenderParagraph p when p.hasSize)
      for (final cut in _cuts(p)) cut,
];

Iterable<String> _cuts(RenderParagraph p) sync* {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  var offset = 0;
  while (offset < text.length) {
    final word = p.getWordBoundary(TextPosition(offset: offset));
    if (word.end <= offset) {
      offset++;
      continue;
    }
    offset = word.end;
    final letters = text.substring(word.start, word.end);
    if (letters.length < 2 || !_letter.hasMatch(letters)) continue;
    // A word laid out on two lines has boxes at two heights.
    final tops = {
      for (final box in p.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      ))
        box.top.round(),
    };
    if (tops.length > 1) yield letters;
  }
}

/// Checks the frame for an overflow and for a word cut in two, then keeps
/// it as an image when the run asks for images.
Future<void> _shot(WidgetTester tester, AppLocale locale, String layout, String scene) async {
  final where = '${locale.languageCode} $layout $scene';
  expect(tester.takeException(), isNull, reason: where);
  // The image first, so a frame that fails the next check can be seen.
  if (autoUpdateGoldenFiles) {
    debugDisableShadows = false;
    try {
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../data/tmp/langues/${locale.languageCode}/$layout-$scene.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }
  expect(_brokenWords(tester), isEmpty, reason: '$where: a word is cut across two lines');
}

Future<TestApp> _pump(WidgetTester tester, AppLocale locale, Size size, double scale) async {
  final app = await pumpLunaway(
    tester,
    size: size,
    textScale: scale,
    locale: locale,
    places: _places,
    map: GoldenMap(_annecy),
  );
  // Images decode on the real event loop, before the frame is looked at.
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    final fetcher = app.container(tester).read(imageFetcherProvider);
    for (final p in samplePhotos) {
      await precacheImage(
        ResizeImage(CachedImage(p.thumbUrl, fetcher: fetcher), width: 480),
        context,
      );
    }
  });
  await settleShort(tester);
  return app;
}

/// Scrolls [scrollable] to its end a screen at a time, so every part of it
/// is laid out once.
Future<void> _scrollThrough(WidgetTester tester, Finder scrollable) async {
  for (var i = 0; i < 12; i++) {
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.pixels >= position.maxScrollExtent) return;
    await tester.drag(scrollable, Offset(0, -position.viewportDimension * 0.8));
    await settleShort(tester, const Duration(milliseconds: 300));
  }
}

/// France's regions and four countries, as the server names them (French
/// and English only).
final _regions = RegionCatalog([
  for (final (code, en, fr) in [
    ('FR-BRE', 'Brittany', 'Bretagne'),
    ('FR-NOR', 'Normandy', 'Normandie'),
    ('FR-PAC', "Provence-Alpes-Côte d'Azur", "Provence-Alpes-Côte d'Azur"),
    ('FR-ARA', 'Auvergne-Rhône-Alpes', 'Auvergne-Rhône-Alpes'),
  ])
    RegionInfo(code: code, country: 'FR', name: en, nameFr: fr),
  const RegionInfo(code: 'FR', country: 'FR', name: 'France', nameFr: 'France'),
  for (final (code, en, fr) in [
    ('DE', 'Germany', 'Allemagne'),
    ('ES', 'Spain', 'Espagne'),
    ('IT', 'Italy', 'Italie'),
    ('NL', 'Netherlands', 'Pays-Bas'),
  ])
    RegionInfo(code: code, country: code, name: en, nameFr: fr),
]);

/// The sheets and pages a signed-in contributor opens, each on its own.
final _contributorScenes = <String, void Function(BuildContext, ProviderContainer)>{
  '15-review': (context, _) => unawaited(showReviewSheet(context, placeId: lakeArea.id)),
  '16-confirm': (context, _) => unawaited(showConfirmSheet(context, placeId: lakeArea.id)),
  '17-issue': (context, _) => unawaited(showIssueSheet(context, placeId: lakeArea.id)),
  '18-report': (context, _) => unawaited(
    showReportSheet(context, target: ReportTarget.place, id: lakeArea.id, placeId: lakeArea.id),
  ),
  '19-place-form': (context, _) => unawaited(
    showFormSheet<void>(
      context,
      builder: (context, scroll) =>
          PlaceForm(position: lakeArea.position, scrollController: scroll),
    ),
  ),
  '20-regions': (context, _) => unawaited(showRegionPicker(context)),
  '21-recovery-card': (_, container) =>
      unawaited(container.read(routerProvider).push(AppRoutes.recoveryCard)),
  '22-offline-maps': (_, container) =>
      unawaited(container.read(routerProvider).push(AppRoutes.offlineMaps)),
  '23-contributions': (_, container) =>
      unawaited(container.read(routerProvider).push(AppRoutes.contributions)),
  '24-delete-account': (_, container) =>
      unawaited(container.read(routerProvider).push(AppRoutes.deleteAccount)),
};

void main() {
  setUpAll(loadRealFonts);

  for (final locale in AppLocale.values) {
    final code = locale.languageCode;
    final t = locale.buildSync();

    for (final (layout, size, scale) in _layoutsOf(locale)) {
      for (final MapEntry(key: scene, value: open) in _contributorScenes.entries) {
        testWidgets('$code, $layout: $scene fits its boxes', (tester) async {
          final app = await pumpLunaway(
            tester,
            size: size,
            textScale: scale,
            locale: locale,
            places: _places,
            map: GoldenMap(_annecy),
            api: FakeApi(level: 2),
            signedIn: true,
            regions: _regions,
          );
          await settleShort(tester);
          open(tester.element(find.byType(Scaffold).first), app.container(tester));
          await settleShort(tester, const Duration(seconds: 2));
          await _shot(tester, locale, layout, scene);
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            await _scrollThrough(tester, scrollables.last);
            await _shot(tester, locale, layout, '$scene-end');
          }
        });
      }
    }

    for (final (layout, size, scale) in _layoutsOf(locale)) {
      testWidgets('$code, $layout: the map, a place, the filters, the favourites, the profile '
          'and the vehicle fit their boxes', (tester) async {
        final app = await _pump(tester, locale, size, scale);
        // The language asked, not French.
        expect(find.text(t.nav.map), findsWidgets, reason: code);
        await _shot(tester, locale, layout, '01-map');

        if (layout == 'medium') {
          await tester.tap(find.textContaining(t.map.showList).first);
          await settleShort(tester);
          await _shot(tester, locale, layout, '02-list');
          await tester.tap(find.byTooltip(t.common.close).first);
          await settleShort(tester);
        }

        app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
        await settleShort(tester, const Duration(seconds: 2));
        await _shot(tester, locale, layout, '03-place');
        final sheet = find.byType(Scrollable);
        if (sheet.evaluate().isNotEmpty) {
          await _scrollThrough(tester, sheet.last);
          await _shot(tester, locale, layout, '04-place-end');
        }
        app.container(tester).read(selectionProvider.notifier).clear();
        await settleShort(tester);

        await tester.tap(find.text(t.map.filters).first);
        await settleShort(tester);
        await _shot(tester, locale, layout, '05-filters');
        await _scrollThrough(tester, find.byType(Scrollable).last);
        await _shot(tester, locale, layout, '06-filters-end');
        await tester.tapAt(const Offset(4, 4));
        await settleShort(tester);
        if (find.text(t.filters.reset).evaluate().isNotEmpty) {
          // A side sheet on a wide window: closed by its own button.
          await tester.tap(find.byTooltip(t.common.close).last);
          await settleShort(tester);
        }

        for (final p in [lakeArea, campsite, dayParking]) {
          await app.favorites.addToDefault(p.summary);
        }
        await app.favorites.createList('Bretagne 2027');
        await tester.tap(find.text(t.nav.favorites).last);
        await settleShort(tester);
        await _shot(tester, locale, layout, '07-favorites');

        await tester.tap(find.text(t.nav.profile).last);
        await settleShort(tester);
        await _shot(tester, locale, layout, '08-profile');
        final profile = find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(Scrollable),
        );
        await _scrollThrough(tester, profile.first);
        await _shot(tester, locale, layout, '09-profile-end');

        await tester.drag(profile.first, const Offset(0, 20000));
        await settleShort(tester);
        await tester.scrollUntilVisible(find.text(t.vehicle.add), 200, scrollable: profile.first);
        // Mid-screen, clear of the bottom bar, which would take the tap.
        await Scrollable.ensureVisible(tester.element(find.text(t.vehicle.add)), alignment: 0.5);
        await settleShort(tester);
        await tester.tap(find.text(t.vehicle.add));
        await settleShort(tester);
        expect(find.byType(VehicleEditor), findsOneWidget);
        await _shot(tester, locale, layout, '10-vehicle');
        await _scrollThrough(tester, find.byType(Scrollable).last);
        await _shot(tester, locale, layout, '11-vehicle-end');
      });
    }

    for (final (layout, size, scale) in [
      _layouts[1],
      _layouts[3],
      if (locale == AppLocale.de) _germanLargest,
    ]) {
      testWidgets('$code, $layout: the route preview fits its boxes', (tester) async {
        final plan = routeFixture('utrillo_motorhome');
        final app = await pumpLunaway(
          tester,
          size: size,
          textScale: scale,
          locale: locale,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            engine: LineEngine([plan]),
          ),
        );
        unawaited(
          app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
        );
        await settleShort(tester);
        expect(find.text(t.navigation.preview.start), findsWidgets, reason: code);
        await _shot(tester, locale, layout, '12-route');
        await _scrollThrough(tester, find.byType(Scrollable).last);
        await _shot(tester, locale, layout, '13-route-end');
      });

      testWidgets('$code, $layout: the guidance fits its boxes', (tester) async {
        final plan = routeFixture('limoges_drive');
        final feed = FakeLocationFeed(position: plan.routes.first.line.first);
        final app = await pumpLunaway(
          tester,
          size: size,
          textScale: scale,
          locale: locale,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: feed,
            engine: LineEngine([plan]),
          ),
        );
        final container = app.container(tester);
        await container
            .read(guidanceControllerProvider.notifier)
            .start(
              plan: plan,
              routeIndex: 0,
              target: utrillo,
              words: TranslatedWording(t, DistanceUnits.metric),
            );
        unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
        await settleShort(tester);
        for (final f in driveFixes(plan.routes.first, toM: 380)) {
          feed.send(f);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await settleShort(tester);
        expect(find.byTooltip(t.navigation.guidance.overview), findsOneWidget, reason: code);
        await _shot(tester, locale, layout, '14-guidance');
      });
    }
  }
}
