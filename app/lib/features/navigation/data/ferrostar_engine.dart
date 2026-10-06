import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway_nav/lunaway_nav.dart' as nav;

final _log = Logger('guidance');

/// Loads the guidance library: built into the app on Android and iOS by the
/// lunaway_nav build hook; [library] points at one built for a desktop
/// host, for tests. Null where there is none (desktop, a failed load).
Future<GuidanceEngine?> loadFerrostarEngine({nav.ExternalLibrary? library}) async {
  final phone =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (library == null && !phone) return null;
  try {
    await nav.RustLib.init(externalLibrary: library);
    return const FerrostarEngine();
  } on Object catch (e, st) {
    _log.warning('the guidance library did not load', e, st);
    return null;
  }
}

/// [GuidanceEngine] over Ferrostar's core, through lunaway_nav.
final class FerrostarEngine implements GuidanceEngine {
  const new();

  @override
  bool get available => true;

  @override
  GuidanceTrack start(String osrmJson, int routeIndex) {
    try {
      return _FerrostarTrack(
        nav.Guidance(
          osrmJson: osrmJson,
          routeIndex: routeIndex,
          settings: nav.defaultGuidanceSettings(),
        ),
      );
    } on nav.GuidanceError catch (e) {
      throw GuidanceUnavailable('${e.kind.name}: ${e.message}');
    }
  }
}

final class _FerrostarTrack implements GuidanceTrack {
  new(this._guidance);

  final nav.Guidance _guidance;

  @override
  GuidanceSnapshot update(Fix fix) => snapshotOf(
    _guidance.update(
      fix: nav.Fix(
        lat: fix.position.lat,
        lon: fix.position.lon,
        accuracyM: fix.accuracyM,
        courseDeg: fix.courseDeg,
        speedMps: fix.speedMps,
        timestampMs: nav.PlatformInt64Util.from(fix.at.millisecondsSinceEpoch),
      ),
    ),
  );

  @override
  List<EventHit> eventsAhead(double fromM, List<EventShape> events) => [
    for (final h in _guidance.eventsAhead(
      fromM: fromM,
      events: [
        for (final e in events)
          nav.EventShape(
            id: e.id,
            points: [for (final p in e.points) nav.LatLon(lat: p.lat, lon: p.lon)],
            directed: e.directed,
            headingDeg: e.headingDeg,
            headingToleranceDeg: e.headingToleranceDeg,
          ),
      ],
      lineToleranceM: eventLineToleranceM,
      pointToleranceM: eventPointToleranceM,
    ))
      EventHit(id: h.id, startM: h.startM, endM: h.endM, at: LatLng(h.lat, h.lon)),
  ];

  @override
  void dispose() => _guidance.dispose();
}

/// The app's snapshot of the bridge's state.
@visibleForTesting
GuidanceSnapshot snapshotOf(nav.GuidanceState s) => GuidanceSnapshot(
  status: s.status == nav.GuidanceStatus.arrived
      ? GuidanceStatus.arrived
      : GuidanceStatus.navigating,
  position: LatLng(s.snappedLat, s.snappedLon),
  courseDeg: s.courseDeg,
  stepIndex: s.stepIndex,
  distanceToManeuverM: s.distanceToManeuverM,
  distanceRemainingM: s.distanceRemainingM,
  durationRemainingS: s.durationRemainingS,
  distanceAlongM: s.distanceAlongM,
  offRouteM: s.offRouteM,
  banner: s.banner == null
      ? null
      : ManeuverBanner(
          primary: s.banner!.primary,
          secondary: s.banner!.secondary,
          maneuverType: s.banner!.maneuverType,
          modifier: s.banner!.modifier,
          roundaboutExitDegrees: s.banner!.roundaboutExitDegrees,
          lanes: [
            for (final l in s.banner!.lanes) LaneHint(directions: l.directions, active: l.active),
          ],
        ),
  instruction: s.utterance == null
      ? null
      : SpokenInstruction(id: s.utterance!.id, text: s.utterance!.text),
  speedLimitKmh: s.speedLimitKmh,
);
