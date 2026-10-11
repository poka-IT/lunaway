import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/tokens.dart';

import '../helpers/fonts.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show utrillo;

const _rules = EnforcementRules(
  version: 1,
  countries: {'FR': EnforcementMode.zones, 'ES': EnforcementMode.exact},
);

/// The guidance on a screen of [size] in [country], driven to 250 m before
/// a fixed camera limited to 70 (Spain) or a danger zone (France), whose
/// alert then shows; the vehicle's limit, 80 km/h, beside its speed.
Future<void> _driveTo(
  WidgetTester tester, {
  required Size size,
  required AppLocale locale,
  required double scale,
  String country = 'ES',
}) async {
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
    size: size,
    locale: locale,
    textScale: scale,
    overrides: navigationOverrides(
      routes: FakeRouteService([plan]),
      feed: feed,
      engine: LineEngine([plan]),
      countries: FakeCountries((_) => country, rules: _rules),
      enforcement: FixedEnforcement(
        rules: _rules,
        items: [
          if (country == 'ES')
            EnforcementItem(
              id: 'camera',
              kind: EnforcementKind.camera,
              category: 'FIXED',
              country: 'ES',
              position: track.at(1000),
              limitKmh: 70,
            )
          else
            EnforcementItem(
              id: 'zone',
              kind: EnforcementKind.zone,
              category: 'FIXED',
              country: 'FR',
              line: [for (var m = 1000.0; m <= 1500; m += 50) track.at(m)],
            ),
        ],
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
}

/// The union of the rects [finder] finds.
Rect _around(WidgetTester tester, Finder finder) => finder
    .evaluate()
    .map((e) => tester.getRect(find.byWidget(e.widget)))
    .reduce((a, b) => a.expandToInclude(b));

/// The camera's or the zone's pill beside the speed, measured on the phones
/// most in hands and on a phone on its side, with the app's own typefaces:
/// next to the sign of the limit, at the foot of the screen, never over the
/// maneuver, the buttons nor the vehicle.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    await initializeDateFormatting('fr');
    await initializeDateFormatting('de');
  });

  for (final (name, size, scale) in [
    ('a small phone, text at 1.3', const Size(360, 640), 1.3),
    ('a phone', const Size(390, 844), 1.0),
    ('a tall phone', const Size(412, 915), 1.0),
    ('a phone on its side', const Size(844, 390), 1.0),
    ('a small phone on its side', const Size(640, 360), 1.0),
  ]) {
    for (final locale in [AppLocale.fr, AppLocale.de]) {
      for (final country in ['ES', 'FR']) {
        testWidgets(
          'on $name in ${locale.languageCode}, ${country == 'ES' ? 'a camera' : 'a zone'}: '
          'the pill beside the speed, clear of the maneuver, the buttons and the vehicle',
          (tester) async {
            await _driveTo(tester, size: size, locale: locale, scale: scale, country: country);
            expect(tester.takeException(), isNull);
            final t = locale.buildSync();
            final pill = tester.getRect(find.byType(EnforcementChip));
            final speed = tester.getRect(find.byType(SpeedAndLimit));
            // The bar that shows the speed and its limit.
            final bar = tester.getRect(
              find.ancestor(of: find.byType(SpeedAndLimit), matching: find.byType(Material)).first,
            );
            final banner = tester.getRect(
              find
                  .ancestor(of: find.byType(ManeuverIcon).first, matching: find.byType(Material))
                  .first,
            );
            final buttons = _around(
              tester,
              find.descendant(
                of: find.byType(Column),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is IconButton &&
                      w.tooltip != null &&
                      w.tooltip != t.navigation.guidance.end &&
                      w.style?.minimumSize?.resolve(const {}) == const Size(56, 56),
                ),
              ),
            );
            final landscape = size.width > size.height;
            // Where following draws the vehicle: right of the panel on its
            // side, under the banner's fixed room and above the bar upright.
            final vehicle = Rect.fromCircle(
              center: followAnchor(
                size,
                landscape
                    ? const EdgeInsets.only(left: 380)
                    : EdgeInsets.only(top: 220, bottom: size.height - bar.top),
              ),
              radius: 15,
            );
            // Beside the speed and its limit: just above the bar that shows
            // them, at the same edge.
            expect(pill.bottom, closeTo(bar.top - Space.s, 0.5), reason: 'pill $pill, bar $bar');
            expect((pill.left - speed.left).abs(), lessThanOrEqualTo(Space.l), reason: '$speed');
            expect(pill.overlaps(banner), isFalse, reason: 'pill $pill, maneuver $banner');
            expect(pill.overlaps(buttons), isFalse, reason: 'pill $pill, buttons $buttons');
            expect(pill.overlaps(vehicle), isFalse, reason: 'pill $pill, vehicle $vehicle');
            expect(pill.overlaps(bar), isFalse);
            // A pill, not a banner: about a third of a phone held upright.
            expect(pill.width, lessThan(landscape ? 365 : size.width * 0.6));
          },
        );
      }
    }
  }
}
