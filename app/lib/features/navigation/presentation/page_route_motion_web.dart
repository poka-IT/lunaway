import 'dart:js_interop';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/presentation/page_route_motion.dart' as contract;

export 'package:lunaway/features/navigation/presentation/page_route_motion.dart'
    show PageRouteMotion;

@JS('lunawayRouteMotion')
external _Binder? get _binder;

extension type _Binder._(JSObject _) implements JSObject {
  external _Run? bind(String tag, JSFunction emit);
  external void dropImage(String tag, String id);
}

/// Takes the image [id] off the page's map that holds the source [tag]:
/// GL JS keeps the first image added under an id, and the rich marks fill
/// their image slots again (`RichMarkEngine.putImage`).
void dropPageImage(String tag, String id) => _binder?.dropImage(tag, id);

extension type _Run._(JSObject _) implements JSObject {
  external void vehicle(String source, double lat, double lon, double? course, JSBoolean jump);
  external void clear();
  external void follow(JSAny options);
  external void free();
  external void overview();
  external void guiding(JSBoolean on);
  external void watch(JSBoolean on);
}

final class _PageRouteMotion implements contract.PageRouteMotion {
  new(this._run);

  final _Run _run;

  @override
  void vehicle(String source, LatLng position, double? course, {required bool jump}) =>
      _run.vehicle(source, position.lat, position.lon, course, jump.toJS);

  @override
  void clear() => _run.clear();

  @override
  void follow({
    required double zoom,
    required EdgeInsets padding,
    required Duration ease,
    required bool enter,
  }) => _run.follow(
    {
      'zoom': zoom,
      'padding': {
        'top': padding.top,
        'bottom': padding.bottom,
        'left': padding.left,
        'right': padding.right,
      },
      'ease': ease.inMilliseconds,
      'enter': enter,
    }.jsify()!,
  );

  @override
  void free() => _run.free();

  @override
  void overview() => _run.overview();

  @override
  void guiding({required bool on}) => _run.guiding(on.toJS);

  @override
  void watch({required bool on}) => _run.watch(on.toJS);
}

/// The motion of the page's map that holds the source [tag], reporting its
/// events to [onEvent]; null while the page has no such map (its style is
/// still loading).
contract.PageRouteMotion? bindPageRouteMotion(
  String tag,
  void Function(Map<Object?, Object?> event) onEvent,
) {
  final binder = _binder;
  if (binder == null) return null;
  final run = binder.bind(
    tag,
    ((JSAny? event) {
      final value = event.dartify();
      if (value is Map) onEvent(value);
    }).toJS,
  );
  return run == null ? null : _PageRouteMotion(run);
}
