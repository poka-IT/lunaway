import 'dart:async';
import 'dart:js_interop';

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
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

/// The browser's fixes while guiding (`watchPosition`): the satellites of a
/// phone when it has them (high accuracy), never a cached fix. Watching
/// starts with the listener and stops when it cancels. A refusal, or no
/// position for the moment, comes as an error: the guidance asks again
/// later, and says the position is lost once none came for a while
/// (`positionLostAfter`; some browsers report errors between fixes).
Stream<Fix> webFixes() {
  int? watch;
  Fix? last;
  late final StreamController<Fix> out;
  out = StreamController<Fix>(
    onListen: () {
      watch = web.window.navigator.geolocation.watchPosition(
        ((web.GeolocationPosition p) {
          final fix = withMotion(_fixOf(p), last);
          last = fix;
          out.add(fix);
        }).toJS,
        ((web.GeolocationPositionError e) => out.addError(
          WebPositionError(code: e.code, message: e.message),
        )).toJS,
        web.PositionOptions(enableHighAccuracy: true, maximumAge: 0),
      );
    },
    onCancel: () {
      if (watch case final id?) web.window.navigator.geolocation.clearWatch(id);
      watch = null;
    },
  );
  return out.stream;
}

/// A browser's fix. Heading and speed are null when the device does not
/// know them, which is the case of most computers and of a phone standing
/// still.
Fix _fixOf(web.GeolocationPosition p) {
  final c = p.coords;
  final heading = c.heading;
  final speed = c.speed;
  final moving = speed != null && speed.isFinite && speed > 0.5;
  return Fix(
    position: LatLng(c.latitude, c.longitude),
    accuracyM: c.accuracy,
    at: browserFixTime(p.timestamp, DateTime.now()),
    courseDeg: heading != null && heading.isFinite && moving ? heading : null,
    speedMps: speed != null && speed.isFinite && speed >= 0 ? speed : null,
  );
}

/// Why the browser gave no position: 1 refused, 2 unavailable, 3 too late.
final class WebPositionError implements Exception {
  const new({required this.code, required this.message});

  final int code;
  final String message;

  @override
  String toString() => 'browser position error $code: $message';
}
