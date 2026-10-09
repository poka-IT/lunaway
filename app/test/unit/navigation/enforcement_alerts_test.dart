import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';

import '../../helpers/navigation.dart';

/// A straight road east, a point every 50 m over 10 km.
final List<LatLng> _road = [for (var i = 0; i <= 200; i++) _at(i * 50.0)];

/// The point [m] metres along [_road].
LatLng _at(double m) => LatLng(45.8336, 1.2611 + m / 77650);

/// The rules of these tests, written out: the table the server sends moves
/// with its reviews, the behaviour under a rule does not.
const _rules = EnforcementRules(
  version: 2,
  countries: {
    'FR': EnforcementMode.zones,
    'ES': EnforcementMode.exact,
    'DE': EnforcementMode.offWhileDriving,
    'CH': EnforcementMode.off,
    'IT': EnforcementMode.zones,
    'AD': EnforcementMode.exact,
    'MC': EnforcementMode.off,
    'SM': EnforcementMode.off,
  },
  optIn: {'FR': EnforcementMode.exact},
);

final _list = EnforcementSource(
  id: 'securite-routiere',
  name: 'Sécurité routière',
  attribution: 'Sécurité routière, radars.securite-routiere.gouv.fr',
  fetchedAt: DateTime.utc(2026, 10, 9, 5),
);

EnforcementItem _zone(String id, double from, double to, {String country = 'FR'}) =>
    EnforcementItem(
      id: id,
      kind: EnforcementKind.zone,
      category: 'FIXED',
      country: country,
      line: [for (var m = from; m <= to; m += 50) _at(m)],
      sourceIds: [_list.id],
    );

EnforcementItem _camera(
  String id,
  double at, {
  String country = 'ES',
  String category = 'FIXED',
  int? limit,
}) => EnforcementItem(
  id: id,
  kind: EnforcementKind.camera,
  category: category,
  country: country,
  position: _at(at),
  limitKmh: limit,
  sourceIds: [_list.id],
);

EnforcementItem _section(String id, double from, double to, {int? limit, String country = 'ES'}) =>
    EnforcementItem(
      id: id,
      kind: EnforcementKind.camera,
      category: 'SECTION_CONTROL',
      country: country,
      position: _at(from),
      line: [for (var m = from; m <= to; m += 50) _at(m)],
      limitKmh: limit,
      sourceIds: [_list.id],
    );

RouteOption _route({List<SpeedLimitSpan>? limits, List<LatLng>? line}) => RouteOption(
  index: 0,
  distanceM: 10000,
  durationS: 600,
  hasToll: false,
  hasFerry: false,
  hasMotorway: false,
  warnings: const [],
  line: line ?? _road,
  speedLimits: limits,
);

/// The limit for the vehicle over the whole road.
List<SpeedLimitSpan> _limit(int kmh, {SpeedLimitSource source = SpeedLimitSource.posted}) => [
  SpeedLimitSpan(fromM: 0, toM: 10000, kmh: kmh, source: source),
];

final _t0 = DateTime.utc(2026, 10, 9, 9);

/// A guidance on [_road]: fixes driven one at a time, the clock moving
/// with them.
final class _Drive {
  new({
    String? Function(LatLng)? country,
    List<String> Function(LatLng)? near,
    List<EnforcementItem> items = const [],
    this.settings = const DrivingAidsSettings(),
    List<SpeedLimitSpan>? limits,
  }) : route = _route(limits: limits) {
    engine = DrivingAidsEngine(
      locator: FakeCountries(country ?? (_) => 'FR', near: near, rules: _rules),
      choices: () => settings,
    )..setData(rules: _rules, items: items, sources: [_list]);
  }

  late final DrivingAidsEngine engine;
  DrivingAidsSettings settings;
  RouteOption route;
  DateTime at = _t0;
  final List<AidCall> said = [];

  /// One fix at [m], [seconds] after the last one.
  DrivingAids fix(double m, {double kmh = 50, double seconds = 1, double accuracy = 5}) {
    at = at.add(Duration(milliseconds: (seconds * 1000).round()));
    final aids = engine.update(
      fix: Fix(position: _at(m), accuracyM: accuracy, at: at, speedMps: kmh / 3.6),
      snap: GuidanceSnapshot(
        status: GuidanceStatus.navigating,
        position: _at(m),
        stepIndex: 0,
        distanceToManeuverM: 100,
        distanceRemainingM: 10000 - m,
        durationRemainingS: 100,
        distanceAlongM: m,
      ),
      route: route,
      totalWeightT: 3.5,
    );
    said.addAll(aids.calls);
    return aids;
  }

  /// Fixes from [from] to [to] at [kmh], one a second; the last aids.
  DrivingAids drive(double from, double to, {double kmh = 50}) {
    final step = kmh / 3.6;
    var aids = fix(from, kmh: kmh);
    for (var m = from + step; m <= to; m += step) {
      aids = fix(m, kmh: kmh);
    }
    return aids;
  }

  List<AidWord> get words => [for (final c in said) c.word];
}

void main() {
  group('France', () {
    final items = [_zone('zone', 2000, 2600), _camera('fr-camera', 4000, country: 'FR', limit: 90)];

    test('by default a zone and never a camera, not even on the map', () {
      final d = _Drive(items: items);
      final aids = d.drive(1500, 2100);
      expect(aids.alert!.kind, EnforcementKind.zone);
      expect(aids.alert!.category, isNull, reason: 'a zone says no kind of camera');
      expect(aids.cameras, isEmpty);
      final later = d.drive(3500, 4020);
      expect(later.alert, isNull, reason: 'the French camera stays a secret');
      expect(d.words, [AidWord.zone]);
    });

    test('with its positions asked for, the camera with its kind and limit, on the map too', () {
      final d = _Drive(
        items: items,
        settings: const DrivingAidsSettings(exactIn: {'FR'}),
      );
      final aids = d.drive(3500, 3700);
      expect(aids.mode, EnforcementMode.exact);
      expect(aids.alert!.kind, EnforcementKind.camera);
      expect(aids.alert!.category, CameraCategory.fixed);
      expect(aids.alert!.limitKmh, 90);
      expect(aids.alert!.cameraLimit, isTrue);
      expect(aids.alert!.sources.single.id, _list.id);
      expect(aids.cameras.map((c) => c.item.id), ['fr-camera']);
    });

    test('the choice made on the way: zones for 30 s more, then the camera; no rule told', () {
      final d = _Drive(items: items)
        ..drive(2900, 3200)
        ..settings = const DrivingAidsSettings(exactIn: {'FR'});
      final soon = d.drive(3210, 3500);
      expect(soon.mode, EnforcementMode.zones, reason: 'a looser rule waits its 30 s');
      expect(soon.alert, isNull);
      final later = d.drive(3510, 3990, kmh: 20);
      expect(later.mode, EnforcementMode.exact);
      expect(later.alert!.id, 'fr-camera');
      expect(later.ruleChange, isNull, reason: 'no border was crossed');
    });

    test('the choice made near a border tells no rule either', () {
      // In Spain, France within a kilometre all along.
      final d = _Drive(country: (_) => 'ES', near: (_) => const ['ES', 'FR'])
        ..drive(1000, 1500)
        ..settings = const DrivingAidsSettings(exactIn: {'FR'});
      var told = false;
      for (var m = 1510.0; m < 3000; m += 14) {
        if (d.fix(m).ruleChange != null) told = true;
      }
      expect(d.fix(3010).mode, EnforcementMode.exact);
      expect(told, isFalse);
    });

    test('the choice withdrawn on the way: the camera goes at once', () {
      final d = _Drive(
        items: items,
        settings: const DrivingAidsSettings(exactIn: {'FR'}),
      );
      expect(d.drive(3500, 3700).alert?.kind, EnforcementKind.camera);
      d.settings = const DrivingAidsSettings();
      final aids = d.fix(3720);
      expect(aids.alert, isNull);
      expect(aids.cameras, isEmpty);
      expect(aids.ruleChange, isNull, reason: 'no border was crossed');
    });
  });

  group('across a border', () {
    // Spain up to 5 km, France after; each within a kilometre of the other.
    String country(LatLng p) => p.lon < _at(5000).lon ? 'ES' : 'FR';
    List<String> near(LatLng p) => [
      if ((p.lon - _at(5000).lon).abs() * 77650 < 1000) ...['ES', 'FR'],
    ];

    test('from Spain into France: the stricter rule at once, told on screen', () {
      final d = _Drive(
        country: country,
        near: near,
        items: [_camera('es', 3000, limit: 90), _camera('late', 4500, limit: 50)],
      );
      expect(d.drive(2500, 2900).alert!.id, 'es');
      expect(d.drive(2950, 3500).ruleChange, isNull, reason: 'no change yet');
      final at = d.fix(4050);
      expect(at.mode, EnforcementMode.zones, reason: 'France within a kilometre');
      expect(at.ruleChange, const RuleChange(country: 'FR', mode: EnforcementMode.zones));
      expect(d.drive(4060, 4600).alert, isNull, reason: 'a camera under the rule of zones');
    });

    test('from France into Spain: the looser rule only after 30 s, then told', () {
      // France until 5 km here, Spain after.
      final d = _Drive(country: (p) => country(p) == 'ES' ? 'FR' : 'ES', near: near)
        ..drive(3000, 3900);
      var aids = d.fix(6100);
      expect(aids.mode, EnforcementMode.zones, reason: 'still within its 30 s');
      for (var s = 0; s < 29; s++) {
        aids = d.fix(6100 + s * 10.0);
      }
      expect(aids.mode, EnforcementMode.zones);
      aids = d.fix(6500, seconds: 2);
      expect(aids.mode, EnforcementMode.exact);
      expect(aids.ruleChange, const RuleChange(country: 'ES', mode: EnforcementMode.exact));
      aids = d.fix(6510, seconds: 9);
      expect(aids.ruleChange, isNull, reason: 'told for a few seconds');
    });

    test('the first fix sets the rule without telling it', () {
      final d = _Drive(country: (_) => 'ES');
      expect(d.fix(0).ruleChange, isNull);
    });

    test('Switzerland: nothing, at once; Morocco: nothing; Germany: nothing at all', () {
      for (final (code, told) in [
        ('CH', EnforcementMode.off),
        ('DE', EnforcementMode.offWhileDriving),
      ]) {
        final d = _Drive(
          country: (p) => p.lon < _at(3000).lon ? 'FR' : code,
          items: [
            _zone('z', 3200, 3800),
            _camera('c', 4000, country: code, limit: 80),
          ],
        )..drive(2000, 2500);
        final aids = d.fix(3050);
        expect(aids.mode, told, reason: code);
        expect(aids.ruleChange?.country, code);
        expect(d.drive(3060, 4200).alert, isNull, reason: code);
        expect(d.drive(4210, 4300).cameras, isEmpty, reason: code);
      }
      final morocco = _Drive(
        country: (_) => 'MA',
        items: [_camera('c', 1000, country: 'MA')],
      );
      expect(morocco.drive(500, 1100).alert, isNull);
    });
  });

  group('micro-states and enclaves', () {
    // A country of 2 km from 4 km to 6 km along the road, in another.
    String Function(LatLng) inside(String enclave, String around) =>
        (p) => p.lon > _at(4000).lon && p.lon < _at(6000).lon ? enclave : around;
    List<String> Function(LatLng) nearOf(String enclave, String around) => (p) {
      final m = (p.lon - _at(0).lon) * 77650;
      return [
        if (m > 3000 && m < 7000) ...[enclave, around],
      ];
    };

    for (final (enclave, around) in [('MC', 'FR'), ('SM', 'IT')]) {
      test('$enclave, off, within $around: no alert from a kilometre before it until 30 s '
          'after', () {
        final d = _Drive(
          country: inside(enclave, around),
          near: nearOf(enclave, around),
          items: [
            _zone('before', 3200, 3600, country: around),
            _zone('after', 8000, 8400, country: around),
          ],
        )..drive(2000, 2900);
        expect(d.fix(3100).mode, EnforcementMode.off, reason: 'the stricter at once');
        expect(d.drive(3110, 3700).alert, isNull);
        final back = d.drive(7100, 8100);
        expect(back.mode, EnforcementMode.zones, reason: 'looser after its 30 s');
        expect(back.alert!.id, 'after');
      });
    }

    test('Andorra, showing points, past France: the French rule holds within a kilometre, '
        "Andorra's after 30 s beyond it", () {
      // Andorra from 4 km on, France before; within a kilometre of the
      // border, both.
      final d = _Drive(
        country: (p) => p.lon > _at(4000).lon ? 'AD' : 'FR',
        near: (p) {
          final m = (p.lon - _at(0).lon) * 77650;
          return [
            if (m > 3000 && m < 5000) ...['AD', 'FR'],
          ];
        },
        items: [
          _camera('border', 4500, country: 'AD', limit: 50),
          _camera('inside', 8000, country: 'AD', limit: 50),
        ],
      )..drive(3000, 3900);
      expect(d.drive(3910, 4600).alert, isNull, reason: "France's zones within its kilometre");
      final inside = d.drive(4610, 7900);
      expect(inside.mode, EnforcementMode.exact);
      expect(inside.alert!.id, 'inside');
      expect(inside.ruleChange, isNull, reason: 'told for 8 s only, long before');
    });

    test('Llívia, Spanish within France: the French rule within a kilometre holds', () {
      final d = _Drive(
        country: inside('ES', 'FR'),
        near: nearOf('ES', 'FR'),
        items: [_camera('llivia', 5000, limit: 50)],
      );
      expect(d.drive(4000, 4900).alert, isNull, reason: 'zones: never a camera');
      final chosen = _Drive(
        country: inside('ES', 'FR'),
        near: nearOf('ES', 'FR'),
        items: [_camera('llivia', 5000, limit: 50)],
        settings: const DrivingAidsSettings(exactIn: {'FR'}),
      );
      expect(chosen.drive(4000, 4900).alert!.id, 'llivia', reason: 'both show points then');
    });
  });

  test("a zone never shows a kind, whatever its category says, and ends as a zone's end", () {
    for (final category in ['SECTION_CONTROL', 'DANGER_ZONE', 'RED_LIGHT', 'SOMETHING_NEW']) {
      final zone = EnforcementItem(
        id: 'z',
        kind: EnforcementKind.zone,
        category: category,
        country: 'FR',
        line: [for (var m = 2000.0; m <= 2600; m += 50) _at(m)],
      );
      final d = _Drive(items: [zone]);
      final aids = d.drive(1700, 2300);
      expect(aids.alert!.category, isNull, reason: category);
      expect(aids.alert!.isSection, isFalse, reason: category);
      expect(d.said.single.word, AidWord.zone, reason: category);
      expect(d.drive(2310, 2700).exit, const AlertExit(id: 'z', section: false), reason: category);
    }
  });

  group('the edges of an alert', () {
    test('a zone shows from its reach, is entered at its real start, ends past its margin', () {
      final d = _Drive(items: [_zone('z', 2000, 2600)], limits: _limit(80));
      expect(d.fix(1550).alert, isNull, reason: '400 m of reach at 80');
      final ahead = d.fix(1650);
      expect(ahead.alert!.inside, isFalse);
      expect(ahead.alert!.aheadM, closeTo(350, 6));
      expect(d.fix(1990).alert!.inside, isFalse);
      final inside = d.fix(2010);
      expect(inside.alert!.inside, isTrue);
      expect(inside.alert!.remainingM, closeTo(590, 6));
      expect(d.fix(2630).alert, isNotNull, reason: 'within its 50 m');
      final out = d.fix(2660);
      expect(out.alert, isNull);
      expect(out.exit, const AlertExit(id: 'z', section: false));
    });

    test('a position wavering 20 m at its edges: neither an end nor a word again', () {
      final d = _Drive(items: [_zone('z', 2000, 2600)], limits: _limit(80))
        ..drive(1600, 2030, kmh: 80);
      for (final m in const <double>[1990, 2015, 1985, 2020]) {
        expect(d.fix(m).alert!.inside, isTrue, reason: 'entered stays entered: $m');
      }
      d.drive(2100, 2580, kmh: 80);
      for (final m in const <double>[2620, 2585, 2618, 2595, 2620]) {
        final aids = d.fix(m);
        expect(aids.alert, isNotNull, reason: '$m');
        expect(aids.exit, isNull, reason: '$m');
      }
      expect(d.words, [AidWord.zone], reason: 'said once');
    });

    test('a shown alert holds when the limit, and so the reach, drops', () {
      final d = _Drive(
        items: [_camera('c', 3000, limit: 90)],
        country: (_) => 'ES',
        limits: const [
          SpeedLimitSpan(fromM: 0, toM: 2300, kmh: 110, source: SpeedLimitSource.posted),
          SpeedLimitSpan(fromM: 2300, toM: 10000, kmh: 50, source: SpeedLimitSource.posted),
        ],
      );
      expect(d.fix(2250, kmh: 100).alert!.aheadM, closeTo(750, 10), reason: '800 m at 110');
      expect(d.fix(2350, kmh: 100).alert, isNotNull, reason: 'held though 200 m at 50');
      expect(d.fix(3020).alert, isNotNull, reason: 'its point passed, within 30 m');
      expect(d.fix(3040).alert, isNull);
      expect(d.fix(3045).exit, isNull, reason: 'a point has no end told');
    });

    test('zones closer than 300 m are one stretch: one word, no end between', () {
      final d = _Drive(items: [_zone('a', 2000, 2400), _zone('b', 2600, 3000)]);
      final ends = <AlertExit>[];
      for (var m = 1700.0; m <= 3000; m += 14) {
        if (d.fix(m).exit case final e?) ends.add(e);
      }
      expect(d.words, [AidWord.zone]);
      expect(ends, isEmpty);
      final out = d.fix(3060);
      expect(out.exit, const AlertExit(id: 'a', section: false));
    });

    test('zones further apart are two, each said', () {
      final d = _Drive(items: [_zone('a', 2000, 2400), _zone('b', 3000, 3400)])..drive(1700, 3500);
      expect(d.words, [AidWord.zone, AidWord.zone]);
    });

    test('the end shows 4 s, then nothing; not at all when another alert comes at once', () {
      final d = _Drive(items: [_zone('a', 2000, 2400)])..drive(1800, 2440);
      final out = d.fix(2460);
      expect(out.exit, isNotNull);
      expect(d.fix(2470, seconds: 3).exit, isNotNull);
      expect(d.fix(2480, seconds: 1.5).exit, isNull, reason: '4 s are up');
      final next = _Drive(items: [_zone('a', 2000, 2400), _zone('b', 2800, 3000)])
        ..drive(1800, 2440);
      final followed = next.fix(2460);
      expect(followed.exit, isNull);
      expect(followed.alert!.id, 'b');
    });

    test('a tunnel: past the end on an imprecise fix, the alert stays until a precise one', () {
      final d = _Drive(items: [_zone('z', 2000, 2600)])..drive(1800, 2500);
      final dark = d.fix(2700, accuracy: 250);
      expect(dark.alert, isNotNull);
      expect(dark.exit, isNull);
      final light = d.fix(2710);
      expect(light.alert, isNull);
      expect(light.exit, isNotNull);
    });

    test('a new route over the same road: the alert goes on, nothing said again', () {
      final d =
          _Drive(
              items: [
                _zone('z', 2000, 2600),
                _camera('c', 4000, country: 'FR'),
              ],
            )
            ..drive(1800, 2200)
            // The same road anew, as a recalculation sends it.
            ..route = _route(line: [..._road]);
      final aids = d.fix(2210);
      expect(aids.alert!.inside, isTrue);
      expect(aids.exit, isNull);
      d
        ..drive(2220, 2800)
        ..route = _route(line: [..._road])
        ..drive(2810, 2900);
      expect(d.words, [AidWord.zone]);
    });

    test('the guidance starting inside a zone says so', () {
      final d = _Drive(items: [_zone('z', 2000, 2600)]);
      final aids = d.fix(2300);
      expect(aids.alert!.inside, isTrue);
      expect(d.said.single.alert!.inside, isTrue);
    });

    test('a camera ahead takes the banner from the stretch the vehicle is in', () {
      final d = _Drive(
        country: (_) => 'ES',
        items: [_section('s', 2000, 5000, limit: 110), _camera('c', 3500, limit: 90)],
      );
      expect(d.drive(1800, 2100).alert!.id, 's');
      expect(d.drive(2110, 3200).alert!.id, 'c');
      expect(d.drive(3210, 3600).alert!.id, 's');
    });

    test('cameras of one kind at one point, one per lane or mapped twice, are one alert', () {
      // The A2 between Amsterdam and Utrecht: six cameras a gantry in
      // OpenStreetMap; the AP-7 north of Barcelona: one camera mapped twice
      // 40 m apart, with its limit and without.
      final d = _Drive(
        country: (_) => 'ES',
        items: [
          _camera('lane1', 3000),
          _camera('lane2', 3005, limit: 100),
          _camera('lane3', 3040),
          _camera('red', 3020, category: 'RED_LIGHT'),
          _camera('next', 4500, limit: 100),
        ],
        limits: _limit(120),
      );
      final ahead = d.drive(2000, 2500, kmh: 98);
      expect(ahead.alert!.id, 'lane1');
      expect(ahead.alert!.limitKmh, 100, reason: 'the limit one of them gives');
      expect(d.drive(2530, 3060, kmh: 98).alert!.id, 'lane1', reason: 'held to the last one');
      d.drive(3090, 4000, kmh: 98);
      expect(d.said.map((c) => c.key), ['aid:camera:lane1', 'aid:camera:red', 'aid:camera:next']);
    });
  });

  group('over the limit', () {
    test('said once per camera, after 2 s over its own limit', () {
      final d = _Drive(
        country: (_) => 'ES',
        items: [_camera('a', 2000, limit: 70), _camera('b', 4000, limit: 70)],
        limits: _limit(90),
      )..fix(1700, kmh: 85);
      expect(d.fix(1720, kmh: 85).alert!.over, isFalse, reason: 'not 2 s yet');
      final over = d.fix(1750, kmh: 85, seconds: 2);
      expect(over.alert!.over, isTrue);
      d
        ..drive(1760, 2040, kmh: 85)
        ..drive(3700, 4040, kmh: 85);
      final slow = [
        for (final c in d.said)
          if (c.word == AidWord.slowDown) c,
      ];
      expect(slow.map((c) => c.key), ['aid:slow:a', 'aid:slow:b']);
      expect(slow.first.alert!.cameraLimit, isTrue);
      expect(slow.first.alert!.limitKmh, 70);
    });

    test(
      "in a zone, the road's limit when it is known; nothing for an estimate or a hidden one",
      () {
        final posted = _Drive(items: [_zone('z', 2000, 2600)], limits: _limit(80))
          ..drive(1700, 2300, kmh: 95);
        final slow = posted.said.where((c) => c.word == AidWord.slowDown).single;
        expect(slow.alert!.cameraLimit, isFalse);
        expect(slow.alert!.limitKmh, 80);
        final estimated = _Drive(
          items: [_zone('z', 2000, 2600)],
          limits: _limit(80, source: SpeedLimitSource.estimated),
        )..drive(1700, 2300, kmh: 95);
        expect(estimated.words, [AidWord.zone]);
        expect(estimated.fix(2310, kmh: 95).alert!.limitEstimated, isTrue);
        final hidden = _Drive(
          items: [_zone('z', 2000, 2600)],
          limits: _limit(80),
          settings: const DrivingAidsSettings(showSpeedLimit: false),
        );
        final aids = hidden.drive(1700, 2300, kmh: 95);
        expect(hidden.words, isNot(contains(AidWord.slowDown)));
        expect(aids.alert!.limitKmh, isNull, reason: 'a limit the user hid is not shown here');
      },
    );

    test("the road's reminder stays quiet while the alert speaks of its own limit", () {
      // From where the camera comes into reach (400 m at 80): the road's
      // word would come after 5 s, the camera's after 2.
      final d = _Drive(
        country: (_) => 'ES',
        items: [_camera('a', 3000, limit: 70)],
        limits: _limit(80),
      )..drive(2610, 2990, kmh: 100);
      expect(d.words.where((w) => w == AidWord.overSpeed), isEmpty);
      expect(d.words, contains(AidWord.slowDown));
    });

    test('a red light camera never says to slow down', () {
      final d = _Drive(
        country: (_) => 'ES',
        items: [_camera('rl', 2000, category: 'RED_LIGHT')],
        limits: _limit(50),
      )..drive(1700, 1990, kmh: 70);
      expect(d.words.where((w) => w == AidWord.slowDown), isEmpty);
      expect(d.fix(1995, kmh: 70).alert!.category, CameraCategory.redLight);
    });
  });

  group('an average speed section', () {
    test('said once, its length known, the average from 200 m inside, over by the average', () {
      final d = _Drive(
        country: (_) => 'ES',
        items: [_section('s', 2000, 6000, limit: 90)],
        limits: _limit(110),
      );
      final ahead = d.drive(1300, 1900, kmh: 85);
      expect(d.words, [AidWord.section]);
      expect(ahead.alert!.sectionM, closeTo(4000, 10));
      expect(ahead.alert!.isSection, isTrue);
      final early = d.drive(1910, 2150, kmh: 100);
      expect(early.alert!.inside, isTrue);
      expect(early.alert!.averageKmh, isNull, reason: 'not 200 m yet');
      final later = d.drive(2160, 3000, kmh: 100);
      expect(later.alert!.averageKmh, closeTo(100, 4));
      expect(later.alert!.over, isTrue, reason: 'its average over 90');
      expect(d.words, [AidWord.section, AidWord.slowDown]);
      final slower = d.drive(3010, 5900, kmh: 70);
      expect(slower.alert!.averageKmh, lessThan(85));
      expect(d.drive(5910, 6100, kmh: 70).exit, const AlertExit(id: 's', section: true));
    });

    test('a guidance that starts inside a section shows no average', () {
      final d = _Drive(country: (_) => 'ES', items: [_section('s', 2000, 6000, limit: 90)]);
      expect(d.drive(2500, 3500).alert!.averageKmh, isNull);
    });
  });
}
