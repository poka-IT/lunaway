import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_mark_focus.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_mark_layers.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_points.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../../helpers/navigation.dart';

const _destination = LatLng(43.30, 5.37);
const _origin = LatLng(43.53, 5.45);

final _station = FuelOffer(
  id: 'st1',
  position: const LatLng(43.4, 5.4),
  priceEur: 1.789,
  priceUpdatedAt: DateTime.utc(2026, 10, 7, 5),
  detourM: 0,
  detourS: 0,
  alongM: 12000,
  fuel: FuelType.diesel,
);

const _place = PlaceSummary(
  id: 'p1',
  kind: PlaceKind.motorhomeArea,
  lat: 43.45,
  lon: 5.41,
  overnight: OvernightStatus.allowed,
  name: 'Aire des Pins',
);

/// The same route as the first one, given as a variant, with its own
/// events: what the preview must not draw until it is chosen.
RouteOption _variantOf(RouteOption r) => RouteOption(
  index: 1,
  distanceM: r.distanceM + 4000,
  durationS: r.durationS + 300,
  hasToll: r.hasToll,
  hasFerry: r.hasFerry,
  hasMotorway: r.hasMotorway,
  warnings: r.warnings,
  line: r.line,
  roadEvents: r.roadEvents,
);

List<RouteMarker> _markers(Translations t, RoutePlan plan, RouteOption route) => previewMarkers(
  t: t,
  destination: _destination,
  destinationLabel: 'Vieux-Port',
  origin: _origin,
  route: route,
  plan: plan,
  points: RoutePoints(
    places: const [_place],
    stations: [_station],
    stops: const [RouteStop(position: LatLng(43.42, 5.42), label: 'Pause')],
  ).markers(t),
);

void main() {
  test("the route's badges keep their place: a town's name under them is left out", () {
    final badges = [
      for (final layer in RouteMarkStyle.jsonLayers())
        if ((layer['id']! as String).endsWith(RouteLayers.badgesOf(''))) layer,
    ];
    expect(badges, isNotEmpty);
    for (final layer in badges) {
      final layout = layer['layout']! as Map<String, Object?>;
      expect(layout['icon-ignore-placement'], isFalse, reason: '${layer['id']}');
      expect(layout['text-ignore-placement'], isFalse, reason: '${layer['id']}');
      expect(layout['icon-allow-overlap'], isTrue, reason: 'always drawn');
    }
  });

  late Translations fr;
  late Translations en;
  setUp(() async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
    fr = await AppLocale.fr.build();
    en = await AppLocale.en.build();
  });

  group('every mark says what it is', () {
    test('the road events take the badge of their class, lanes closed drawn small', () {
      final plan = routeFixture('aix_marseille_closures');
      final route = plan.routes.first;
      final marks = [for (final m in _markers(fr, plan, route)) m.mark];
      final met = {
        for (final e in route.roadEvents)
          e.event.eventClass.name: marks.singleWhere(
            (m) => m.id == eventMarkId(route.index, e.event.id),
          ),
      };
      expect(met['laneRestriction']!.kind, RouteMarkKind.lanes);
      expect(met['laneRestriction']!.badge, RouteBadge.lanes);
      expect(met['laneRestriction']!.minor, isTrue);
      expect(met['closure']!.kind, RouteMarkKind.closure);
      expect(met['closure']!.badge, RouteBadge.closure);
      expect(met['closure']!.minor, isFalse);
      // "INFO": works beside the road, not about the vehicle.
      expect(met['works']!.kind, RouteMarkKind.works);
      expect(met['works']!.minor, isTrue);
      final avoided = marks.where((m) => m.id.startsWith('avoided:')).toList();
      expect(avoided, hasLength(2));
      expect(avoided.map((m) => m.badge), everyElement(RouteBadge.closure));
    });

    test('the ends, the stop, the station and the place each have their own badge', () {
      final plan = routeFixture('aix_marseille_closures');
      final marks = {for (final m in _markers(fr, plan, plan.routes.first)) m.id: m.mark};
      expect(marks['origin']!.badge, RouteBadge.origin);
      expect(marks['destination']!.badge, RouteBadge.destination);
      expect(marks['stop:0']!.badge, RouteBadge.stop);
      expect(marks['stop:0']!.label, '1', reason: 'stops are numbered');
      expect(marks['poi:st1']!.badge, RouteBadge.fuel);
      expect(marks['poi:st1']!.side, '1,789 €', reason: 'the price beside the pump');
      expect(marks['place:p1']!.badge, RouteBadge.place(PlaceKind.motorhomeArea));
      expect(marks['place:p1']!.minor, isTrue);
      final anonymous = marks.values.where((m) => !RouteBadge.all.contains(m.badge));
      expect(anonymous, isEmpty, reason: 'every badge has its image in the style');
    });

    test('a limit is its sign, heavier when the vehicle cannot pass, its figure beside', () {
      final plan = routeFixture('utrillo_van');
      final route = plan.routes.first;
      final warning = route.warnings.single;
      final passes = warningMarker('w', warning, fr).mark;
      expect(passes.kind, RouteMarkKind.clearance);
      expect(passes.badge, RouteBadge.sign(SignGlyph.height));
      expect(passes.side, '2,70 m');
      final stops = warningMarker('b', warning, fr, blocking: true).mark;
      expect(stops.badge, RouteBadge.sign(SignGlyph.height, blocking: true));
      expect(warningMarkKind(RouteWarningKind.tooHeavy), RouteMarkKind.weight);
      expect(warningMarkKind(RouteWarningKind.narrow), RouteMarkKind.limit);
    });

    test("a variant's marks stay off the map until it is chosen", () {
      final plan = routeFixture('aix_marseille_closures');
      final first = plan.routes.first;
      final variant = _variantOf(first);
      final onFirst = _markers(fr, plan, first).map((m) => m.id);
      expect(onFirst.where((id) => id.startsWith('event:1:')), isEmpty);
      expect(onFirst.where((id) => id.startsWith('event:0:')), hasLength(4));
      final onVariant = _markers(fr, plan, variant).map((m) => m.id);
      expect(onVariant.where((id) => id.startsWith('event:1:')), hasLength(4));
      expect(onVariant.where((id) => id.startsWith('event:0:')), isEmpty);
    });

    test('the tooltip of a road event: kind, road, distance, source and age of the data', () {
      final plan = routeFixture('aix_marseille_closures');
      final route = plan.routes.first;
      final lanes = route.roadEvents.firstWhere(
        (e) => e.event.eventClass.name == 'laneRestriction',
      );
      final marker = _markers(
        fr,
        plan,
        route,
      ).singleWhere((m) => m.id == eventMarkId(route.index, lanes.event.id));
      final words = markWords(
        marker,
        fr,
        units: DistanceUnits.metric,
        now: DateTime.utc(2026, 10, 6, 21),
        plan: plan,
      );
      expect(words.category, 'Voies réduites');
      expect(words.title, 'A51 · Voies réduites');
      expect(words.lines.single, startsWith('à '));
      expect(words.lines.single, endsWith(' du départ'));
      expect(words.source, contains('DIR'));
      expect(words.source, contains('données de'));
      final english = markWords(
        marker,
        en,
        units: DistanceUnits.metric,
        now: DateTime.utc(2026, 10, 6, 21),
        plan: plan,
      );
      expect(english.category, 'Lanes closed');
      expect(english.lines.single, endsWith('from the start'));
    });
  });

  group('the speed cameras', () {
    final list = EnforcementSource(
      id: 'securite-routiere',
      name: 'Sécurité routière',
      attribution: 'Sécurité routière',
      fetchedAt: DateTime.utc(2026, 10, 6, 5),
    );
    CameraOnRoute camera(
      String id, {
      int? limit = 90,
      String category = 'FIXED',
      double? bearing,
      List<LatLng> line = const [],
    }) => CameraOnRoute(
      onRoute: ItemOnRoute(
        item: EnforcementItem(
          id: id,
          kind: EnforcementKind.camera,
          category: category,
          country: 'ES',
          position: const LatLng(43.41, 5.41),
          bearingDeg: bearing,
          limitKmh: limit,
          line: line,
        ),
        startM: 12000,
        endM: line.isEmpty ? 12000 : 17200,
      ),
      sources: [list],
    );

    test('a camera is its own badge, its limit beside it, in the units of the user', () {
      final mark = cameraMarker(camera('c'), fr, units: DistanceUnits.metric)!.mark;
      expect(mark.id, 'camera:c');
      expect(mark.kind, RouteMarkKind.camera);
      expect(mark.badge, RouteBadge.camera);
      expect(mark.side, '90 km/h');
      expect(RouteBadge.all, contains(RouteBadge.camera), reason: 'its image in the style');
      expect(cameraMarker(camera('c'), en, units: DistanceUnits.imperial)!.mark.side, '56 mph');
      expect(
        cameraMarker(camera('n', limit: null), fr, units: DistanceUnits.metric)!.mark.side,
        isNull,
      );
      expect(RouteMarkKind.camera.tone, MarkTone.caution);
    });

    test("the marks reach the maps' pages as the others do: badge, kind and limit", () {
      final plan = routeFixture('aix_marseille_closures');
      final route = plan.routes.first;
      final markers = previewMarkers(
        t: fr,
        destination: _destination,
        points: const [],
        route: route,
        plan: plan,
        cameras: [camera('c')],
      );
      final sources = routeMarkSources([for (final m in markers) m.mark]);
      final features = [
        for (final f in sources[RouteLayers.marksSource]!['features']! as List<Object?>)
          (f! as Map<String, Object?>)['properties']! as Map<String, Object?>,
      ];
      final props = features.singleWhere((p) => p['mark'] == 'camera:c');
      expect(props['badge'], RouteBadge.camera.id);
      expect(props['kind'], 'camera');
      expect(props['side'], '90 km/h');
      expect(RouteMarkStyle.clusterProperties.keys, contains('n_camera'));
    });

    test("a variant's cameras stay off the map: only the route chosen has them", () {
      final plan = routeFixture('aix_marseille_closures');
      final ids = previewMarkers(
        t: fr,
        destination: _destination,
        points: const [],
        plan: plan,
        cameras: [camera('c')],
      ).map((m) => m.id);
      expect(ids, isNot(contains('camera:c')));
    });

    test("a camera's card: its kind and limit, where, its direction when known, its list", () {
      final words = markWords(
        cameraMarker(camera('c', bearing: 92), fr, units: DistanceUnits.metric)!,
        fr,
        units: DistanceUnits.metric,
        now: DateTime.utc(2026, 10, 9),
      );
      expect(words.category, 'Radar');
      expect(words.title, 'Radar fixe · 90 km/h');
      expect(words.lines, ['à 12 km du départ', 'Contrôle votre sens de circulation']);
      expect(words.source, 'Sécurité routière, liste du 6 oct.');
      final section = markWords(
        cameraMarker(
          camera(
            's',
            limit: 110,
            category: 'SECTION_CONTROL',
            line: const [LatLng(43.41, 5.41), LatLng(43.45, 5.45)],
          ),
          fr,
          units: DistanceUnits.metric,
        )!,
        fr,
        units: DistanceUnits.metric,
        now: DateTime.utc(2026, 10, 9),
      );
      expect(section.title, 'Radar tronçon · moyenne 110 km/h');
      expect(section.lines, contains('Tronçon de 5,2 km'));
      expect(section.lines, isNot(contains('Contrôle votre sens de circulation')));
    });

    test('the legend has the row of the cameras with how many there are', () {
      final rows = legendRows([
        for (final id in ['a', 'b', 'c'])
          cameraMarker(camera(id), fr, units: DistanceUnits.metric)!.mark,
      ]);
      expect(rows.first.kind, RouteMarkKind.camera);
      expect(legendText(fr, rows.first), '3 radars');
      expect(legendText(en, rows.first), '3 speed cameras');
      expect(
        legendText(
          fr,
          legendRows([cameraMarker(camera('a'), fr, units: DistanceUnits.metric)!.mark]).first,
        ),
        '1 radar',
      );
    });
  });

  group('marks close together gather', () {
    test('the ends and stops are never grouped, minor marks apart from the others', () {
      final plan = routeFixture('aix_marseille_closures');
      final markers = _markers(fr, plan, plan.routes.first);
      final sources = routeMarkSources([for (final m in markers) m.mark]);
      List<Object?> ids(String source) => [
        for (final f in sources[source]!['features']! as List<Object?>)
          ((f! as Map<String, Object?>)['properties']! as Map<String, Object?>)['mark'],
      ];
      expect(ids(RouteLayers.anchorsSource), containsAll(['origin', 'destination', 'stop:0']));
      expect(ids(RouteLayers.minorSource), contains('place:p1'));
      expect(ids(RouteLayers.marksSource), contains('poi:st1'));
      expect(ids(RouteLayers.marksSource), isNot(contains('place:p1')));
      expect(RouteMarkStyle.sourceOptions(RouteLayers.anchorsSource), isEmpty);
      for (final line in [RouteLayers.routeSource, RouteLayers.alternativesSource]) {
        expect(RouteMarkStyle.sourceOptions(line), isEmpty, reason: 'a grouped line draws nothing');
      }
      for (final s in [RouteLayers.marksSource, RouteLayers.minorSource]) {
        expect(RouteMarkStyle.sourceOptions(s)['cluster'], isTrue);
      }
    });

    test('a group counts its marks by kind, takes the tone of the most pressing one', () {
      final counts = RouteMarkStyle.clusterProperties;
      expect(counts['top'], [
        'max',
        ['get', 'rank'],
      ]);
      expect(counts.keys, containsAll(['n_works', 'n_closure', 'n_lanes', 'n_place']));
      expect(counts.keys, isNot(contains('n_origin')), reason: 'the ends are never grouped');
      final group = RouteMarkStyle.groupCounts({
        'point_count': 3,
        'n_works': 2,
        'n_closure': 1,
        'n_place': 0,
      });
      expect(group, {RouteMarkKind.works: 2, RouteMarkKind.closure: 1});
      final words = groupWords(fr, group);
      expect(words.category, '3 repères');
      expect(words.title, 'Route fermée : 1 · Travaux : 2', reason: 'the most pressing first');
      expect(groupWords(en, group).title, 'Road closed: 1 · Works: 2');
      expect(RouteMarkKind.closure.tone, MarkTone.alert);
      expect(RouteMarkKind.works.tone, MarkTone.caution);
      expect(RouteMarkKind.place.tone, MarkTone.info);
      expect(RouteBadge.all, contains(RouteBadge.cluster(MarkTone.alert)));
    });

    test('a lit mark under the mouse wears the hover ring alone', () {
      // The subset of the style's expressions the halo's opacity uses,
      // evaluated as MapLibre does for a feature in [state].
      Object? eval(Object? e, Map<String, bool> state) {
        if (e is! List) return e;
        switch (e.first) {
          case 'case':
            for (var i = 1; i + 1 < e.length; i += 2) {
              if (eval(e[i], state) == true) return eval(e[i + 1], state);
            }
            return eval(e.last, state);
          case 'boolean':
            final v = eval(e[1], state);
            return v is bool ? v : e[2];
          case 'feature-state':
            return state[e[1]];
        }
        throw UnsupportedError('$e');
      }

      double opacity(Map<String, bool> state) =>
          (eval(RouteMarkStyle.haloOpacity, state)! as num).toDouble();
      expect(opacity(const {}), 0);
      expect(opacity(const {'lit': true}), 1, reason: 'lit by its row, or chosen');
      expect(
        opacity(const {'lit': true, 'hover': true}),
        0,
        reason: 'the hover ring stands for it',
      );
      expect(opacity(const {'hover': true}), 0);
    });

    test('a mark under the mouse on the map lights its row, not its ring; a chosen one stays '
        'lit', () {
      final container = ProviderContainer.test();
      final provider = routeMarkFocusProvider(const RouteTarget(destination: _destination));
      container.read(provider.notifier)
        ..select('chosen')
        ..hover({'pointed'}, onMap: true);
      expect(container.read(provider).lit, {'chosen', 'pointed'}, reason: 'the rows');
      expect(container.read(provider).litOnMap, {'chosen'}, reason: 'the map rings its own hover');
      container.read(provider.notifier).hover({'pointed'});
      expect(container.read(provider).litOnMap, {'chosen', 'pointed'}, reason: 'through its row');
      container.read(provider.notifier).leave({'pointed'});
      expect(container.read(provider).litOnMap, {'chosen'});
    });

    test('a feature id names its mark, never a group of the same source', () {
      expect(routeMarkIndex(routeMarkFeatureId(7)), 7);
      expect(routeMarkIndex('${routeMarkFeatureId(3)}'), 3);
      expect(routeMarkIndex(12), isNull, reason: 'a group id from MapLibre');
    });
  });

  group('the legend', () {
    test('lists only the kinds on this route, in a fixed order, then the groups', () {
      final plan = routeFixture('aix_marseille_closures');
      final rows = legendRows([for (final m in _markers(fr, plan, plan.routes.first)) m.mark]);
      expect(rows.map((r) => r.kind), [
        RouteMarkKind.origin,
        RouteMarkKind.destination,
        RouteMarkKind.stop,
        RouteMarkKind.closure,
        RouteMarkKind.works,
        RouteMarkKind.lanes,
        RouteMarkKind.fuel,
        RouteMarkKind.place,
        null,
      ]);
      expect(rows.first.badge, RouteBadge.origin);
      expect(rows.last.badge, RouteBadge.cluster(MarkTone.alert));
    });

    test('a route without marks along it has the ends only, and no group', () {
      final rows = legendRows([
        const RouteMapMark(
          id: 'origin',
          position: _origin,
          kind: RouteMarkKind.origin,
          badge: RouteBadge.origin,
        ),
        const RouteMapMark(
          id: 'destination',
          position: _destination,
          kind: RouteMarkKind.destination,
          badge: RouteBadge.destination,
        ),
      ]);
      expect(rows.map((r) => r.kind), [RouteMarkKind.origin, RouteMarkKind.destination]);
      expect(markKindName(fr, RouteMarkKind.clearance), 'Hauteur limitée');
      expect(markKindName(en, RouteMarkKind.clearance), 'Height limit');
    });
  });
}
