import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

final _log = Logger('notifications');

/// The notification of the location service that guidance runs on Android.
/// From Android 13 it shows only with the permission to notify; guidance
/// runs without it, the notification then hidden from the drawer.
abstract interface class NotificationAccess {
  /// Asks for the permission when the system still may ask.
  Future<void> ask();
}

/// [NotificationAccess] through the system's permission dialog, on Android
/// only: iOS shows its own blue indicator, other platforms do not guide.
final class SystemNotificationAccess implements NotificationAccess {
  const new();

  @override
  Future<void> ask() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (await Permission.notification.isDenied) await Permission.notification.request();
    } on Object catch (e) {
      // The guidance starts all the same, its notification maybe hidden.
      _log.info('notification permission: $e');
    }
  }
}
