import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lunaway/core/layout/window_size.dart';

/// Whether a mouse and a keyboard are the usual input: a desktop build, or a
/// browser on a desktop system. On the web `defaultTargetPlatform` is the
/// browser's system, and an iPad asking for the desktop site still reads
/// as iOS (the engine counts its touch points).
bool get pointerPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
};

/// Whether the app draws its denser desktop look: a pointer platform in a
/// window wide enough for the rail. A narrow browser window keeps the touch
/// sizes, since it is laid out as a phone and may well be one.
bool pointerDensity(Size window) => pointerPlatform && WindowSize.ofWidth(window.width) != .compact;
