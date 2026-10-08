import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show tallPhone, utrillo;

const _rules = EnforcementRules(
  version: 1,
  countries: {
    'FR': EnforcementMode.zones,
    'ES': EnforcementMode.exact,
    'DE': EnforcementMode.offWhileDriving,
    'CH': EnforcementMode.off,
  },
);

/// The route of the drive with the limits for the vehicle the server
/// gives: 30 km/h signed to 600 m, 80 km/h for the vehicle to 1 300 m,
/// then an estimate.
RoutePlan _plan() => routeFixture(
  'limoges_drive',
  edit: (answer) {
    final routes = answer['routes'] as List<dynamic>;
    (routes.first as Map<String, dynamic>)['speedLimits'] = [
      {'fromM': 0.0, 'toM': 600.0, 'kmh': 30, 'source': 'POSTED'},
      {'fromM': 600.0, 'toM': 1300.0, 'kmh': 80, 'source': 'VEHICLE'},
      {'fromM': 1300.0, 'toM': 9000.0, 'kmh': 50, 'source': 'DEFAULT'},
    ];
  },
);

/// A zone along the route from [from] to [to] metres, a point every 50 m,
/// as the server draws them.
EnforcementItem _zoneOn(RouteOption route, double from, double to, {String country = 'FR'}) {
  final track = LineTrack(route);
  return EnforcementItem(
    id: 'zone-$from',
    kind: EnforcementKind.zone,
    category: 'FIXED',
    country: country,
    line: [for (var m = from; m <= to; m += 50) track.at(m)],
  );
}

/// Fixes along [route] to [toM], every 10 m, at [kmh].
List<Fix> _drive(RouteOption route, {required double fromM, required double toM, double kmh = 36}) {
  final track = LineTrack(route);
  final step = kmh / 3.6;
  final out = <Fix>[];
  var at = DateTime.utc(2026, 10, 6, 9).add(Duration(seconds: (fromM / step).round()));
  for (var m = fromM; m <= toM; m += step) {
    out.add(Fix(position: track.at(m), accuracyM: 5, at: at, speedMps: kmh / 3.6));
    at = at.add(const Duration(seconds: 1));
  }
  return out;
}

void main() {
  late FakeLocationFeed feed;
  late RecordingVoice voice;

  Future<TestApp> guide(
    WidgetTester tester,
    RoutePlan plan, {
    String? Function(LatLng)? country,
    List<EnforcementItem> items = const [],
    List<EnforcementSource> sources = const [],
    bool speak = false,
    bool showLimit = true,
  }) async {
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    voice = RecordingVoice();
    final app = await pumpLunaway(
      tester,
      size: tallPhone,
      overrides: navigationOverrides(
        routes: FakeRouteService([plan]),
        feed: feed,
        voice: voice,
        engine: LineEngine([plan]),
        countries: FakeCountries(country ?? (_) => 'FR', rules: _rules),
        enforcement: FixedEnforcement(rules: _rules, items: items, sources: sources),
      ),
    );
    final container = app.container(tester);
    if (speak) {
      await container.read(drivingAidsSettingsControllerProvider.notifier).setSpeedSound(on: true);
    }
    if (!showLimit) {
      await container
          .read(drivingAidsSettingsControllerProvider.notifier)
          .setShowSpeedLimit(on: false);
    }
    await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: plan.routes.first.index,
          target: utrillo,
          words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
        );
    unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
    await settleShort(tester);
    return app;
  }

  Future<void> drive(WidgetTester tester, List<Fix> fixes) async {
    for (final f in fixes) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleShort(tester);
  }

  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  testWidgets('in France the zone shows ahead, then what is left of it, never a camera', (
    tester,
  ) async {
    final plan = _plan();
    final route = plan.routes.first;
    final camera = EnforcementItem(
      id: 'camera',
      kind: EnforcementKind.camera,
      category: 'FIXED',
      country: 'FR',
      position: LineTrack(route).at(1000),
    );
    final zone = _zoneOn(route, 1000, 1500);
    await guide(
      tester,
      plan,
      items: [
        EnforcementItem(
          id: zone.id,
          kind: zone.kind,
          category: zone.category,
          country: zone.country,
          line: zone.line,
          sourceIds: const ['fr-securite-routiere'],
        ),
        camera,
      ],
      sources: [
        EnforcementSource(
          id: 'fr-securite-routiere',
          name: 'Sécurité routière',
          attribution: 'Sécurité routière',
          fetchedAt: DateTime.utc(2026, 10, 6, 5),
        ),
      ],
    );
    // At 80 km/h of limit, the zone shows from 400 m.
    await drive(tester, _drive(route, fromM: 0, toM: 750));
    expect(find.textContaining('Zone de danger dans'), findsOneWidget);
    // The French list is cited with its date, as its reuse requires.
    expect(find.text('Sécurité routière, liste du 6 oct.'), findsOneWidget);
    await drive(tester, _drive(route, fromM: 760, toM: 1200));
    expect(find.textContaining('Zone de danger, encore'), findsOneWidget);
    expect(find.textContaining('Radar'), findsNothing, reason: 'France: zones only');
    await drive(tester, _drive(route, fromM: 1210, toM: 1600));
    expect(find.textContaining('Zone de danger'), findsNothing);
    expect(
      voice.said.where((s) => s.contains('Zone de danger')),
      isEmpty,
      reason: 'silent by default',
    );
  });

  testWidgets('entering a country that is off, the zone goes at once', (tester) async {
    final plan = _plan();
    final route = plan.routes.first;
    final border = LineTrack(route).at(1100);
    final start = route.line.first;
    await guide(
      tester,
      plan,
      country: (p) => p.distanceTo(start) > border.distanceTo(start) ? 'CH' : 'FR',
      items: [_zoneOn(route, 1000, 1500)],
    );
    await drive(tester, _drive(route, fromM: 0, toM: 1050));
    expect(find.textContaining('Zone de danger'), findsOneWidget);
    await drive(tester, _drive(route, fromM: 1060, toM: 1200));
    expect(find.textContaining('Zone de danger'), findsNothing);
  });

  testWidgets('in Germany, nothing while driving', (tester) async {
    final plan = _plan();
    final route = plan.routes.first;
    await guide(
      tester,
      plan,
      country: (_) => 'DE',
      items: [_zoneOn(route, 1000, 1500, country: 'DE')],
    );
    await drive(tester, _drive(route, fromM: 0, toM: 1200));
    expect(find.textContaining('Zone de danger'), findsNothing);
    expect(find.textContaining('Radar'), findsNothing);
  });

  testWidgets('in Spain, the camera ahead with its limit', (tester) async {
    final plan = _plan();
    final route = plan.routes.first;
    final camera = EnforcementItem(
      id: 'camera',
      kind: EnforcementKind.camera,
      category: 'FIXED',
      country: 'ES',
      position: LineTrack(route).at(1000),
      limitKmh: 70,
    );
    await guide(tester, plan, country: (_) => 'ES', items: [camera]);
    await drive(tester, _drive(route, fromM: 0, toM: 900));
    expect(find.textContaining('Radar dans'), findsOneWidget);
    expect(find.textContaining('70 km/h'), findsOneWidget);
  });

  testWidgets('the limit for the vehicle beside the speed; over it the speed warns, and speaks '
      'only when asked', (tester) async {
    final plan = _plan();
    final route = plan.routes.first;
    await guide(tester, plan, speak: true);
    // 36 km/h on a stretch signed 30: over after 2 s, a word after 5 s.
    await drive(tester, _drive(route, fromM: 0, toM: 100));
    expect(find.bySemanticsLabel(RegExp('Limite 30')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('au-dessus de la limite')), findsOneWidget);
    expect(voice.said, contains('Vitesse limitée à 30.'));
    await drive(tester, _drive(route, fromM: 700, toM: 800));
    expect(find.bySemanticsLabel(RegExp('Limite 80')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('au-dessus de la limite')), findsNothing);
    // The road's default: an estimate, which never warns.
    await drive(tester, _drive(route, fromM: 1400, toM: 1500, kmh: 70));
    expect(find.bySemanticsLabel(RegExp('Limite estimée 50')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('au-dessus de la limite')), findsNothing);
  });

  testWidgets('a limit the user hid is neither shown nor spoken', (tester) async {
    final plan = _plan();
    await guide(tester, plan, speak: true, showLimit: false);
    await drive(tester, _drive(plan.routes.first, fromM: 0, toM: 100));
    expect(find.bySemanticsLabel(RegExp('Limite')), findsNothing);
    expect(voice.said.where((s) => s.startsWith('Vitesse')), isEmpty);
  });

  testWidgets('without the sound asked for, the excess shows and says nothing', (tester) async {
    final plan = _plan();
    await guide(tester, plan);
    await drive(tester, _drive(plan.routes.first, fromM: 0, toM: 100));
    expect(find.bySemanticsLabel(RegExp('au-dessus de la limite')), findsOneWidget);
    expect(voice.said.where((s) => s.startsWith('Vitesse')), isEmpty);
  });

  group('the danger zones on the map', () {
    final listed = EnforcementSource(
      id: 'fr-securite-routiere',
      name: 'Sécurité routière',
      attribution: 'Sécurité routière',
      fetchedAt: DateTime.utc(2026, 10, 6, 5),
    );
    EnforcementItem cited(EnforcementItem zone) => EnforcementItem(
      id: zone.id,
      kind: zone.kind,
      category: zone.category,
      country: zone.country,
      line: zone.line,
      sourceIds: [listed.id],
    );

    testWidgets('while guiding in France, the zone is a stretch of the route on the map', (
      tester,
    ) async {
      final plan = _plan();
      final route = plan.routes.first;
      await guide(tester, plan, items: [_zoneOn(route, 1000, 1500)]);
      await drive(tester, _drive(route, fromM: 0, toM: 100));
      final zones = SchematicRouteMap.last!.zones;
      expect(zones, hasLength(1));
      expect(zones.single.fromM, closeTo(1000, 15));
      expect(zones.single.toM, closeTo(1500, 15));
    });

    for (final strict in ['DE', 'CH']) {
      testWidgets('while guiding where $strict is the rule, no zone on the map', (tester) async {
        final plan = _plan();
        final route = plan.routes.first;
        await guide(tester, plan, country: (_) => strict, items: [_zoneOn(route, 1000, 1500)]);
        await drive(tester, _drive(route, fromM: 0, toM: 100));
        expect(SchematicRouteMap.last!.zones, isEmpty);
      });
    }

    /// The preview of the drive's route, read from [origin]'s country.
    Future<void> preview(WidgetTester tester, String originCountry) async {
      final plan = _plan();
      final route = plan.routes.first;
      final origin = route.line.first;
      final app = await pumpLunaway(
        tester,
        size: tallPhone,
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: FakeLocationFeed(position: origin),
          countries: FakeCountries(
            (p) => p.distanceTo(origin) < 30 ? originCountry : 'FR',
            rules: _rules,
          ),
          enforcement: FixedEnforcement(
            rules: _rules,
            items: [cited(_zoneOn(route, 1000, 1500))],
            sources: [listed],
          ),
        ),
      );
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
    }

    testWidgets('in France the preview highlights the zone, explains it and cites its list', (
      tester,
    ) async {
      await preview(tester, 'FR');
      expect(SchematicRouteMap.last!.zones, hasLength(1));
      expect(find.text('Zone de danger'), findsOneWidget, reason: 'its row of the legend');
      // At the foot of the panel, with the route's own sources.
      expect(
        find.text('Zones de danger : Sécurité routière, liste du 6 oct.', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.textContaining('Radar'), findsNothing);
    });

    testWidgets('read from Germany at rest, the preview shows the zones of France', (tester) async {
      await preview(tester, 'DE');
      expect(SchematicRouteMap.last!.zones, hasLength(1));
    });

    testWidgets('a preview opened during a guidance follows the vehicle across a border', (
      tester,
    ) async {
      final plan = _plan();
      final route = plan.routes.first;
      final start = route.line.first;
      final border = LineTrack(route).at(300).distanceTo(start);
      // France for the first 300 m, then Germany, where nothing shows while
      // driving; the preview was opened in France.
      final app = await guide(
        tester,
        plan,
        country: (p) => p.distanceTo(start) > border ? 'DE' : 'FR',
        items: [cited(_zoneOn(route, 1000, 1500))],
        sources: [listed],
      );
      await drive(tester, _drive(route, fromM: 0, toM: 100));
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      // The preview's map, the one on screen over the guidance.
      List<RouteSpan> shown() =>
          tester.widget<SchematicRouteMap>(find.byType(SchematicRouteMap)).props.zones;
      expect(shown(), hasLength(1), reason: 'in France, driving');
      await drive(tester, _drive(route, fromM: 350, toM: 420));
      expect(shown(), isEmpty, reason: 'in Germany, while driving');
    });

    for (final (name, device) in [
      ('in Switzerland', const LatLng(46.2044, 6.1432)),
      ('nowhere known', null),
    ]) {
      testWidgets('a start chosen in France, the device $name: the rule is read where the '
          'device is', (tester) async {
        final plan = _plan();
        final route = plan.routes.first;
        final app = await pumpLunaway(
          tester,
          size: tallPhone,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: FakeLocationFeed(position: device),
            countries: FakeCountries(
              (p) => p.distanceTo(const LatLng(46.2044, 6.1432)) < 1000 ? 'CH' : 'FR',
              rules: _rules,
            ),
            enforcement: FixedEnforcement(
              rules: _rules,
              items: [cited(_zoneOn(route, 1000, 1500))],
              sources: [listed],
            ),
          ),
        );
        app
            .container(tester)
            .read(chosenDepartureProvider.notifier)
            .choose(RouteDeparture(position: route.line.first, label: 'Limoges'));
        unawaited(
          app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
        );
        await settleShort(tester);
        expect(find.text('Départ : Limoges'), findsOneWidget);
        expect(SchematicRouteMap.last!.zones, isEmpty);
        expect(find.textContaining('Zones de danger', skipOffstage: false), findsNothing);
      });
    }

    for (final off in ['CH', 'MA']) {
      testWidgets('read from $off, the preview shows no zone and cites nothing', (tester) async {
        await preview(tester, off);
        expect(SchematicRouteMap.last!.zones, isEmpty);
        expect(find.text('Zone de danger'), findsNothing);
        expect(find.textContaining('Zones de danger', skipOffstage: false), findsNothing);
      });
    }
  });

  testWidgets('the limit can be hidden from the profile', (tester) async {
    final app = await pumpLunaway(
      tester,
      size: tallPhone,
      overrides: navigationOverrides(routes: FakeRouteService(const [])),
    );
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    final speedLimit = find.widgetWithText(SwitchListTile, 'Limite de vitesse');
    await tester.scrollUntilVisible(speedLimit, 200);
    // In the middle of the screen: clear of the dock.
    await Scrollable.ensureVisible(tester.element(speedLimit), alignment: 0.5);
    await settleShort(tester);
    expect(tester.widget<SwitchListTile>(speedLimit).value, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Alertes de vitesse parlées'))
          .value,
      isFalse,
      reason: 'off by default',
    );
    await tester.tap(speedLimit);
    await settleShort(tester);
    expect(tester.widget<SwitchListTile>(speedLimit).value, isFalse);
    final stored = await app.container(tester).read(drivingAidsStoreProvider).load();
    expect(stored.showSpeedLimit, isFalse);
  });
}
