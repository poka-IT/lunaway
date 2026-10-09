import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/geo/geo.dart';
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
        'Liste des radars fixes en France, liste du 30 déc. 2025',
      );
    });

    test('goes without it this year', () {
      expect(
        fr.enforcementSource(dsr, now: DateTime(2025, 12, 31)),
        'Liste des radars fixes en France, liste du 30 déc.',
      );
    });
  });
}
