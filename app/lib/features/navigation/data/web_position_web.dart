import 'dart:async';
import 'dart:js_interop';

import 'package:lunaway/core/geo/geo.dart';
import 'package:web/web.dart' as web;

/// The browser's position, through its own prompt; null when refused or
/// when none came in time.
Future<({LatLng position, double accuracyM})?> webPosition(Duration timeout) {
  final done = Completer<({LatLng position, double accuracyM})?>();
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition p) {
      if (!done.isCompleted) {
        done.complete((
          position: LatLng(p.coords.latitude, p.coords.longitude),
          accuracyM: p.coords.accuracy,
        ));
      }
    }).toJS,
    ((web.GeolocationPositionError _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS,
    web.PositionOptions(timeout: timeout.inMilliseconds, maximumAge: 60000),
  );
  return done.future.timeout(timeout, onTimeout: () => null);
}
