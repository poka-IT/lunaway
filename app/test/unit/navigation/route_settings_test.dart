import 'dart:convert';

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
        voiceMode: VoiceMode.alerts,
        units: DistanceUnits.imperial,
        acceptedDisclaimer: 'routing.disclaimer.v1',
        notificationExplained: true,
      );
      expect(NavigationSettings.decode(s.encode()), s);
      expect(NavigationSettings.decode(s.encode()).notificationExplained, isTrue);
      expect(NavigationSettings.decode('{not json'), const NavigationSettings());
      expect(NavigationSettings.decode('{"units": "parsecs"}').units, DistanceUnits.metric);
      expect(
        NavigationSettings.decode(null).voiceMode,
        VoiceMode.full,
        reason: 'the whole voice by default',
      );
    });

    group('the voice mode', () {
      VoiceMode read(String raw) => NavigationSettings.decode(raw).voiceMode;

      test('of an app older than the modes: off is muted, on or unsaid is full', () {
        expect(read('{"voice": false}'), VoiceMode.muted);
        expect(read('{"voice": true}'), VoiceMode.full);
        expect(read('{"units": "metric"}'), VoiceMode.full);
      });

      test('is read from its own key first, the older one only without a known mode', () {
        expect(read('{"voiceMode": "alerts", "voice": true}'), VoiceMode.alerts);
        expect(read('{"voiceMode": "full", "voice": false}'), VoiceMode.full);
        expect(read('{"voiceMode": "whisper", "voice": false}'), VoiceMode.muted);
      });

      test('is written for an older app too, which hears alerts only as on', () {
        Map<String, dynamic> written(VoiceMode mode) =>
            jsonDecode(NavigationSettings(voiceMode: mode).encode()) as Map<String, dynamic>;
        expect(written(VoiceMode.full), containsPair('voiceMode', 'full'));
        expect(written(VoiceMode.full), containsPair('voice', true));
        expect(written(VoiceMode.alerts), containsPair('voiceMode', 'alerts'));
        expect(written(VoiceMode.alerts), containsPair('voice', true));
        expect(written(VoiceMode.muted), containsPair('voiceMode', 'muted'));
        expect(written(VoiceMode.muted), containsPair('voice', false));
      });

      test('moves on full, alerts only, muted, then full again', () {
        expect(VoiceMode.full.next, VoiceMode.alerts);
        expect(VoiceMode.alerts.next, VoiceMode.muted);
        expect(VoiceMode.muted.next, VoiceMode.full);
      });
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
