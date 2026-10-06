import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

/// The real location feed on a device, as guidance uses it: geolocator's
/// foreground service over Android's location manager, its notification and
/// its wake lock. The simulated drive of navigation_drive_test.dart never
/// starts it.
///
/// The system's permission dialog is out of a test's reach, and the
/// emulator's GPS moves only when told: from another terminal, once the
/// app is installed,
///
///   adb shell pm grant legal.p2p.lunaway android.permission.ACCESS_FINE_LOCATION
///   adb emu geo fix 1.2610 45.8335     (then a few more, a second apart)
///
/// `adb shell dumpsys activity services legal.p2p.lunaway` shows the
/// service in the foreground, type location, while the test listens, and
/// gone once it has cancelled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the guidance feed starts its service and brings the fixes', (tester) async {
    final geolocator = GeolocatorPlatform.instance;
    final granted = DateTime.now().add(const Duration(minutes: 3));
    while (await geolocator.checkPermission() == LocationPermission.denied) {
      if (DateTime.now().isAfter(granted)) fail('no location permission given');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    debugPrint('FEED LISTENING');
    const feed = GeolocatorFeed();
    final fixes = <Fix>[];
    final subscription = feed
        .guidance(
          const BackgroundNotice(title: 'Lunaway', text: 'Guidage en cours', channel: 'Guidage'),
        )
        .listen(fixes.add);
    final end = DateTime.now().add(const Duration(minutes: 2));
    while (fixes.length < 3 && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('FEED FIXES ${fixes.length}');
    await subscription.cancel();
    debugPrint('FEED STOPPED');
    // A moment for the service to leave the foreground, checked from outside.
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(fixes.length, greaterThanOrEqualTo(3));
    expect(fixes.last.position.lat, closeTo(45.83, 0.05));
    expect(fixes.last.accuracyM, lessThan(100));
  });
}
