import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/data/place_thumbs.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/rich_mark_art.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// A map 390 x 760 seen from straight above: a place's point on screen is
/// given by the test.
final class _Engine implements RichMarkEngine {
  double zoom = 15;
  double pitch = 0;
  Offset centre = const Offset(195, 380);
  final Map<LatLng, Offset> screen = {};
  List<({Map<Object?, Object?> properties, LatLng at})> tiles = [];
  final images = <String, Uint8List>{};
  final puts = <String>[];
  bool refuse = false;
  Map<String, Object?>? shown;
  List<String> hidden = const [];
  int shows = 0;

  @override
  Future<List<({Map<Object?, Object?> properties, LatLng at})>> tilePlaces() async => tiles;

  @override
  Future<RichView?> view(List<LatLng> points) async => RichView(
    points: [for (final p in points) screen[p]],
    zoom: zoom,
    pitch: pitch,
    centre: centre,
  );

  @override
  Future<bool> putImage(String id, Uint8List png) async {
    if (refuse) return false;
    images[id] = png;
    puts.add(id);
    return true;
  }

  @override
  Future<void> show(Map<String, Object?> collection, {required List<String> hiddenMarks}) async {
    shown = collection;
    hidden = hiddenMarks;
    shows++;
  }

  List<Map<String, Object?>> get features => [
    for (final f in (shown?['features'] as List<Object?>?) ?? const [])
      (f! as Map<String, Object?>)['properties']! as Map<String, Object?>,
  ];

  List<String> get ids => [for (final f in features) f[PlaceTiles.id]! as String];
}

/// Draws a mark at once, or when [gate] completes; a place in [photos] is
/// a photo, the others a capsule with a label; one in [pending] is not
/// planned yet, until [answer]; one in [broken] fails to draw.
final class _Art implements RichArt {
  final drawn = <(String, double)>[];
  Set<String> photos = {};
  Set<String> pending = {};
  Set<String> broken = {};
  Completer<void>? gate;

  /// The places asked about, and who to call once they are known.
  final asked = <String, VoidCallback?>{};

  @override
  RichPlan? plan(PlaceSummary place, RichStyle style, {bool ask = true, VoidCallback? onReady}) {
    if (pending.contains(place.id)) {
      if (ask) asked[place.id] = onReady;
      return null;
    }
    return photos.contains(place.id)
        ? RichPlan.photo
        : const RichPlan(capsule: true, label: '12 €', labelWidth: 40);
  }

  /// The photo and price of [id] came.
  void answer(String id) {
    pending.remove(id);
    asked[id]?.call();
  }

  @override
  Future<RichArtwork?> draw(
    PlaceSummary place,
    RichPlan plan, {
    required double size,
    required double ratio,
    required RichStyle style,
  }) async {
    await gate?.future;
    if (broken.contains(place.id)) return null;
    drawn.add((place.id, size));
    return RichArtwork(
      png: Uint8List.fromList('${place.id}-$size-${style.muted.join()}'.codeUnits),
      geometry: plan.geometry(size),
    );
  }
}

final _words = RichWords(
  free: 'Gratuit',
  nightOk: 'Nuit OK',
  price: (e) => '$e €',
  rating: (r) => '$r',
);

PlaceSummary _place(String id, double lat, {double? rating}) => PlaceSummary(
  id: id,
  name: 'Aire $id',
  kind: PlaceKind.motorhomeArea,
  lat: lat,
  lon: 4,
  overnight: OvernightStatus.allowed,
  ratingForFilters: rating,
);

/// A route north from 45.0: a vehicle `alongM` along it is at 45.0 + alongM / 111195.
final List<LatLng> _line = [for (var i = 0; i <= 40; i++) LatLng(45 + i * 0.001, 4.002)];

RichInput _input(
  _Art art, {
  GuidanceLook look = GuidanceLook.photos,
  List<PlaceSummary> places = const [],
  bool tiles = false,
  bool yielding = false,
  int limit = 4,
  LatLng? vehicle,
  double? alongM,
  List<LatLng> marks = const [],
  Set<String> muted = const {},
}) => RichInput(
  rich: RouteMapRich(
    style: RichStyle(look: look, words: _words, muted: muted),
    art: art,
    places: places,
    tiles: tiles,
    yielding: yielding,
    limit: limit,
    vehicleAlongM: alongM,
    clear: const EdgeInsets.fromLTRB(0, 120, 72, 140),
  ),
  size: const Size(390, 760),
  ratio: 3,
  line: _line,
  vehicle: vehicle,
  marks: marks,
);

void main() {
  late _Engine engine;
  late _Art art;
  late RichMarkDriver driver;

  setUp(() {
    engine = _Engine();
    art = _Art()..photos = {'a', 'b'};
    driver = RichMarkDriver(engine);
  });

  /// Places [places] at the screen points given.
  void at(Map<PlaceSummary, Offset> places) {
    for (final e in places.entries) {
      engine.screen[e.key.position] = e.value;
    }
  }

  test('a pass draws the marks it lacks, the next shows them with their image', () async {
    final a = _place('a', 45.01);
    final b = _place('b', 45.02);
    at({a: const Offset(100, 400), b: const Offset(240, 300)});
    await driver.refresh(_input(art, places: [a, b]));
    expect([for (final d in art.drawn) d.$1], unorderedEquals(['a', 'b']));
    expect(engine.features, isEmpty, reason: 'nothing drawn yet');
    await driver.refresh(_input(art, places: [a, b]));
    final features = engine.features;
    expect(engine.ids, unorderedEquals(['a', 'b']));
    for (final f in features) {
      expect(engine.images.keys, contains(f[RichLayers.image]), reason: 'image added before');
      expect(f[RichLayers.mark], 'place:${f[PlaceTiles.id]}');
    }
    expect(engine.hidden, unorderedEquals(['place:a', 'place:b']), reason: 'small badges hidden');
    expect(driver.shown, {'a', 'b'});
  });

  test('a mark still drawing waits; once drawn, it is asked for again', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    art.gate = Completer<void>();
    var asked = 0;
    driver = RichMarkDriver(engine, onReady: () => asked++);
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
    expect(art.drawn, isEmpty);
    art.gate!.complete();
    await pumpEventQueue();
    expect(asked, 1);
    await driver.refresh(_input(art, places: [a]));
    expect(engine.ids, ['a']);
  });

  test('a place whose photo and price are not known yet stays a small pin', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    art.pending = {'a'};
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
    expect(art.drawn, isEmpty, reason: 'nothing drawn before the plan is known');
    art.pending = {};
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.ids, ['a']);
  });

  test("a place's photo and price coming ask for a pass, with no fix to bring one", () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    var passes = 0;
    driver = RichMarkDriver(engine, onReady: () => passes++);
    art.pending = {'a'};
    await driver.refresh(_input(art, places: [a]));
    expect(passes, 0);
    art.answer('a');
    expect(passes, 1, reason: 'the preview has no fix to pass again');
  });

  test('of the places in view, only those with a chance to stand out are asked about', () async {
    // Twenty places in a column, the best rated lowest on the screen.
    final places = [for (var i = 0; i < 20; i++) _place('p$i', 45 + i / 1000, rating: 1 + i / 5)];
    for (final (i, p) in places.indexed) {
      engine.screen[p.position] = Offset(40.0 + (i % 4) * 70, 200.0 + (i ~/ 4) * 90);
    }
    art.pending = {for (final p in places) p.id};
    await driver.refresh(_input(art, places: places));
    expect(art.asked.length, inInclusiveRange(1, 4 * 3), reason: 'three per mark at most');
    expect(art.asked.keys, contains('p19'), reason: 'the best rated first');
    expect(art.asked.keys, isNot(contains('p0')));
  });

  test('a drawing made before an author was muted is never shown', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    art.gate = Completer<void>();
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a], muted: {'x'}));
    art.gate!.complete();
    await pumpEventQueue();
    await driver.refresh(_input(art, places: [a], muted: {'x'}));
    await driver.refresh(_input(art, places: [a], muted: {'x'}));
    expect(engine.ids, ['a']);
    for (final png in engine.images.values) {
      expect(String.fromCharCodes(png), endsWith('-x'), reason: 'drawn for the muted set');
    }
  });

  test('a mark that cannot be drawn is not asked for again, nor shown', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    art.broken = {'a'};
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
    expect(engine.puts, isEmpty);
  });

  test('a mark that could not be drawn is tried again after a while', () async {
    var now = DateTime(2026, 10, 9, 12);
    driver = RichMarkDriver(engine, clock: () => now);
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    // A photo lost to a weak signal, then the signal back.
    art.broken = {'a'};
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    art.broken = {};
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty, reason: 'not tried again at once');
    now = now.add(const Duration(minutes: 6));
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.ids, ['a']);
  });

  test('an image the engine refused leaves no mark pointing at it', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    engine.refuse = true;
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
  });

  test('coming closer, a mark keeps showing while its larger drawing is made', () async {
    final a = _place('a', 45.02);
    // The vehicle 1 200 m away, then 900, then 400.
    at({a: const Offset(100, 300)});
    Future<void> pass(double alongM) async {
      engine.screen[LatLng(45 + alongM / 111195, 4.002)] = const Offset(195, 600);
      await driver.refresh(
        _input(art, places: [a], vehicle: LatLng(45 + alongM / 111195, 4.002), alongM: alongM),
      );
    }

    await pass(1024);
    await pass(1024);
    expect(engine.ids, ['a']);
    final far = engine.features.single[RichLayers.scale]! as double;
    art.gate = Completer<void>();
    await pass(1700);
    expect(engine.ids, ['a'], reason: 'no blink while the next size draws');
    final standIn = engine.features.single[RichLayers.scale]! as double;
    expect(standIn, greaterThan(far), reason: 'the drawing at hand, brought to the size wanted');
    art.gate!.complete();
    await pumpEventQueue();
    await pass(1700);
    expect(engine.ids, ['a']);
    expect(engine.features.single[RichLayers.scale], 1, reason: 'its own size drawn now');
    expect(art.drawn.map((d) => d.$2).toSet().length, 2);
  });

  test('a larger drawing the engine refuses leaves the one shown', () async {
    final a = _place('a', 45.02);
    at({a: const Offset(100, 300)});
    Future<void> pass(double alongM) async {
      engine.screen[LatLng(45 + alongM / 111195, 4.002)] = const Offset(195, 600);
      await driver.refresh(
        _input(art, places: [a], vehicle: LatLng(45 + alongM / 111195, 4.002), alongM: alongM),
      );
    }

    await pass(1024);
    await pass(1024);
    expect(engine.ids, ['a']);
    engine.refuse = true;
    await pass(1700);
    await pass(1700);
    expect(engine.ids, ['a'], reason: 'no blink');
  });

  test('small pins only, a maneuver ahead or a map too far out: no mark', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, hasLength(1));
    await driver.refresh(_input(art, places: [a], look: GuidanceLook.dots));
    expect(engine.features, isEmpty);
    expect(engine.hidden, isEmpty, reason: 'the small badge back');
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, hasLength(1));
    await driver.refresh(_input(art, places: [a], yielding: true));
    expect(engine.features, isEmpty);
    await driver.refresh(_input(art, places: [a]));
    engine.zoom = 9;
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
  });

  test('no mark over a mark of the route: a closure, a limit, a stop', () async {
    final a = _place('a', 45.01);
    const closure = LatLng(45.05, 4.05);
    at({a: const Offset(100, 400)});
    engine.screen[closure] = const Offset(100, 380);
    await driver.refresh(_input(art, places: [a], marks: [closure]));
    await driver.refresh(_input(art, places: [a], marks: [closure]));
    expect(engine.features, isEmpty);
    engine.screen[closure] = const Offset(300, 600);
    await driver.refresh(_input(art, places: [a], marks: [closure]));
    await driver.refresh(_input(art, places: [a], marks: [closure]));
    expect(engine.ids, ['a']);
  });

  test('the same marks are not sent again', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    final shows = engine.shows;
    await driver.refresh(_input(art, places: [a]));
    expect(engine.shows, shows);
  });

  test("the tiles' places in view are candidates, opened as their pin opens", () async {
    final place = _place('t', 45.03, rating: 4.4);
    engine.tiles = [(properties: placeTileProperties(place), at: place.position)];
    at({place: const Offset(120, 420)});
    art.photos = {'t'};
    await driver.refresh(_input(art, tiles: true));
    await driver.refresh(_input(art, tiles: true));
    final properties = engine.features.single;
    expect(properties[RichLayers.mark], isNull, reason: 'no route mark stands for it');
    expect(placeFromTile(properties, [place.lon, place.lat]), place);
  });

  test('a place off the screen is neither weighed nor drawn', () async {
    final off = _place('off', 45.01);
    at({off: const Offset(100, 900)});
    await driver.refresh(_input(art, places: [off]));
    expect(art.drawn, isEmpty);
  });

  test('the images stay in a few slots, never one the map shows', () async {
    driver = RichMarkDriver(engine, maxImages: 3);
    final places = [for (var i = 0; i < 6; i++) _place('p$i', 45 + i / 100)];
    art.photos = {for (final p in places) p.id};
    final used = <String>{};
    // Two places at a time pass across the open map.
    for (var i = 0; i < places.length - 1; i++) {
      engine.screen.clear();
      at({places[i]: const Offset(100, 400), places[i + 1]: const Offset(250, 300)});
      final before = {for (final f in engine.features) f[RichLayers.image]};
      await driver.refresh(_input(art, places: [places[i], places[i + 1]]));
      await driver.refresh(_input(art, places: [places[i], places[i + 1]]));
      for (final id in engine.puts) {
        expect(before, isNot(contains(id)), reason: 'a slot shown is not filled again');
      }
      engine.puts.clear();
      used.addAll([for (final f in engine.features) f[RichLayers.image]! as String]);
      expect(engine.features, hasLength(2));
    }
    expect(used.length, lessThanOrEqualTo(3));
    expect(engine.images.length, lessThanOrEqualTo(3));
  });

  test('on a tilted map, a mark low on the screen is scaled back to its size', () async {
    engine
      ..pitch = 55
      ..centre = const Offset(195, 300);
    final a = _place('a', 45.01);
    at({a: const Offset(100, 560)});
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    final scale = engine.features.single[RichLayers.scale]! as double;
    expect(scale, lessThan(0.95));
    expect(scale, closeTo(1 / symbolPerspective(dy: 260, height: 760, pitchDeg: 55), 0.01));
  });

  test('a mark is a target the size it is drawn, a finger 20 px off its head included', () async {
    final a = _place('a', 45.01);
    at({a: const Offset(100, 400)});
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    final properties = engine.features.single;
    final candidate = HitCandidate(
      layer: RichLayers.marks,
      properties: properties,
      points: const [Offset(100, 400)],
    );
    final radius = properties[RichLayers.headRadius]! as double;
    final lift = properties[RichLayers.lift]! as double;
    final head = Offset(100, 400 - lift);
    final shapes = {RichLayers.marks: RichLayers.hit};
    expect(
      nearestHit(
        head + Offset(radius + 20, 0),
        [candidate],
        shapes: shapes,
        zoom: 15,
        tolerance: 22,
      ),
      isNotNull,
    );
    expect(
      nearestHit(
        head + Offset(radius + 30, 0),
        [candidate],
        shapes: shapes,
        zoom: 15,
        tolerance: 22,
      ),
      isNull,
    );
  });

  test("a place's tile properties read back as the same place", () {
    const place = PlaceSummary(
      id: 'x',
      name: 'Aire du lac',
      city: 'Annecy',
      kind: PlaceKind.campsite,
      lat: 45.9,
      lon: 6.1,
      overnight: OvernightStatus.tolerated,
      services: {Service.drinkingWater, Service.showers},
      priceParkingEur: 0,
      ratingForFilters: 4.2,
      maxHeightM: 3.1,
      openingSeason: [DayRange(92, 305)],
    );
    expect(placeFromTile(placeTileProperties(place), [place.lon, place.lat]), place);
  });

  test('the drawings keyed by place, look, label, plan and size', () {
    const style = RichStyle(
      look: GuidanceLook.photos,
      words: RichWords(free: '', nightOk: '', price: _none, rating: _none),
    );
    final photo = richMarkKey('a', style, 48, RichPlan.photo);
    final capsule = richMarkKey('a', style, 48, const RichPlan(capsule: true, label: '12 €'));
    expect(photo, isNot(capsule), reason: 'a pictogram drawn offline is no photo online');
    expect(sizeless(richMarkKey('a', style, 52, RichPlan.photo)), sizeless(photo));
  });

  group('the passes', () {
    test('one at a time, at most one per gap, the last request kept', () {
      fakeAsync((async) {
        var runs = 0;
        final gate = <Completer<void>>[];
        final passes = RichPasses(() {
          runs++;
          final c = Completer<void>();
          gate.add(c);
          return c.future;
        }, clock: () => async.elapsed)..request();
        expect(runs, 1);
        passes
          ..request()
          ..request();
        expect(runs, 1, reason: 'one at a time');
        gate.last.complete();
        async.flushMicrotasks();
        expect(runs, 1, reason: 'the gap first');
        async.elapse(const Duration(milliseconds: 700));
        expect(runs, 2, reason: 'the request kept runs once');
        gate.last.complete();
        async.elapse(const Duration(seconds: 2));
        expect(runs, 2);
        passes.dispose();
      });
    });
  });

  group('the photos and prices asked', () {
    test('asks gathered go in one request per eight places, each answer kept', () {
      fakeAsync((async) {
        final source = _Thumbs({
          for (var i = 0; i < 10; i++) 'p$i': PlaceThumb(external: 'u$i', priceEur: i.toDouble()),
        });
        final thumbs = PlaceThumbs(source);
        final answers = <String, PlaceThumb?>{};
        for (var i = 0; i < 10; i++) {
          unawaited(thumbs.of('p$i').then((t) => answers['p$i'] = t));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, [
          ['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'],
          ['p8', 'p9'],
        ]);
        expect(answers['p9'], const PlaceThumb(external: 'u9', priceEur: 9));
        expect(thumbs.known('p3'), const PlaceThumb(external: 'u3', priceEur: 3));
        unawaited(thumbs.of('p3'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, hasLength(2), reason: 'known: not asked again');
      });
    });

    test('a place asked again while its request runs waits for the same answer', () {
      fakeAsync((async) {
        final source = _Thumbs({'a': const PlaceThumb(external: 'u'), 'b': const PlaceThumb()})
          ..delay = const Duration(seconds: 2);
        final thumbs = PlaceThumbs(source);
        unawaited(thumbs.of('a'));
        async.elapse(const Duration(milliseconds: 100));
        PlaceThumb? again;
        unawaited(thumbs.of('a').then((t) => again = t));
        unawaited(thumbs.of('b'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, [
          ['a'],
          ['b'],
        ], reason: 'b alone in the second request');
        async.elapse(const Duration(seconds: 3));
        expect(again, const PlaceThumb(external: 'u'));
      });
    });

    test('a failed request answers null, and is not asked again for a while', () {
      fakeAsync((async) {
        var now = DateTime(2026, 10, 9, 12);
        final source = _Thumbs(const {})..fail = true;
        final thumbs = PlaceThumbs(source, clock: () => now);
        PlaceThumb? answer = const PlaceThumb();
        unawaited(thumbs.of('p').then((t) => answer = t));
        async.elapse(const Duration(milliseconds: 100));
        expect(answer, isNull);
        expect(thumbs.failed('p'), isTrue);
        unawaited(thumbs.of('p'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, hasLength(1));
        now = now.add(const Duration(minutes: 6));
        expect(thumbs.failed('p'), isFalse);
        source.fail = false;
        unawaited(thumbs.of('p'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, hasLength(2));
      });
    });

    test("the community's photo first, never a muted author's, else the partner's", () {
      const thumb = PlaceThumb(
        community: [(authorId: 'muted', url: 'theirs'), (authorId: 'friend', url: 'mine')],
        external: 'partner',
      );
      expect(thumb.photo(), 'theirs');
      expect(thumb.photo(muted: {'muted'}), 'mine');
      expect(thumb.photo(muted: {'muted', 'friend'}), 'partner');
    });

    test("of the partner's photos, the place itself before a street view, never around", () {
      expect(
        externalMapPhoto([
          (sourceId: 'extcom', kind: 'SURROUNDINGS', thumbUrl: 'around'),
          (sourceId: 'extcom', kind: 'STREET_VIEW', thumbUrl: 'street'),
          (sourceId: 'extcom', kind: 'PLACE', thumbUrl: 'place'),
        ]),
        'place',
      );
    });

    test('never a photo whose credit belongs beside it', () {
      expect(
        externalMapPhoto([
          (sourceId: 'datatourisme', kind: 'PLACE', thumbUrl: 'office'),
          (sourceId: 'wikimedia-commons', kind: 'PLACE', thumbUrl: 'commons'),
          (sourceId: 'panoramax', kind: 'STREET_VIEW', thumbUrl: 'street'),
        ]),
        isNull,
      );
      final parsed = placeThumbsOperation(1).parse({
        't0': {
          'id': 'a',
          'priceParkingEur': null,
          'coverPhotos': [
            {'sourceId': 'other', 'thumbUrl': 'x', 'authorId': null},
          ],
          'externalPhotos': <Object>[],
        },
      });
      expect(parsed['a']!.photo(), isNull);
    });

    test('a request names as few places as it may, and reads each answer', () {
      for (final size in thumbsSizes) {
        expect(
          RegExp(r'place\(id:').allMatches(placeThumbsOperation(size).document),
          hasLength(size),
        );
      }
      final parsed = placeThumbsOperation(4).parse({
        't0': {
          'id': 'a',
          'priceParkingEur': 12,
          'coverPhotos': [
            {'sourceId': 'community-cc-by', 'thumbUrl': 'https://api/c/thumb', 'authorId': 'u1'},
          ],
          'externalPhotos': [
            {'sourceId': 'extcom', 'kind': 'PLACE', 'thumbUrl': 'https://api/x/thumb'},
          ],
        },
        't1': null,
        't2': {
          'id': 'b',
          'priceParkingEur': null,
          'coverPhotos': <Object>[],
          'externalPhotos': <Object>[],
        },
      });
      expect(parsed, {
        'a': const PlaceThumb(
          community: [(authorId: 'u1', url: 'https://api/c/thumb')],
          external: 'https://api/x/thumb',
          priceEur: 12,
        ),
        'b': const PlaceThumb(),
      });
    });

    test('the request for three places is the one for four, the first repeated', () async {
      Map<String, dynamic>? sent;
      final client = GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'data': <String, Object?>{}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        userAgent: 'test',
      );
      await GraphQLPlaceThumbs(client).fetch(['a', 'b', 'c']);
      expect(sent!['operationName'], 'PlaceThumbs4');
      expect(sent!['variables'], {'p0': 'a', 'p1': 'b', 'p2': 'c', 'p3': 'a'});
    });
  });

  group("the places' art", () {
    final place = _place('a', 45.01);
    final credited = RichStyle(look: GuidanceLook.photos, words: _words, credited: true);
    final uncredited = RichStyle(look: GuidanceLook.photos, words: _words);
    final offline = RichStyle(
      look: GuidanceLook.photos,
      words: _words,
      online: false,
      credited: true,
    );
    final photoAndPrice = _Thumbs({'a': const PlaceThumb(external: 'u', priceEur: 12)});

    test('asks about a place only when told, and says when the answer came', () {
      fakeAsync((async) {
        final art = PlaceRichArt(
          thumbs: PlaceThumbs(photoAndPrice),
          load: (_) async => Uint8List(0),
        );
        expect(art.plan(place, credited, ask: false), isNull);
        async.elapse(const Duration(milliseconds: 100));
        expect(photoAndPrice.asked, isEmpty, reason: 'not asked');
        var ready = 0;
        expect(art.plan(place, credited, onReady: () => ready++), isNull);
        async.elapse(const Duration(milliseconds: 100));
        expect(photoAndPrice.asked, [
          ['a'],
        ]);
        expect(ready, 1);
        expect(art.plan(place, credited), RichPlan.photo);
      });
    });

    test('a photo only online, on a map that credits its source', () {
      fakeAsync((async) {
        final thumbs = PlaceThumbs(photoAndPrice);
        final art = PlaceRichArt(thumbs: thumbs, load: (_) async => Uint8List(0));
        unawaited(thumbs.of('a'));
        async.elapse(const Duration(milliseconds: 100));
        expect(art.plan(place, credited), RichPlan.photo);
        for (final style in [uncredited, offline]) {
          final plan = art.plan(place, style)!;
          expect(plan.capsule, isTrue, reason: 'the pictogram');
          expect(plan.label, startsWith('12'), reason: 'with the price known');
        }
      });
    });

    test(
      'a photo that did not come leaves the pictogram for a while, then is tried again',
      () async {
        var now = DateTime(2026, 10, 9, 12);
        final thumbs = PlaceThumbs(photoAndPrice);
        final art = PlaceRichArt(
          thumbs: thumbs,
          load: (_) => Future.error(StateError('no signal')),
          clock: () => now,
        );
        await thumbs.of('a');
        expect(art.plan(place, credited), RichPlan.photo);
        expect(await art.draw(place, RichPlan.photo, size: 48, ratio: 1, style: credited), isNull);
        expect(art.plan(place, credited)!.capsule, isTrue);
        now = now.add(const Duration(minutes: 6));
        expect(art.plan(place, credited), RichPlan.photo, reason: 'a weak signal passes');
      },
    );
  });

  test("the plugin's layer of the marks is the desktop page's", () {
    expect(richSymbolProperties(1.5).toJson(), RichLayers.layout(1.5));
  });
}

String _none(double _) => '';

final class _Thumbs implements PlaceThumbsSource {
  new(this.answers);

  final Map<String, PlaceThumb> answers;
  final asked = <List<String>>[];
  bool fail = false;
  Duration delay = Duration.zero;

  @override
  Future<Map<String, PlaceThumb>> fetch(List<String> ids) async {
    asked.add(ids);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw StateError('no network');
    return {for (final id in ids) id: ?answers[id]};
  }
}
