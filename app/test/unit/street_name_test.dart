import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/domain/street_name.dart';

void main() {
  test('the house number leaves the street that titles an unnamed place', () {
    // Lines as the sources and the reverse geocoding write them, number
    // first, from the production catalogue of 2026-10-10.
    expect(streetName('11 Chemin de la Grotte'), 'Chemin de la Grotte');
    expect(streetName('616-644 Route de Fréjus'), 'Route de Fréjus');
    expect(streetName('4 bis, rue Haute'), 'rue Haute');
    expect(streetName('12A Rue des Lilas'), 'Rue des Lilas');
    expect(streetName('17+555 Strada Statale 487'), 'Strada Statale 487');
    expect(streetName('938 SP27'), 'SP27', reason: 'a road number is a street');
    expect(streetName('15 Burgstraße'), 'Burgstraße');
  });

  test('a line without a leading number is kept whole', () {
    expect(streetName('D933N'), 'D933N');
    expect(streetName('Via Monte Grappa'), 'Via Monte Grappa');
    expect(
      streetName('Strada Statale 260 Picente'),
      'Strada Statale 260 Picente',
      reason: 'a number inside the name is part of it',
    );
  });

  test('nothing is a street when only a number is left', () {
    expect(streetName(null), isNull);
    expect(streetName('  '), isNull);
    expect(streetName('12'), isNull);
    expect(streetName('12 B'), isNull);
  });
}
