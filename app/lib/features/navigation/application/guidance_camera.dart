import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
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
  /// overview's strip): the countdown back to the road starts again, so
  /// the new route shows before the map goes back to the vehicle.
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
