import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';

void main() {
  const lyon = LatLng(45.7629, 4.831697);

  group('decimal, the copied format', () {
    test('puts latitude first with six decimals, a comma and a space', () {
      expect(CoordinateFormat.decimal.format(lyon), '45.762900, 4.831697');
    });

    test('keeps a point as decimal separator under a French locale', () {
      final previous = Intl.defaultLocale;
      Intl.defaultLocale = 'fr_FR';
      addTearDown(() => Intl.defaultLocale = previous);
      expect(CoordinateFormat.decimal.format(lyon), '45.762900, 4.831697');
    });

    test('writes southern and western positions with a minus sign', () {
      expect(
        CoordinateFormat.decimal.format(const LatLng(-33.868820, 151.209296)),
        '-33.868820, 151.209296',
      );
      expect(
        CoordinateFormat.decimal.format(const LatLng(40.712776, -74.005974)),
        '40.712776, -74.005974',
      );
    });

    test('rounds to six decimals and never prints a negative zero', () {
      expect(
        CoordinateFormat.decimal.format(const LatLng(0.00000004, -0.00000004)),
        '0.000000, 0.000000',
      );
      expect(
        CoordinateFormat.decimal.format(const LatLng(1.23456789, 2.0000005)),
        '1.234568, 2.000001',
      );
    });
  });

  group('degrees, minutes, seconds', () {
    test('matches the usual notation for a northern, eastern point', () {
      expect(CoordinateFormat.dms.format(lyon), '45°45\'46.4"N 4°49\'54.1"E');
    });

    test('uses S and W for the southern and western hemispheres', () {
      expect(
        CoordinateFormat.dms.format(const LatLng(-33.868820, -70.5)),
        '33°52\'7.8"S 70°30\'0.0"W',
      );
    });

    test('carries rounded seconds into the minute instead of printing 60', () {
      // 59.98 seconds rounds to 60.0: it must read as the next minute.
      expect(CoordinateFormat.dms.format(const LatLng(10.0166661, 0)), '10°1\'0.0"N 0°0\'0.0"E');
    });
  });

  test('the link formats carry the same six-decimal position', () {
    expect(CoordinateFormat.geoUri.format(lyon), 'geo:45.762900,4.831697');
    expect(
      CoordinateFormat.googleMaps.format(lyon),
      'https://www.google.com/maps/search/?api=1&query=45.762900,4.831697',
    );
    expect(
      CoordinateFormat.openStreetMap.format(lyon),
      'https://www.openstreetmap.org/?mlat=45.762900&mlon=4.831697#map=17/45.762900/4.831697',
    );
  });
}
