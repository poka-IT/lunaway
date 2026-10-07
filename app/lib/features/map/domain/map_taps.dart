import 'dart:async';

import 'package:flutter/foundation.dart';

/// How far from a tap the maps look for something to open, in logical
/// pixels each way, and what a tap on bare map does.
///
/// Kept apart from the engines so that one rule serves the phone, the web
/// and the desktop maps, and so that a shared hit resolution can replace it
/// in one place.
abstract final class MapHit {
  /// A finger is wider than a pin: a tap this close to one opens it.
  static const double select = 14;

  /// Before a tap on bare map opens the card of a free point, the map looks
  /// this much further for a pin, a cluster or a marker: a tap that just
  /// missed one opens it rather than the free point.
  static const double freePoint = select * 1.5;

  /// From this zoom (street level) a tap on bare map opens the card of the
  /// point. Further out a tap there is no place in particular, and the map
  /// keeps its own behaviour: a click must not open anything.
  static const double freePointMinZoom = 14;

  /// A second tap within this time makes a double tap, which zooms: the
  /// first one then opens nothing. The browsers report both clicks before
  /// the double click.
  static const Duration doubleTapWindow = Duration(milliseconds: 250);

  /// The wait of [DoubleTapGate] on an engine: MapLibre Native on Android
  /// and iOS reports a tap only once it knows no second one follows, so the
  /// app adds no wait of its own there. MapLibre GL JS (the web, the desktop
  /// page) reports every click.
  static Duration doubleTapWindowFor({required bool web, required TargetPlatform platform}) =>
      !web && (platform == TargetPlatform.android || platform == TargetPlatform.iOS)
      ? Duration.zero
      : doubleTapWindow;
}

/// The features a tap at [zoom] reaches: those within [MapHit.select] when
/// there are any, else, from [MapHit.freePointMinZoom] where a bare tap
/// opens a point, those within [MapHit.freePoint]. Further out the map
/// keeps the selection's square alone, so a click there does no more than
/// it did. [query] reads the engine's rendered features in a square of that
/// half side around the tap.
Future<List<T>> featuresAroundTap<T>(
  Future<List<T>> Function(double slop) query, {
  required double? zoom,
}) async {
  final near = await query(MapHit.select);
  if (near.isNotEmpty || zoom == null || zoom < MapHit.freePointMinZoom) return near;
  return await query(MapHit.freePoint);
}

/// What a tap on bare map does.
enum BareTap {
  /// Closes what is open (a place's card, a free point), as in every map
  /// app.
  close,

  /// Opens the card of the point tapped.
  freePoint,

  /// Nothing: the map is too far out for a point to mean anything.
  nothing,
}

/// The outcome of a tap on bare map at [zoom], with something already open
/// or not. A tap elsewhere closes the open card first; the next one opens a
/// point, so a tap never swaps one card for another by surprise.
BareTap bareTapAt({required double zoom, required bool open}) {
  if (open) return BareTap.close;
  return zoom >= MapHit.freePointMinZoom ? BareTap.freePoint : BareTap.nothing;
}

/// Waits [window] after a tap on bare map before acting on it: a second tap
/// in that time is the end of a double tap (the map zooms) and cancels
/// both.
final class DoubleTapGate {
  new({this.window = MapHit.doubleTapWindow});

  final Duration window;
  Timer? _pending;

  /// Whether a tap waits for the end of its window.
  @visibleForTesting
  bool get waiting => _pending?.isActive ?? false;

  /// A tap on bare map: [act] runs once the window has passed without a
  /// second tap.
  void tap(VoidCallback act) {
    if (window == Duration.zero) return act();
    if (waiting) {
      cancel();
      return;
    }
    _pending = Timer(window, () {
      _pending = null;
      act();
    });
  }

  /// Drops the tap that waits: a pin was tapped, the map was dragged or
  /// left.
  void cancel() {
    _pending?.cancel();
    _pending = null;
  }
}
