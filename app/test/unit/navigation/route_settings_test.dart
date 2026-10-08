import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/navigation/data/route_settings_store.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

import '../../helpers/navigation.dart';
import '../../helpers/pump.dart';

void main() {
  group('the vehicle a route is computed for', () {
    test('every figure is needed: a guessed height could pass under a bridge', () {
      expect(checkVehicle(null).missing, MissingDimension.values.toSet());
      final noHeight = checkVehicle(motorhome.copyWith(heightM: () => null));
      expect(noHeight.ready, isFalse);
      expect(noHeight.missing, {MissingDimension.height});
    });

    test('the profile carries the figures and the kind the router knows', () {
      final p = checkVehicle(motorhome).profile!;
      expect(p.type, RouterVehicleType.integrated);
      expect((p.heightM, p.widthM, p.lengthM, p.weightT), (3.3, 2.3, 7.4, 3.5));
      expect(p.trailer, isNull);
    });

    test('a vehicle that tows gets the usual car trailer, taken off the total length', () {
      final p = checkVehicle(motorhome.copyWith(towing: Towing.car, lengthM: () => 12.2)).profile!;
      expect(p.trailer, assumedTrailer);
      expect(p.lengthM, closeTo(12.2 - 4.78, 1e-9));
    });

    test('the cruising speed goes with the profile only when the driver set one', () {
      final usual = checkVehicle(motorhome).profile!;
      expect(usual.toJson(), isNot(contains('cruiseSpeedKph')));
      final slow = checkVehicle(motorhome.copyWith(cruiseSpeedKph: () => 95)).profile!;
      expect(slow.cruiseSpeedKph, 95);
      expect(slow.toJson()['cruiseSpeedKph'], 95);
      expect(slow, isNot(usual), reason: 'another speed is another route to ask');
    });

    test('a figure outside what the router accepts is named, not sent', () {
      final c = checkVehicle(motorhome.copyWith(lengthM: () => 18));
      expect(c.ready, isFalse);
      expect(c.outOfBounds, {MissingDimension.length});
    });
  });

  group('the route settings', () {
    test('survive a round trip and fall back to the defaults on a corrupt value', () {
      const s = NavigationSettings(
        avoid: AvoidOptions(tolls: true, ferries: true),
        voice: false,
        units: DistanceUnits.imperial,
        acceptedDisclaimer: 'routing.disclaimer.v1',
        notificationExplained: true,
      );
      expect(NavigationSettings.decode(s.encode()), s);
      expect(NavigationSettings.decode(s.encode()).notificationExplained, isTrue);
      expect(NavigationSettings.decode('{not json'), const NavigationSettings());
      expect(NavigationSettings.decode('{"units": "parsecs"}').units, DistanceUnits.metric);
      expect(NavigationSettings.decode(null).voice, isTrue, reason: 'the voice is on by default');
    });

    test('are kept in the user database, beside the other settings', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = UserDatabase(memoryDatabase());
      addTearDown(db.close);
      final store = DriftRouteSettingsStore(db);
      expect(await store.load(), const NavigationSettings());
      await store.save(const NavigationSettings(avoid: AvoidOptions(unpaved: true)));
      expect((await store.load()).avoid.unpaved, isTrue);
      final rows = await db.select(db.settings).get();
      expect(rows.map((r) => r.id), contains('route_settings'));
    });
  });
}
