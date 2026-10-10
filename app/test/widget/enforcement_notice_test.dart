import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/plural_rules.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

final _list = EnforcementSource(
  id: 'securite-routiere',
  name: 'Sécurité routière',
  attribution: 'Sécurité routière',
  fetchedAt: DateTime.utc(2026, 10, 6, 5),
);

/// Every look of the aids' standing notice, as long as each gets.
final _banners = <String, EnforcementAlert>{
  'a camera ahead': EnforcementAlert(
    id: 'c',
    kind: EnforcementKind.camera,
    category: CameraCategory.levelCrossing,
    aheadM: 780,
    remainingM: 0,
    limitKmh: 110,
    cameraLimit: true,
    sources: [_list, _list],
  ),
  'a section over its average': EnforcementAlert(
    id: 's',
    kind: EnforcementKind.camera,
    category: CameraCategory.section,
    aheadM: 0,
    remainingM: 12400,
    limitKmh: 110,
    cameraLimit: true,
    sectionM: 15000,
    averageKmh: 118,
    over: true,
    sources: [_list],
  ),
  'a zone with an estimated limit': EnforcementAlert(
    id: 'z',
    kind: EnforcementKind.zone,
    aheadM: 0,
    remainingM: 1200,
    limitKmh: 80,
    limitEstimated: true,
    sources: [_list],
  ),
};

Future<void> _pump(WidgetTester tester, EnforcementAlert banner, {required double width}) async {
  await LocaleSettings.setLocale(AppLocale.de);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: lunaTheme(Brightness.light),
        // The notices scroll where they run out of height: only the
        // width binds.
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: EnforcementNotice(
                  alert: banner,
                  units: DistanceUnits.metric,
                  now: DateTime(2026, 10, 9),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await registerPluralRules();
    await initializeDateFormatting('de');
  });

  // German runs the longest of the six; 240 dp is a small phone's notice
  // column once the buttons have their room.
  for (final MapEntry(key: name, value: banner) in _banners.entries) {
    for (final width in [240.0, 364.0]) {
      testWidgets('$name fits $width dp in German with text twice as large', (tester) async {
        await _pump(tester, banner, width: width);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a zone never shows a camera; a camera shows its badge, as on the map', (
    tester,
  ) async {
    await _pump(tester, _banners['a zone with an estimated limit']!, width: 364);
    expect(find.byType(RouteBadgeView), findsNothing);
    await _pump(tester, _banners['a camera ahead']!, width: 364);
    expect(find.byType(RouteBadgeView), findsOneWidget);
  });

  testWidgets('three lists of a French zone take one line, cut short', (tester) async {
    EnforcementSource list(String id, String name) => EnforcementSource(
      id: id,
      name: name,
      attribution: name,
      fetchedAt: DateTime.utc(2026, 10, 9, 5),
      listUpdatedAt: DateTime.utc(2025, 12, 30),
    );
    final zone = EnforcementAlert(
      id: 'z',
      kind: EnforcementKind.zone,
      aheadM: 0,
      remainingM: 1800,
      sources: [
        list('securite-routiere', 'Sécurité routière, radars'),
        list('fr-dsr', 'Liste des radars fixes en France'),
        list('osm', 'OpenStreetMap'),
      ],
    );
    await _pump(tester, zone, width: 364);
    final cited = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.textContaining(' · '), matching: find.byType(RichText)),
    );
    final line = cited.getFullHeightForCaret(const TextPosition(offset: 0));
    expect(cited.size.height, lessThan(line * 1.5), reason: 'one line, at text 2x');
    expect(find.textContaining('Liste des radars'), findsNothing, reason: 'named in German');
  });

  testWidgets('the lists are cited in one run of text, not a line each', (tester) async {
    await _pump(tester, _banners['a camera ahead']!, width: 364);
    final cited = find.textContaining(' · ');
    expect(cited, findsOneWidget, reason: 'two lists, one text');
    expect(find.textContaining('Sécurité routière'), findsOneWidget);
  });

  testWidgets('the look gives the notice one sentence and makes no live region of its own', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _banners['a section over its average']!, width: 364);
    final de = AppLocale.de.buildSync();
    final sentence = enforcementText(
      de,
      _banners['a section over its average']!,
      DistanceUnits.metric,
    );
    expect(sentence, contains(de.navigation.guidance.overLimit));
    // The notice's own node is live on its first frame; a live region here
    // would read every new distance.
    expect(find.bySemanticsLabel(sentence), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(sentence)),
      isNot(isSemantics(isLiveRegion: true)),
    );
    semantics.dispose();
  });

  test('graver as the vehicle comes, enters, then goes over the limit', () {
    final ahead = _banners['a camera ahead']!;
    final inside = _banners['a zone with an estimated limit']!;
    final over = _banners['a section over its average']!;
    expect([enforcementLevel(ahead), enforcementLevel(inside), enforcementLevel(over)], [1, 2, 3]);
  });

  test("a camera's point just passed is no stretch entered: its notice is not told again", () {
    const passed = EnforcementAlert(
      id: 'c',
      kind: EnforcementKind.camera,
      category: CameraCategory.fixed,
      aheadM: 0,
      remainingM: 0,
      limitKmh: 90,
      cameraLimit: true,
    );
    expect(enforcementLevel(passed), 1);
    final de = AppLocale.de.buildSync();
    expect(
      enforcementText(de, passed, DistanceUnits.metric),
      isNot(contains(de.navigation.enforcement.remaining(distance: ''))),
    );
  });

  testWidgets('a zone held past its end, or just ahead, shows no "0 m" figure', (tester) async {
    const held = EnforcementAlert(id: 'z', kind: EnforcementKind.zone, aheadM: 0, remainingM: 0);
    const near = EnforcementAlert(id: 'z', kind: EnforcementKind.zone, aheadM: 6, remainingM: 0);
    for (final alert in [held, near]) {
      await _pump(tester, alert, width: 360);
      expect(find.textContaining(RegExp(r'\b0 m\b')), findsNothing, reason: '$alert');
      expect(find.textContaining('Gefahrenzone'), findsWidgets, reason: 'the kind alone');
    }
    final fr = AppLocale.fr.buildSync();
    expect(enforcementText(fr, held, DistanceUnits.metric), 'Zone de danger.');
    expect(enforcementText(fr, near, DistanceUnits.metric), 'Zone de danger.');
  });

  test('the end of a zone or a section and a rule come as passing notices, calm', () {
    final de = AppLocale.de.buildSync();
    final end = alertExitNotice(de, const AlertExit(id: 's', section: true));
    expect(end.text, de.navigation.enforcement.sectionEnd);
    expect(end.priority, NoticePriority.quiet);
    expect(
      alertExitNotice(de, const AlertExit(id: 'z', section: false)).text,
      de.navigation.enforcement.zoneEnd,
    );
    const change = RuleChange(country: 'NL', mode: EnforcementMode.exact);
    final rule = ruleChangeNotice(de, change);
    expect(rule.text, de.ruleChange(change));
    expect(rule.text, startsWith(de.countryName('NL')));
    expect(rule.id, isNot(end.id));
  });
}
