import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_marks_overlay.dart';
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
    Set<String> exactIn = const {},
    Size size = tallPhone,
    double textScale = 1,
  }) async {
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    voice = RecordingVoice();
    final app = await pumpLunaway(
      tester,
      size: size,
      textScale: textScale,
      overrides: navigationOverrides(
        routes: FakeRouteService([plan]),
        feed: feed,
        voice: voice,
        engine: LineEngine([plan]),
        countries: FakeCountries(country ?? (_) => 'FR', rules: _rules),
        enforcement: FixedEnforcement(rules: _rules, items: items, sources: sources),
        drivingAids: memoryDrivingAids(DrivingAidsSettings(exactIn: exactIn)),
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
    final banner = find.byType(EnforcementNotice);
    expect(find.descendant(of: banner, matching: find.text('Zone de danger')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Zone de danger dans \d+ m')), findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.byType(RouteBadgeView)),
      findsNothing,
      reason: 'a warning sign, never a camera',
    );
    // The French list is cited with its date, as its reuse requires.
    expect(find.text('Sécurité routière, liste du 6 oct.'), findsOneWidget);
    await drive(tester, _drive(route, fromM: 760, toM: 1200));
    expect(find.descendant(of: banner, matching: find.textContaining('encore')), findsOneWidget);
    expect(find.textContaining('Radar'), findsNothing, reason: 'France: zones only');
    expect(
      SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.camera),
      isEmpty,
      reason: 'nor a camera on the map',
    );
    await drive(tester, _drive(route, fromM: 1210, toM: 1560));
    expect(find.text('Fin de la zone de danger'), findsOneWidget);
    await drive(tester, _drive(route, fromM: 1570, toM: 1700));
    expect(find.textContaining('Zone de danger'), findsNothing);
    expect(find.text('Fin de la zone de danger'), findsNothing, reason: 'told for 4 s');
    expect(voice.said.where((s) => s.contains('Zone de danger')), [
      'Zone de danger dans 400 mètres.',
    ], reason: 'an alert, said once in the full voice, the speed reminders off');
    expect(voice.calls.where((c) => c.text.contains('Zone de danger')).single.chime, isTrue);
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

  testWidgets('in Germany, nothing at all', (tester) async {
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
    final banner = find.byType(EnforcementNotice);
    expect(find.descendant(of: banner, matching: find.text('Radar fixe')), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('70')), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.byType(RouteBadgeView)), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Radar fixe dans \d+ m, limite 70 km/h\.$')),
      findsOneWidget,
    );
    final mark = SchematicRouteMap.last!.marks.singleWhere((m) => m.kind == RouteMarkKind.camera);
    expect(mark.badge, RouteBadge.camera);
    expect(mark.side, '70 km/h');
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

    testWidgets('read from Germany at rest, the preview shows nothing: a stop at a light counts '
        'as driving there', (tester) async {
      await preview(tester, 'DE');
      expect(SchematicRouteMap.last!.zones, isEmpty);
      expect(find.textContaining('Zones de danger', skipOffstage: false), findsNothing);
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

    // With a start chosen, the device is not asked where it is: the
    // position the map located this run, if any, reads the rule.
    for (final (name, device) in [
      ('located in Switzerland', const LatLng(46.2044, 6.1432)),
      ('not located', null),
    ]) {
      testWidgets('a start chosen in France, the device $name: the rule is read where the '
          'device is', (tester) async {
        final feed = FakeLocationFeed(position: const LatLng(46.2044, 6.1432));
        final plan = _plan();
        final route = plan.routes.first;
        final app = await pumpLunaway(
          tester,
          size: tallPhone,
          overrides: navigationOverrides(
            routes: FakeRouteService([plan]),
            feed: feed,
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
        app.container(tester).read(userLocationProvider.notifier).update(device);
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
        expect(feed.currentAsked, 0, reason: 'a trip planned from elsewhere asks no position');
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
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Rappel vocal de la limite'))
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

  group('the speed cameras', () {
    final listed = EnforcementSource(
      id: 'fr-securite-routiere',
      name: 'Sécurité routière',
      attribution: 'Sécurité routière',
      fetchedAt: DateTime.utc(2026, 10, 6, 5),
    );

    EnforcementItem camera(
      RouteOption route,
      double at, {
      String country = 'FR',
      int? limit = 70,
      String category = 'FIXED',
    }) => EnforcementItem(
      id: 'camera-$country-$at',
      kind: EnforcementKind.camera,
      category: category,
      country: country,
      position: LineTrack(route).at(at),
      limitKmh: limit,
      sourceIds: [listed.id],
    );

    Iterable<RouteMapMark> cameraMarks() =>
        SchematicRouteMap.last!.marks.where((m) => m.kind == RouteMarkKind.camera);

    testWidgets('France with its positions asked for: the camera on the map, in the banner, on '
        'its card', (tester) async {
      final plan = _plan();
      final route = plan.routes.first;
      final item = camera(route, 1000);
      await guide(tester, plan, items: [item], sources: [listed], exactIn: {'FR'});
      await drive(tester, _drive(route, fromM: 0, toM: 750));
      final banner = find.byType(EnforcementNotice);
      expect(find.descendant(of: banner, matching: find.text('Radar fixe')), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('70')), findsOneWidget);
      final mark = cameraMarks().single;
      expect(mark.id, 'camera:${item.id}');
      expect(mark.side, '70 km/h');
      SchematicRouteMap.last!.onMarkTap!(mark.id);
      await settleShort(tester);
      final card = find.byType(MarkCard);
      expect(
        find.descendant(of: card, matching: find.text('Radar fixe · 70 km/h')),
        findsOneWidget,
      );
      expect(find.descendant(of: card, matching: find.text('Radar')), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Sécurité routière, liste du 6 oct.')),
        findsOneWidget,
      );
    });

    testWidgets('the choice made during a trip asks for the data at once, not at the next poll', (
      tester,
    ) async {
      final plan = _plan();
      final route = plan.routes.first;
      final enforcement = FixedEnforcement(rules: _rules, sources: [listed]);
      feed = FakeLocationFeed(position: route.line.first);
      final app = await pumpLunaway(
        tester,
        size: tallPhone,
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: feed,
          engine: LineEngine([plan]),
          countries: FakeCountries((_) => 'FR', rules: _rules),
          enforcement: enforcement,
        ),
      );
      final container = app.container(tester);
      await container
          .read(guidanceControllerProvider.notifier)
          .start(
            plan: plan,
            routeIndex: route.index,
            target: utrillo,
            words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
          );
      await settleShort(tester);
      final before = enforcement.asked.length;
      await container
          .read(drivingAidsSettingsControllerProvider.notifier)
          .setExactPositions('FR', on: true);
      await settleShort(tester);
      expect(enforcement.asked.length, before + 1);
      container.read(guidanceControllerProvider.notifier).stop();
    });

    testWidgets('France by default: no camera on the map nor in the banner', (tester) async {
      final plan = _plan();
      final route = plan.routes.first;
      await guide(tester, plan, items: [camera(route, 1000)], sources: [listed]);
      await drive(tester, _drive(route, fromM: 0, toM: 1100));
      expect(cameraMarks(), isEmpty);
      expect(find.byType(EnforcementNotice), findsNothing);
    });

    testWidgets("over the camera's limit the banner says so, to the eye and to the screen "
        'reader', (tester) async {
      final plan = _plan();
      final route = plan.routes.first;
      await guide(
        tester,
        plan,
        country: (_) => 'ES',
        items: [camera(route, 500, country: 'ES', limit: 30)],
      );
      await drive(tester, _drive(route, fromM: 100, toM: 400, kmh: 50));
      final banner = find.byType(EnforcementNotice);
      expect(
        find.descendant(of: banner, matching: find.text('au-dessus de la limite')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'limite 30 km/h, au-dessus de la limite\.$')),
        findsOneWidget,
      );
      final material = tester.widget<Material>(
        find.descendant(of: banner, matching: find.byType(Material)).first,
      );
      expect(material.color, Theme.of(tester.element(banner)).colorScheme.error);
    });

    testWidgets('into Switzerland, the rule is told calmly for a few seconds', (tester) async {
      final plan = _plan();
      final route = plan.routes.first;
      final start = route.line.first;
      final border = LineTrack(route).at(600).distanceTo(start);
      await guide(tester, plan, country: (p) => p.distanceTo(start) > border ? 'CH' : 'ES');
      const told = "Suisse : pas d'alerte radar";
      await drive(tester, _drive(route, fromM: 0, toM: 580));
      expect(find.text(told), findsNothing);
      await drive(tester, _drive(route, fromM: 610, toM: 640));
      expect(find.text(told), findsOneWidget);
      await drive(tester, _drive(route, fromM: 650, toM: 800));
      expect(find.text(told), findsNothing);
    });

    for (final (name, size) in [
      ('a phone held upright', const Size(400, 860)),
      ('a phone on its side', const Size(860, 400)),
      ('a tablet upright', const Size(800, 1280)),
      ('a tablet on its side', const Size(1280, 800)),
      ('a desktop', const Size(1440, 900)),
    ]) {
      testWidgets('on $name with large text, a section and its average fit the banner', (
        tester,
      ) async {
        final plan = _plan();
        final route = plan.routes.first;
        final track = LineTrack(route);
        final section = EnforcementItem(
          id: 'section',
          kind: EnforcementKind.camera,
          category: 'SECTION_CONTROL',
          country: 'ES',
          position: track.at(200),
          line: [for (var m = 200.0; m <= 1500; m += 50) track.at(m)],
          limitKmh: 30,
          sourceIds: [listed.id],
        );
        // The banner's own errors only: the map screen under the guidance
        // has large-text overflows of its own, outside this test.
        final original = FlutterError.onError;
        final banners = <String>[];
        FlutterError.onError = (details) {
          final text = details.toString();
          if (text.contains('enforcement_notice.dart') || text.contains('speed_sign.dart')) {
            banners.add(text);
          }
        };
        await guide(
          tester,
          plan,
          country: (_) => 'ES',
          items: [section],
          sources: [listed],
          size: size,
          textScale: 2,
        );
        await drive(tester, _drive(route, fromM: 0, toM: 600, kmh: 50));
        FlutterError.onError = original;
        expect(banners, isEmpty);
        final banner = find.byType(EnforcementNotice, skipOffstage: false);
        expect(banner, findsOneWidget);
        expect(
          find.descendant(of: banner, matching: find.text('Radar tronçon', skipOffstage: false)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: banner,
            matching: find.textContaining('votre moyenne', skipOffstage: false),
          ),
          findsOneWidget,
        );
        final box = tester.getRect(banner);
        for (final text in tester.widgetList<Text>(
          find.descendant(of: banner, matching: find.byType(Text), skipOffstage: false),
        )) {
          final at = tester.getRect(find.byWidget(text, skipOffstage: false));
          expect(
            box.contains(at.topLeft) && box.contains(at.bottomRight - const Offset(1, 1)),
            isTrue,
          );
        }
      });
    }

    /// The preview of the drive's route read from [device]'s country,
    /// [exactIn] asked.
    Future<TestApp> preview(
      WidgetTester tester, {
      required List<EnforcementItem> Function(RouteOption) items,
      Set<String> exactIn = const {},
      String device = 'FR',
    }) async {
      final plan = _plan();
      final route = plan.routes.first;
      final origin = route.line.first;
      final app = await pumpLunaway(
        tester,
        size: tallPhone,
        overrides: navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: FakeLocationFeed(position: origin),
          countries: FakeCountries((p) => p.distanceTo(origin) < 30 ? device : 'FR', rules: _rules),
          enforcement: FixedEnforcement(rules: _rules, items: items(route), sources: [listed]),
          drivingAids: memoryDrivingAids(DrivingAidsSettings(exactIn: exactIn)),
        ),
      );
      unawaited(
        app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(utrillo)),
      );
      await settleShort(tester);
      return app;
    }

    testWidgets("the preview with France's positions asked for: the marks, their legend row "
        'with the count, a card, the list cited', (tester) async {
      await preview(
        tester,
        items: (route) => [camera(route, 1000), camera(route, 2000, limit: null)],
        exactIn: {'FR'},
      );
      expect(cameraMarks(), hasLength(2));
      expect(find.text('2 radars'), findsOneWidget, reason: 'its row of the legend');
      expect(
        find.text('Radars : Sécurité routière, liste du 6 oct.', skipOffstage: false),
        findsOneWidget,
      );
      final mark = cameraMarks().firstWhere((m) => m.side != null);
      SchematicRouteMap.last!.onMarkTap!(mark.id, at: const Offset(200, 300));
      await settleShort(tester);
      expect(find.text('Radar fixe · 70 km/h'), findsOneWidget);
      expect(find.textContaining('du départ'), findsOneWidget);
    });

    testWidgets('the preview in France by default: no camera, its zone only', (tester) async {
      await preview(tester, items: (route) => [camera(route, 1000), _zoneOn(route, 2000, 2500)]);
      expect(cameraMarks(), isEmpty);
      expect(find.textContaining('radar'), findsNothing);
      expect(SchematicRouteMap.last!.zones, hasLength(1));
    });

    testWidgets('the preview read from Germany shows no camera of the route, even of a country '
        'that allows them', (tester) async {
      await preview(
        tester,
        items: (route) => [camera(route, 1000, country: 'ES')],
        device: 'DE',
      );
      expect(cameraMarks(), isEmpty);
    });

    testWidgets('the setting of the positions in France: off by default, the law under it, and '
        'withdrawn, what the device holds of them goes', (tester) async {
      final enforcement = FixedEnforcement(rules: _rules);
      final app = await pumpLunaway(
        tester,
        size: tallPhone,
        overrides: navigationOverrides(
          routes: FakeRouteService(const []),
          enforcement: enforcement,
        ),
      );
      await tester.tap(find.text('Profil').last);
      await settleShort(tester);
      final exact = find.widgetWithText(SwitchListTile, 'Position exacte des radars en France');
      await tester.scrollUntilVisible(exact, 200);
      await Scrollable.ensureVisible(tester.element(exact), alignment: 0.5);
      await settleShort(tester);
      expect(tester.widget<SwitchListTile>(exact).value, isFalse);
      expect(
        find.descendant(
          of: exact,
          matching: find.text(
            'En France, détenir un appareil qui signale la position des radars est puni de '
            "1 500 € d'amende et 6 points (Code de la route, art. R413-15).",
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(exact);
      await settleShort(tester);
      final store = app.container(tester).read(drivingAidsStoreProvider);
      expect((await store.load()).exactIn, {'FR'});
      expect(find.byType(AlertDialog), findsNothing, reason: 'one gesture, no confirmation');
      expect(enforcement.purged, 0);
      await tester.tap(exact);
      await settleShort(tester);
      expect((await store.load()).exactIn, isEmpty);
      expect(enforcement.purged, 1);
    });
  });
}
