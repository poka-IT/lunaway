import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

import 'fixtures/drive_routes.dart';

/// The guidance engine on a real phone: the Rust library the build hook
/// compiled for the device, loaded through flutter_rust_bridge, driven along
/// a route recorded from the Lunaway API.
///
///   fvm flutter test integration_test/navigation_engine_test.dart -d emulator-5554 --flavor store
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the Rust engine loads on the device and guides a drive to the end', () async {
    final engine = await loadFerrostarEngine();
    expect(engine, isNotNull, reason: 'the library is bundled for Android and iOS');
    final data = (jsonDecode(limogesDrive) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final plan = await withShapes(routePlanFromJson(data['route'] as Map<String, dynamic>));
    final track = engine!.start(plan.osrmJson!, 0);
    final fixes = drive(
      plan.routes.first.line,
      stepM: 10,
      start: DateTime.utc(2026, 10, 6, 9),
      tick: const Duration(seconds: 1),
      speedMps: 10,
    );
    final spoken = <String>{};
    GuidanceSnapshot? last;
    for (final f in fixes) {
      last = track.update(f);
      if (last.instruction != null) spoken.add(last.instruction!.id);
      if (last.status == GuidanceStatus.arrived) break;
    }
    expect(last?.status, GuidanceStatus.arrived);
    expect(spoken.length, greaterThanOrEqualTo(8));

    // The closure of Port du Naveix lies ahead from the start.
    final line = plan.routes.first.line;
    final naveix = [
      for (
        var i = 0, along = 0.0;
        i + 1 < line.length;
        along += line[i].distanceTo(line[i + 1]), i++
      )
        if (along >= 1500 && along <= 1900) line[i],
    ];
    final fresh = engine.start(plan.osrmJson!, 0);
    final hits = fresh.eventsAhead(0, [EventShape(id: 'closure', points: naveix)]);
    expect(hits.single.id, 'closure');
    expect(hits.single.startM, inInclusiveRange(1450, 1600));
    fresh.dispose();
    track.dispose();

    // Off the route: 0.003 degrees east of the line, about 230 m.
    final away = engine.start(plan.osrmJson!, 0);
    fixes.take(30).forEach(away.update);
    final p = fixes[30].position;
    final off = Fix(position: LatLng(p.lat, p.lon + 0.003), accuracyM: 5, at: fixes[30].at);
    away.update(off);
    final second = away.update(
      Fix(position: off.position, accuracyM: 5, at: off.at.add(const Duration(seconds: 1))),
    );
    expect(second.offRoute, isTrue);
    away.dispose();
  });
}
