import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/plural_rules.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

import '../helpers/fonts.dart';

final _list = EnforcementSource(
  id: 'fr-dsr',
  name: 'Délégation à la sécurité routière, radars fixes',
  attribution: "Ministère de l'Intérieur, Délégation à la sécurité routière (data.gouv.fr)",
  fetchedAt: DateTime.utc(2026, 10, 6, 5),
);

/// Every look of the camera's pill, as long as each gets.
final _pills = <String, EnforcementAlert>{
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

/// The pill alone, at the start of a room [width] wide, as the guidance
/// gives it beside the speed.
Future<void> _pump(
  WidgetTester tester,
  EnforcementAlert alert, {
  required double width,
  double scale = 1,
  AppLocale locale = AppLocale.de,
}) async {
  await LocaleSettings.setLocale(locale);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: lunaTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: width,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: EnforcementChip(alert: alert, units: DistanceUnits.metric),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The colour the pill is drawn on.
Color _ground(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(of: find.byType(EnforcementChip), matching: find.byType(Material)).first,
    )
    .color!;

void main() {
  setUpAll(() async {
    await registerPluralRules();
    await initializeDateFormatting('de');
    await initializeDateFormatting('fr');
  });

  // German runs the longest of the six; 160 dp is what a small phone leaves
  // left of the road behind the vehicle.
  for (final MapEntry(key: name, value: pill) in _pills.entries) {
    for (final width in [160.0, 240.0]) {
      testWidgets('$name fits $width dp in German with text twice as large', (tester) async {
        await _pump(tester, pill, width: width, scale: 2);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(EnforcementChip)).width, lessThanOrEqualTo(width));
      });
    }
  }

  testWidgets('a compact pill: the pictogram, the distance and the limit, nothing more', (
    tester,
  ) async {
    await loadRealFonts();
    await _pump(tester, _pills['a camera ahead']!, width: 390, locale: AppLocale.fr);
    final pill = find.byType(EnforcementChip);
    expect(find.descendant(of: pill, matching: find.byType(RouteBadgeView)), findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('780 m')), findsOneWidget);
    final sign = tester.widget<LimitSign>(
      find.descendant(of: pill, matching: find.byType(LimitSign)),
    );
    expect(sign.value, 110);
    // The kind, the lists and their date go to the screen reader and to the
    // camera's card, not on the road's view.
    final words = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: pill, matching: find.byType(Text)),
      ))
        t.data,
    ];
    expect(words, ['780 m', '110'], reason: 'one figure and the limit');
    // A touch target high, no more; about a third of a phone's width.
    final size = tester.getSize(pill);
    expect(size.height, 48);
    expect(size.width, lessThan(170));
  });

  testWidgets("red only over the camera's limit, sober otherwise", (tester) async {
    final scheme = lunaTheme(Brightness.light).colorScheme;
    const ahead = EnforcementAlert(
      id: 'c',
      kind: EnforcementKind.camera,
      category: CameraCategory.fixed,
      aheadM: 400,
      remainingM: 0,
      limitKmh: 90,
      cameraLimit: true,
    );
    await _pump(tester, ahead, width: 360);
    expect(_ground(tester), scheme.surfaceContainerLowest, reason: 'under the limit');
    expect(_ground(tester), isNot(scheme.error));
    expect(_ground(tester), isNot(scheme.errorContainer));
    final over = ahead.withOver();
    await _pump(tester, over, width: 360);
    expect(_ground(tester), scheme.error, reason: 'over the limit');
    final sign = tester.widget<LimitSign>(find.byType(LimitSign));
    expect(sign.outline, scheme.onError, reason: "the sign's red ring kept apart on the red");
    await _pump(tester, _pills['a zone with an estimated limit']!, width: 360);
    expect(_ground(tester), scheme.surfaceContainerLowest, reason: 'a zone, under the limit');
  });

  testWidgets('a zone never shows a camera; a camera shows its badge, as on the map', (
    tester,
  ) async {
    await _pump(tester, _pills['a zone with an estimated limit']!, width: 364);
    expect(find.byType(RouteBadgeView), findsNothing);
    await _pump(tester, _pills['a camera ahead']!, width: 364);
    expect(find.byType(RouteBadgeView), findsOneWidget);
  });

  testWidgets("inside a section: the average's sign and the vehicle's average under the figure", (
    tester,
  ) async {
    await _pump(tester, _pills['a section over its average']!, width: 360, locale: AppLocale.fr);
    final fr = AppLocale.fr.buildSync();
    expect(find.text(fr.navigation.enforcement.averageLabel), findsOneWidget);
    expect(find.text('encore 12 km'), findsOneWidget);
    expect(find.text(fr.navigation.enforcement.yourAverage(speed: '118 km/h')), findsOneWidget);
    expect(find.text(fr.navigation.guidance.overLimit), findsNothing, reason: 'the colour says it');
  });

  testWidgets('the look gives the notice one sentence and makes no live region of its own', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _pills['a section over its average']!, width: 364);
    final de = AppLocale.de.buildSync();
    final sentence = enforcementText(
      de,
      _pills['a section over its average']!,
      DistanceUnits.metric,
    );
    expect(sentence, contains(de.navigation.guidance.overLimit));
    expect(sentence, contains(de.alertKind(_pills['a section over its average']!)));
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
    final ahead = _pills['a camera ahead']!;
    final inside = _pills['a zone with an estimated limit']!;
    final over = _pills['a section over its average']!;
    expect([enforcementLevel(ahead), enforcementLevel(inside), enforcementLevel(over)], [1, 2, 3]);
  });

  test('the standing notice of a pill: folded in the colours of the error only over the limit', () {
    final de = AppLocale.de.buildSync();
    final ahead = enforcementNotice(de, _pills['a camera ahead']!, DistanceUnits.metric);
    expect(ahead.strong, isFalse);
    expect(ahead.level, 1);
    expect(ahead.look, isA<EnforcementChip>());
    final over = enforcementNotice(de, _pills['a section over its average']!, DistanceUnits.metric);
    expect(over.strong, isTrue);
    expect(over.level, 3);
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
      expect(tester.takeException(), isNull);
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

extension on EnforcementAlert {
  /// The same alert, the vehicle over its limit.
  EnforcementAlert withOver() => EnforcementAlert(
    id: id,
    kind: kind,
    category: category,
    aheadM: aheadM,
    remainingM: remainingM,
    limitKmh: limitKmh,
    cameraLimit: cameraLimit,
    over: true,
  );
}
