import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

import '../../helpers/navigation.dart';

/// A guidance whose vehicle drives at the speed the test sets.
final class _Driving extends GuidanceController {
  @override
  GuidanceSession? build() => null;

  void speed(double mps) {
    final plan = routeFixture('limoges_drive');
    state = GuidanceSession(
      target: const RouteTarget(destination: LatLng(45.8, 1.26)),
      plan: plan,
      routeIndex: plan.routes.first.index,
      phase: GuidancePhase.navigating,
      voiceOn: true,
      voice: VoiceReadiness.ready,
      lastFix: Fix(
        position: const LatLng(45.84, 1.28),
        accuracyM: 5,
        at: DateTime.utc(2026, 10, 7),
        speedMps: mps,
      ),
    );
  }
}

void main() {
  late ProviderContainer container;
  late _Driving guidance;

  GuidanceView view() => container.read(guidanceCameraProvider);
  GuidanceCamera camera() => container.read(guidanceCameraProvider.notifier);

  /// A container whose camera is listened to, as the guidance screen does.
  void open({double speed = 14}) {
    container = ProviderContainer.test(
      overrides: [guidanceControllerProvider.overrideWith(_Driving.new)],
    )..listen(guidanceCameraProvider, (_, _) {});
    guidance = container.read(guidanceControllerProvider.notifier) as _Driving..speed(speed);
  }

  test('follows the vehicle until the user moves the map', () {
    open();
    expect(view().mode, GuidanceCameraMode.follow);
    camera().moved();
    expect(view().mode, GuidanceCameraMode.free);
  });

  test('"Recentrer" eases back from afar, the magnet snaps back in a short ease', () {
    open();
    camera()
      ..moved()
      ..recenter();
    expect((view().mode, view().ease), (GuidanceCameraMode.follow, FreeMap.recenterEase));
    camera()
      ..moved()
      ..snap();
    expect((view().mode, view().ease), (GuidanceCameraMode.follow, FreeMap.snapEase));
  });

  test('each request to follow is a new one, even right after a gesture', () {
    open();
    final first = view().follows;
    // A nudge the magnet brings back before the screen showed the map free.
    camera()
      ..moved()
      ..snap();
    expect(view().follows, first + 1);
    camera()
      ..moved()
      ..recenter();
    expect(view().follows, first + 2);
  });

  test('while driving, the map comes back after 12 s without a touch', () {
    fakeAsync((time) {
      open();
      camera().moved();
      time.elapse(const Duration(seconds: 11));
      expect(view().mode, GuidanceCameraMode.free);
      time.elapse(const Duration(seconds: 1, milliseconds: 1));
      expect((view().mode, view().ease), (GuidanceCameraMode.follow, FreeMap.recenterEase));
    });
  });

  test('each gesture counts the delay again', () {
    fakeAsync((time) {
      open();
      camera().moved();
      time.elapse(const Duration(seconds: 10));
      camera().moved();
      time.elapse(const Duration(seconds: 10));
      expect(view().mode, GuidanceCameraMode.free);
      time.elapse(const Duration(seconds: 3));
      expect(view().mode, GuidanceCameraMode.follow);
    });
  });

  test('never while a finger is on the map: the delay starts when it lifts', () {
    fakeAsync((time) {
      open();
      camera()
        ..touching(down: true)
        ..moved();
      time.elapse(const Duration(seconds: 40));
      expect(view().mode, GuidanceCameraMode.free);
      camera().touching(down: false);
      time.elapse(const Duration(seconds: 11));
      expect(view().mode, GuidanceCameraMode.free);
      time.elapse(const Duration(seconds: 2));
      expect(view().mode, GuidanceCameraMode.follow);
    });
  });

  test('a card open from the map holds it until it closes', () {
    fakeAsync((time) {
      open();
      camera().moved();
      final release = camera().hold();
      time.elapse(const Duration(seconds: 30));
      expect(view().mode, GuidanceCameraMode.free);
      release();
      // Released twice (a card closed, then the screen gone) counts once.
      release();
      time.elapse(const Duration(seconds: 13));
      expect(view().mode, GuidanceCameraMode.follow);
    });
  });

  test('parked, the map stays where the user left it; driving off brings it back', () {
    fakeAsync((time) {
      open(speed: 0);
      camera().moved();
      time.elapse(const Duration(minutes: 5));
      expect(view().mode, GuidanceCameraMode.free);
      guidance.speed(8);
      time.elapse(const Duration(seconds: 11));
      expect(view().mode, GuidanceCameraMode.free);
      time.elapse(const Duration(seconds: 2));
      expect(view().mode, GuidanceCameraMode.follow);
    });
  });

  test('stopping before the delay keeps the map free', () {
    fakeAsync((time) {
      open();
      camera().moved();
      time.elapse(const Duration(seconds: 6));
      guidance.speed(0.5);
      time.elapse(const Duration(seconds: 30));
      expect(view().mode, GuidanceCameraMode.free);
    });
  });

  test('the whole route is a view of its own, back to the vehicle on the same button', () {
    fakeAsync((time) {
      open();
      camera().toggleOverview();
      expect(view().mode, GuidanceCameraMode.overview);
      camera().toggleOverview();
      expect(view().mode, GuidanceCameraMode.follow);
      // Left alone while driving, the overview gives way to the road too.
      camera().toggleOverview();
      time.elapse(const Duration(seconds: 13));
      expect(view().mode, GuidanceCameraMode.follow);
    });
  });

  test('moving the whole route frees it', () {
    open();
    camera()
      ..toggleOverview()
      ..moved();
    expect(view().mode, GuidanceCameraMode.free);
  });
}
