import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

Place _priced({
  double? parking,
  double? services,
  bool included = false,
  Set<PriceInclusion> includes = const {},
}) => Place(
  id: 'priced',
  kind: PlaceKind.campsite,
  lat: 45.3,
  lon: 5.2,
  overnight: OvernightStatus.allowed,
  updatedAt: DateTime.utc(2026, 10, 8),
  priceParkingEur: parking,
  priceServicesEur: services,
  priceServicesIncluded: included,
  priceParkingIncludes: includes,
);

void main() {
  group('the services read as included', () {
    test('when a source says so', () {
      expect(_priced(parking: 14.5, included: true).servicesIncluded, isTrue);
      expect(_priced(included: true).servicesIncluded, isTrue, reason: 'whatever the night');
    });

    test('when they cost nothing and the night is paid', () {
      expect(
        _priced(parking: 60, services: 0).servicesIncluded,
        isTrue,
        reason: 'free services at a 60 euro campsite come with the pitch, it is no free stop',
      );
    });

    test('not when the night is free or unknown, nor when they have a price', () {
      expect(_priced(parking: 0, services: 0).servicesIncluded, isFalse);
      expect(_priced(services: 0).servicesIncluded, isFalse);
      expect(_priced(parking: 12, services: 3).servicesIncluded, isFalse);
      expect(_priced(parking: 12).servicesIncluded, isFalse);
    });
  });

  group("the API's price inclusions", () {
    test('are read, the values this app does not know left out', () {
      final p = placeFromJson({
        'id': 'p',
        'kind': 'MOTORHOME_AREA',
        'lat': 45.2,
        'lon': 5.1,
        'overnight': 'ALLOWED',
        'priceParkingEur': 14.5,
        'priceParkingIncludes': ['TOURIST_TAX', 'SAUNA', 'SERVICES'],
        'priceServicesIncluded': true,
      });
      expect(p.priceParkingIncludes, {PriceInclusion.touristTax, PriceInclusion.services});
      expect(p.priceServicesIncluded, isTrue);
    });

    test('from an API older than them, are none', () {
      final p = placeFromJson({
        'id': 'p',
        'kind': 'PARKING',
        'lat': 45.2,
        'lon': 5.1,
        'overnight': 'ALLOWED',
      });
      expect(p.priceParkingIncludes, isEmpty);
      expect(p.priceServicesIncluded, isFalse);
    });

    test('are written back as the API writes them', () {
      final p = _priced(
        parking: 14.5,
        included: true,
        includes: {PriceInclusion.electricity, PriceInclusion.services},
      );
      final json = placeToJson(p);
      expect(json['priceParkingIncludes'], ['SERVICES', 'ELECTRICITY']);
      expect(json['priceServicesIncluded'], isTrue);
      expect(placeFromJson(json), p);
    });
  });
}
