import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// A straight road east, a point every 50 m over 5 km.
final List<LatLng> _road = [for (var i = 0; i <= 100; i++) _at(i * 50)];

/// The point [m] metres along [_road], [northM] metres beside it.
LatLng _at(double m, {double northM = 0}) => LatLng(45.8336 + northM / 111195, 1.2611 + m / 77650);

const _rules = EnforcementRules(
  version: 2,
  countries: {'ES': EnforcementMode.exact, 'FR': EnforcementMode.zones},
);

EnforcementItem _camera(
  String id,
  double at, {
  double northM = 0,
  int? limit,
  String category = 'FIXED',
}) => EnforcementItem(
  id: id,
  kind: EnforcementKind.camera,
  category: category,
  country: 'ES',
  position: _at(at, northM: northM),
  limitKmh: limit,
);

/// The motorway's limit along [_road]: 120 from a sign, an estimate past
/// 3 km.
const _limits = [
  SpeedLimitSpan(fromM: 0, toM: 3000, kmh: 120, source: SpeedLimitSource.posted),
  SpeedLimitSpan(fromM: 3000, toM: 5000, kmh: 120, source: SpeedLimitSource.estimated),
];

List<String> _ids(Iterable<ItemOnRoute> items) => [for (final r in items) r.item.id];

void main() {
  group('a camera beside the route', () {
    List<ItemOnRoute> matched(List<EnforcementItem> items) =>
        withoutBeside(itemsOnRoute(_road, items), (m) => knownLimitAt(_limits, m));

    test('the offset of a camera from the route is measured', () {
      final on = itemsOnRoute(_road, [_camera('c', 1000, northM: 15)]).single;
      expect(on.offsetM, closeTo(15, 0.5));
    });

    test("a slip road's camera, limited to 30 beside a motorway at 120, is not the route's", () {
      // The AP-7 near Llinars: two cameras of the slip road, 12 and 22 m
      // from the route.
      expect(
        _ids(
          matched([
            _camera('slip a', 1000, northM: 12, limit: 30),
            _camera('slip b', 1400, northM: 22, limit: 30),
          ]),
        ),
        isEmpty,
      );
    });

    test(
      'the bounds: 8 m off and 40 km/h under are beside; nearer, or closer in limit, are not',
      () {
        expect(_ids(matched([_camera('at the bounds', 1000, northM: 8.05, limit: 80)])), isEmpty);
        expect(_ids(matched([_camera('nearer', 1000, northM: 7.9, limit: 80)])), ['nearer']);
        expect(_ids(matched([_camera('closer in limit', 1000, northM: 20, limit: 81)])), [
          'closer in limit',
        ]);
      },
    );

    test("a camera on the route's own road stays, whatever its limit", () {
      expect(_ids(matched([_camera('works', 1000, northM: 3, limit: 30)])), ['works']);
    });

    test("a camera beside the road with a limit near the route's stays: the pole of a list", () {
      expect(_ids(matched([_camera('pole', 1000, northM: 20, limit: 90)])), ['pole']);
    });

    test('nothing is set aside without its limit, nor where the route has only an estimate', () {
      expect(
        _ids(
          matched([
            _camera('no limit', 1000, northM: 20),
            _camera('estimate', 3500, northM: 20, limit: 30),
          ]),
        ),
        ['no limit', 'estimate'],
      );
    });
  });

  group('a gantry on the map', () {
    List<ItemOnRoute> drawn(List<EnforcementItem> items) =>
        camerasOnRoute(itemsOnRoute(_road, items), here: EnforcementMode.exact, rules: _rules);

    test('one camera per lane is one mark, with the lowest limit known', () {
      final lanes = [
        for (var i = 0; i < 6; i++) _camera('lane $i', 2000 + i * 5.0, limit: i == 3 ? 100 : null),
      ];
      final marks = drawn(lanes);
      expect(marks, hasLength(1), reason: 'the legend counts one camera, not six');
      expect(marks.single.item.limitKmh, 100);
    });

    test('a chain of cameras 40 m apart is one gantry, as the alerts count it', () {
      expect(_ids(drawn([_camera('a', 2000), _camera('b', 2040), _camera('c', 2080)])), ['a']);
    });

    test('two sections end to end are two controls, two marks', () {
      EnforcementItem section(String id, double from, double to, int limit) => EnforcementItem(
        id: id,
        kind: EnforcementKind.camera,
        category: 'SECTION_CONTROL',
        country: 'ES',
        position: _at(from),
        line: [for (var m = from; m <= to; m += 50) _at(m)],
        limitKmh: limit,
      );
      expect(_ids(drawn([section('a', 1000, 2500, 130), section('b', 2500, 4000, 110)])), [
        'a',
        'b',
      ]);
    });

    test('a camera drawn with a stretch of road, a section without its kind, joins its gantry', () {
      final drawnLong = EnforcementItem(
        id: 'with a road',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: _at(2010),
        line: [_at(2010), _at(2060), _at(2110)],
      );
      expect(drawn([_camera('lane', 2000), drawnLong]), hasLength(1));
    });

    test('cameras of other kinds, or farther apart, stay apart', () {
      expect(
        _ids(
          drawn([
            _camera('speed', 2000),
            _camera('red light', 2010, category: 'RED_LIGHT'),
            _camera('next', 2080),
          ]),
        ),
        ['speed', 'red light', 'next'],
      );
    });
  });

  group('a word that waited', () {
    EnforcementAlert alert(EnforcementKind kind, {double aheadM = 400, double? sectionM}) =>
        EnforcementAlert(id: 'a', kind: kind, aheadM: aheadM, remainingM: 0, sectionM: sectionM);
    AidCall word(EnforcementAlert a, {AidWord w = AidWord.camera}) =>
        AidCall(word: w, key: 'k', alert: a);

    test('tells the distance left once the vehicle drove on', () {
      expect(word(alert(EnforcementKind.camera)).after(100)!.alert!.aheadM, 300);
    });

    test("a camera's point passed meanwhile is no longer worth a word", () {
      expect(word(alert(EnforcementKind.camera)).after(450), isNull);
      expect(word(alert(EnforcementKind.camera), w: AidWord.slowDown).after(450), isNull);
    });

    test('a zone or a section entered meanwhile says the vehicle is in it', () {
      final zone = word(alert(EnforcementKind.zone), w: AidWord.zone).after(450)!;
      expect(zone.alert!.within, isTrue);
      final section = word(alert(EnforcementKind.camera, sectionM: 4000)).after(450)!;
      expect(section.alert!.within, isTrue);
    });

    test('a word without a distance stays as it came', () {
      final inside = word(alert(EnforcementKind.zone, aheadM: 0), w: AidWord.zone);
      expect(inside.after(300), same(inside));
    });

    test('a word said at once, or a fix behind the one it came from, stays as it came', () {
      final ahead = word(alert(EnforcementKind.camera));
      expect(ahead.after(0), same(ahead));
      expect(ahead.after(-15), same(ahead));
    });
  });

  group("a list's date", () {
    late Translations fr;
    setUpAll(() async {
      await initializeDateFormatting('fr');
      fr = await AppLocale.fr.build();
    });

    final dsr = EnforcementSource(
      id: 'fr-dsr',
      name: 'Liste des radars fixes en France',
      attribution: "Ministère de l'Intérieur",
      fetchedAt: DateTime.utc(2026, 10, 9),
      listUpdatedAt: DateTime.utc(2025, 12, 30, 12),
    );

    test('carries its year when it is not this year', () {
      expect(
        fr.enforcementSource(dsr, now: DateTime(2026, 10, 9)),
        "Ministère de l'Intérieur, liste du 30 déc. 2025",
      );
    });

    test('names the list in the language of the app, by its authority', () async {
      await initializeDateFormatting('de');
      final de = await AppLocale.de.build();
      final cited = de.enforcementSource(dsr, now: DateTime(2026, 10, 9));
      expect(cited, startsWith('Französisches Innenministerium, Liste vom '));
      expect(cited, isNot(contains('radars fixes')), reason: 'the API names it in French');
      final unknown = EnforcementSource(
        id: 'xx-new',
        name: 'Nowa lista',
        attribution: 'Nowa lista',
        fetchedAt: DateTime.utc(2026, 10, 9),
      );
      expect(de.listName(unknown), 'Nowa lista', reason: 'a list the app does not know yet');
    });

    test('goes without it this year', () {
      expect(
        fr.enforcementSource(dsr, now: DateTime(2025, 12, 31)),
        "Ministère de l'Intérieur, liste du 30 déc.",
      );
    });
  });
}
