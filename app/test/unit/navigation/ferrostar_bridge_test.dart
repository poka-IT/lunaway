import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway_nav/lunaway_nav.dart' show ExternalLibrary;

import '../../helpers/navigation.dart';

/// The guidance library built for this computer, when it is: the bridge is
/// the same on a phone, only the library differs. Build it with
/// `cargo build --locked --release` in `packages/lunaway_nav/rust/`, as
/// `tool/check.sh` does before the tests; without it these tests say so and
/// skip.
String? hostLibrary() {
  final name = Platform.isMacOS
      ? 'liblunaway_nav.dylib'
      : Platform.isWindows
      ? 'lunaway_nav.dll'
      : 'liblunaway_nav.so';
  final file = File('packages/lunaway_nav/rust/target/release/$name');
  return file.existsSync() ? file.absolute.path : null;
}

void main() {
  final library = hostLibrary();
  late GuidanceEngine engine;

  setUpAll(() async {
    if (library == null) return;
    engine = (await loadFerrostarEngine(library: ExternalLibrary.open(library)))!;
  });

  final skip = library == null
      ? 'the guidance library is not built here (cargo build --release in packages/lunaway_nav/rust)'
      : null;

  test('a drive along the recorded route walks every step to the arrival', () {
    final plan = routeFixture('limoges_drive');
    final track = engine.start(plan.osrmJson!, 0);
    addTearDown(track.dispose);
    final fixes = drive(
      plan.routes.single.line,
      stepM: 10,
      start: DateTime.utc(2026, 10, 6, 9),
      tick: const Duration(seconds: 1),
      speedMps: 10,
    );
    final spoken = <String>[];
    final types = <String?>{};
    var along = 0.0;
    final limits = <double>{};
    late GuidanceSnapshot last;
    for (final f in fixes) {
      last = track.update(f);
      if (last.status == GuidanceStatus.arrived) break;
      expect(last.distanceAlongM, greaterThanOrEqualTo(along - 1));
      along = last.distanceAlongM;
      expect(last.offRoute, isFalse);
      types.add(last.banner?.maneuverType);
      if (last.instruction case final i? when !spoken.contains(i.id)) spoken.add(i.id);
      if (last.speedLimitKmh case final l?) limits.add(l);
    }
    expect(last.status, GuidanceStatus.arrived);
    expect(spoken.length, greaterThanOrEqualTo(8));
    expect(types, containsAll(['turn', 'arrive']));
    expect(limits, contains(50));
  }, skip: skip);

  test('the vehicle off the line is off the route, by its distance', () {
    final plan = routeFixture('limoges_drive');
    final track = engine.start(plan.osrmJson!, 0);
    addTearDown(track.dispose);
    final fixes = drive(
      plan.routes.single.line,
      stepM: 10,
      start: DateTime.utc(2026, 10, 6, 9),
      tick: const Duration(seconds: 1),
      speedMps: 10,
    ).take(40).toList();
    final p = fixes.last.position;
    final away = LatLng(p.lat, p.lon + 0.003);
    // Ferrostar judges a fix against the state before it: the second fix
    // away is the one that says the vehicle left.
    [
      ...fixes,
      Fix(position: away, accuracyM: 5, at: fixes.last.at.add(const Duration(seconds: 1))),
    ].forEach(track.update);
    final second = track.update(
      Fix(position: away, accuracyM: 5, at: fixes.last.at.add(const Duration(seconds: 2))),
    );
    expect(second.offRouteM, greaterThan(100));
  }, skip: skip);

  test('road events: a directed closure one way, a point within 15 m', () {
    final plan = routeFixture('limoges_drive');
    final track = engine.start(plan.osrmJson!, 0);
    addTearDown(track.dispose);
    final line = LineTrack(plan.routes.single);
    final naveix = [for (var m = 1500.0; m <= 1900; m += 20) line.at(m)];
    final point = LatLng(line.at(2500).lat + 0.0001, line.at(2500).lon);
    final course = bearing(line.at(2495), line.at(2505));
    final hits = track.eventsAhead(0, [
      EventShape(id: 'this-way', points: naveix, directed: true),
      EventShape(id: 'other-way', points: naveix.reversed.toList(), directed: true),
      EventShape(id: 'point', points: [point]),
      EventShape(
        id: 'point-this-way',
        points: [point],
        headingDeg: course,
        headingToleranceDeg: 60,
      ),
      EventShape(
        id: 'point-other-way',
        points: [point],
        headingDeg: (course + 180) % 360,
        headingToleranceDeg: 60,
      ),
    ]);
    expect(hits.map((h) => h.id), ['this-way', 'point', 'point-this-way']);
    expect(hits.first.startM, closeTo(1500, 60));
    expect(track.eventsAhead(2000, [EventShape(id: 'behind', points: naveix)]), isEmpty);
  }, skip: skip);

  test('an answer that cannot be read is refused with a reason', () {
    expect(() => engine.start('{"code":', 0), throwsA(isA<GuidanceUnavailable>()));
    expect(
      () => engine.start(routeFixture('limoges_drive').osrmJson!, 3),
      throwsA(isA<GuidanceUnavailable>()),
    );
  }, skip: skip);
}
