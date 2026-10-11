import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/route_progress.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_layer_order.dart';
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

  /// A speed camera, where its country lets its position be shown: never
  /// a danger zone, which is a band under the route.
  camera,

  /// A fuel station the fuel list found.
  fuel,

  /// A place of the map near the route: tapped, it becomes a stop.
  place;

  /// How pressing it is, for the colour of a group that holds it.
  MarkTone get tone => switch (this) {
    closure || clearance || weight || limit => MarkTone.alert,
    works || lanes || camera => MarkTone.caution,
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
    this.sideInk,
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

  /// Written on the badge: a stop's number; in the limit's sign beside a
  /// camera's badge, the limit.
  final String? label;

  /// Written beside it: a station's price, a restriction's figure.
  final String? side;

  /// The colour of [side]: a price's, by its rank among the prices shown;
  /// null for the navy.
  final Color? sideInk;

  @override
  bool operator ==(Object other) =>
      other is RouteMapMark &&
      other.id == id &&
      other.position == position &&
      other.kind == kind &&
      other.badge == badge &&
      other.minor == minor &&
      other.label == label &&
      other.side == side &&
      other.sideInk == sideInk;

  @override
  int get hashCode => Object.hash(id, position, kind, badge, minor, label, side, sideInk);
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
/// driver sees the road; framing the next maneuver, closer and flatter as
/// it comes, wider and toward the horizon down a straight ([autoAim]). The
/// map glides the vehicle from fix to fix ([VehicleMotion]) and eases the
/// camera toward [zoom], [tilt] and the course.
final class FollowCamera extends RouteCamera {
  const new({
    required this.position,
    this.course,
    this.zoom = AutoZoom.parkedZoom,
    this.tilt = AutoTilt.cruise,
    this.ease = FreeMap.recenterEase,
    this.request = 0,
  });

  final LatLng position;
  final double? course;

  /// The zoom and the tilt the camera eases toward ([autoAim]).
  final double zoom;
  final double tilt;

  /// How long the way in takes, from the view the map had.
  final Duration ease;

  /// Which request to follow this answers ("Recentrer", the magnet, the
  /// return after a while): a new one starts following again even when
  /// the screen never showed the map free in between.
  final int request;

  @override
  bool operator ==(Object other) =>
      other is FollowCamera &&
      other.position == position &&
      other.course == course &&
      other.zoom == zoom &&
      other.tilt == tilt &&
      other.ease == ease &&
      other.request == request;

  @override
  int get hashCode => Object.hash(position, course, zoom, tilt, ease, request);
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
      tilt: camera.tilt,
      bearing: camera.course ?? 0,
    ),
    FreeCamera(:final view) => (
      target: view?.center ?? p.vehicle?.position ?? middle,
      zoom: view?.zoom ?? AutoZoom.parkedZoom,
      tilt: view?.tilt ?? followTiltDeg,
      bearing: view?.bearing ?? p.vehicle?.course ?? 0,
    ),
  };
}

/// The vehicle on the map: its position on the route and its course.
@immutable
final class VehiclePuck {
  const new({required this.position, this.course, this.speedMps});

  final LatLng position;
  final double? course;

  /// The speed of the fix, when known: a parked vehicle's fixes wander
  /// around it, and the map does not glide the vehicle through them
  /// ([VehicleMotion.retarget]).
  final double? speedMps;

  /// The same fix: the guidance screen rebuilds for many reasons besides a
  /// new position (a poll, the voice, a banner), and only a new fix may
  /// start a glide. The speed alone moves nothing.
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

  /// A filter that keeps no place.
  static const List<Object> drawsNothing = [
    '==',
    ['get', 'id'],
    '',
  ];

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
    this.fuelPrices = const [],
    this.rich,
    this.zones = const [],
    this.traveledM,
    this.arrow,
    this.onLineTap,
    this.onMarkTap,
    this.onMarkHover,
    this.onEmptyTap,
    this.onCameraMove,
    this.onCameraIdle,
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

  /// The places and points of interest, their pins over the route; null draws
  /// none.
  final RouteMapPlaces? places;

  /// The price of the vehicle's fuel under the pins of the stations of
  /// [places] (`routePrices`); drawn with those pins only.
  final List<FuelLabel> fuelPrices;

  /// The few places drawn large, their photo or their pictogram; null
  /// draws none.
  final RouteMapRich? rich;

  /// The stretches of the chosen route a danger zone covers, highlighted
  /// under it: a stretch of road and nothing more, never a camera's place
  /// nor its picture (docs/speed-cameras.md). The screen passes only what
  /// the rules of the countries allow.
  final List<RouteSpan> zones;

  /// Metres of the chosen route behind the vehicle, drawn grey
  /// ([RouteLook.traveled]); null keeps what the map drew for this route
  /// (off the route, a distance along it means nothing; parked, a fix
  /// that wanders would move it for nothing), or none for a route it has
  /// not drawn yet.
  final double? traveledM;

  /// The arrow of the next maneuver on the route; null draws none.
  final ManeuverArrow? arrow;

  /// A tap on a route that is not the chosen one.
  final ValueChanged<int>? onLineTap;

  /// A tap on a mark. A group of marks zooms in by itself.
  final RouteMarkTap? onMarkTap;

  /// The pointer came over a mark or a group, or left it (null). Only an
  /// engine with a mouse reports it.
  final ValueChanged<RouteMapHover?>? onMarkHover;

  /// A tap with no mark and no route within reach (`hitAroundTap`), at
  /// that point, with the map's zoom then; `meant` as for the main map
  /// (`LunaMapProps.onEmptyTap`).
  final void Function(LatLng at, double zoom, {bool? meant})? onEmptyTap;

  /// The camera started moving: what is pinned over the map is out of place.
  final VoidCallback? onCameraMove;

  /// The camera came to rest after a move, whoever moved it: the preview's
  /// tap guard counts its quiet time from there (`MapTapGuard`).
  final VoidCallback? onCameraIdle;

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

/// How the route layers look, for every engine.
///
/// The chosen route stands above every road of the basemap, as a driver's
/// app draws it: wider than the widest road at each zoom (a motorway of the
/// basemap is 7.5 px at 15 and 21 px at 18), a saturated fill inside a dark
/// rim on both themes, never a tone of the basemap's roads or water. Its
/// width follows the zoom ([lineStops]); behind the vehicle it greys
/// ([traveled]). The other routes are thin and neutral beside it.
abstract final class RouteLook {
  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// The chosen route: a deep saturated teal inside a darker rim by day
  /// (4.8:1 against the land); a pale teal inside the night's darkest navy
  /// at night (11:1 against the land, and lighter than the night's
  /// slate motorways, 2.5:1, the rim between them).
  static String line({required bool dark}) =>
      _hex(dark ? Palette.sarcelle200 : Palette.sarcelleVive);
  static String casing({required bool dark}) =>
      _hex(dark ? Palette.minuit950 : Palette.sarcelle900);

  /// The chosen route behind the vehicle: a quiet grey inside a grey rim,
  /// the road already driven.
  static String traveled({required bool dark}) =>
      _hex(dark ? Palette.minuit500 : Palette.minuit200);
  static String traveledCasing({required bool dark}) =>
      _hex(dark ? Palette.minuit800 : Palette.minuit400);

  /// The other routes, thin and neutral beside it.
  static String alternative({required bool dark}) =>
      _hex(dark ? Palette.minuit400 : Palette.minuit300);
  static String alternativeCasing({required bool dark}) =>
      _hex(dark ? Palette.minuit800 : Palette.minuit500);

  /// The arrow of the next maneuver drawn on the route: white in a navy
  /// rim on both themes, as a road marking.
  static String arrow({required bool dark}) => _hex(Palette.white);
  static String arrowCasing({required bool dark}) => _hex(arrowRim);
  static const Color arrowRim = Palette.minuit950;

  /// The chosen route's fill by zoom, logical pixels: about twice a road's
  /// width in town, a little wider than a motorway out of town. Over the
  /// zooms the guidance follows at it is 9.4 (14.4, a motorway) to 11.7
  /// (17.1, a street corner), where Google Maps' is 10.2 to 10.5 (measured
  /// on the A41 at 110 km/h and in Lyon); the whole route seen at once is
  /// thinner.
  static const List<(double, double)> lineStops = [
    (8, 3),
    (11, 4.5),
    (13, 6.5),
    (14, 9),
    (15, 10),
    (17, 11.5),
    (19, 16),
    (21, 22),
  ];

  /// Its rim, each side, logical pixels.
  static const double rim = 2;

  /// The other routes, a little over half the chosen one.
  static const double alternativeShare = 0.6;

  /// The shaft of the maneuver's arrow, a share of the route's fill.
  static const double arrowShare = 0.62;

  /// [stops] as a MapLibre expression of the zoom, [plus] pixels wider and
  /// [times] as wide; exponential like the basemap's roads.
  static List<Object> byZoom(List<(double, double)> stops, {double times = 1, double plus = 0}) => [
    'interpolate',
    ['exponential', 1.5],
    ['zoom'],
    for (final (z, w) in stops) ...[z, w * times + plus],
  ];

  static final List<Object> lineWidthByZoom = byZoom(lineStops);
  static final List<Object> casingWidthByZoom = byZoom(lineStops, plus: 2 * rim);
  static final List<Object> alternativeWidthByZoom = byZoom(lineStops, times: alternativeShare);
  static final List<Object> alternativeCasingWidthByZoom = byZoom(
    lineStops,
    times: alternativeShare,
    plus: 3,
  );
  static final List<Object> arrowWidthByZoom = byZoom(lineStops, times: arrowShare);
  static final List<Object> arrowCasingWidthByZoom = byZoom(
    lineStops,
    times: arrowShare,
    plus: 2 * rim,
  );

  /// The route's colour along it ([fill]) with the part behind the vehicle,
  /// up to [traveledShare] of its length as the map measures it
  /// (`line-progress`, [RouteProgress]), in [behind].
  static List<Object> progressGradient(String fill, String behind, double traveledShare) => [
    'step',
    ['line-progress'],
    behind,
    traveledShare.clamp(0, 1).toDouble(),
    fill,
  ];

  /// The widths the legend's swatch draws, those of the map a little above
  /// zoom 13, the whole route seen at once.
  static const double lineWidth = 7;
  static const double casingWidth = lineWidth + 2 * rim;
  static const double alternativeWidth = lineWidth * alternativeShare;

  /// A danger zone: a soft coral band under the routes, wider than the chosen
  /// one's casing, as a highlighter would mark it on a paper map.
  static String zone = _hex(Palette.corail);
  static const double zoneWidth = 20;
  static final List<Object> zoneWidthByZoom = byZoom(lineStops, plus: 2 * rim + 9);
  static const double zoneOpacity = 0.4;

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

/// The GeoJSON of [zones]: the stretches of the chosen route of [lines]
/// they cover.
Map<String, Object?> routeZonesCollection(List<RouteMapLine> lines, List<RouteSpan> zones) {
  final line = lines.firstWhereOrNull((l) => l.selected)?.points ?? const <LatLng>[];
  return {
    'type': 'FeatureCollection',
    'features': [
      for (final z in zones)
        if (lineAlong(line, z) case final points when points.length >= 2)
          {
            'type': 'Feature',
            'properties': <String, Object?>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in points) [p.lon, p.lat],
              ],
            },
          },
    ],
  };
}

/// The paint of the route's line layer [id] ([RouteLayers.lineLayers]) in
/// the style's terms, the same on every engine; the chosen route grey up
/// to [traveledShare] of its length ([RouteProgress]). Every engine sends
/// the whole of it when the share moves: maplibre_gl resets a property it
/// is not given.
Map<String, Object> routeLinePaint(String id, {required bool dark, double traveledShare = 0}) =>
    switch (id) {
      RouteLayers.zones => {
        'line-color': RouteLook.zone,
        'line-width': RouteLook.zoneWidthByZoom,
        'line-opacity': RouteLook.zoneOpacity,
      },
      RouteLayers.alternativesCasing => {
        'line-color': RouteLook.alternativeCasing(dark: dark),
        'line-width': RouteLook.alternativeCasingWidthByZoom,
      },
      RouteLayers.alternatives => {
        'line-color': RouteLook.alternative(dark: dark),
        'line-width': RouteLook.alternativeWidthByZoom,
      },
      RouteLayers.routeCasing => {
        'line-color': RouteLook.casing(dark: dark),
        'line-width': RouteLook.casingWidthByZoom,
        'line-gradient': RouteLook.progressGradient(
          RouteLook.casing(dark: dark),
          RouteLook.traveledCasing(dark: dark),
          traveledShare,
        ),
      },
      RouteLayers.route => {
        'line-color': RouteLook.line(dark: dark),
        'line-width': RouteLook.lineWidthByZoom,
        'line-gradient': RouteLook.progressGradient(
          RouteLook.line(dark: dark),
          RouteLook.traveled(dark: dark),
          traveledShare,
        ),
      },
      RouteLayers.traveledCasing => {
        'line-color': RouteLook.traveledCasing(dark: dark),
        'line-width': RouteLook.casingWidthByZoom,
      },
      RouteLayers.traveled => {
        'line-color': RouteLook.traveled(dark: dark),
        'line-width': RouteLook.lineWidthByZoom,
      },
      RouteLayers.arrowCasing => {
        'line-color': RouteLook.arrowCasing(dark: dark),
        'line-width': RouteLook.arrowCasingWidthByZoom,
      },
      RouteLayers.arrow => {
        'line-color': RouteLook.arrow(dark: dark),
        'line-width': RouteLook.arrowWidthByZoom,
      },
      _ => throw ArgumentError.value(id, 'id', 'no line of the route map'),
    };

/// The source of the route's line layer [id].
String routeLineSource(String id) => switch (id) {
  RouteLayers.zones => RouteLayers.zonesSource,
  RouteLayers.alternativesCasing || RouteLayers.alternatives => RouteLayers.alternativesSource,
  RouteLayers.routeCasing || RouteLayers.route => RouteLayers.routeSource,
  RouteLayers.traveledCasing || RouteLayers.traveled => RouteLayers.traveledSource,
  RouteLayers.arrowCasing || RouteLayers.arrow => RouteLayers.arrowSource,
  _ => throw ArgumentError.value(id, 'id', 'no line of the route map'),
};

/// The layout of the maneuver arrow's head, in the style's terms; [scale]
/// as for the vehicle's arrow (an image pixel is a physical pixel on a
/// phone, a CSS pixel in a browser).
Map<String, Object> routeArrowHeadLayout(double scale) => {
  'icon-image': RouteLayers.arrowHeadImage,
  // As wide as [arrowHeadShare] shafts at every zoom.
  'icon-size': RouteLook.byZoom(
    RouteLook.lineStops,
    times: RouteLook.arrowShare * arrowHeadShare / arrowHeadExtent * scale,
  ),
  'icon-rotate': const ['get', 'course'],
  'icon-rotation-alignment': 'map',
  'icon-pitch-alignment': 'map',
  'icon-allow-overlap': true,
  'icon-ignore-placement': true,
};

/// The head of the maneuver's arrow, this many shafts wide.
const arrowHeadShare = 2.6;

/// The head's image, logical pixels across.
const arrowHeadExtent = 40.0;

/// The GeoJSON of the maneuver arrow's shaft.
Map<String, Object?> routeArrowCollection(ManeuverArrow? arrow) => {
  'type': 'FeatureCollection',
  'features': [
    if (arrow != null)
      {
        'type': 'Feature',
        'properties': <String, Object?>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in arrow.shaft) [p.lon, p.lat],
          ],
        },
      },
  ],
};

/// The GeoJSON of the maneuver arrow's head, at its tip.
Map<String, Object?> routeArrowHeadCollection(ManeuverArrow? arrow) => {
  'type': 'FeatureCollection',
  'features': [
    if (arrow != null)
      {
        'type': 'Feature',
        'properties': {'course': arrow.headCourse},
        'geometry': {
          'type': 'Point',
          'coordinates': [arrow.tip.lon, arrow.tip.lat],
        },
      },
  ],
};

/// The colours MapLibre Native gives a line's gradient along the whole of
/// it (a ramp of 256): a step of the gradient lands on one of them, so the
/// grey of a 300 km route moves by 1.2 km at a time.
const gradientRamp = 256;

/// What an engine draws of the part of the chosen route behind the vehicle,
/// recomputed when the vehicle moved by a few metres, kept off the route,
/// none on a new route: the gradient grey up to a colour of its ramp a
/// little behind the vehicle ([share], [RouteProgress.shareAt]), and from
/// there up to the vehicle a short grey line drawn over the route
/// ([tail]), which the ramp cannot place to the metre.
final class TraveledLine {
  List<LatLng>? _line;
  RouteProgress? _progress;
  double? _sentM;
  double? _lastM;

  /// The gradient's share drawn, or 0 before any.
  double share = 0;

  /// The grey from the gradient's end to the vehicle; empty before any.
  List<LatLng> tail = const [];

  /// The route drawn again from scratch (a new style): the next call sends
  /// what was drawn, or the vehicle's place when it has one.
  void forget() => _sentM = null;

  /// Whether the grey moved for [lines] with [traveledM] behind the
  /// vehicle ([share] and [tail] say how); false when the drawn one holds.
  bool next(List<RouteMapLine> lines, double? traveledM) {
    final line = lines.firstWhereOrNull((l) => l.selected)?.points;
    if (!identical(line, _line)) {
      _line = line;
      _progress = null;
      _sentM = null;
      _lastM = null;
    }
    // Measured once the route is driven: the preview's never is.
    if (traveledM != null && _progress == null && line != null && line.length >= 2) {
      _progress = RouteProgress(line);
    }
    final progress = _progress;
    final sent = _sentM;
    // Off the route, what was drawn holds, again after a new style.
    final m = traveledM ?? (sent == null ? _lastM ?? 0.0 : null);
    // Within a few metres the grey would move by a pixel or two at a
    // town's zoom: no call for it.
    if (m == null || (sent != null && (m - sent).abs() < 3)) return false;
    _sentM = m;
    _lastM = m;
    if (progress == null || m <= 0) {
      share = 0;
      tail = const [];
      return true;
    }
    // A whole colour of the ramp behind the one the vehicle is in: the
    // ramp blends each colour into the next over half a colour.
    final steps = (progress.shareAt(m) * gradientRamp).floor() - 1;
    share = steps <= 0 ? 0 : steps / gradientRamp;
    final from = math.max(0, progress.alongAt((steps - 0.5) / gradientRamp));
    tail = progress.between(from.toDouble(), m);
    return true;
  }
}

/// The GeoJSON of the grey up to the vehicle ([TraveledLine.tail]).
Map<String, Object?> routeTraveledCollection(List<LatLng> tail) => {
  'type': 'FeatureCollection',
  'features': [
    if (tail.length >= 2)
      {
        'type': 'Feature',
        'properties': <String, Object?>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in tail) [p.lon, p.lat],
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
/// Two badges the pointer is on at once go to the one drawn on top.
final Map<String, HitShape> routeHitShapes = {
  for (final source in RouteLayers.markSources)
    RouteLayers.badgesOf(source): HitShape(
      radius: _badgeHit,
      priority: RouteLayerOrder.hitPriority(RouteLayers.badgesOf(source)),
      hoverState: 'mark',
    ),
  RouteLayers.alternatives: _lineHit,
  RouteLayers.alternativesCasing: _lineHit,
};

/// The size of a minor mark beside a major one.
const routeMinorScale = 0.72;

/// A badge's disc and rim, half of [RouteBadge.extent], smaller for a
/// minor mark (`size`, which a group takes from its largest mark).
const _badgeHit = StopsHit('size', [(routeMinorScale, 15.5 * routeMinorScale), (1, 15.5)]);
final _lineHit = HitShape(
  radius: const FixedHit(0),
  priority: RouteLayerOrder.linePriority,
  line: true,
);

/// Ids of the route map's sources and layers, shared by both engines.
abstract final class RouteLayers {
  static const alternativesSource = 'lw-route-alternatives';
  static const routeSource = 'lw-route';

  /// The danger zones of the chosen route.
  static const zonesSource = 'lw-route-zones';
  static const zones = 'lw-route-zones-line';
  static const vehicleSource = 'lw-route-vehicle';

  /// The start and the arrival, never grouped.
  static const endsSource = 'lw-route-ends';

  /// The stops on the way, never grouped.
  static const stopsSource = 'lw-route-stops';

  /// The marks about the vehicle, grouped where they overlap.
  static const marksSource = 'lw-route-marks';

  /// The minor marks, grouped apart, from a closer zoom.
  static const minorSource = 'lw-route-minor';

  /// Bottom to top ([RouteLayerOrder] puts the rich marks between the stops
  /// and the ends).
  static const List<String> markSources = [minorSource, marksSource, stopsSource, endsSource];

  static const alternativesCasing = 'lw-route-alternatives-casing';
  static const alternatives = 'lw-route-alternatives-line';
  static const routeCasing = 'lw-route-casing';
  static const route = 'lw-route-line';

  /// The grey of the chosen route just behind the vehicle
  /// ([TraveledLine.tail]), over the route.
  static const traveledSource = 'lw-route-traveled';
  static const traveledCasing = 'lw-route-traveled-casing';
  static const traveled = 'lw-route-traveled-line';
  static const vehicle = 'lw-route-vehicle';
  static const vehicleImage = 'lw-vehicle-arrow';

  /// The arrow of the next maneuver on the route: its shaft, a stretch of
  /// the route, and its head.
  static const arrowSource = 'lw-route-arrow';
  static const arrowHeadSource = 'lw-route-arrow-tip';
  static const arrowCasing = 'lw-route-arrow-casing';
  static const arrow = 'lw-route-arrow-line';
  static const arrowHead = 'lw-route-arrow-head';
  static const arrowHeadImage = 'lw-route-arrow-head';

  /// The route's line layers, drawn by [routeLinePaint].
  static const List<String> lineLayers = [
    zones,
    alternativesCasing,
    alternatives,
    routeCasing,
    route,
    traveledCasing,
    traveled,
    arrowCasing,
    arrow,
  ];

  static String haloOf(String source) => '$source-halo';
  static String badgesOf(String source) => '$source-badges';
  static String sideOf(String source) => '$source-side';

  /// The badges, the topmost first: what a tap or a pointer picks among the
  /// marks ([routeHitShapes]).
  static final List<String> badges = [for (final s in markSources.reversed) badgesOf(s)];

  /// The layers of the marks of [source], bottom to top: the lit ring, the
  /// badges with their text, the text beside them.
  static List<String> layersOf(String source) => [haloOf(source), badgesOf(source), sideOf(source)];
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

/// The head of the maneuver's arrow, drawn once per screen density: a
/// white triangle in the arrow's rim, pointing north (the layer turns it),
/// [arrowHeadExtent] across.
Future<Uint8List> arrowHeadPng(double ratio) async {
  final size = arrowHeadExtent * ratio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final path = Path()
    ..moveTo(size / 2, size * 0.1)
    ..lineTo(size * 0.9, size * 0.8)
    ..lineTo(size * 0.1, size * 0.8)
    ..close();
  canvas
    ..drawPath(
      path,
      Paint()
        ..color = RouteLook.arrowRim
        // The shaft's rim, at the scale the head is drawn.
        ..strokeWidth = 4.5 * ratio
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(path, Paint()..color = Palette.white);
  final image = await recorder.endRecording().toImage(size.ceil(), size.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
