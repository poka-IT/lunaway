import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('lunaway/system');

/// Whether the system shows what was copied by itself: Android 13 and later
/// draw a preview of the clipboard, and a message from the app would say
/// the same thing twice. Elsewhere, or when the system does not answer, the
/// app says it.
Future<bool> systemShowsCopies() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _channel.invokeMethod<bool>('showsCopies') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
