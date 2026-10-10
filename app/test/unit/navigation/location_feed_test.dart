import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';

/// Answers every request with one fix and keeps the settings it came with.
final class _RecordingGeolocator extends GeolocatorPlatform {
  final List<LocationSettings?> asked = [];

  static final _fix = Position(
    latitude: 45.7772,
    longitude: 3.087,
    timestamp: DateTime.utc(2026, 10, 10),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    asked.add(locationSettings);
    return _fix;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    asked.add(locationSettings);
    return Stream.value(_fix);
  }
}

/// On Android, geolocator hands a request without `forceLocationManager` to
/// Play services' FusedLocationProviderClient whenever they are installed,
/// and Google's location library then runs inside the app
/// (docs/play-store.md, "Location through Play Services"). Both reads of
/// the position must stay on the platform's LocationManager.
void main() {
  late GeolocatorPlatform original;
  late _RecordingGeolocator geolocator;

  setUp(() {
    original = GeolocatorPlatform.instance;
    geolocator = _RecordingGeolocator();
    GeolocatorPlatform.instance = geolocator;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    GeolocatorPlatform.instance = original;
  });

  final onLocationManager = isA<AndroidSettings>().having(
    (s) => s.forceLocationManager,
    'forceLocationManager',
    isTrue,
  );

  test("the start of a route reads the position through Android's location manager", () async {
    final fix = await const GeolocatorFeed().current();

    expect(fix?.position.lat, closeTo(45.7772, 1e-9));
    expect(geolocator.asked, [onLocationManager]);
  });

  test("guidance follows the position through Android's location manager", () async {
    const notice = BackgroundNotice(title: 'Lunaway', text: 'Guidage en cours', channel: 'Guidage');
    await const GeolocatorFeed().guidance(notice).first;

    expect(geolocator.asked, [onLocationManager]);
  });
}
