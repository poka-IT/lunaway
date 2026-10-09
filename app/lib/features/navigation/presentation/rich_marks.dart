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
import 'package:lunaway/features/navigation/domain/route_stops.dart';
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

/// What a rich mark of a place shows, once drawn.
@immutable
final class RichArtwork {
  const new({required this.png, required this.geometry, required this.photo});

  final Uint8List png;
  final RichGeometry geometry;

  /// The place's photo, or its illustrated mark.
  final bool photo;
}

/// Draws the rich marks: asks the API what a place's photo and price are,
/// fetches the photo, paints the mark.
abstract interface class RichArt {
  /// How [place]'s mark would look with what is known of it now: its
  /// photo, or the illustrated capsule ([RichGeometry.capsule]) with the
  /// width of its label (zero for none).
  ({bool capsule, double labelWidth}) plan(
    PlaceSummary place,
    GuidanceLook look,
    RichWords words, {
    required bool online,
  });

  /// The mark of [place] at disc [size], at [ratio] physical pixels per
  /// logical one; null when it cannot be drawn.
  Future<RichArtwork?> draw(
    PlaceSummary place, {
    required GuidanceLook look,
    required double size,
    required double ratio,
    required RichWords words,
    required bool online,
  });
}

/// How the route map draws its rich marks (`RouteMapProps.rich`).
@immutable
final class RouteMapRich {
  const new({
    required this.look,
    required this.art,
    required this.words,
    this.tiles = false,
    this.places = const [],
    this.clear = EdgeInsets.zero,
    this.limit = RichMarks.compactLimit,
    this.sizes = RichMarks.phone,
    this.yielding = false,
    this.vehicleAlongM,
    this.speedMps,
    this.online = true,
  });

  final GuidanceLook look;
  final RichArt art;
  final RichWords words;

  /// The places of the tiles drawn in view are candidates (the guidance,
  /// online).
  final bool tiles;

  /// Places the screen holds are candidates too: the preview's places near
  /// the route, the device's offline. Each is drawn as the small route mark
  /// `place:<id>`, hidden while the place stands out.
  final List<PlaceSummary> places;

  /// The edges of the map something covers ([RichFrame.clear]).
  final EdgeInsets clear;
  final int limit;
  final RichSizes sizes;

  /// A complex maneuver is close: the marks step aside ([richMarksYield]).
  final bool yielding;

  /// How far along the route the vehicle is; null without a guidance.
  final double? vehicleAlongM;
  final double? speedMps;

  /// Whether the API answers: offline, a mark keeps its pictogram.
  final bool online;

  /// Below the zoom the small pins start at, no place shows, and none
  /// stands out.
  static const double minZoom = 10;

  /// Whether any mark may stand out now.
  bool get active => look.rich && !yielding && limit > 0;

  @override
  bool operator ==(Object other) =>
      other is RouteMapRich &&
      other.look == look &&
      identical(other.art, art) &&
      identical(other.words, words) &&
      other.tiles == tiles &&
      listEquals(other.places, places) &&
      other.clear == clear &&
      other.limit == limit &&
      other.sizes == sizes &&
      other.yielding == yielding &&
      other.vehicleAlongM == vehicleAlongM &&
      other.speedMps == speedMps &&
      other.online == online;

  @override
  int get hashCode => Object.hash(
    look,
    identityHashCode(art),
    tiles,
    Object.hashAll(places),
    clear,
    limit,
    sizes,
    yielding,
    vehicleAlongM,
    speedMps,
    online,
  );
}

/// Ids of the rich marks' source and layers, shared by the engines.
abstract final class RichLayers {
  static const source = 'lw-route-rich';

  /// The marks themselves, above the small pins: placed first, each hides
  /// the pin of its place and those it covers.
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
  /// upright whatever the camera, the best placed first. Each takes its
  /// room: the pins and the names under it are left out rather than drawn
  /// through it.
  static Map<String, Object?> layout(double scale) => {
    'icon-image': const ['get', image],
    'icon-size': [
      '*',
      scale,
      const ['get', RichLayers.scale],
    ],
    'icon-anchor': 'bottom',
    'icon-allow-overlap': false,
    'icon-ignore-placement': false,
    'icon-padding': 2,
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
  static const HitShape hit = HitShape(
    radius: PropertyHit(headRadius),
    lift: PropertyHit(lift),
    priority: 3,
  );
}

/// What an engine does for the rich marks.
abstract interface class RichMarkEngine {
  /// The places of the tiles drawn in view ([RichLayers.probe]).
  Future<List<({Map<Object?, Object?> properties, LatLng at})>> tilePlaces();

  /// Where [points] are drawn and how the camera looks; null when the
  /// engine cannot tell.
  Future<RichView?> view(List<LatLng> points);

  /// Adds the image [id], or replaces it: the marks draw from a few image
  /// slots, filled again as places come and go (maplibre_gl cannot remove
  /// an image on Android and iOS, where adding one of a known id replaces
  /// it).
  Future<void> putImage(String id, Uint8List png);

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
  });

  final RouteMapRich rich;

  /// The map's size, logical pixels.
  final Size size;

  /// Physical pixels per logical one.
  final double ratio;

  /// The route chosen.
  final List<LatLng> line;
  final LatLng? vehicle;
}

/// Keeps the rich marks of one route map: at each pass reads the places in
/// view and the screen, chooses ([chooseRichMarks]), draws the marks it
/// lacks off the pass and shows those it has. The marks draw from
/// [maxImages] image slots in the engine, the least recently shown filled
/// again first, never one the map shows.
final class RichMarkDriver {
  new(this.engine, {this.onDrawn, this.maxImages = 16});

  final RichMarkEngine engine;

  /// A mark finished drawing: another pass can show it.
  final VoidCallback? onDrawn;

  /// Image slots in the engine.
  final int maxImages;

  /// What each slot holds, by the mark's key ([richMarkKey]), the most
  /// recently shown last.
  final _slots = <String, ({String slot, RichGeometry geometry})>{};

  /// The artworks drawn, by key, until a slot takes them.
  final _drawn = <String, RichArtwork>{};
  final _drawing = <String>{};
  final _failed = <String>{};

  /// The places shown last, for the bonus of staying.
  Set<String> _shown = const {};
  (List<Map<String, Object?>>, List<String>)? _sent;
  int _generation = 0;

  static const _deep = DeepCollectionEquality();

  /// The places shown at the last pass.
  Set<String> get shown => _shown;

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
    final path = vehicle == null || along == null
        ? const <LatLng>[]
        : roadAhead(input.line, alongM: along, aheadM: immediateM(rich.speedMps));
    final entries = found.values.toList();
    final view = await engine.view([for (final e in entries) e.at, ...path, ?vehicle]);
    if (view == null || generation != _generation) return;
    if (view.zoom < RouteMapRich.minZoom) return await clear();
    final screen = view.points;
    final candidates = <RichCandidate>[];
    for (final (i, e) in entries.indexed) {
      final at = screen[i];
      if (at == null) continue;
      final beside = vehicle == null || along == null
          ? null
          : placeAlong(e.at, input.line, alongM: along);
      final plan = rich.art.plan(e.place, rich.look, rich.words, online: rich.online);
      candidates.add(
        RichCandidate(
          id: e.place.id,
          at: at,
          place: e.place,
          aheadM: beside?.aheadM,
          offRouteM: beside?.offM ?? nearestOnLine(e.at, input.line)?.offM,
          fromVehicleM: vehicle?.distanceTo(e.at),
          capsule: plan.capsule,
          labelWidth: plan.labelWidth,
        ),
      );
    }
    final frame = RichFrame(
      size: input.size,
      limit: rich.limit,
      sizes: rich.sizes,
      clear: rich.clear,
      vehicle: vehicle == null ? null : screen.last,
      path: [for (var i = 0; i < path.length; i++) ?screen[entries.length + i]],
    );
    final picks = chooseRichMarks(candidates, frame, previous: _shown);
    // The slots the map shows now stay as they are until the new marks
    // replace them: filling one would put another place's image under a
    // mark still drawn.
    final busy = {for (final f in _sent?.$1 ?? const <Map<String, Object?>>[]) _imageOf(f)};
    final features = <Map<String, Object?>>[];
    final hidden = <String>[];
    for (final (rank, pick) in picks.indexed) {
      final place = pick.candidate.place;
      final held = await _ensure(
        richMarkKey(place.id, rich.look, pick.size),
        place,
        pick,
        input,
        busy,
      );
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
        _feature(entry.at, place, held.slot, held.geometry, rank, 1 / perspective, entry.mark),
      );
      if (entry.mark case final mark?) hidden.add(mark);
    }
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

  /// The slot holding the mark [key], filled first when it is drawn; null
  /// while it draws, when it cannot be, or when every slot is busy.
  Future<({String slot, RichGeometry geometry})?> _ensure(
    String key,
    PlaceSummary place,
    RichPick pick,
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
      if (slot == null) return null;
      _drawn.remove(key);
      await engine.putImage(slot, art.png);
      return _slots[key] = (slot: slot, geometry: art.geometry);
    }
    if (_drawing.contains(key) || _failed.contains(key)) return null;
    _drawing.add(key);
    final rich = input.rich;
    final generation = _generation;
    unawaited(
      rich.art
          .draw(
            place,
            look: rich.look,
            size: pick.size,
            ratio: input.ratio,
            words: rich.words,
            online: rich.online,
          )
          .then(
            (art) {
              _drawing.remove(key);
              if (art == null) {
                _failed.add(key);
                return;
              }
              // Drawn for a style that is gone: a new pass draws again.
              if (generation != _generation) return;
              _drawn[key] = art;
              onDrawn?.call();
            },
            onError: (Object e, StackTrace st) {
              _drawing.remove(key);
              _failed.add(key);
              _log.fine('could not draw the mark of ${place.id}', e, st);
            },
          ),
    );
    return null;
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
    String? mark,
  ) {
    // Two decimals: a mark a pixel lower on the screen than at the last
    // pass keeps its size, and the source stays as it was.
    final rounded = (scale * 100).round() / 100;
    return {
      'type': 'Feature',
      'properties': {
        ...placeTileProperties(place),
        RichLayers.image: image,
        RichLayers.scale: rounded,
        RichLayers.rank: rank,
        RichLayers.headRadius: g.hitRadius * rounded,
        RichLayers.lift: g.tipDrop * rounded,
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

/// What tells two marks apart: the place, the look, the disc's size.
String richMarkKey(String place, GuidanceLook look, double size) =>
    '$place-${look.name}-${size.round()}';

/// [place] as a tile of the places carries it ([placeFromTile] reads it
/// back): a rich mark opens the same card as the pin it stands for.
Map<String, Object?> placeTileProperties(PlaceSummary place) => {
  PlaceTiles.id: place.id,
  PlaceTiles.kind: tileKindCode(place.kind),
  PlaceTiles.night: tileNightCode(place.overnight),
  PlaceTiles.name: ?place.name,
  PlaceTiles.city: ?place.city,
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

/// The larger of two insets, side by side.
EdgeInsets maxInsets(EdgeInsets a, EdgeInsets b) => EdgeInsets.fromLTRB(
  math.max(a.left, b.left),
  math.max(a.top, b.top),
  math.max(a.right, b.right),
  math.max(a.bottom, b.bottom),
);
