import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_progress.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'guidance_camera.g.dart';

/// Where the guidance map looks.
enum GuidanceCameraMode {
  /// Behind the vehicle, turned to the road and tilted.
  follow,

  /// Where the user moved it: following stopped at the first gesture.
  free,

  /// The whole route, flat and north up.
  overview,
}

/// The guidance map's camera, and how the last return to following eases in.
@immutable
final class GuidanceView {
  const new({
    this.mode = GuidanceCameraMode.follow,
    this.ease = FreeMap.recenterEase,
    this.rest,
    this.follows = 0,
    this.legTo,
  });

  final GuidanceCameraMode mode;

  /// How long the way back into following takes: short for the magnet, from
  /// a view already close; longer from anywhere else.
  final Duration ease;

  /// Where the free map last rested: a map made anew in the other layout
  /// (the phone turned) opens there.
  final FreeView? rest;

  /// How many times following was asked for: a map the user took in the
  /// same frame as a new request (a nudge the magnet brings back at once)
  /// still hears that request (`FollowCamera.request`).
  final int follows;

  /// In the overview, the leg of the trip it frames, named by the stop or
  /// the destination it leads to as the user asked for it; null for the
  /// whole route. Each overview starts on the whole route.
  final LatLng? legTo;

  @override
  bool operator ==(Object other) =>
      other is GuidanceView &&
      other.mode == mode &&
      other.ease == ease &&
      other.rest == rest &&
      other.follows == follows &&
      other.legTo == legTo;

  @override
  int get hashCode => Object.hash(mode, ease, rest, follows, legTo);
}

/// The guidance map's camera mode: following by default; free as soon as
/// the user moves the map; the whole route on demand. Back to following on
/// "Recentrer", by the magnet, or after [FreeMap.idleReturn] without a
/// touch while the vehicle drives, never while a finger, the mouse or a
/// card opened from the map holds it.
///
/// The guidance itself (instructions, voice, new routes) does not read it:
/// it runs the same whatever the map shows.
@riverpod
class GuidanceCamera extends _$GuidanceCamera {
  Timer? _idle;
  bool _touching = false;
  int _held = 0;
  bool _driving = false;

  @override
  GuidanceView build() {
    ref.onDispose(() => _idle?.cancel());
    // Only the crossing of the driving speed matters: a fix a second must
    // not restart the countdown.
    ref.listen(
      guidanceControllerProvider.select((s) => (s?.lastFix?.speedMps ?? 0) > FreeMap.drivingMps),
      (before, driving) {
        _driving = driving;
        // The first call comes from build, before there is a state; the
        // camera then follows and nothing counts down.
        if (before != null) _arm();
      },
      fireImmediately: true,
    );
    // A new route landing while the whole route shows (a stop taken out or
    // put back, a detour): it shows for the whole countdown, however long
    // the server took to answer.
    ref.listen(guidanceControllerProvider.select((s) => s?.plan), (before, plan) {
      if (plan != null && before != null && state.mode == GuidanceCameraMode.overview) _arm();
    });
    return const GuidanceView();
  }

  /// The user moved the map (a drag, a pinch, a turn, a tilt, the wheel).
  void moved() {
    if (state.mode != GuidanceCameraMode.free) {
      state = GuidanceView(mode: GuidanceCameraMode.free, ease: state.ease, follows: state.follows);
    }
    _arm();
  }

  /// The free map came to rest at [view].
  void rested(FreeView view) {
    if (state.mode == GuidanceCameraMode.free) {
      state = GuidanceView(
        mode: GuidanceCameraMode.free,
        ease: state.ease,
        rest: view,
        follows: state.follows,
      );
    }
  }

  /// "Recentrer", or the return after a while.
  void recenter() => _follow(FreeMap.recenterEase);

  /// The magnet: the view came back close to the driver's.
  void snap() => _follow(FreeMap.snapEase);

  /// The whole route, or back to the vehicle from it.
  void toggleOverview() {
    if (state.mode == GuidanceCameraMode.overview) {
      recenter();
      return;
    }
    state = GuidanceView(
      mode: GuidanceCameraMode.overview,
      ease: state.ease,
      follows: state.follows,
    );
    _arm();
  }

  /// In the overview, frames the leg leading to [to] (null: the whole
  /// route). A choice counts as a touch: the countdown back to the road
  /// starts again.
  void frameLeg(LatLng? to) {
    if (state.mode != GuidanceCameraMode.overview) return;
    state = GuidanceView(
      mode: GuidanceCameraMode.overview,
      ease: state.ease,
      follows: state.follows,
      legTo: to,
    );
    _arm();
  }

  /// A touch on a control of the view shown (a stop taken out from the
  /// overview's strip or put back by the notice's undo, the strip
  /// scrolled): the countdown back to the road starts again.
  void touched() => _arm();

  /// A finger or the mouse button is down on the map ([down]), or no more.
  void touching({required bool down}) {
    if (_touching == down) return;
    _touching = down;
    _arm();
  }

  /// Something opened from the map (a place's card, the places sheet)
  /// holds it until the returned function is called: the map does not
  /// leave what the user is reading about.
  void Function() hold() {
    _held++;
    _arm();
    var released = false;
    return () {
      if (released || !ref.mounted) return;
      released = true;
      _held--;
      _arm();
    };
  }

  void _follow(Duration ease) {
    _idle?.cancel();
    state = GuidanceView(ease: ease, follows: state.follows + 1);
  }

  /// (Re)starts the countdown back to following, from now: only away from
  /// following, while driving, with nothing holding the map.
  void _arm() {
    _idle?.cancel();
    _idle = null;
    if (state.mode == GuidanceCameraMode.follow || _touching || _held > 0 || !_driving) return;
    _idle = Timer(FreeMap.idleReturn, () {
      if (ref.mounted && !_touching && _held == 0) recenter();
    });
  }
}

/// The arrow the guidance map draws on the route at the next maneuver
/// ([arrowForManeuver]); none off the route, while a new one is sought or
/// at the arrival. Worked out once per maneuver: where it lies along the
/// route (the distance driven plus the distance to it) is read when the
/// maneuver comes up and holds while the vehicle drives toward it, so a
/// fix that wanders, parked, neither moves it nor redraws the map.
@riverpod
ManeuverArrow? guidanceArrow(Ref ref) {
  final ahead = ref.watch(
    guidanceControllerProvider.select((s) {
      final snap = s?.snapshot;
      if (s == null ||
          snap == null ||
          snap.offRoute ||
          s.phase != GuidancePhase.navigating ||
          snap.status == GuidanceStatus.arrived) {
        return null;
      }
      final steps = s.route.steps;
      final i = snap.stepIndex;
      final next = i + 1 < steps.length ? steps[i + 1] : null;
      final type = snap.banner?.maneuverType ?? next?.maneuverType;
      // A roundabout entered at the maneuver: its ring is the next step.
      final ring = type == 'roundabout' || type == 'rotary' ? next?.distanceM ?? 0.0 : 0.0;
      return (
        line: s.route.line,
        step: i,
        type: type,
        modifier: snap.banner?.modifier ?? next?.modifier,
        ringM: ring,
      );
    }),
  );
  if (ahead == null) return null;
  final snap = ref.read(guidanceControllerProvider)?.snapshot;
  if (snap == null) return null;
  return arrowForManeuver(
    ahead.line,
    atM: snap.distanceAlongM + snap.distanceToManeuverM,
    type: ahead.type,
    modifier: ahead.modifier,
    ringM: ahead.ringM,
  );
}

/// The zoom and the tilt the guidance map aims at while it follows
/// ([autoAim]): the speed held through [SpeedHold], so a GPS speed that
/// wavers does not make the view breathe, and the next maneuver's distance
/// and kind, so the camera frames it, closer as it comes, flatter over a
/// junction, wider and toward the horizon down a long straight. The
/// engines ease toward it at each frame of the glide.
@riverpod
class GuidanceAim extends _$GuidanceAim {
  final _speed = SpeedHold();

  /// The aim last worked out while the vehicle moved: parked, it holds,
  /// as the drawn vehicle does ([AutoZoom.holdBelowMps]); a fix that
  /// wanders by a few metres moves neither the zoom nor the tilt, and the
  /// map draws no frame.
  CameraAim? _moving;

  @override
  CameraAim build() {
    // Listened rather than watched: the speed held lives in this notifier,
    // which a rebuild at each fix would start over.
    var building = true;
    var first = restingAim;
    ref.listen(guidanceControllerProvider, (_, session) {
      final aim = _aimOf(session);
      if (building) {
        first = aim;
      } else if (aim != state) {
        state = aim;
      }
    }, fireImmediately: true);
    building = false;
    return first;
  }

  CameraAim _aimOf(GuidanceSession? session) {
    final speed = session?.lastFix?.speedMps;
    final kmh = _speed.update(speed);
    if (_moving case final held? when speed != null && speed < AutoZoom.holdBelowMps) {
      return held;
    }
    return _moving = _aimMoving(session, kmh);
  }

  CameraAim _aimMoving(GuidanceSession? session, double kmh) {
    final snap = session?.snapshot;
    // Off the route the maneuver is that of a road the vehicle left.
    if (session == null || snap == null || snap.offRoute) {
      return autoAim(speedKmh: kmh, distanceToManeuverM: null);
    }
    final steps = session.route.steps;
    final next = snap.stepIndex + 1 < steps.length ? steps[snap.stepIndex + 1] : null;
    return autoAim(
      speedKmh: kmh,
      distanceToManeuverM: snap.distanceToManeuverM,
      maneuverType: snap.banner?.maneuverType ?? next?.maneuverType,
      modifier: snap.banner?.modifier ?? next?.modifier,
      // The road after the next maneuver, to the one after it.
      afterM: next?.distanceM,
      motorway: session.step?.motorway ?? false,
    );
  }
}
