import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../unit/contrast_test.dart' show contrast, text;
import 'navigation_test.dart' show utrillo;

/// The map's credit, as the OpenStreetMap Foundation's attribution
/// guidelines allow it at its least: "© OpenStreetMap" without a tap, then
/// an "(i)" in the corner after five seconds or a press on the map, the
/// licence a tap away.
void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  Finder inCredit(Finder f) => find.descendant(of: find.byType(MapCredit), matching: f);

  /// The ground the credit draws its mark and its words on.
  Finder ground() => inCredit(find.byType(DecoratedBox)).first;

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    group(name, () {
      testWidgets('the map names OpenStreetMap at first, without a tap', (tester) async {
        await pumpLunaway(tester, size: size);
        expect(inCredit(find.text('© OpenStreetMap')), findsOneWidget);
        expect(
          find.textContaining('Protomaps'),
          findsNothing,
          reason: 'Protomaps asks for a credit without requiring one: the credits name it',
        );
      });

      testWidgets('after five seconds the credit folds into its mark, a finger-sized target '
          'still, never under a button', (tester) async {
        await pumpLunaway(tester, size: size);
        final full = tester.getSize(ground());
        await tester.pump(mapCreditInFull);
        await settleShort(tester);
        expect(inCredit(find.text('© OpenStreetMap')), findsNothing);
        final mark = tester.getRect(ground());
        expect(mark.width, lessThan(full.width / 3), reason: 'folded from $full to ${mark.size}');
        expect(mark.width, lessThanOrEqualTo(24));
        expect(mark.height, lessThanOrEqualTo(24));
        final target = tester.getSize(find.byType(MapCredit));
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        for (final button in [
          find.byTooltip('Afficher ma position'),
          find.byTooltip('Zoomer'),
          find.byTooltip('Dézoomer'),
          find.text('Voir autour de moi'),
        ]) {
          for (final e in button.evaluate()) {
            final rect = tester.getRect(find.byElementPredicate((x) => x == e));
            expect(rect.overlaps(mark), isFalse, reason: '$button at $rect over $mark');
          }
        }
      });

      testWidgets('a press on the map folds it at once', (tester) async {
        await pumpLunaway(tester, size: size);
        final map = tester.getRect(find.byKey(const ValueKey('fake-map')));
        // Above the pins the fake map lays out in its middle, below the
        // search: bare map.
        await tester.tapAt(Offset(map.center.dx, map.center.dy - 150));
        await settleShort(tester);
        expect(inCredit(find.text('© OpenStreetMap')), findsNothing);
      });

      testWidgets('a tap on the mark opens the credits: OpenStreetMap under the ODbL with its '
          'copyright page, the Protomaps style, where every source is', (tester) async {
        final app = await pumpLunaway(tester, size: size);
        await tester.pump(mapCreditInFull);
        await settleShort(tester);
        await tester.tap(find.byType(MapCredit));
        await settleShort(tester);
        expect(find.text('Crédits de la carte'), findsOneWidget);
        expect(find.text('Style du fond de carte : Protomaps'), findsOneWidget);
        expect(
          find.text('Toutes les sources et leurs licences : Profil, Sources et crédits.'),
          findsOneWidget,
        );
        expect(find.textContaining('ODbL'), findsOneWidget);
        await tester.tap(find.text("© les contributeurs d'OpenStreetMap"));
        await tester.pump();
        expect(app.external.opened, [osmCopyright]);
        await tester.tap(find.text('Style du fond de carte : Protomaps'));
        await tester.pump();
        expect(app.external.opened, [osmCopyright, protomapsBasemaps]);
      });
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: the words and the mark read at 4.5:1 over a white map and '
        'a black one', (tester) async {
      await pumpLunaway(tester, brightness: brightness);
      final scheme = Theme.of(tester.element(find.byType(MapCredit))).colorScheme;
      final paint = (tester.widget<DecoratedBox>(ground()).decoration as ShapeDecoration).color!;
      for (final under in [Colors.white, Colors.black]) {
        final behind = Color.alphaBlend(paint, under);
        expect(contrast(scheme.onSurface, behind), greaterThanOrEqualTo(text), reason: '$under');
      }
      final words = tester.widget<Text>(inCredit(find.text('© OpenStreetMap')));
      expect(words.style?.color, scheme.onSurface);
    });
  }

  testWidgets('folded once, a map opened after it shows the mark alone: the route preview', (
    tester,
  ) async {
    final app = await pumpLunaway(
      tester,
      overrides: navigationOverrides(routes: FakeRouteService([routeFixture('utrillo_van')])),
    );
    await tester.pump(mapCreditInFull);
    await settleShort(tester);
    unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)));
    await settleShort(tester);
    final preview = find.descendant(
      of: find.byType(RoutePreviewScreen),
      matching: find.byType(MapCredit),
    );
    expect(preview, findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('© OpenStreetMap')), findsNothing);
  });

  testWidgets('the five seconds run while the map is on screen: another tab holds them', (
    tester,
  ) async {
    await pumpLunaway(tester);
    await tester.tap(find.text('Favoris').last);
    // The frame that hides the map's tab.
    await tester.pump();
    expect(
      TickerMode.valuesOf(tester.element(find.byType(MapCredit, skipOffstage: false))).enabled,
      isFalse,
    );
    await tester.pump(mapCreditInFull * 2);
    await settleShort(tester);
    await tester.tap(find.text('Carte').last);
    await settleShort(tester);
    expect(inCredit(find.text('© OpenStreetMap')), findsOneWidget, reason: 'not seen yet');
    await tester.pump(mapCreditInFull);
    await settleShort(tester);
    expect(inCredit(find.text('© OpenStreetMap')), findsNothing);
  });

  /// [credit] alone at the foot of a screen, as a route map holds it.
  Future<void> pumpCredit(WidgetTester tester, MapCredit credit) => tester.pumpWidget(
    ProviderScope(
      child: TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.bottomLeft, child: credit),
          ),
        ),
      ),
    ),
  );

  const photos = 'Photos : Source communautaire externe';

  testWidgets("the photos' line shows in full with the credit, then folds with it into the mark, "
      "and the credits' sheet names the source", (tester) async {
    await pumpCredit(tester, const MapCredit(photos: true));
    expect(inCredit(find.text('© OpenStreetMap')), findsOneWidget);
    expect(inCredit(find.text(photos)), findsOneWidget, reason: 'in full at first');
    await tester.pump(mapCreditInFull);
    await tester.pumpAndSettle();
    expect(
      inCredit(find.text(photos)),
      findsNothing,
      reason: 'its agreement lets the mention stand a tap away (art. 5.3)',
    );
    expect(inCredit(find.text('© OpenStreetMap')), findsNothing);
    final mark = tester.getRect(ground());
    expect(mark.width, lessThanOrEqualTo(24), reason: 'the mark alone, $mark');
    await tester.tap(find.byType(MapCredit));
    await tester.pumpAndSettle();
    expect(find.text('Crédits de la carte'), findsOneWidget);
    expect(find.text(photos), findsOneWidget, reason: "the sheet names the photos' source");
  });

  testWidgets("over the guidance, folded, the caption is the mark alone, read with the photos' "
      'source', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCredit(tester, const MapCredit(photos: true, caption: true));
    await tester.pump(mapCreditInFull);
    await tester.pumpAndSettle();
    expect(inCredit(find.text(photos)), findsNothing);
    expect(tester.getRect(ground()).width, lessThanOrEqualTo(24));
    expect(find.bySemanticsLabel('© OpenStreetMap. $photos'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the credits read in every language of the app', (tester) async {
    for (final locale in AppLocale.values) {
      await pumpLunaway(tester, locale: locale);
      await tester.pump(mapCreditInFull);
      await settleShort(tester);
      await tester.tap(find.byType(MapCredit));
      await settleShort(tester);
      final t = locale.translations;
      expect(find.text(t.map.creditsTitle), findsOneWidget, reason: locale.languageCode);
      expect(find.text(t.map.creditsOsm), findsOneWidget, reason: locale.languageCode);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
