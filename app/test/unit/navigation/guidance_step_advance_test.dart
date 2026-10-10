import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway_nav/lunaway_nav.dart' show ExternalLibrary;

import '../../helpers/navigation.dart';
import 'ferrostar_bridge_test.dart' show hostLibrary;

/// The guidance controller over the real engine, driven as a browser drove
/// the web app on 2026-10-10: Perpignan to Figueres by the D 900, a fix a
/// second at 25 m/s, then a jump of the position. An engine that waits for
/// a fix near each step's end stays on "Serrez à droite." at 0 m after the
/// fork, and on the roundabout before a jump, saying nothing more.
void main() {
  final library = hostLibrary();
  late GuidanceEngine engine;
  late Translations fr;

  setUpAll(() async {
    fr = await AppLocale.fr.build();
    if (library == null) return;
    engine = (await loadFerrostarEngine(library: ExternalLibrary.open(library)))!;
  });

  final skip = library == null
      ? 'the guidance library is not built here (cargo build --release in packages/lunaway_nav/rust)'
      : null;

  final t0 = DateTime.utc(2026, 10, 10, 1, 12, 52);
  const target = RouteTarget(destination: LatLng(42.266461, 2.960676), label: 'Figueres');

  late FakeLocationFeed feed;
  late RecordingVoice voice;
  late ProviderContainer container;
  late RouteOption route;

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> start() async {
    final plan = routeFixture('perpignan_figueres');
    route = plan.routes.single;
    feed = FakeLocationFeed();
    voice = RecordingVoice();
    container = ProviderContainer.test(
      overrides: [
        ...navigationOverrides(
          routes: FakeRouteService([plan]),
          feed: feed,
          engine: engine,
          voice: voice,
          drivingAids: DrivingAidsStore(() async => null, (_) async {}),
        ),
        clockProvider.overrideWithValue(() => t0),
      ],
    );
    await container.read(routeSettingsControllerProvider.future);
    final started = await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: 0,
          target: target,
          words: TranslatedWording(fr, DistanceUnits.metric),
        );
    expect(started, isTrue);
    await settle();
  }

  GuidanceSession session() => container.read(guidanceControllerProvider)!;

  /// A fix every [tick] at each of [metres] along the route, as the
  /// bench's browser gave them, at [speedMps].
  Future<void> drive(
    Iterable<double> metres, {
    required double speedMps,
    Duration tick = const Duration(seconds: 1),
  }) async {
    final line = LineTrack(route);
    var at = t0;
    for (final m in metres) {
      final p = line.at(m);
      feed.send(
        Fix(
          position: p,
          accuracyM: 5,
          at: at,
          courseDeg: bearing(p, line.at(m + 5)),
          speedMps: speedMps,
        ),
      );
      at = at.add(tick);
      await settle();
    }
  }

  Iterable<double> every(double stepM, double fromM, double toM) sync* {
    for (var m = fromM; m <= toM; m += stepM) {
      yield m;
    }
  }

  test(
    'a fix every 25 m: past the 7 m step after the fork, the next instructions are said',
    () async {
      await start();
      await drive(every(25, 0, 1500), speedMps: 25);
      final snap = session().snapshot!;
      expect(snap.stepIndex, greaterThan(5), reason: 'the steps after the fork were walked');
      expect(snap.distanceToManeuverM, greaterThan(1), reason: 'not pinned at 0 m');
      expect(snap.distanceAlongM, closeTo(1500, 60));
      expect(
        voice.said,
        containsAll([
          // The roundabout after the fork, then its way out.
          contains('Entrez dans Place Salvador Espriu'),
          'Prenez la sortie.',
          'Continuez pendant 3 kilomètres.',
        ]),
      );
      expect(session().phase, GuidancePhase.navigating);
    },
    skip: skip,
  );

  test('a jump of 900 m over a roundabout: the guidance takes up from the new position', () async {
    await start();
    // Two fixes a second up to the jump: the bench's witness, which the
    // old engine followed past the fork.
    await drive(
      [...every(12.5, 0, 3200), ...every(12.5, 4100, 5000)],
      speedMps: 25,
      tick: const Duration(milliseconds: 500),
    );
    final snap = session().snapshot!;
    expect(snap.distanceAlongM, closeTo(5000, 60), reason: 'the vehicle where it is');
    expect(snap.stepIndex, 10, reason: 'past the roundabout of the Compagnons d’Emmaüs');
    expect(
      voice.said,
      contains(
        "Entrez dans Rond-Point des Compagnons d'Emmaüs et prenez la 2e sortie dans "
        'Route du Perthus, D 900.',
      ),
    );
    expect(session().phase, GuidancePhase.navigating);
  }, skip: skip);
}
