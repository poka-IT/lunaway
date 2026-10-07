import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/features/navigation/presentation/web_view_route_map_stub.dart'
    if (dart.library.io) 'package:lunaway/features/navigation/presentation/web_view_route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
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

/// What a mark on the route map stands for: its badge, its row of the
/// legend, its words in a tooltip.
enum RouteMarkKind {
  /// Where the route starts.
  origin,

  /// Where it ends.
  destination,

  /// A stop on the way, numbered.
  stop,

  /// A road closed: on the route, gone around, or stopping every route.
  closure,

  /// Works on the route.
  works,

  /// Lanes closed, alternating traffic: passable, for information.
  lanes,

  /// A height limit.
  clearance,

  /// A weight limit.
  weight,

  /// Another limit: width, length, a ban.
  limit,

  /// A fuel station the fuel list found.
  fuel,

  /// A place of the map near the route: tapped, it becomes a stop.
  place;

  /// How pressing it is, for the colour of a group that holds it.
  MarkTone get tone => switch (this) {
    closure || clearance || weight || limit => MarkTone.alert,
    works || lanes => MarkTone.caution,
    origin || destination || stop || fuel || place => MarkTone.info,
  };

  /// Never merged into a group: the ends and the stops of the trip.
  bool get anchor => this == origin || this == destination || this == stop;
}

/// A point on the route map.
@immutable
final class RouteMapMark {
  const new({
    required this.id,
    required this.position,
    required this.kind,
    required this.badge,
    this.minor = false,
    this.label,
    this.side,
  });

  /// What a tap or a hover on it reports (`place:<id>`, `poi:<id>`,
  /// `stop:<index>`, `event:<id>`...), unique among the marks of a map.
  final String id;
  final LatLng position;
  final RouteMarkKind kind;
  final RouteBadge badge;

  /// Not about the vehicle (lanes closed, a place near the route): drawn
  /// smaller, from a closer zoom.
  final bool minor;

  /// Written on the badge: a stop's number, a limit's figure.
  final String? label;

  /// Written beside it: a station's price.
  final String? side;

  @override
  bool operator ==(Object other) =>
      other is RouteMapMark &&
      other.id == id &&
      other.position == position &&
      other.kind == kind &&
      other.badge == badge &&
      other.minor == minor &&
      other.label == label &&
      other.side == side;

  @override
  int get hashCode => Object.hash(id, position, kind, badge, minor, label, side);
}

/// What the pointer is over on the route map: a mark, or a group of them.
@immutable
final class RouteMapHover {
  const new({required this.at, this.mark, this.group});

  /// The pointer, in logical pixels of the map.
  final Offset at;

  /// The mark's id.
  final String? mark;

  /// The marks a group holds, by kind.
  final Map<RouteMarkKind, int>? group;
}

/// Marks the map shows and pulses at once: a row of the list was chosen.
@immutable
final class RouteMapFocus {
  const new({required this.marks, required this.position, required this.serial});

  final List<String> marks;

  /// Where the camera goes.
  final LatLng position;

  /// A new request each time, even for the same marks.
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is RouteMapFocus && other.serial == serial && listEquals(other.marks, marks);

  @override
  int get hashCode => Object.hash(serial, Object.hashAll(marks));
}

/// A tap on a mark: its id, and where it was in logical pixels of the map
/// when the engine tells.
typedef RouteMarkTap = void Function(String id, {Offset? at});

/// Where the camera looks.
@immutable
sealed class RouteCamera {
  const new();
}

/// The whole of [bounds] in view.
final class FitCamera extends RouteCamera {
  const new(this.bounds, {this.room = EdgeInsets.zero});

  final GeoBounds bounds;

  /// Room over the map the bounds keep clear of, on top of the map's
  /// padding: the preview's legend, open by itself the first time.
  final EdgeInsets room;

  @override
  bool operator ==(Object other) =>
      other is FitCamera && other.bounds == bounds && other.room == room;

  @override
  int get hashCode => Object.hash(bounds, room);
}

/// Behind the vehicle, the map turned to its course and tilted, as a
/// driver sees the road; closer in town, further out on a fast road
/// ([followZoom]). The map glides the vehicle from fix to fix
/// ([VehicleMotion]).
final class FollowCamera extends RouteCamera {
  const new({
    required this.position,
    this.course,
    this.speedMps,
    this.ease = FreeMap.recenterEase,
    this.request = 0,
  });

  final LatLng position;
  final double? course;

  /// The speed of the vehicle, which sets how far the camera looks ahead.
  final double? speedMps;

  /// How long the way in takes, from the view the map had.
  final Duration ease;

  /// Which request to follow this answers ("Recentrer", the magnet, the
  /// return after a while): a new one starts following again even when
  /// the screen never showed the map free in between.
  final int request;

  double get zoom => followZoom(speedMps);

  @override
  bool operator ==(Object other) =>
      other is FollowCamera &&
      other.position == position &&
      other.course == course &&
      other.speedMps == speedMps &&
      other.ease == ease &&
      other.request == request;

  @override
  int get hashCode => Object.hash(position, course, speedMps, ease, request);
}

/// Where the user left it: the camera stays as the last gesture put it,
/// the vehicle still glides on the map.
final class FreeCamera extends RouteCamera {
  const new({this.view});

  /// Where the camera last rested, for a map made anew (the phone turned
  /// and the other layout built its own map); a map that exists keeps its
  /// camera whatever this says, so it takes no part in equality.
  final FreeView? view;

  @override
  bool operator ==(Object other) => other is FreeCamera;

  @override
  int get hashCode => (FreeCamera).hashCode;
}

/// What an engine does with the camera the screen asks for after the one
/// it sent ([cameraStep]): a user's gesture that stopped following keeps
/// the map where the user puts it until the screen asks again to follow.
enum CameraStep {
  /// Nothing to send.
  none,

  /// Into following, easing from the view the map has.
  enterFollow,

  /// Following still: a new fix, a new zoom.
  follow,

  /// Following stops where the camera is.
  free,

  /// Flat and north up, then the whole route.
  overview,

  /// The bounds of a fitting camera.
  fit,
}

CameraStep cameraStep({
  required RouteCamera? sent,
  required RouteCamera next,
  required bool heldByUser,
}) => switch (next) {
  FollowCamera() when heldByUser => CameraStep.none,
  FollowCamera() when sent is! FollowCamera || sent.request != next.request =>
    CameraStep.enterFollow,
  FollowCamera() => next == sent ? CameraStep.none : CameraStep.follow,
  FreeCamera() => sent is FreeCamera ? CameraStep.none : CameraStep.free,
  FitCamera() when next == sent => CameraStep.none,
  FitCamera() => sent is FollowCamera || sent is FreeCamera ? CameraStep.overview : CameraStep.fit,
};

/// Whether a user's gesture still holds the camera once the screen asks
/// for [after] instead of [before]: a new request to follow ("Recentrer",
/// the magnet, the return after a while) lets it go, even one that came in
/// the same frame as the gesture; a gesture after that request holds it
/// again.
bool heldAfter({required bool held, required RouteCamera before, required RouteCamera after}) =>
    held &&
    !(after is FollowCamera && (before is! FollowCamera || before.request != after.request));

/// The page's report of a camera the user moved and left
/// (`lunawayRouteMotion`, `rest`), the map's own [size] when it says none.
FreeView freeViewOfPage(Map<Object?, Object?> event, {required Size size}) {
  double number(String key) => (event[key] as num?)?.toDouble() ?? 0;
  final (x, y) = (event['x'], event['y']);
  final (width, height) = (event['width'], event['height']);
  return FreeView(
    size: width is num && height is num ? Size(width.toDouble(), height.toDouble()) : size,
    center: switch ((event['lat'], event['lon'])) {
      (final num lat, final num lon) => LatLng(lat.toDouble(), lon.toDouble()),
      _ => null,
    },
    vehicle: x is num && y is num ? Offset(x.toDouble(), y.toDouble()) : null,
    zoom: number('zoom'),
    bearing: number('bearing'),
    tilt: number('pitch'),
  );
}

/// The camera a map made anew opens on: the vehicle's, the user's last
/// rest, or the middle of the route.
({LatLng target, double zoom, double tilt, double bearing}) initialCamera(RouteMapProps p) {
  final camera = p.camera;
  final route = [for (final l in p.lines) ...l.points];
  // A map with neither a route nor a vehicle has nothing to show: it opens
  // anywhere until one comes.
  final middle = GeoBounds.around(route)?.center ?? const LatLng(0, 0);
  return switch (camera) {
    FitCamera(:final bounds) => (target: bounds.center, zoom: 12, tilt: 0, bearing: 0),
    FollowCamera(:final position) => (
      target: position,
      zoom: camera.zoom,
      tilt: followTiltDeg,
      bearing: camera.course ?? 0,
    ),
    FreeCamera(:final view) => (
      target: view?.center ?? p.vehicle?.position ?? middle,
      zoom: view?.zoom ?? followZoom(null),
      tilt: view?.tilt ?? followTiltDeg,
      bearing: view?.bearing ?? p.vehicle?.course ?? 0,
    ),
  };
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

/// The places and points of interest the guidance map draws from the main
/// map's vector tiles (`RoutePlaceLayers`).
@immutable
final class RouteMapPlaces {
  const new({
    required this.placeTileJsonUrl,
    required this.poiTileJsonUrl,
    this.placeFilter,
    this.poiFilter,
  });

  /// `/places/tiles.json` and `/poi/tiles.json` on the API.
  final String placeTileJsonUrl;
  final String poiTileJsonUrl;

  /// The MapLibre filters of the places and of the points; null hides them.
  final List<Object>? placeFilter;
  final List<Object>? poiFilter;

  static const _deep = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is RouteMapPlaces &&
      other.placeTileJsonUrl == placeTileJsonUrl &&
      other.poiTileJsonUrl == poiTileJsonUrl &&
      _deep.equals(other.placeFilter, placeFilter) &&
      _deep.equals(other.poiFilter, poiFilter);

  @override
  int get hashCode =>
      Object.hash(placeTileJsonUrl, poiTileJsonUrl, _deep.hash(placeFilter), _deep.hash(poiFilter));
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
    this.highlighted = const {},
    this.focus,
    this.guiding = false,
    this.places,
    this.onLineTap,
    this.onMarkTap,
    this.onMarkHover,
    this.onEmptyTap,
    this.onCameraMove,
    this.onLongPress,
    this.onGesture,
    this.onTouch,
    this.onRest,
    this.onPlaceTap,
    this.onPoiTap,
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

  /// The marks drawn lit: under the pointer, or of the row under it.
  final Set<String> highlighted;

  /// The marks to bring into view and pulse.
  final RouteMapFocus? focus;

  /// The guidance's map: the user may pan, zoom, turn and tilt it at any
  /// time, following or not (the preview keeps north up).
  final bool guiding;

  /// The places and points of interest drawn under the route; null draws
  /// none.
  final RouteMapPlaces? places;

  /// A tap on a route that is not the chosen one.
  final ValueChanged<int>? onLineTap;

  /// A tap on a mark. A group of marks zooms in by itself.
  final RouteMarkTap? onMarkTap;

  /// The pointer came over a mark or a group, or left it (null). Only an
  /// engine with a mouse reports it.
  final ValueChanged<RouteMapHover?>? onMarkHover;

  /// A tap with no mark and no route within reach (`hitAroundTap`), at
  /// that point, with the map's zoom then.
  final void Function(LatLng at, double zoom)? onEmptyTap;

  /// The camera started moving: what is pinned over the map is out of place.
  final VoidCallback? onCameraMove;

  /// A long press on the map (a right click on a desktop), at that point.
  final ValueChanged<LatLng>? onLongPress;

  /// The user started moving the map: a drag, a pinch, a turn, a tilt, the
  /// wheel, a double tap. Following stops at once, before the screen
  /// answers with a [FreeCamera].
  final VoidCallback? onGesture;

  /// A finger or the mouse button went down on the map (true), or the last
  /// one came up (false).
  final ValueChanged<bool>? onTouch;

  /// The camera the user moved came to rest, with nothing pressing on the
  /// map: where the vehicle is drawn and how the map is turned.
  final ValueChanged<FreeView>? onRest;

  /// A tap on a place of [places], with what its tile says of it.
  final ValueChanged<PlaceSummary>? onPlaceTap;

  /// A tap on a point of interest of [places].
  final ValueChanged<PoiFeature>? onPoiTap;
}

typedef RouteMapBuilder = Widget Function(BuildContext context, RouteMapProps props);

/// The map engine of the platform, as for the main map: maplibre_gl on
/// Android, iOS and the web, MapLibre GL JS in a web view on macOS and
/// Windows.
Widget buildPlatformRouteMap(BuildContext context, RouteMapProps props) {
  // On the web the map is an HTML element: covered while a dialog or a
  // sheet is open, so their clicks and wheel stay theirs (as the main map).
  if (kIsWeb) return MapShield(child: GlRouteMap(props));
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

  static String vehicleFill = _hex(Palette.lanterne);
  static String vehicleStroke = _hex(Palette.minuit);

  /// The ring of a lit mark: the amber that means "this one".
  static String halo = _hex(LunaTokens.selection);
  static String haloRim = _hex(Palette.minuit);
  static String hex(Color c) => _hex(c);
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

/// The route map's targets, for the pointer ([nearestHit]): every badge
/// (a mark or a group of them), then the other routes, which a tap
/// anywhere along picks. A mark under the mouse is told so (`hover`), and
/// its lit ring gives way to the hover's (`RouteMarkStyle.haloOpacity`).
final Map<String, HitShape> routeHitShapes = {
  // The ends and stops over the marks, the marks over the minor ones.
  for (final (i, source) in RouteLayers.markSources.reversed.indexed)
    RouteLayers.badgesOf(source): HitShape(radius: _badgeHit, priority: 1 + i, hoverState: 'mark'),
  RouteLayers.alternatives: _lineHit,
  RouteLayers.alternativesCasing: _lineHit,
};

/// The size of a minor mark beside a major one.
const routeMinorScale = 0.72;

/// A badge's disc and rim, half of [RouteBadge.extent], smaller for a
/// minor mark (`size`, which a group takes from its largest mark).
const _badgeHit = StopsHit('size', [(routeMinorScale, 15.5 * routeMinorScale), (1, 15.5)]);
const _lineHit = HitShape(radius: FixedHit(0), priority: 9, line: true);

/// Ids of the route map's sources and layers, shared by both engines.
abstract final class RouteLayers {
  static const alternativesSource = 'lw-route-alternatives';
  static const routeSource = 'lw-route';
  static const vehicleSource = 'lw-route-vehicle';

  /// The ends and the stops, never grouped.
  static const anchorsSource = 'lw-route-anchors';

  /// The marks about the vehicle, grouped where they overlap.
  static const marksSource = 'lw-route-marks';

  /// The minor marks, grouped apart, from a closer zoom.
  static const minorSource = 'lw-route-minor';

  /// Bottom to top.
  static const List<String> markSources = [minorSource, marksSource, anchorsSource];

  static const alternativesCasing = 'lw-route-alternatives-casing';
  static const alternatives = 'lw-route-alternatives-line';
  static const routeCasing = 'lw-route-casing';
  static const route = 'lw-route-line';
  static const vehicle = 'lw-route-vehicle';
  static const vehicleImage = 'lw-vehicle-arrow';

  static String haloOf(String source) => '$source-halo';
  static String badgesOf(String source) => '$source-badges';
  static String sideOf(String source) => '$source-side';

  /// The badges, the topmost first: what a tap or a pointer picks among the
  /// marks ([routeHitShapes]).
  static final List<String> badges = [for (final s in markSources.reversed) badgesOf(s)];

  /// Every layer of the marks, bottom to top.
  static final List<String> markLayers = [
    for (final s in markSources) ...[haloOf(s), badgesOf(s), sideOf(s)],
  ];
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
