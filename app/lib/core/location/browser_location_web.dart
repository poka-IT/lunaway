import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/browser_location.dart';
import 'package:web/web.dart' as web;

/// `navigator.geolocation.getCurrentPosition`, called at once so the
/// browser sees the click that led here.
final class PlatformBrowserLocation implements BrowserLocation {
  const new();

  // GeolocationPositionError.PERMISSION_DENIED.
  static const _denied = 1;

  @override
  Future<BrowserFix> locate() {
    final done = Completer<BrowserFix>();
    // Absent outside a secure context (plain HTTP).
    if (!web.window.navigator.has('geolocation')) return Future.value(const BrowserNoFix());
    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition p) {
        if (done.isCompleted) return;
        done.complete(
          BrowserPosition(
            LatLng(p.coords.latitude, p.coords.longitude),
            accuracy: p.coords.accuracy,
          ),
        );
      }).toJS,
      ((web.GeolocationPositionError e) {
        if (done.isCompleted) return;
        done.complete(e.code == _denied ? const BrowserDenied() : const BrowserNoFix());
      }).toJS,
      // A position from the last minute will do; fifteen seconds at most,
      // the time a laptop's Wi-Fi positioning may take.
      web.PositionOptions(enableHighAccuracy: true, timeout: 15000, maximumAge: 60000),
    );
    return done.future;
  }
}
