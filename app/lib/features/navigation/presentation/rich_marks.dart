import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/presentation/route_layer_order.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_mark_layers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

final _log = Logger('rich_marks');

/// The words of the illustrated marks' labels, in the app's language.
@immutable
final class RichWords {
  const new({required this.free, required this.nightOk, required this.price, required this.rating});

  /// The words of [t]'s language, one instance per language: the route
  /// map's props compare them by identity.
  factory of(Translations t) => _byLanguage[t] ??= RichWords(
    free: t.navigation.guidance.places.free,
    nightOk: t.navigation.guidance.places.nightOk,
    price: t.euros,
    rating: t.ratingValue,
  );

  static final _byLanguage = Expando<RichWords>();

  final String free;
  final String nightOk;
  final String Function(double eur) price;

  /// The figure alone: the painter draws the star before it.
  final String Function(double rating) rating;

  String text(RichLabel label) => switch (label) {
    FreeLabel() => free,
    PriceLabel(:final eur) => price(eur),
    RatingLabel(rating: final r) => rating(r),
    NightLabel() => nightOk,
  };
}

/// What the art reads of the map's choice.
@immutable
final class RichStyle {
  const new({
    required this.look,
    required this.words,
    this.online = true,
    this.credited = false,
    this.muted = const {},
    this.labelScale = 1,
  });

  final GuidanceLook look;
  final RichWords words;

  /// Whether the API answers: offline, a mark keeps its pictogram.
  final bool online;

  /// Whether the screen names the external community source with the map,
  /// whose mention its licence requires wherever its photos show: the
  /// map's credit (the preview's `MapCredit`, the guidance's in its bar or
  /// over the map) adds its line of the photos while [photos] holds. A
  /// screen without the room for that line draws no photo. Lunaway's
  /// community photos name their author on the place's card, a tap away
  /// (`communityPhotoSource`).
  final bool credited;

  /// The authors whose photos this device hides.
  final Set<String> muted;

  /// The labels' size beside their own, from the system's text size.
  final double labelScale;

  /// Whether a mark may be a photo.
  bool get photos => look == GuidanceLook.photos && online && credited;

  @override
  bool operator ==(Object other) =>
      other is RichStyle &&
      other.look == look &&
      identical(other.words, words) &&
      other.online == online &&
      other.credited == credited &&
      setEquals(other.muted, muted) &&
      other.labelScale == labelScale;

  @override
  int get hashCode => Object.hash(
    look,
    identityHashCode(words),
    online,
    credited,
    Object.hashAllUnordered(muted),
    labelScale,
  );
}

/// How a place's mark looks, decided before it is drawn: the shape the
/// selection keeps clear, and what tells two drawings apart.
@immutable
final class RichPlan {
  const new({this.capsule = false, this.label, this.star = false, this.labelWidth = 0});

  /// The place's photo.
  static const photo = RichPlan();

  /// The pictogram, its label and the label's width, or none.
  final bool capsule;

  /// The label's words; null for none.
  final String? label;

  /// A star before the words: they are a rating.
  final bool star;

  /// The label's width, its padding included.
  final double labelWidth;

  String get key => capsule ? 'c:${star ? '*' : ''}${label ?? ''}' : 'p';

  RichGeometry geometry(double size) =>
      RichGeometry(size, labelWidth: labelWidth, capsule: capsule);

  @override
  bool operator ==(Object other) =>
      other is RichPlan &&
      other.capsule == capsule &&
      other.label == label &&
      other.star == star &&
      other.labelWidth == labelWidth;

  @override
  int get hashCode => Object.hash(capsule, label, star, labelWidth);
}

/// What a rich mark of a place shows, once drawn.
@immutable
final class RichArtwork {
  const new({required this.png, required this.geometry});

  final Uint8List png;
  final RichGeometry geometry;
}

/// Draws the rich marks: asks the API what a place's photo and price are,
/// fetches the photo, paints the mark.
abstract interface class RichArt {
  /// How [place]'s mark looks with what is known of it now; null while
  /// that is not known yet, the place staying a small pin meanwhile. With
  /// [ask], its photo and price are asked, and [onReady] called once they
  /// are known; without, a place not known yet waits for a pass that asks.
  RichPlan? plan(PlaceSummary place, RichStyle style, {bool ask = true, VoidCallback? onReady});

  /// The mark of [place] as [plan] says, at [size], at [ratio] physical
  /// pixels per logical one; null when it cannot be drawn so (a photo that
  /// does not come: the next plan is the pictogram).
  Future<RichArtwork?> draw(
    PlaceSummary place,
    RichPlan plan, {
    required double size,
    required double ratio,
    required RichStyle style,
  });
}

/// How the route map draws its rich marks (`RouteMapProps.rich`).
@immutable
final class RouteMapRich {
  const new({
    required this.style,
    required this.art,
    this.tiles = false,
    this.places = const [],
    this.clear = EdgeInsets.zero,
    this.obstacles = const [],
    this.limit = RichMarks.compactLimit,
    this.sizes = RichMarks.phone,
    this.yielding = false,
    this.vehicleAlongM,
    this.speedMps,
  });

  final RichStyle style;
  final RichArt art;

  /// The places of the tiles drawn in view are candidates (the guidance,
  /// online).
  final bool tiles;

  /// Places the screen holds are candidates too: the preview's places near
  /// the route, the device's offline. Each is drawn as the small route mark
  /// `place:<id>`, hidden while the place stands out.
  final List<PlaceSummary> places;

  /// The edges of the map something covers ([RichFrame.clear]).
  final EdgeInsets clear;

  /// What covers a part of the map only ([RichFrame.obstacles]).
  final List<Rect> obstacles;
  final int limit;
  final RichSizes sizes;

  /// A complex maneuver is close: the marks step aside ([richMarksYield]).
  final bool yielding;

  /// How far along the route the vehicle is; null without a guidance.
  final double? vehicleAlongM;
  final double? speedMps;

  /// Below the zoom the small pins start at, no place shows, and none
  /// stands out.
  static const double minZoom = 10;

  /// Whether any mark may stand out now.
  bool get active => style.look.rich && !yielding && limit > 0;

  @override
  bool operator ==(Object other) =>
      other is RouteMapRich &&
      other.style == style &&
      identical(other.art, art) &&
      other.tiles == tiles &&
      listEquals(other.places, places) &&
      other.clear == clear &&
      listEquals(other.obstacles, obstacles) &&
      other.limit == limit &&
      other.sizes == sizes &&
      other.yielding == yielding &&
      other.vehicleAlongM == vehicleAlongM &&
      other.speedMps == speedMps;

  @override
  int get hashCode => Object.hash(
    style,
    identityHashCode(art),
    tiles,
    Object.hashAll(places),
    clear,
    Object.hashAll(obstacles),
    limit,
    sizes,
    yielding,
    vehicleAlongM,
    speedMps,
  );
}

/// Ids of the rich marks' source and layers, shared by the engines.
abstract final class RichLayers {
  static const source = 'lw-route-rich';

  /// The marks themselves, over the small pins, the names and the marks of
  /// the route but the start and the arrival ([RouteLayerOrder]).
  static const marks = 'lw-route-rich-marks';

  /// Every place of the tiles in view, drawn invisible: a pin the engine
  /// left out for want of room is still a candidate.
  static const probe = 'lw-route-place-probe';

  /// The prefix of the marks' images.
  static const imagePrefix = 'lw-rich-';

  /// A mark's properties beyond its place's (those of the tiles).
  static const image = 'img';
  static const scale = 'scale';
  static const rank = 'rank';
  static const headRadius = 'hr';
  static const lift = 'lift';
  static const mark = 'mark';

  /// The marks' layout: the image of each anchored by its tip, at the size
  /// its scale says ([scale] brings an image pixel to the engine's unit),
  /// upright whatever the camera. Always drawn: the choice already keeps
  /// them apart and clear of what driving needs, and a mark the engine
  /// left out would leave its place without even its small badge (hidden
  /// while it stands out). Each still takes its room: the pins and the
  /// names under it give way rather than draw through it.
  static Map<String, Object?> layout(double scale) => {
    'icon-image': const ['get', image],
    'icon-size': [
      '*',
      scale,
      const ['get', RichLayers.scale],
    ],
    'icon-anchor': 'bottom',
    'icon-allow-overlap': true,
    'icon-ignore-placement': false,
    'icon-pitch-alignment': 'viewport',
    'icon-rotation-alignment': 'viewport',
    'symbol-sort-key': const ['get', rank],
  };

  /// The probe's paint: a dot nobody sees.
  static const Map<String, Object?> probePaint = {
    'circle-radius': 2,
    'circle-opacity': 0,
    'circle-stroke-width': 0,
  };

  /// What the pointer picks: the head, standing [lift] above the place,
  /// at the size the mark is drawn.
  static final HitShape hit = HitShape(
    radius: const PropertyHit(headRadius),
    lift: const PropertyHit(lift),
    priority: RouteLayerOrder.hitPriority(marks),
  );
}

/// What an engine does for the rich marks.
abstract interface class RichMarkEngine {
  /// The places of the tiles drawn in view ([RichLayers.probe]).
  Future<List<({Map<Object?, Object?> properties, LatLng at})>> tilePlaces();

  /// Where [points] are drawn and how the camera looks; null when the
  /// engine cannot tell.
  Future<RichView?> view(List<LatLng> points);

  /// Adds the image [id], or replaces it; false when it could not be added.
  /// The marks draw from a few image slots, filled again as places come
  /// and go (maplibre_gl cannot remove an image on Android and iOS, where
  /// adding one of a known id replaces it).
  Future<bool> putImage(String id, Uint8List png);

  /// Shows [collection] in [RichLayers.source], and hides the route marks
  /// of [hiddenMarks].
  Future<void> show(Map<String, Object?> collection, {required List<String> hiddenMarks});
}

/// What an engine tells of points on its screen.
@immutable
final class RichView {
  const new({required this.points, required this.zoom, this.pitch = 0, this.centre});

  /// Each point asked, logical pixels of the map; null for one the engine
  /// could not place.
  final List<Offset?> points;
  final double zoom;

  /// The camera's tilt, degrees from straight down.
  final double pitch;

  /// Where the point the camera looks at is drawn, for the perspective
  /// ([symbolPerspective]).
  final Offset? centre;
}

/// What the driver reads of the route map at each pass.
@immutable
final class RichInput {
  const new({
    required this.rich,
    required this.size,
    required this.ratio,
    this.line = const [],
    this.vehicle,
    this.marks = const [],
  });

  final RouteMapRich rich;

  /// The map's size, logical pixels.
  final Size size;

  /// Physical pixels per logical one.
  final double ratio;

  /// The route chosen.
  final List<LatLng> line;
  final LatLng? vehicle;

  /// The route's own marks (a closure, a limit, a camera, a stop, the
  /// ends; [routeSigns]): no rich mark covers one, nor the text beside it.
  final List<RouteSign> marks;
}

/// A mark of the route a rich mark keeps clear of: where it stands, and
/// the text written beside its badge, if any.
typedef RouteSign = ({LatLng at, String? side});

/// The marks of [marks] the rich marks keep clear of: all but the places
/// near the route, whose small badge a rich mark stands for.
List<RouteSign> routeSigns(List<RouteMapMark> marks) => [
  for (final m in marks)
    if (m.kind != RouteMarkKind.place) (at: m.position, side: m.side),
];

/// The room a route's mark takes, its badge and a margin.
const double _routeMarkRoom = 30;

/// The room a mark of the route standing at [at] takes on the map: its
/// badge and a margin, and the text beside it ([side]: a station's price, a
/// camera's limit), which the rich marks drawn over the marks would
/// otherwise hide. The engine does not tell where it wrote that text: its
/// figures are taken at 0.6 em each, with their halo.
@visibleForTesting
Rect routeSignRoom(Offset at, String? side) {
  final badge = Rect.fromCenter(center: at, width: _routeMarkRoom, height: _routeMarkRoom);
  if (side == null || side.isEmpty) return badge;
  const size = RouteMarkStyle.sideTextSize;
  final end = at.dx + (RouteMarkStyle.sideEms + side.length * 0.6) * size + RouteMarkStyle.sideHalo;
  return Rect.fromLTRB(badge.left, badge.top, math.max(badge.right, end), badge.bottom);
}

/// The finest the whole route of a map without a vehicle is kept, metres:
/// 3 px at zoom 16 and 6 at zoom 17 in France, how far a mark's head may
/// then come over the road's middle. A pixel's metres there would keep
/// about twice the points, each placed at every pass: on the route
/// fixtures, 900 to 1 000 per 100 km at zoom 15, against 500 to 600 at
/// 5 m.
const double _wholeFinestM = 5;

/// What a pixel of a map covers at [zoom] at [lat], metres: Web Mercator
/// with 512-pixel tiles, as MapLibre draws.
double _metresPerPixel(double lat, double zoom) =>
    40075016.686 * math.cos(lat * math.pi / 180) / (512 * math.pow(2, zoom));

/// The places asked about per mark a map may show: the choice still drops
/// some once their shape is known (a capsule wider than a photo), and the
/// next ones in line are known by then.
const int _askedPerMark = 3;

/// Keeps the rich marks of one route map: at each pass reads the places in
/// view and the screen, chooses ([chooseRichMarks]), draws the marks it
/// lacks off the pass and shows those it has. The marks draw from
/// [maxImages] image slots in the engine, the least recently shown filled
/// again first, never one the map shows.
final class RichMarkDriver {
  new(
    this.engine, {
    this.onReady,
    this.maxImages = 16,
    this.retryAfter = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RichMarkEngine engine;

  /// A mark finished drawing, or a place's photo and price came: another
  /// pass can show it. The guidance passes at each fix, the preview only
  /// when asked.
  final VoidCallback? onReady;

  /// Image slots in the engine.
  final int maxImages;

  /// How long a mark that could not be drawn or added is not tried again:
  /// a photo lost to a weak signal comes back, as its place's plan does.
  final Duration retryAfter;
  final DateTime Function() _clock;

  /// What each slot holds, by the mark's key ([richMarkKey]), the most
  /// recently shown last.
  final _slots = <String, ({String slot, double size})>{};

  /// The artworks drawn, by key, until a slot takes them.
  final _drawn = <String, RichArtwork>{};
  final _drawing = <String>{};

  /// The marks that could not be drawn or added, until when.
  final _failed = <String, DateTime>{};

  bool _isFailed(String key) {
    final until = _failed[key];
    if (until == null) return false;
    if (until.isAfter(_clock())) return true;
    _failed.remove(key);
    return false;
  }

  void _fail(String key) => _failed[key] = _clock().add(retryAfter);

  /// The places shown last, for the bonus of staying.
  Set<String> _shown = const {};
  (List<Map<String, Object?>>, List<String>)? _sent;
  int _generation = 0;
  RichStyle? _style;
  RouteIndex? _route;

  /// The whole route, for a map without a vehicle, without what a pixel
  /// does not show, by whole zoom level ([_wholeAt]).
  final _whole = <int, List<LatLng>>{};

  static const _deep = DeepCollectionEquality();

  /// The places shown at the last pass.
  Set<String> get shown => _shown;

  /// The whole [line] at [zoom], without the points that stray less than a
  /// pixel from it there, kept per whole zoom level (the next one up, the
  /// finer), and never finer than [_wholeFinestM].
  List<LatLng> _wholeAt(List<LatLng> line, double zoom) {
    final level = zoom.ceil();
    return _whole[level] ??= simplifyLine(
      line,
      toleranceM: math.max(_wholeFinestM, _metresPerPixel(line.first.lat, level.toDouble())),
    );
  }

  /// The style was loaded again: its images and the marks are gone.
  void reset() {
    _slots.clear();
    _drawn.clear();
    _shown = const {};
    _sent = null;
    _generation++;
  }

  /// Takes every mark off the map.
  Future<void> clear() => _show(const [], const []);

  /// One pass: the places in view, the screen, the choice, the marks.
  Future<void> refresh(RichInput input) async {
    final rich = input.rich;
    if (!rich.active || input.size.isEmpty) return await clear();
    final style = rich.style;
    if (style != _style) {
      // Another look, language, text size or set of muted authors: the
      // drawings made for the last one are of no use, those still drawing
      // included (a photo its author was just muted for).
      _style = style;
      _slots.clear();
      _drawn.clear();
      _failed.clear();
      _generation++;
    }
    final generation = _generation;
    final found = <String, ({PlaceSummary place, LatLng at, String? mark})>{};
    if (rich.tiles) {
      for (final f in await engine.tilePlaces()) {
        final place = placeFromTile(f.properties, [f.at.lon, f.at.lat]);
        if (place != null) found[place.id] = (place: place, at: f.at, mark: null);
      }
    }
    for (final p in rich.places) {
      found[p.id] = (place: p, at: p.position, mark: 'place:${p.id}');
    }
    final vehicle = input.vehicle;
    final along = rich.vehicleAlongM;
    var route = _route;
    if (route == null || !identical(route.line, input.line)) {
      route = _route = RouteIndex(input.line);
      _whole.clear();
    }
    final immediate = immediateM(rich.speedMps);
    final path = vehicle == null || along == null
        ? const <LatLng>[]
        : roadAhead(route, alongM: along, aheadM: immediate);
    // Without a vehicle (the preview), the whole route is the road the
    // marks keep their heads off, as the guidance does farther ahead (the
    // PO's rule of 2026-10-10): placed once the zoom is known, without
    // what a pixel does not show at it.
    final whole = vehicle == null || along == null;
    final line = whole
        ? const <LatLng>[]
        : roadAhead(route, alongM: along + immediate, aheadM: RichMarks.lineAheadM);
    final entries = found.values.toList();
    final view = await engine.view([
      for (final e in entries) e.at,
      ...path,
      ...line,
      for (final m in input.marks) m.at,
      ?vehicle,
    ]);
    if (view == null || generation != _generation) return;
    if (view.zoom < RouteMapRich.minZoom) return await clear();
    final screen = view.points;
    // Only what the map shows is weighed: the geometry along the route is
    // the costly part of a pass, and most places near a long route are off
    // the screen.
    final onScreen = Offset.zero & input.size;
    final pathStart = entries.length;
    final lineStart = pathStart + path.length;
    final marksStart = lineStart + line.length;
    var road = [for (var i = 0; i < line.length; i++) ?screen[lineStart + i]];
    if (whole && input.line.length > 1) {
      final placed = await engine.view(_wholeAt(input.line, view.zoom));
      if (placed == null || generation != _generation) return;
      road = [for (final p in placed.points) ?p];
    }
    RichFrame frame(int limit) => RichFrame(
      size: input.size,
      limit: limit,
      sizes: rich.sizes,
      clear: rich.clear,
      obstacles: [
        ...rich.obstacles,
        for (final (i, mark) in input.marks.indexed)
          if (screen[marksStart + i] case final at?) routeSignRoom(at, mark.side),
      ],
      vehicle: vehicle == null ? null : screen.last,
      path: [for (var i = 0; i < path.length; i++) ?screen[pathStart + i]],
      line: road,
    );
    final seen = <RichCandidate>[];
    for (final (i, e) in entries.indexed) {
      final at = screen[i];
      if (at == null || !onScreen.contains(at)) continue;
      final beside = vehicle == null || along == null
          ? null
          : placeAlong(e.at, route, alongM: along);
      seen.add(
        RichCandidate(
          id: e.place.id,
          at: at,
          place: e.place,
          aheadM: beside?.aheadM,
          offRouteM: beside?.offM,
          fromVehicleM: vehicle?.distanceTo(e.at),
          // The shape most of them will take, before their plan is known.
          capsule: !style.photos,
        ),
      );
    }
    // Only the places with a chance to stand out are asked about: a town's
    // view holds dozens of pins, each costing the client's API budget, and
    // a pan of the preview hundreds.
    final askable = {
      for (final pick in chooseRichMarks(seen, frame(rich.limit * _askedPerMark), previous: _shown))
        pick.candidate.id,
    };
    final candidates = <RichCandidate>[];
    final plans = <String, RichPlan>{};
    for (final c in seen) {
      final plan = rich.art.plan(c.place, style, ask: askable.contains(c.id), onReady: onReady);
      if (plan == null) continue;
      plans[c.id] = plan;
      candidates.add(
        RichCandidate(
          id: c.id,
          at: c.at,
          place: c.place,
          aheadM: c.aheadM,
          offRouteM: c.offRouteM,
          fromVehicleM: c.fromVehicleM,
          capsule: plan.capsule,
          labelWidth: plan.labelWidth,
        ),
      );
    }
    final picks = chooseRichMarks(candidates, frame(rich.limit), previous: _shown);
    // The slots the map shows now stay as they are until the new marks
    // replace them: filling one would put another place's image under a
    // mark still drawn.
    final busy = {for (final f in _sent?.$1 ?? const <Map<String, Object?>>[]) _imageOf(f)};
    final asked = <String>{};
    final features = <Map<String, Object?>>[];
    final hidden = <String>[];
    for (final (rank, pick) in picks.indexed) {
      final place = pick.candidate.place;
      final plan = plans[place.id]!;
      final key = richMarkKey(place.id, style, pick.size, plan);
      asked.add(key);
      final held = await _ensure(key, place, plan, pick.size, input, busy);
      if (generation != _generation) return;
      if (held == null) continue;
      busy.add(held.slot);
      final centre = view.centre;
      final perspective = centre == null
          ? 1.0
          : symbolPerspective(
              dy: pick.candidate.at.dy - centre.dy,
              height: input.size.height,
              pitchDeg: view.pitch,
            );
      final entry = found[place.id]!;
      features.add(
        _feature(
          entry.at,
          place,
          held.slot,
          plan.geometry(pick.size),
          rank,
          // A drawing of another size while the right one draws: brought to
          // the size wanted.
          pick.size / held.size / perspective,
          1 / perspective,
          entry.mark,
        ),
      );
      if (entry.mark case final mark?) hidden.add(mark);
    }
    // Drawings that came for a mark no longer chosen go: the next one of
    // that place is drawn again if it comes back.
    _drawn.removeWhere((key, _) => !asked.contains(key));
    await _show(features, hidden);
  }

  Future<void> _show(List<Map<String, Object?>> features, List<String> hidden) async {
    final sent = _sent;
    if (sent != null && _deep.equals(sent.$1, features) && listEquals(sent.$2, hidden)) return;
    _sent = (features, hidden);
    _shown = {for (final f in features) _placeOf(f)};
    await engine.show(_collection(features), hiddenMarks: hidden);
  }

  static Map<String, Object?> _properties(Map<String, Object?> feature) =>
      feature['properties']! as Map<String, Object?>;

  static String _imageOf(Map<String, Object?> feature) =>
      _properties(feature)[RichLayers.image]! as String;

  static String _placeOf(Map<String, Object?> feature) =>
      _properties(feature)[PlaceTiles.id]! as String;

  /// The slot holding the mark [key], filled first once it is drawn. While
  /// it draws, a slot holding the same mark at another size stands in for
  /// it (the size changes as the vehicle comes closer: no blink); null when
  /// there is none, when it cannot be drawn, or when every slot is busy.
  Future<({String slot, double size})?> _ensure(
    String key,
    PlaceSummary place,
    RichPlan plan,
    double size,
    RichInput input,
    Set<String> busy,
  ) async {
    final held = _slots.remove(key);
    if (held != null) {
      _slots[key] = held;
      return held;
    }
    final art = _drawn[key];
    if (art != null) {
      final slot = _freeSlot(busy);
      if (slot != null) {
        final generation = _generation;
        final put = await engine.putImage(slot, art.png);
        if (generation != _generation) return null;
        _drawn.remove(key);
        if (put) return _slots[key] = (slot: slot, size: size);
        // Refused: the drawing at hand of another size stays, if any.
        _fail(key);
      }
    } else if (!_drawing.contains(key) && !_isFailed(key)) {
      _draw(key, place, plan, size, input);
    }
    final other = sizeless(key);
    final stand = _slots.entries.firstWhereOrNull((e) => sizeless(e.key) == other);
    return stand?.value;
  }

  void _draw(String key, PlaceSummary place, RichPlan plan, double size, RichInput input) {
    _drawing.add(key);
    final rich = input.rich;
    final generation = _generation;
    unawaited(
      rich.art
          .draw(place, plan, size: size, ratio: input.ratio, style: rich.style)
          .then(
            (art) {
              _drawing.remove(key);
              // Drawn for a style that is gone: a new pass draws again.
              if (generation == _generation) {
                // A photo that did not come is planned as a pictogram next.
                if (art == null) {
                  _fail(key);
                } else {
                  _drawn[key] = art;
                }
              }
              onReady?.call();
            },
            onError: (Object e, StackTrace st) {
              _drawing.remove(key);
              if (generation == _generation) _fail(key);
              _log.fine('could not draw the mark of ${place.id}', e, st);
            },
          ),
    );
  }

  /// A slot no mark of [busy] uses: an empty one, else the one shown the
  /// longest ago.
  String? _freeSlot(Set<String> busy) {
    final used = {for (final v in _slots.values) v.slot};
    for (var i = 0; i < maxImages; i++) {
      final slot = '${RichLayers.imagePrefix}$i';
      if (!used.contains(slot)) return slot;
    }
    final oldest = _slots.entries.firstWhereOrNull((e) => !busy.contains(e.value.slot));
    if (oldest == null) return null;
    _slots.remove(oldest.key);
    return oldest.value.slot;
  }

  static Map<String, Object?> _feature(
    LatLng at,
    PlaceSummary place,
    String image,
    RichGeometry g,
    int rank,
    double scale,
    double reach,
    String? mark,
  ) {
    // Two decimals: a mark a pixel lower on the screen than at the last
    // pass keeps its size, and the source stays as it was.
    double rounded(double v) => (v * 100).round() / 100;
    return {
      'type': 'Feature',
      'properties': {
        ...placeTileProperties(place),
        RichLayers.image: image,
        RichLayers.scale: rounded(scale),
        RichLayers.rank: rank,
        RichLayers.headRadius: rounded(g.hitRadius * reach),
        RichLayers.lift: rounded(g.anchorDrop * reach),
        RichLayers.mark: ?mark,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [at.lon, at.lat],
      },
    };
  }

  static Map<String, Object?> _collection(List<Map<String, Object?>> features) => {
    'type': 'FeatureCollection',
    'features': features,
  };
}

/// When the passes of the rich marks run: one at a time, at most one per
/// [gap], the last request kept. A fix comes about once a second while
/// guiding; the camera comes to rest after a gesture.
final class RichPasses {
  new(this._run, {this.gap = const Duration(milliseconds: 700), Duration Function()? clock})
    : _now = clock ?? _stopwatch();

  final Future<void> Function() _run;
  final Duration gap;

  /// Time since some fixed moment, injectable for the tests.
  final Duration Function() _now;
  bool _busy = false;
  bool _again = false;
  bool _disposed = false;
  Timer? _timer;
  Duration? _last;

  /// A pass soon: now when none ran for [gap], else once that time is up.
  void request() {
    if (_disposed) return;
    if (_busy) {
      _again = true;
      return;
    }
    final last = _last;
    final wait = last == null ? Duration.zero : gap - (_now() - last);
    if (wait > Duration.zero) {
      _timer ??= Timer(wait, () {
        _timer = null;
        request();
      });
      return;
    }
    _busy = true;
    _last = _now();
    unawaited(
      _run()
          .catchError(
            (Object e, StackTrace st) => _log.fine('a pass of the rich marks failed', e, st),
          )
          .whenComplete(() {
            _busy = false;
            if (_again) {
              _again = false;
              request();
            }
          }),
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}

/// What tells two drawings apart: the place, the look, the label's size,
/// the plan and the size. The size comes last, cut off by [sizeless].
String richMarkKey(String place, RichStyle style, double size, RichPlan plan) =>
    '$place|${style.look.name}|${style.labelScale}|${plan.key}|${size.round()}';

/// [key] without its size: the same mark, drawn at any size.
String sizeless(String key) => key.substring(0, key.lastIndexOf('|'));

/// [place] as a tile of the places carries it ([placeFromTile] reads it
/// back): a rich mark opens the same card as the pin it stands for.
Map<String, Object?> placeTileProperties(PlaceSummary place) => {
  PlaceTiles.id: place.id,
  PlaceTiles.kind: tileKindCode(place.kind),
  PlaceTiles.night: tileNightCode(place.overnight),
  PlaceTiles.name: ?place.name,
  PlaceTiles.city: ?place.city,
  // As the tiles carry it: for a place without a name only, never a private
  // host's, so a mark opens the page with the title the list gives it.
  if (place.name == null && place.kind != PlaceKind.homestay) PlaceTiles.street: ?place.street,
  if (place.services.isNotEmpty) PlaceTiles.services: Service.maskOf(place.services),
  if (place.priceParkingEur case final price?) PlaceTiles.price: price == 0 ? 0 : 1,
  if (place.maxHeightM case final h?) PlaceTiles.height: heightCentimetres(h),
  if (place.ratingForFilters case final r?) PlaceTiles.rating: ratingTenths(r),
  if (place.openingSeason case final season? when season.isNotEmpty)
    PlaceTiles.season1: season.first.code,
  if (place.openingSeason case final season? when season.length > 1)
    PlaceTiles.season2: season[1].code,
};

/// The disc's sizes of the rich marks and how many at once, by the
/// window: a phone's, upright or on its side (its shorter side under 600),
/// a tablet's, a computer's.
({RichSizes sizes, int limit}) richMarksFor(Size window) => switch (window) {
  Size(shortestSide: < 600) => (sizes: RichMarks.phone, limit: RichMarks.compactLimit),
  Size(width: < 840) => (sizes: RichMarks.wide, limit: RichMarks.mediumLimit),
  _ => (sizes: RichMarks.wide, limit: RichMarks.expandedLimit),
};

/// The labels' size beside their own for the system's text size: larger
/// with it, up to a third more, so a mark stays a mark.
double richLabelScale(TextScaler scaler) => (scaler.scale(13) / 13).clamp(1.0, 1.3);
