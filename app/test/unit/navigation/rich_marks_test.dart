import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/data/place_thumbs.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
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
  Future<void> putImage(String id, Uint8List png) async {
    images[id] = png;
    puts.add(id);
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
}

/// Draws a mark at once, or when [gate] completes; a place in [photos] is
/// a photo, the others illustrated.
final class _Art implements RichArt {
  final drawn = <String>[];
  Set<String> photos = {};
  Completer<void>? gate;

  @override
  ({bool capsule, double labelWidth}) plan(
    PlaceSummary place,
    GuidanceLook look,
    RichWords words, {
    required bool online,
  }) => (capsule: !photos.contains(place.id), labelWidth: photos.contains(place.id) ? 0 : 40);

  @override
  Future<RichArtwork?> draw(
    PlaceSummary place, {
    required GuidanceLook look,
    required double size,
    required double ratio,
    required RichWords words,
    required bool online,
  }) async {
    await gate?.future;
    drawn.add(place.id);
    final photo = photos.contains(place.id);
    return RichArtwork(
      png: Uint8List.fromList(place.id.codeUnits),
      geometry: RichGeometry(size, labelWidth: photo ? 0 : 40, capsule: !photo),
      photo: photo,
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

RichInput _input(
  _Art art, {
  GuidanceLook look = GuidanceLook.photos,
  List<PlaceSummary> places = const [],
  bool tiles = false,
  bool yielding = false,
  int limit = 4,
}) => RichInput(
  rich: RouteMapRich(
    look: look,
    art: art,
    words: _words,
    places: places,
    tiles: tiles,
    yielding: yielding,
    limit: limit,
    clear: const EdgeInsets.fromLTRB(0, 120, 72, 140),
  ),
  size: const Size(390, 760),
  ratio: 3,
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

  /// Places [places] at the screen points given, inside the open map.
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
    expect(art.drawn, unorderedEquals(['a', 'b']));
    expect(engine.features, isEmpty, reason: 'nothing drawn yet');
    await driver.refresh(_input(art, places: [a, b]));
    final features = engine.features;
    expect([for (final f in features) f[PlaceTiles.id]], unorderedEquals(['a', 'b']));
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
    driver = RichMarkDriver(engine, onDrawn: () => asked++);
    await driver.refresh(_input(art, places: [a]));
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
    expect(art.drawn, isEmpty);
    art.gate!.complete();
    await pumpEventQueue();
    expect(asked, 1);
    await driver.refresh(_input(art, places: [a]));
    expect([for (final f in engine.features) f[PlaceTiles.id]], ['a']);
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
    expect(engine.features, hasLength(1));
    await driver.refresh(_input(art, places: [a], yielding: true));
    expect(engine.features, isEmpty);
    await driver.refresh(_input(art, places: [a]));
    engine.zoom = 9;
    await driver.refresh(_input(art, places: [a]));
    expect(engine.features, isEmpty);
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
          for (var i = 0; i < 10; i++) 'p$i': PlaceThumb(url: 'u$i', priceEur: i.toDouble()),
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
        expect(answers['p9'], const PlaceThumb(url: 'u9', priceEur: 9));
        expect(thumbs.known('p3'), const PlaceThumb(url: 'u3', priceEur: 3));
        unawaited(thumbs.of('p3'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, hasLength(2), reason: 'known: not asked again');
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
        unawaited(thumbs.of('p'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, hasLength(1));
        now = now.add(const Duration(minutes: 6));
        source.fail = false;
        unawaited(thumbs.of('p'));
        async.elapse(const Duration(milliseconds: 100));
        expect(source.asked, hasLength(2));
      });
    });

    test("the map shows the community's photo, else the partner's of the place itself", () {
      expect(
        mapPhotoOf(
          community: [(sourceId: 'community-cc-by', thumbUrl: 'mine')],
          external: [(sourceId: 'extcom', kind: 'PLACE', thumbUrl: 'theirs')],
        ),
        'mine',
      );
      expect(
        mapPhotoOf(
          community: const [],
          external: [
            (sourceId: 'extcom', kind: 'SURROUNDINGS', thumbUrl: 'around'),
            (sourceId: 'extcom', kind: 'STREET_VIEW', thumbUrl: 'street'),
            (sourceId: 'extcom', kind: 'PLACE', thumbUrl: 'place'),
          ],
        ),
        'place',
      );
    });

    test('never a photo whose credit belongs beside it', () {
      expect(
        mapPhotoOf(
          community: const [],
          external: [
            (sourceId: 'datatourisme', kind: 'PLACE', thumbUrl: 'office'),
            (sourceId: 'wikimedia-commons', kind: 'PLACE', thumbUrl: 'commons'),
            (sourceId: 'panoramax', kind: 'STREET_VIEW', thumbUrl: 'street'),
          ],
        ),
        isNull,
      );
    });

    test('the request names eight places and reads each answer', () {
      final document = placeThumbsOperation.document;
      expect(RegExp(r'place\(id:').allMatches(document), hasLength(thumbsBatch));
      final parsed = placeThumbsOperation.parse({
        't0': {
          'id': 'a',
          'priceParkingEur': 12,
          'coverPhotos': <Object>[],
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
        'a': const PlaceThumb(url: 'https://api/x/thumb', priceEur: 12),
        'b': const PlaceThumb(),
      });
    });
  });
}

final class _Thumbs implements PlaceThumbsSource {
  new(this.answers);

  final Map<String, PlaceThumb> answers;
  final asked = <List<String>>[];
  bool fail = false;

  @override
  Future<Map<String, PlaceThumb>> fetch(List<String> ids) async {
    asked.add(ids);
    if (fail) throw StateError('no network');
    return {for (final id in ids) id: ?answers[id]};
  }
}
