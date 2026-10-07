import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/features/navigation/presentation/web_view_route_map_stub.dart'
    if (dart.library.io) 'package:lunaway/features/navigation/presentation/web_view_route_map.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// A route line on the map.
@immutable
final class RouteMapLine {
  const new({required this.index, required this.points, required this.selected});

  /// The route's index in its answer, reported back on a tap.
  final int index;
  final List<LatLng> points;

  /// The chosen route draws above the others, in the brand's teal.
  final bool selected;

  /// The same line: its points are the route's own list, compared by
  /// identity, so a screen rebuilt at every fix sends the line only when
  /// the route changes.
  @override
  bool operator ==(Object other) =>
      other is RouteMapLine &&
      other.index == index &&
      other.selected == selected &&
      identical(other.points, points);

  @override
  int get hashCode => Object.hash(index, selected, identityHashCode(points));
}

/// What a point on the route map stands for.
enum RouteMarkKind {
  /// Where the route starts.
  origin,

  /// Where it ends.
  destination,

  /// A restriction passed with little margin.
  warning,

  /// A restriction the vehicle exceeds (no safe route).
  blocker,

  /// A road event on the route.
  event,

  /// A stop on the way.
  stop,

  /// A place of the map near the route: tapped, it becomes a stop.
  place,

  /// A fuel station the fuel list found.
  station,
}

@immutable
final class RouteMapMark {
  const new({required this.position, required this.kind, this.id});

  final LatLng position;
  final RouteMarkKind kind;

  /// What a tap on it reports (`place:<id>`, `poi:<id>`, `stop:<index>`);
  /// a mark without one is not tappable.
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is RouteMapMark && other.position == position && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(position, kind, id);
}

/// Where the camera looks.
@immutable
sealed class RouteCamera {
  const new();
}

/// The whole of [bounds] in view.
final class FitCamera extends RouteCamera {
  const new(this.bounds);

  final GeoBounds bounds;

  @override
  bool operator ==(Object other) => other is FitCamera && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

/// Behind the vehicle, the map turned to its course and tilted, as a
/// driver sees the road; closer in town, further out on a fast road
/// ([followZoom]). The map glides the vehicle from fix to fix
/// ([VehicleMotion]).
final class FollowCamera extends RouteCamera {
  const new({required this.position, this.course, this.speedMps});

  final LatLng position;
  final double? course;

  /// The speed of the vehicle, which sets how far the camera looks ahead.
  final double? speedMps;

  double get zoom => followZoom(speedMps);

  @override
  bool operator ==(Object other) =>
      other is FollowCamera &&
      other.position == position &&
      other.course == course &&
      other.speedMps == speedMps;

  @override
  int get hashCode => Object.hash(position, course, speedMps);
}

/// The vehicle on the map: its position on the route and its course.
@immutable
final class VehiclePuck {
  const new({required this.position, this.course});

  final LatLng position;
  final double? course;

  /// The same fix: the guidance screen rebuilds for many reasons besides a
  /// new position (a poll, the voice, a banner), and only a new fix may
  /// start a glide.
  @override
  bool operator ==(Object other) =>
      other is VehiclePuck && other.position == position && other.course == course;

  @override
  int get hashCode => Object.hash(position, course);
}

/// The route map's contract: data in, taps out. Built through
/// `routeMapBuilderProvider`, so tests draw a plain widget instead of a
/// platform view.
@immutable
final class RouteMapProps {
  const new({
    required this.style,
    required this.dark,
    required this.lines,
    required this.camera,
    this.marks = const [],
    this.vehicle,
    this.padding = EdgeInsets.zero,
    this.onLineTap,
    this.onMarkTap,
    this.onLongPress,
  });

  /// The basemap: a style URL or a style document (JSON text).
  final String style;
  final bool dark;
  final List<RouteMapLine> lines;
  final List<RouteMapMark> marks;
  final VehiclePuck? vehicle;
  final RouteCamera camera;

  /// Space covered by panels over the map: the camera frames what is left.
  final EdgeInsets padding;

  /// A tap on a route that is not the chosen one.
  final ValueChanged<int>? onLineTap;

  /// A tap on a mark that has an id.
  final ValueChanged<String>? onMarkTap;

  /// A long press on the map (a right click on a desktop), at that point.
  final ValueChanged<LatLng>? onLongPress;
}

typedef RouteMapBuilder = Widget Function(BuildContext context, RouteMapProps props);

/// The map engine of the platform, as for the main map: maplibre_gl on
/// Android, iOS and the web, MapLibre GL JS in a web view on macOS and
/// Windows.
Widget buildPlatformRouteMap(BuildContext context, RouteMapProps props) {
  if (kIsWeb) return GlRouteMap(props);
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => GlRouteMap(props),
    TargetPlatform.macOS || TargetPlatform.windows => WebViewRouteMap(props),
    _ => MessageView(title: context.t.map.unsupported),
  };
}

/// How the route layers look, for both engines.
abstract final class RouteLook {
  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// The chosen route: teal over a navy casing by day; a lighter teal over
  /// the night basemap.
  static String line({required bool dark}) => _hex(dark ? Palette.sarcelle300 : Palette.sarcelle);
  static String casing({required bool dark}) =>
      _hex(dark ? Palette.minuit950 : Palette.sarcelleProfonde);

  /// The other routes, quiet beside it.
  static String alternative({required bool dark}) =>
      _hex(dark ? Palette.minuit400 : Palette.minuit300);
  static String alternativeCasing({required bool dark}) =>
      _hex(dark ? Palette.minuit800 : Palette.minuit500);

  static const double lineWidth = 6;
  static const double casingWidth = 9.5;
  static const double alternativeWidth = 5;

  static String markFill(RouteMarkKind kind) => switch (kind) {
    RouteMarkKind.origin => _hex(Palette.sarcelle),
    RouteMarkKind.destination => _hex(Palette.minuit),
    // Coral is the colour of alerts; the amber stays the selection's.
    RouteMarkKind.warning => _hex(Palette.corail),
    RouteMarkKind.blocker => _hex(Palette.corail700),
    RouteMarkKind.event => _hex(Palette.corail800),
    RouteMarkKind.stop => _hex(Palette.sarcelleProfonde),
    RouteMarkKind.place => _hex(Palette.minuit400),
    RouteMarkKind.station => _hex(Palette.lanterne700),
  };

  static double markRadius(RouteMarkKind kind) => switch (kind) {
    RouteMarkKind.origin => 6,
    RouteMarkKind.destination => 9,
    // Places along the way are many: small, so the route stays readable
    // under them; a station is one picked.
    RouteMarkKind.place => 4,
    RouteMarkKind.station => 6,
    _ => 8,
  };

  static String markStroke = _hex(Palette.creme);
  static const double markStrokeWidth = 3;

  static String vehicleFill = _hex(Palette.lanterne);
  static String vehicleStroke = _hex(Palette.minuit);
}

/// The GeoJSON of [lines], alternatives first so the chosen route draws on
/// top.
Map<String, Object?> routeLinesCollection(List<RouteMapLine> lines, {required bool selected}) => {
  'type': 'FeatureCollection',
  'features': [
    for (final l in lines)
      if (l.selected == selected && l.points.length >= 2)
        {
          'type': 'Feature',
          'properties': {'index': l.index},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in l.points) [p.lon, p.lat],
            ],
          },
        },
  ],
};

Map<String, Object?> routeMarksCollection(List<RouteMapMark> marks) => {
  'type': 'FeatureCollection',
  'features': [
    for (final m in marks)
      {
        'type': 'Feature',
        'properties': {
          // `place` with an id is what the desktop map page reports a tap
          // on (assets/map/lunaway_map.js), whatever the mark is.
          'kind': m.id == null ? m.kind.name : 'place',
          'id': ?m.id,
          'fill': RouteLook.markFill(m.kind),
          'radius': RouteLook.markRadius(m.kind),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [m.position.lon, m.position.lat],
        },
      },
  ],
};

Map<String, Object?> vehicleCollection(VehiclePuck? v) => {
  'type': 'FeatureCollection',
  'features': [
    if (v != null)
      {
        'type': 'Feature',
        'properties': {'course': v.course ?? 0},
        'geometry': {
          'type': 'Point',
          'coordinates': [v.position.lon, v.position.lat],
        },
      },
  ],
};

/// Ids of the route map's sources and layers, shared by both engines.
abstract final class RouteLayers {
  static const alternativesSource = 'lw-route-alternatives';
  static const routeSource = 'lw-route';
  static const marksSource = 'lw-route-marks';
  static const vehicleSource = 'lw-route-vehicle';

  static const alternativesCasing = 'lw-route-alternatives-casing';
  static const alternatives = 'lw-route-alternatives-line';
  static const routeCasing = 'lw-route-casing';
  static const route = 'lw-route-line';
  static const marks = 'lw-route-marks';

  /// The marks with an id (places, stations, stops), above the others: the
  /// layer the desktop map page reads taps from.
  static const tappableMarks = 'lw-route-marks-tappable';
  static const vehicle = 'lw-route-vehicle';
  static const vehicleImage = 'lw-vehicle-arrow';
}

/// The vehicle's arrow, drawn once per screen density: a lantern-amber
/// chevron with a navy rim, pointing north (the layer turns it).
Future<Uint8List> vehicleArrowPng(double ratio) async {
  final size = 30 * ratio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final path = Path()
    ..moveTo(size / 2, size * 0.08)
    ..lineTo(size * 0.86, size * 0.88)
    ..lineTo(size / 2, size * 0.68)
    ..lineTo(size * 0.14, size * 0.88)
    ..close();
  canvas
    ..drawPath(
      path,
      Paint()
        ..color = Palette.minuit
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * ratio
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(path, Paint()..color = Palette.lanterne);
  final image = await recorder.endRecording().toImage(size.ceil(), size.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
