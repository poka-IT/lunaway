import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/locality.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/locality_line.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';
import 'package:lunaway/i18n/strings.g.dart';

void main() {
  final t = AppLocale.fr.buildSync();
  String? line(Locality l, {String home = 'FR'}) => localityLine(t, l, home: home);

  group('where a result lies, on one short line', () {
    test('in France, the town and its department, or the arrondissement', () {
      expect(
        line(const Locality(town: 'Annecy', department: '74', countryCode: 'FR')),
        'Annecy\u00a0(74)',
      );
      expect(
        line(Locality.fromAddress(town: 'Donzère', postcode: '26290', countryCode: 'FR')),
        'Donzère\u00a0(26)',
        reason: 'the department of the postcode',
      );
      expect(
        line(Locality.fromAddress(town: 'Lyon', postcode: '69003', countryCode: 'FR')),
        'Lyon\u00a03e',
      );
      expect(line(Locality.fromAddress(town: 'Paris', postcode: '75001')), 'Paris\u00a01er');
      expect(
        line(Locality.fromAddress(postcode: '26200', countryCode: 'FR')),
        'Drôme',
        reason: 'a town itself: its department by name',
      );
      expect(line(const Locality(town: 'Viviers', countryCode: 'FR')), 'Viviers');
    });

    test("abroad, the town and the country when it is not the user's, else the region", () {
      final munich = Locality.fromAddress(
        town: 'München',
        postcode: '80331',
        countryCode: 'de',
        region: 'Bayern',
      );
      expect(line(munich), 'München · Allemagne', reason: 'a French user is told the country');
      expect(line(munich, home: 'DE'), 'München · Bayern', reason: 'at home, the region');
      expect(munich.department, isNull, reason: 'a German postcode is no department');
      expect(
        line(
          const Locality(town: 'Annecy', department: '74', countryCode: 'FR'),
          home: 'DE',
        ),
        'Annecy\u00a0(74) · France',
      );
    });

    test('nothing known, nothing said', () {
      expect(line(const Locality(countryCode: 'FR')), isNull);
      expect(line(const Locality(countryCode: 'ES')), 'Espagne', reason: 'the country, abroad');
      expect(localityLine(t, null, home: 'FR'), isNull);
    });

    test('an address of a town places it, an address in a town names it', () {
      const street = AddressMatch(
        kind: AddressKind.street,
        name: 'Rue Neuve',
        postcode: '69003',
        city: 'Lyon',
        countryCode: 'FR',
        position: LatLng(45.76, 4.84),
        sourceId: 'ban',
        attribution: '',
      );
      expect(line(street.locality), 'Lyon\u00a03e');
      const town = AddressMatch(
        kind: AddressKind.town,
        name: 'Donzère',
        postcode: '26290',
        countryCode: 'FR',
        position: LatLng(44.44, 4.72),
        sourceId: 'ban',
        attribution: '',
      );
      expect(line(town.locality), 'Drôme', reason: 'the town is the title, not its line');
    });
  });

  group('an entry of the search history', () {
    test('keeps what reopens it, through its stored form', () {
      final entries = <RecentSearch>[
        const RecentPlace(
          PlaceSummary(
            id: 'p1',
            name: 'Aire du Lac',
            kind: PlaceKind.motorhomeArea,
            lat: 45.9,
            lon: 6.12,
            overnight: OvernightStatus.allowed,
            city: 'Annecy',
            postcode: '74000',
            countryCode: 'FR',
          ),
        ),
        const RecentPoi(
          id: 'poi1',
          poiKind: PoiKind.restaurant,
          position: LatLng(45.9, 6.13),
          name: 'La Ciboulette',
          locality: Locality(town: 'Annecy', department: '74', countryCode: 'FR'),
        ),
        const RecentAddress(
          AddressMatch(
            kind: AddressKind.houseNumber,
            name: '20 Avenue de Ségur',
            postcode: '75007',
            city: 'Paris',
            countryCode: 'FR',
            position: LatLng(48.85, 2.31),
            sourceId: 'ban',
            attribution: 'Base Adresse Nationale',
          ),
        ),
        const RecentText('pizzeria annecy'),
      ];
      for (final e in entries) {
        final back = RecentSearch.fromStored(e.kind, e.toJson())!;
        expect(back.key, e.key);
        expect(back.title, e.title);
      }
      final poi = RecentSearch.fromStored('poi', entries[1].toJson())! as RecentPoi;
      expect(poi.feature.id, 'poi1', reason: 'its page opens by its id');
      expect(poi.locality?.town, 'Annecy');
      expect(RecentSearch.fromStored('later-kind', const {}), isNull);
    });

    test('a text matches it when each word starts one of its words', () {
      const entry = RecentText("Camping du Lac d'Annecy");
      expect(entry.matches('lac ann'), isTrue);
      expect(entry.matches('LAC'), isTrue);
      expect(entry.matches('nnecy'), isFalse);
      expect(entry.matches(''), isFalse);
      expect(const RecentText('Évian').key, const RecentText('evian').key, reason: 'one entry');
    });
  });
}
