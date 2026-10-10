import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/web_position.dart'
    if (dart.library.js_interop) 'package:lunaway/features/navigation/data/web_position_web.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

final _log = Logger('location');

/// The words of the Android notification that keeps the position coming
/// while guidance runs with the screen off.
@immutable
final class BackgroundNotice {
  const new({required this.title, required this.text, required this.channel});

  final String title;
  final String text;

  /// The name of the notification channel, in the system's settings.
  final String channel;
}

/// The device position: once for the start of a route, then a stream while
/// guiding. The permission is the screens' business: they ask, with an
/// explanation, before calling this.
abstract interface class LocationFeed {
  /// The position now; null when none came in time.
  Future<Fix?> current();

  /// The last position the device knew, with when it was taken, without
  /// asking the receiver: null when it knows none, or cannot tell (a
  /// browser).
  Future<Fix?> lastKnown();

  /// Fixes while guiding, until the subscription is cancelled.
  Stream<Fix> guidance(BackgroundNotice notice);
}

/// [LocationFeed] over geolocator: Android's location manager, Core
/// Location on iOS and macOS, the browser's on the web.
///
/// On Android, `forceLocationManager` keeps every request on the platform's
/// LocationManager, and the system's provider answers it. From Android 12
/// geolocator takes the `fused` provider when the device has one: Google
/// Play services serve it on a phone that carries them, the AOSP provider
/// or microG elsewhere. Before Android 12 it takes `gps`, else `network`.
/// Without the flag, geolocator would hand the request to Play services'
/// FusedLocationProviderClient whenever they are installed, which runs
/// Google's location library inside the app: the store declarations would
/// then have to cover what that library collects (`docs/play-store.md`,
/// "Location through Play Services").
final class GeolocatorFeed implements LocationFeed {
  const new();

  static const _timeout = Duration(seconds: 15);

  @override
  Future<Fix?> current() async {
    if (kIsWeb) {
      final p = await webPosition(_timeout);
      return p == null
          ? null
          : Fix(position: p.position, accuracyM: p.accuracyM, at: DateTime.now());
    }
    try {
      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(forceLocationManager: true, timeLimit: _timeout)
          : const LocationSettings(timeLimit: _timeout);
      final p = await GeolocatorPlatform.instance
          .getCurrentPosition(locationSettings: settings)
          .timeout(_timeout);
      return _fix(p);
    } on Object catch (e) {
      _log.info('no position: $e');
      return null;
    }
  }

  @override
  Future<Fix?> lastKnown() async {
    if (kIsWeb) return null;
    try {
      // On Android the platform's LocationManager, as every request here.
      final p = await GeolocatorPlatform.instance.getLastKnownPosition(forceLocationManager: true);
      return p == null ? null : _fix(p);
    } on Object catch (e) {
      _log.info('no last position: $e');
      return null;
    }
  }

  @override
  Stream<Fix> guidance(BackgroundNotice notice) => kIsWeb
      ? webFixes()
      : GeolocatorPlatform.instance
            .getPositionStream(locationSettings: _settings(notice))
            .map(_fix);

  /// A fix a second at full precision, standing still too (no distance
  /// filter): the arrival time and the alerts follow the fixes' clock,
  /// which must not stop in a queue. The cost of guidance is the GPS, on
  /// either way, and it stops with the guidance.
  static LocationSettings _settings(BackgroundNotice notice) {
    const accuracy = LocationAccuracy.bestForNavigation;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notice.title,
          notificationText: notice.text,
          notificationChannelName: notice.channel,
          // The voice must keep coming with the screen off: without the
          // lock, Android batches the fixes until the device wakes.
          enableWakeLock: true,
          setOngoing: true,
          color: const Color(0xFF061F43),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.automotiveNavigation,
        // Background updates are on by default (UIBackgroundModes location
        // in Info.plist); the blue pill tells the driver the position is in use.
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: accuracy);
  }

  static Fix _fix(Position p) => Fix(
    position: LatLng(p.latitude, p.longitude),
    accuracyM: p.accuracy,
    at: p.timestamp,
    courseDeg: p.heading >= 0 && p.speed > 0.5 ? p.heading : null,
    speedMps: p.speed >= 0 ? p.speed : null,
  );
}
