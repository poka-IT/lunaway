import 'dart:js_interop';

import 'package:lunaway/core/geo/geo.dart';
import 'package:web/web.dart' as web;

@JS('lunawayPremap')
external _Premap? get _premap;

extension type _Premap._(JSObject _) implements JSObject {
  external _Camera? camera([JSNumber? x, JSNumber? y]);
  external _Place? takePlace();
  external void handOver();
}

extension type _Place._(JSObject _) implements JSObject {
  external JSAny? get properties;
  external JSArray<JSNumber>? get coordinates;
}

({Map<Object?, Object?> properties, List<Object?> coordinates})? premapTakePlace() {
  final place = _premap?.takePlace();
  if (place == null) return null;
  final properties = place.properties.dartify();
  final coordinates = place.coordinates?.toDart.map((n) => n.toDartDouble).toList();
  if (properties is! Map || coordinates == null) return null;
  return (properties: properties.cast<Object?, Object?>(), coordinates: coordinates);
}

extension type _Camera._(JSObject _) implements JSObject {
  external double get lat;
  external double get lon;
  external double get zoom;
}

({LatLng center, double zoom})? premapCamera({double? x, double? y}) {
  final premap = _premap;
  if (premap == null) return null;
  final camera = x != null && y != null ? premap.camera(x.toJS, y.toJS) : premap.camera();
  if (camera == null) return null;
  return (center: LatLng(camera.lat, camera.lon), zoom: camera.zoom);
}

void premapHandOver() => _premap?.handOver();

/// Where the page's first map reads what the app keeps for it (web/premap.js).
const _key = 'lunaway.premap';
const _frameKey = 'lunaway.premapFrame';

String? _kept;
String? _keptFrame;

void premapRemember(String json) {
  if (json == _kept) return;
  _kept = json;
  _store(_key, json);
}

void premapRememberFrame(String json) {
  if (json == _keptFrame) return;
  _keptFrame = json;
  _store(_frameKey, json);
}

void _store(String key, String json) {
  try {
    web.window.localStorage.setItem(key, json);
  } on Object {
    // Storage refused (private browsing, quota): the next visit opens on
    // France, as a first one does.
  }
}
