import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fonts.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show utrillo;

/// The lists a French zone cites, as the API serves them: the map of the
/// Sécurité routière, the yearly file of fixed cameras, and OpenStreetMap
/// for a camera all three hold.
final _map = EnforcementSource(
  id: 'securite-routiere',
  name: 'Sécurité routière, radars',
  attribution: 'Sécurité routière, radars.securite-routiere.gouv.fr',
  fetchedAt: DateTime.utc(2026, 10, 6, 5),
);
final _dsr = EnforcementSource(
  id: 'fr-dsr',
  name: 'Délégation à la sécurité routière, radars fixes',
  attribution: "Ministère de l'Intérieur, Délégation à la sécurité routière (data.gouv.fr)",
  fetchedAt: DateTime.utc(2026, 10, 6, 5),
);
final _osm = EnforcementSource(
  id: 'osm',
  name: 'OpenStreetMap',
  attribution: '© OpenStreetMap contributors',
  fetchedAt: DateTime.utc(2026, 10, 6, 5),
);

const _rules = EnforcementRules(version: 1, countries: {'FR': EnforcementMode.zones});

typedef _Line = ({String text, RenderParagraph paragraph});

/// The guidance on a phone [width] wide, driven to 250 m before a zone
/// that cites [sources]: the lines of its notice that cite a list, as
/// drawn.
Future<List<_Line>> _citedLines(
  WidgetTester tester, {
  required double width,
  required AppLocale locale,
  required double scale,
  required List<EnforcementSource> sources,
}) async {
  // The limit for the vehicle the server gives, 80 km/h through the zone:
  // the zone shows from 400 m ahead.
  final plan = routeFixture(
    'limoges_drive',
    edit: (answer) {
      final routes = answer['routes'] as List<dynamic>;
      (routes.first as Map<String, dynamic>)['speedLimits'] = [
        {'fromM': 0.0, 'toM': 1300.0, 'kmh': 80, 'source': 'VEHICLE'},
      ];
    },
  );
  final route = plan.routes.first;
  final track = LineTrack(route);
  final feed = FakeLocationFeed(position: route.line.first);
  final app = await pumpLunaway(
    tester,
    size: Size(width, 800),
    locale: locale,
    textScale: scale,
    overrides: navigationOverrides(
      routes: FakeRouteService([plan]),
      feed: feed,
      engine: LineEngine([plan]),
      countries: FakeCountries((_) => 'FR', rules: _rules),
      enforcement: FixedEnforcement(
        rules: _rules,
        items: [
          EnforcementItem(
            id: 'zone',
            kind: EnforcementKind.zone,
            category: 'FIXED',
            country: 'FR',
            line: [for (var m = 1000.0; m <= 1500; m += 50) track.at(m)],
            sourceIds: [for (final s in sources) s.id],
          ),
        ],
        sources: sources,
      ),
    ),
  );
  final container = app.container(tester);
  await container
      .read(guidanceControllerProvider.notifier)
      .start(
        plan: plan,
        routeIndex: route.index,
        target: utrillo,
        words: TranslatedWording(await locale.build(), DistanceUnits.metric),
      );
  unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
  await settleShort(tester);
  // Up to 750 m at 36 km/h.
  var at = DateTime.utc(2026, 10, 6, 9);
  for (var m = 0.0; m <= 750; m += 10) {
    feed.send(Fix(position: track.at(m), accuracyM: 5, at: at, speedMps: 10));
    at = at.add(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await settleShort(tester);
  final banner = find.byType(EnforcementNotice);
  expect(banner, findsOneWidget);
  final t = locale.buildSync();
  final names = [for (final s in sources) t.listName(s)];
  return [
    for (final e in find.descendant(of: banner, matching: find.byType(RichText)).evaluate())
      if ((e.widget as RichText).text.toPlainText() case final text when names.any(text.contains))
        (text: text, paragraph: e.renderObject! as RenderParagraph),
  ];
}

/// The lists of the guidance's zone notice on the phones most in hands,
/// measured with the app's own typefaces: the test font draws every glyph
/// as a square and would decide nothing about the real widths. Kept in its
/// own file, as the fonts stay loaded for the rest of the file.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    await initializeDateFormatting('fr');
    await initializeDateFormatting('de');
  });

  for (final (name, sources) in [
    ('both French lists', [_map, _dsr]),
    ('three lists', [_map, _dsr, _osm]),
  ]) {
    for (final locale in [AppLocale.fr, AppLocale.de]) {
      for (final width in [360.0, 390.0]) {
        for (final scale in [1.0, 1.3]) {
          testWidgets('on a phone $width dp wide in ${locale.languageCode}, text at $scale, $name: '
              'the French ones named in full, nothing cut, two lines at most', (tester) async {
            final lines = await _citedLines(
              tester,
              width: width,
              locale: locale,
              scale: scale,
              sources: sources,
            );
            final t = locale.buildSync();
            final shown = lines.map((l) => l.text).toList();
            expect(lines.length, inInclusiveRange(1, 2), reason: '$shown');
            expect(shown.first, startsWith(t.listName(_map)), reason: 'never cut at its start');
            for (final line in lines) {
              expect(line.paragraph.didExceedMaxLines, isFalse, reason: 'cut: ${line.text}');
            }
            // OpenStreetMap may give way to an ellipsis; the two lists
            // the Licence Ouverte asks to credit never do.
            for (final list in [_map, _dsr]) {
              expect(shown.any((l) => l.contains(t.listName(list))), isTrue, reason: '$shown');
            }
            if (scale == 1) {
              expect(
                shown.first,
                contains(t.listDate(_map, now: DateTime(2026, 10, 9))),
                reason: 'the date of the list, where the line holds it',
              );
            }
          });
        }
      }
    }
  }
}
