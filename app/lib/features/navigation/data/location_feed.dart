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

  /// Fixes while guiding, until the subscription is cancelled.
  Stream<Fix> guidance(BackgroundNotice notice);
}

/// [LocationFeed] over geolocator: the fused provider where Play Services
/// exist and Android's own location manager otherwise (the F-Droid build
/// leaves them out); Core Location on iOS and macOS; the browser's on the
/// web.
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
      final p = await GeolocatorPlatform.instance
          .getCurrentPosition(locationSettings: const LocationSettings(timeLimit: _timeout))
          .timeout(_timeout);
      return _fix(p);
    } on Object catch (e) {
      _log.info('no position: $e');
      return null;
    }
  }

  @override
  Stream<Fix> guidance(BackgroundNotice notice) =>
      GeolocatorPlatform.instance.getPositionStream(locationSettings: _settings(notice)).map(_fix);

  /// A fix a second while moving and none while parked, the satellites at
  /// full precision: the cost of guidance is the GPS, and it stops with
  /// the guidance.
  static LocationSettings _settings(BackgroundNotice notice) {
    const accuracy = LocationAccuracy.bestForNavigation;
    const distanceFilter = 2;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
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
        distanceFilter: distanceFilter,
        activityType: ActivityType.automotiveNavigation,
        // Background updates are on by default (UIBackgroundModes location
        // in Info.plist); the blue pill tells the driver the position is in use.
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }

  static Fix _fix(Position p) => Fix(
    position: LatLng(p.latitude, p.longitude),
    accuracyM: p.accuracy,
    at: p.timestamp,
    courseDeg: p.heading >= 0 && p.speed > 0.5 ? p.heading : null,
    speedMps: p.speed >= 0 ? p.speed : null,
  );
}
