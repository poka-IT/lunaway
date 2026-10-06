import 'package:flutter/foundation.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart' as geo;
import 'package:permission_handler/permission_handler.dart';

/// Where the app stands with the device position, each case with its own
/// message and way out: never asked (explain first, then ask), refused for
/// good (only the system settings can change it), location turned off on
/// the device, or no position service at all.
enum LocationAccess { granted, notGranted, deniedForever, serviceOff, unsupported }

/// The platform's location permission, behind an interface so the screens'
/// flows are tested without a device.
abstract interface class LocationPermissions {
  Future<LocationAccess> status();

  /// Shows the system prompt; returns the access after the user's answer.
  Future<LocationAccess> request();

  /// Opens the app's page of the system settings; false when it could not.
  Future<bool> openSettings();
}

/// permission_handler on Android and iOS, geolocator on macOS and Windows,
/// the browser's own prompt on the web (which has no status to read).
final class PlatformLocationPermissions implements LocationPermissions {
  const new();

  static bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  Future<LocationAccess> status() async {
    // The browser asks when the map requests the position: nothing to
    // explain beforehand that its own prompt does not say.
    if (kIsWeb) return LocationAccess.granted;
    if (_mobile) {
      if (await Permission.locationWhenInUse.serviceStatus == ServiceStatus.disabled) {
        return LocationAccess.serviceOff;
      }
      return _fromHandler(await Permission.locationWhenInUse.status);
    }
    if (_desktop) {
      final g = geo.GeolocatorPlatform.instance;
      if (!await g.isLocationServiceEnabled()) return LocationAccess.serviceOff;
      return _fromGeolocator(await g.checkPermission());
    }
    return LocationAccess.unsupported;
  }

  @override
  Future<LocationAccess> request() async {
    if (kIsWeb) return LocationAccess.granted;
    if (_mobile) return _fromHandler(await Permission.locationWhenInUse.request());
    if (_desktop) {
      return _fromGeolocator(await geo.GeolocatorPlatform.instance.requestPermission());
    }
    return LocationAccess.unsupported;
  }

  @override
  Future<bool> openSettings() async {
    if (_mobile) return await openAppSettings();
    if (_desktop) return await geo.GeolocatorPlatform.instance.openAppSettings();
    return false;
  }

  static LocationAccess _fromHandler(PermissionStatus s) => switch (s) {
    PermissionStatus.granted || PermissionStatus.limited => LocationAccess.granted,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => LocationAccess.deniedForever,
    _ => LocationAccess.notGranted,
  };

  static LocationAccess _fromGeolocator(geo.LocationPermission p) => switch (p) {
    geo.LocationPermission.always || geo.LocationPermission.whileInUse => LocationAccess.granted,
    geo.LocationPermission.deniedForever => LocationAccess.deniedForever,
    geo.LocationPermission.unableToDetermine => LocationAccess.unsupported,
    geo.LocationPermission.denied => LocationAccess.notGranted,
  };
}
