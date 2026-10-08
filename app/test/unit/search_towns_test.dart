import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/french_departments.dart';
import 'package:lunaway/features/places/domain/town_names.dart';
import 'package:lunaway/i18n/strings.g.dart';

({Municipality town, String? area}) _group(
  String name,
  int places, {
  String? area,
  String? postcode,
  String country = 'FR',
  LatLng center = const LatLng(45, 6),
}) => (
  town: Municipality(
    name: name,
    postcode: postcode,
    department: country == 'FR' ? area : null,
    countryCode: country,
    center: center,
    placeCount: places,
  ),
  area: area,
);

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group("the device's towns", () {
    test('two spellings of one commune are one town, its places all counted', () {
      // The device listed "Chamonix-Mont-Blanc 74400 · 98 lieux" and "Chamonix
      // 74400 · 1 lieu".
      final towns = mergeTowns('Chamonix', [
        _group(
          'Chamonix-Mont-Blanc',
          98,
          area: '74',
          postcode: '74400',
          center: const LatLng(45.92, 6.87),
        ),
        _group('Chamonix', 1, area: '74', postcode: '74400', center: const LatLng(45.92, 6.87)),
      ]);
      expect(towns.map((t) => (t.name, t.placeCount)), [('Chamonix-Mont-Blanc', 99)]);
    });

    test('homonyms of two departments stay two towns, the name typed first', () {
      final towns = mergeTowns('viviers', [
        _group('Viviers-du-Lac', 8, area: '73'),
        _group('Viviers', 18, area: '07', postcode: '07220'),
        _group('Viviers', 2, area: '89', postcode: '89700'),
      ]);
      expect(towns.map((t) => (t.name, t.department, t.placeCount)), [
        ('Viviers', '07', 18),
        ('Viviers', '89', 2),
        ('Viviers-du-Lac', '73', 8),
      ]);
    });

    test('a place of an unknown area joins the one town of its name', () {
      final towns = mergeTowns('sete', [
        _group('Sète', 5, area: '34', postcode: '34200', center: const LatLng(43.40, 3.70)),
        _group('Sète', 1, center: const LatLng(43.41, 3.70)),
      ]);
      expect(towns, hasLength(1));
      expect(towns.single.placeCount, 6);
      expect(towns.single.center.lat, closeTo((43.40 * 5 + 43.41) / 6, 1e-9));
    });

    test('a town of an unknown area joins only the one town of its name, whatever the order', () {
      // Two Viviers of known departments: the 3 places without a postcode
      // belong to neither for sure.
      final viviers = mergeTowns('viviers', [
        _group('Viviers', 18, area: '07', postcode: '07220'),
        _group('Viviers', 3),
        _group('Viviers', 2, area: '89', postcode: '89700'),
      ]);
      expect(viviers.map((t) => (t.department, t.placeCount)), [('07', 18), (null, 3), ('89', 2)]);
      // Bigger than the one known Sète, it still joins it.
      final sete = mergeTowns('sete', [
        _group('Sète', 5),
        _group('Sète', 1, area: '34', postcode: '34200'),
      ]);
      expect(sete.map((t) => (t.department, t.placeCount)), [('34', 6)]);
    });

    test('two spellings that fold alike in one department are one town', () {
      final towns = mergeTowns('saint malo', [
        _group('Saint-Malo', 10, area: '35', postcode: '35400'),
        _group('SAINT MALO', 2, area: '35', postcode: '35400'),
      ]);
      expect(towns.map((t) => (t.name, t.placeCount)), [('Saint-Malo', 12)]);
    });

    test('a commune whose name starts another of its department, another postcode, stays', () {
      final towns = mergeTowns('pont', [
        _group('Pont-de-Pany', 4, area: '21', postcode: '21410'),
        _group('Pont', 2, area: '21', postcode: '21320'),
      ]);
      expect(towns, hasLength(2));
    });

    test('the bigger spelling gives the name, the shorter one or the longer one', () {
      final towns = mergeTowns('chamonix', [
        _group('Chamonix', 100, area: '74', postcode: '74400'),
        _group('Chamonix-Mont-Blanc', 98, area: '74', postcode: '74400'),
      ]);
      expect(towns.map((t) => (t.name, t.placeCount)), [('Chamonix', 198)]);
    });

    test('a shorter name of another department or country is another town', () {
      final towns = mergeTowns('vaux', [
        _group('Vaux-le-Pénil', 10, area: '77'),
        _group('Vaux', 3, area: '86'),
        _group('Vaux', 2, area: '77', country: 'BE'),
      ]);
      expect(towns, hasLength(3));
    });
  });

  test("the API's towns are read with their department and country", () {
    final answer = searchAnswerFromJson({
      'towns': [
        {
          'name': 'Viviers',
          'postcode': '07220',
          'department': '07',
          'countryCode': 'FR',
          'placeCount': 18,
          'lat': 44.48,
          'lon': 4.68,
        },
        {'name': 'Broken', 'placeCount': 1},
      ],
    });
    expect(answer.towns, [
      const Municipality(
        name: 'Viviers',
        postcode: '07220',
        department: '07',
        countryCode: 'FR',
        center: LatLng(44.48, 4.68),
        placeCount: 18,
      ),
    ]);
  });

  test('a town reads with its department in France, its country elsewhere', () {
    final t = AppLocale.fr.buildSync();
    expect(
      townDetail(
        t,
        const Municipality(
          name: 'Viviers',
          postcode: '89700',
          department: '89',
          countryCode: 'FR',
          center: LatLng(47.9, 4),
          placeCount: 2,
        ),
      ),
      '89700 · Yonne · 2 lieux',
    );
    expect(
      townDetail(
        t,
        const Municipality(
          name: 'Neustadt',
          postcode: '67433',
          countryCode: 'DE',
          center: LatLng(49.35, 8.14),
          placeCount: 1,
        ),
      ),
      '67433 · Allemagne · 1 lieu',
    );
  });

  test('the department of a postcode, Corsica and overseas included', () {
    expect(departmentOfPostcode('07220'), '07');
    expect(departmentOfPostcode('20000'), '2A');
    expect(departmentOfPostcode('20250'), '2B');
    expect(departmentOfPostcode('97400'), '974');
    expect(departmentOfPostcode('1052'), isNull);
    expect(frenchDepartments['2A'], 'Corse-du-Sud');
  });

  test('a town name folds as the server folds it', () {
    expect(townKey('Chamonix-Mont-Blanc'), 'chamonix mont blanc');
    expect(townKey("Saint-Maurice-d'Ibie"), 'saint maurice d ibie');
    expect(sameTownArea('69001', '69009'), isTrue);
    expect(sameTownArea('07220', '89700'), isFalse);
    expect(sameTownArea(null, '89700'), isTrue);
    expect(sameTownArea('97450', '97134'), isFalse, reason: 'La Réunion is not Guadeloupe');
    expect(sameTownArea('20000', '20250'), isFalse, reason: 'Corse-du-Sud is not Haute-Corse');
    expect(
      sameTownArea('20095', '20457', aCountry: 'DE', bCountry: 'DE'),
      isTrue,
      reason: 'Hamburg is one area',
    );
  });
}
