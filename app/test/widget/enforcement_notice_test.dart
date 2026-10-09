import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/plural_rules.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

final _list = EnforcementSource(
  id: 'securite-routiere',
  name: 'Sécurité routière',
  attribution: 'Sécurité routière',
  fetchedAt: DateTime.utc(2026, 10, 6, 5),
);

/// Every banner the guidance shows, as long as each gets.
final _banners = <String, AidsBanner>{
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
  'the end of a section': const AlertExit(id: 's', section: true),
  'a rule': const RuleChange(country: 'NL', mode: EnforcementMode.offWhileDriving),
};

Future<void> _pump(WidgetTester tester, AidsBanner banner, {required double width}) async {
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
                child: EnforcementNotice(banner: banner, units: DistanceUnits.metric),
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
}
