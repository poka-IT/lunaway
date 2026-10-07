import 'dart:js_interop';

import 'package:lunaway/core/geo/geo.dart';
import 'package:web/web.dart' as web;

@JS('lunawayPremap')
external _Premap? get _premap;

extension type _Premap._(JSObject _) implements JSObject {
  external _Camera? camera();
  external void handOver();
}

extension type _Camera._(JSObject _) implements JSObject {
  external double get lat;
  external double get lon;
  external double get zoom;
}

({LatLng center, double zoom})? premapCamera() {
  final camera = _premap?.camera();
  if (camera == null) return null;
  return (center: LatLng(camera.lat, camera.lon), zoom: camera.zoom);
}

void premapHandOver() => _premap?.handOver();

/// Where the page's first map reads what the app keeps for it (web/premap.js).
const _key = 'lunaway.premap';

String? _kept;

void premapRemember(String json) {
  if (json == _kept) return;
  _kept = json;
  try {
    web.window.localStorage.setItem(_key, json);
  } on Object {
    // Storage refused (private browsing, quota): the next visit opens on
    // France, as a first one does.
  }
}
