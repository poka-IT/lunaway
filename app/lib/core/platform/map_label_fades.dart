import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('lunaway/map');

/// Whether the native map whose style holds the source [tag] fades its
/// labels in and out as they are placed ([on]), on Android
/// (`MainActivity`, the style's `TransitionOptions`). With the fades,
/// MapLibre Native keeps drawing between two moves of the camera (measured
/// on an emulator: a frame every 25 ms for a move every 100 ms); without
/// them it draws when the app moves the map, and the guidance's cadence
/// holds (`plan/research/124-cadence-carte-guidage.md`). The maplibre_gl
/// plugin has no call for it. Elsewhere, or when the system does not
/// answer, nothing changes.
Future<void> setMapLabelFades(String tag, {required bool on}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<void>('labelFades', {'source': tag, 'on': on});
  } on PlatformException {
    // The map went with its style before the call landed.
  } on MissingPluginException {
    // A host without the channel (tests, another embedding).
  }
}
