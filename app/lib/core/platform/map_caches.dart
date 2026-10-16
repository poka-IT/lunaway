import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android host's channel of the native maps (`MainActivity`), the one
/// `setMapLabelFades` also speaks on.
const _channel = MethodChannel('lunaway/map');

/// How long a map that let go of its cache keeps drawing before it pauses:
/// MapLibre Native frees the tiles as it draws its next frame, and a paused
/// map draws none. On the emulator, under the load of other builds, the
/// tiles were gone within this wait (`plan/research/139-memoire-android.md`).
const mapCacheReleaseFrame = Duration(milliseconds: 200);

/// Asks the native maps on Android to let go of what they keep beyond their
/// views: the tiles of the views left behind (after the country's view, a
/// hundred megabytes and more) and the engine's spare buffers. The tiles in
/// view stay, so a map shows the same thing when it comes back; a view left
/// behind is read again from the device's copy of the tiles when the user
/// returns to it, as it is once the engine's cache has moved on. Elsewhere,
/// or when the host does not answer, nothing changes.
Future<void> releaseMapCaches() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<void>('releaseCaches');
  } on PlatformException {
    // A map that went with its style meanwhile.
  } on MissingPluginException {
    // A host without the channel (tests, another embedding).
  }
}
