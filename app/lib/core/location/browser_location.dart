import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/browser_location_stub.dart'
    if (dart.library.js_interop) 'package:lunaway/core/location/browser_location_web.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'browser_location.g.dart';

/// What the browser answered when asked for the position.
sealed class BrowserFix {
  const new();
}

/// A position, with its radius of uncertainty in metres when the browser
/// gives one.
final class BrowserPosition extends BrowserFix {
  const new(this.position, {this.accuracy});

  final LatLng position;
  final double? accuracy;
}

/// The user, or the browser's settings for the site, refused.
final class BrowserDenied extends BrowserFix {
  const new();
}

/// No position came: none available, too slow, or no geolocation at all
/// (a page not served over HTTPS has none).
final class BrowserNoFix extends BrowserFix {
  const new();
}

/// The browser's Geolocation API. The first call shows the browser's own
/// prompt, which some browsers only allow during a click: callers start it
/// before anything else they await.
abstract interface class BrowserLocation {
  Future<BrowserFix> locate();
}

/// The browser's position on the web; null on the other platforms, which
/// ask the system through their own permission flow.
// keepAlive: a stateless gateway to the browser for the whole run.
@Riverpod(keepAlive: true)
BrowserLocation? browserLocation(Ref ref) => kIsWeb ? const PlatformBrowserLocation() : null;
