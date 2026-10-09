import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/voice_queue.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/simulated_feed.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'guidance_controller.g.dart';

final _log = Logger('guidance');

/// The sentences the guidance says, in the app's language; built by the
/// screen from its translations, so the controller stays free of widgets.
abstract interface class GuidanceWording {
  /// The Android notification that keeps the position coming.
  BackgroundNotice get notice;

  /// "Recalcul de l'itinéraire."
  String get rerouting;

  /// "Nouvel itinéraire.", with the minutes it adds when they are known.
  String rerouted(Duration? extra);

  /// "Point d'arrivée déplacé de 120 mètres vers la rue accessible la plus
  /// proche.": a stop a new route moved, [lastStop] being the destination's
  /// index in the route asked.
  String moved(MovedStop move, {required int lastStop});

  /// "Route fermée dans 2 kilomètres. Nouvel itinéraire."
  String closureAhead(RoadEventFinding finding);

  /// "Route fermée dans 2 kilomètres, aucun autre chemin."
  String noDetour(RoadEventFinding finding);

  /// "Attention, pont à 3,20 mètres dans 2 kilomètres."
  String warningAhead(RouteWarning warning, double aheadM);

  /// What the aids say for [call], one of [DrivingAids.calls]:
  /// "Vitesse limitée à 90.", "Zone de danger dans 800 mètres."
  String aid(AidCall call, DrivingAids aids);

  /// A road event that does not stop the vehicle, [aheadM] ahead: "Travaux
  /// dans 2 kilomètres.", "Route peut-être fermée dans 2 kilomètres."
  String roadEventAhead(RoadEvent event, double aheadM);

  /// "Position indisponible. Vérifiez la localisation de l'appareil."
  String get positionLost;

  /// "Vous êtes arrivé."
  String get arrived;
}

/// Where the guidance stands.
enum GuidancePhase { navigating, offRoute, rerouting, arrived }

/// Why the route changed.
enum RerouteReason {
  offRoute,
  roadEvent,

  /// The user added, removed or reordered stops.
  stops,

  /// The user chose another destination.
  destination,
}

/// A calm message over the guidance, for a while.
@immutable
sealed class GuidanceAlert {
  const new({required this.until, this.moved = const [], this.lastStop = 1});

  /// When it goes, in the fixes' time.
  final DateTime until;

  /// The stops the route in use moved, told under this message: those the
  /// driver had not been told of, numbered as in the route asked, 1 for the
  /// first stop ahead, [lastStop] for the destination.
  final List<MovedStop> moved;

  final int lastStop;

  /// This message with [moved] told under it.
  GuidanceAlert withMoves(List<MovedStop> moved, int lastStop) => switch (this) {
    ReroutedAlert(:final reason, :final extra) => ReroutedAlert(
      reason: reason,
      extra: extra,
      until: until,
      moved: moved,
      lastStop: lastStop,
    ),
    ClosureAheadAlert(:final finding) => ClosureAheadAlert(
      finding: finding,
      until: until,
      moved: moved,
      lastStop: lastStop,
    ),
    NoDetourAlert(:final finding) => NoDetourAlert(
      finding: finding,
      until: until,
      moved: moved,
      lastStop: lastStop,
    ),
    RerouteFailedAlert(:final failure, :final cause) => RerouteFailedAlert(
      failure: failure,
      cause: cause,
      until: until,
      moved: moved,
      lastStop: lastStop,
    ),
  };
}

/// A new route was computed.
final class ReroutedAlert extends GuidanceAlert {
  const new({required this.reason, required super.until, this.extra, super.moved, super.lastStop});

  final RerouteReason reason;

  /// How much longer than the remaining route before, when known.
  final Duration? extra;
}

/// A road event ahead stops the vehicle; a new route is being computed.
final class ClosureAheadAlert extends GuidanceAlert {
  const new({required this.finding, required super.until, super.moved, super.lastStop});

  final RoadEventFinding finding;
}

/// A road event ahead stops the vehicle and no other route avoids it.
final class NoDetourAlert extends GuidanceAlert {
  const new({required this.finding, required super.until, super.moved, super.lastStop});

  final RoadEventFinding finding;
}

/// A recalculation failed; the guidance keeps the route it had.
final class RerouteFailedAlert extends GuidanceAlert {
  const new({required this.failure, required super.until, this.cause, super.moved, super.lastStop});

  /// Null when the server answered without a route for the vehicle.
  final RouteFailure? failure;

  /// The road event the recalculation was for, when one was.
  final RoadEventFinding? cause;
}

/// A restriction of the route ahead, with its distance.
@immutable
final class WarningAhead {
  const new({required this.warning, required this.aheadM});

  final RouteWarning warning;
  final double aheadM;
}

/// Where the server moved the stops of a route: the destination, and each
/// stop by itself, so that a stop passed and dropped from the list leaves
/// the others where they are.
@immutable
final class StopMoves {
  const new({this.destination, this.stops = const {}});

  /// The moves of [plan], computed for [stops], the stops it was asked
  /// with (stop 0 of the plan is the origin, the vehicle, never moved).
  factory of(RoutePlan plan, List<RouteStop> stops) => StopMoves(
    destination: plan.movedTo(stops.length + 1),
    stops: {
      for (final m in plan.movedStops)
        if (m.stopIndex >= 1 && m.stopIndex <= stops.length) stops[m.stopIndex - 1]: m.position,
    },
  );

  final LatLng? destination;
  final Map<RouteStop, LatLng> stops;
}

/// One guidance, from the start to the arrival.
@immutable
final class GuidanceSession {
  const new({
    required this.target,
    required this.plan,
    required this.routeIndex,
    required this.phase,
    required this.voiceMode,
    required this.voice,
    this.snapshot,
    this.lastFix,
    this.lastFixAt,
    this.alert,
    this.ahead = const [],
    this.eventAlerts = const [],
    this.reroutes = 0,
    this.positionLost = false,
    this.stops = const [],
    this.moves = const StopMoves(),
    this.aids = DrivingAids.none,
    this.voiceNoticeClosed = false,
  });

  final RouteTarget target;
  final RoutePlan plan;
  final int routeIndex;
  final GuidancePhase phase;

  /// What the voice says: everything, the alerts only, or nothing.
  final VoiceMode voiceMode;
  final VoiceReadiness voice;
  final GuidanceSnapshot? snapshot;
  final Fix? lastFix;

  /// When [lastFix] came, by this device's clock: how old the position is
  /// and when the vehicle arrives read the clock the screen shows, whatever
  /// time the receiver gave the fix.
  final DateTime? lastFixAt;
  final GuidanceAlert? alert;

  /// The restrictions within reach ahead, nearest first.
  final List<WarningAhead> ahead;

  /// Road events ahead worth a word, nearest first: those in force that do
  /// not stop the vehicle (a lane closed), and the closures it meets still
  /// (no other way, or a new route not found yet).
  final List<RoadEventFinding> eventAlerts;

  final int reroutes;

  /// The position stopped coming: location turned off, or its permission
  /// taken back, and no fix for [positionLostAfter] since. The next fix
  /// clears it.
  final bool positionLost;

  /// The stops still ahead, in order.
  final List<RouteStop> stops;

  /// Where the server moved the destination and the stops of [plan].
  final StopMoves moves;

  /// The limit, the excess, and the danger zone or camera ahead, where the
  /// rule of the country the vehicle is in allows it.
  final DrivingAids aids;

  /// The driver closed the notice of a missing voice: it stays closed
  /// for this guidance.
  final bool voiceNoticeClosed;

  RouteOption get route =>
      plan.routes.where((r) => r.index == routeIndex).firstOrNull ?? plan.routes.first;

  /// The step being driven, from the parsed answer (its lanes, its road).
  RouteStep? get step {
    final i = snapshot?.stepIndex;
    final steps = route.steps;
    return i == null || i < 0 || i >= steps.length ? null : steps[i];
  }

  GuidanceSession copyWith({
    RouteTarget? target,
    RoutePlan? plan,
    int? routeIndex,
    GuidancePhase? phase,
    VoiceMode? voiceMode,
    VoiceReadiness? voice,
    GuidanceSnapshot? snapshot,
    Fix? lastFix,
    DateTime? lastFixAt,
    GuidanceAlert? Function()? alert,
    List<WarningAhead>? ahead,
    List<RoadEventFinding>? eventAlerts,
    int? reroutes,
    bool? positionLost,
    List<RouteStop>? stops,
    StopMoves? moves,
    DrivingAids? aids,
    bool? voiceNoticeClosed,
  }) => GuidanceSession(
    target: target ?? this.target,
    plan: plan ?? this.plan,
    routeIndex: routeIndex ?? this.routeIndex,
    phase: phase ?? this.phase,
    voiceMode: voiceMode ?? this.voiceMode,
    voice: voice ?? this.voice,
    snapshot: snapshot ?? this.snapshot,
    lastFix: lastFix ?? this.lastFix,
    lastFixAt: lastFixAt ?? this.lastFixAt,
    alert: alert == null ? this.alert : alert(),
    ahead: ahead ?? this.ahead,
    eventAlerts: eventAlerts ?? this.eventAlerts,
    reroutes: reroutes ?? this.reroutes,
    positionLost: positionLost ?? this.positionLost,
    stops: stops ?? this.stops,
    moves: moves ?? this.moves,
    aids: aids ?? this.aids,
    voiceNoticeClosed: voiceNoticeClosed ?? this.voiceNoticeClosed,
  );
}

/// Restrictions are shown from this far ahead, metres.
const warningReachM = 3000.0;

/// The road events of [route] within [warningReachM] ahead of [alongM] that
/// are worth a look while driving (lanes closed, a closure not placed for
/// sure), nearest first; works beside the road stay in the preview.
List<({RouteRoadEvent event, double aheadM})> roadEventsAhead(RouteOption route, double alongM) => [
  for (final e in route.roadEvents)
    if (e.weight != RoadEventWeight.info)
      if (e.distanceFromStartM - alongM case final d when d >= -e.lengthM && d <= warningReachM)
        (event: e, aheadM: math.max(0, d)),
]..sort((a, b) => a.aheadM.compareTo(b.aheadM));

/// And announced at these distances, once each.
const warningCallsM = [2000.0, 500.0];

/// A road event that does not stop the vehicle (works, a lane closed, a
/// closure not placed for sure) is said once from this far ahead, metres;
/// a size limit, which the driver may have to check, once more from the
/// second distance.
const roadEventCallsM = [2000.0, 500.0];

/// The least time between two recalculations, doubled after each failure up
/// to [_maxBackoff]: the API allows 30 routes in ten minutes, and a vehicle
/// that parks off the route must not use them up.
const _minBackoff = Duration(seconds: 20);
const _maxBackoff = Duration(minutes: 2);

/// Fixes off the route before a recalculation: one is noise.
const _offRouteFixes = 2;

/// Until the vehicle first reaches the route, being off it within this
/// distance of where it started is the way to the route, metres: a
/// motorhome leaves an aire or a car park, off the road network.
const _joinWithinM = 250.0;

/// A fix this close to its point on the route is on the route, metres.
const _onRouteM = 30.0;

/// Below this speed, metres per second, the vehicle is parked: off the
/// route in a car park is not a wrong turn.
const _movingMps = 1.5;

const _alertFor = Duration(seconds: 10);

/// A quote made this far behind the vehicle is made again before use, metres.
const _quoteReachM = 300.0;

/// A stop counts as reached this close, metres.
const _stopReachedM = 80.0;

/// After the position stream fails, how long before it is asked for again.
const _fixRetryAfter = Duration(seconds: 10);

/// How long after a position error without any fix the position counts as
/// lost: a browser reports an error now and then while its fixes keep
/// coming (Firefox), which is no lost position.
const positionLostAfter = Duration(seconds: 15);

/// How often the route ahead is checked again against the known events as
/// the vehicle moves.
const _eventCheckEvery = Duration(seconds: 10);

/// A stop moved this close to where it was told moved before is the same
/// move, metres: the engine may end on another edge of the same street
/// when the vehicle comes from elsewhere. The server tells a move only from
/// 25 m on (`TOLD_MOVED_M`).
const _sameMoveM = 25.0;

/// The guidance: the engine fed with each fix, the spoken instructions, the
/// recalculation when the vehicle leaves the route or a road event closes
/// it ahead.
// keepAlive: the guidance runs while the screen is off and the app in the
// background; it ends only through stop().
@Riverpod(keepAlive: true)
class GuidanceController extends _$GuidanceController {
  GuidanceTrack? _track;
  StreamSubscription<Fix>? _fixes;
  Timer? _poll;
  DrivingAidsEngine? _aids;
  Timer? _enforcementPoll;
  Timer? _fixRetry;

  /// Says the position is lost, unless a fix comes first.
  Timer? _lostCheck;

  /// A position error came and no fix since.
  bool _noFixSinceError = false;
  GuidanceWording? _words;
  VoiceOutput? _voice;

  /// The sentences of this guidance, one at a time, as the voice mode
  /// allows.
  VoiceQueue? _speech;
  ScreenWake? _wake;
  final _events = RoadEventsTracker();
  final Set<String> _spoken = {};
  final Map<String, int> _warned = {};
  final Set<String> _reroutedFor = {};
  final Set<String> _announced = {};

  /// The calls said of each road event that does not stop the vehicle, by
  /// its id: kept across new routes, so an event is never said twice.
  final Map<String, int> _eventCalls = {};

  /// Recalculations asked for, and positions lost, in this guidance: each
  /// gets its own sentence.
  int _reroutesAsked = 0;
  int _positionLosses = 0;

  /// Where the driver knows each stop was moved, by the point asked: the
  /// moves of the route the guidance started with (the preview showed
  /// them), then those a new route told.
  final Map<LatLng, LatLng> _toldMoves = {};

  /// The moves of a route that landed while a closure on it asked for
  /// another at once, with the stops and the destination it was asked
  /// with: the next route tells its own, a failure that keeps this one
  /// tells these.
  ({List<MovedStop> moved, List<RouteStop> stops, LatLng destination})? _deferred;
  int _fixRetries = 0;
  int _offRoute = 0;

  /// Whether the vehicle has been on the current route yet, and where it
  /// was when the route began.
  bool _joined = false;
  LatLng? _joinFrom;
  DateTime? _lastReroute;
  DateTime? _lastEventCheck;
  Duration _backoff = _minBackoff;
  bool _rerouting = false;

  /// Counts the guidances: an answer that comes back after its guidance
  /// ended (stopped, arrived, another started) is dropped.
  int _generation = 0;

  @override
  GuidanceSession? build() {
    ref.onDispose(_release);
    // Positions asked for or withdrawn during a trip: the data of its
    // countries is asked again at once, rather than at the server's rhythm.
    // Weak: a controller that never guides leaves the settings unread.
    ref.listen(drivingAidsSettingsControllerProvider, weak: true, (before, after) {
      final was = before?.value?.exactIn;
      final next = after.value?.exactIn;
      if (was != null && next != null && !setEquals(was, next)) unawaited(_pollEnforcement());
    });
    return null;
  }

  /// Starts guiding along [routeIndex] of [plan] to [target]. False when
  /// the device cannot guide.
  Future<bool> start({
    required RoutePlan plan,
    required int routeIndex,
    required RouteTarget target,
    required GuidanceWording words,
    List<RouteStop> stops = const [],
  }) async {
    final json = plan.osrmJson;
    final engine = await ref.read(guidanceEngineProvider.future);
    if (!ref.mounted || engine == null || json == null) return false;
    _release();
    state = null;
    final generation = _generation;
    final GuidanceTrack track;
    try {
      track = engine.start(json, routeIndex);
    } on GuidanceUnavailable catch (e) {
      _log.warning('guidance did not start: $e');
      return false;
    }
    _track = track;
    _words = words;
    final voice = ref.read(voiceOutputProvider);
    final wake = ref.read(screenWakeProvider);
    _voice = voice;
    _wake = wake;
    final settings = ref.read(routeSettingsControllerProvider).value ?? const NavigationSettings();
    final speech = VoiceQueue(
      output: voice,
      now: ref.read(clockProvider),
      mode: settings.voiceMode,
    );
    _speech = speech;
    state = GuidanceSession(
      target: target,
      plan: plan,
      routeIndex: routeIndex,
      phase: GuidancePhase.navigating,
      voiceMode: settings.voiceMode,
      voice: VoiceReadiness.none,
      stops: stops,
      moves: StopMoves.of(plan, stops),
    );
    _tell(plan.movedStops, stops, target.destination);
    final readiness = await voice.prepare(plan.applied.language);
    if (!ref.mounted || generation != _generation) return false;
    speech.ready = readiness == VoiceReadiness.ready;
    state = state!.copyWith(voice: readiness);
    await wake.keepOn(on: true);
    if (!ref.mounted || generation != _generation) return false;
    await ref.read(appForegroundProvider).resumed();
    if (!ref.mounted || generation != _generation) return false;
    final locator = await ref.read(countryLocatorProvider.future);
    if (!ref.mounted || generation != _generation) return false;
    // The user's choices before the first fix: a rule read without them
    // would keep its stricter reading for 30 s once they came.
    await ref
        .read(drivingAidsSettingsControllerProvider.future)
        .catchError((Object _) => const DrivingAidsSettings());
    if (!ref.mounted || generation != _generation) return false;
    _aids = DrivingAidsEngine(
      locator: locator,
      choices: () =>
          ref.read(drivingAidsSettingsControllerProvider).value ?? const DrivingAidsSettings(),
    );
    _listenFixes();
    unawaited(_pollEvents());
    unawaited(_pollEnforcement());
    return true;
  }

  /// Ends the guidance and releases the position, the screen and the voice.
  void stop() {
    _release();
    state = null;
  }

  /// Says from now on what [mode] allows, and keeps it for the next
  /// guidances: muted cuts the sentence being said, alerts only cuts an
  /// instruction.
  Future<void> setVoiceMode(VoiceMode mode) async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(voiceMode: mode);
    _speech?.mode = mode;
    await ref.read(routeSettingsControllerProvider.notifier).setVoiceMode(mode);
  }

  /// Moves to the next voice mode, as the guidance's button goes through
  /// them (full, alerts only, muted, full again), and returns it at once,
  /// the setting written meanwhile. Null without a guidance.
  VoiceMode? cycleVoiceMode() {
    final next = state?.voiceMode.next;
    if (next != null) {
      // The guidance has the mode at once; a write that fails costs only
      // the next guidance's start in it.
      unawaited(
        setVoiceMode(next).catchError((Object e) => _log.warning('voice mode not kept: $e')),
      );
    }
    return next;
  }

  /// The route with [stop] added where it lengthens the rest of the trip
  /// the least, from where the vehicle is, and what it adds; null without a
  /// position yet, or with no room for another stop. Throws a
  /// [RouteFailure] when the route could not be asked for.
  Future<StopQuote?> quoteStop(RouteStop stop) async {
    final s = state;
    final fix = s?.lastFix;
    final generation = _generation;
    if (s == null || fix == null || s.stops.length >= maxRouteStops) return null;
    final at = bestInsertion(
      origin: fix.position,
      stops: s.stops,
      destination: s.target.destination,
      stop: stop.position,
    );
    final stops = insertStop(s.stops, at, stop);
    final plan = await ref.read(routeServiceProvider).route(_request(fix, s, stops: stops));
    if (!_current(generation)) return null;
    final after = plan.routes.firstOrNull;
    final before = state!.snapshot;
    final comparable = after != null && before != null && plan.status == RouteStatus.ok;
    return StopQuote(
      stop: stop,
      stops: stops,
      base: s.stops,
      from: fix.position,
      routeVersion: s.reroutes,
      plan: plan,
      extraS: comparable ? after.durationS - before.durationRemainingS : null,
      extraM: comparable ? after.distanceM - before.distanceRemainingM : null,
    );
  }

  /// Takes the route of [quote]: its stop is added. A quote made before a
  /// stop was passed, on another route, or from too far behind, is made
  /// again first. False when it could not be (a recalculation running, the
  /// guidance over); throws a [RouteFailure] when the new quote could not be
  /// asked for.
  Future<bool> applyQuote(StopQuote quote) async {
    final s = state;
    final fix = s?.lastFix;
    if (s == null || fix == null) return false;
    final from = quote.from;
    final version = quote.routeVersion;
    final stale =
        !listEquals(quote.base, s.stops) ||
        (version != null && version != s.reroutes) ||
        (from != null && from.distanceTo(fix.position) > _quoteReachM);
    final fresh = stale ? await quoteStop(quote.stop) : quote;
    if (fresh == null || fresh.extraS == null) return false;
    // A stop passed, or another route, while the new quote was asked for:
    // its stops are already out of date.
    final now = state;
    if (stale &&
        (now == null || !listEquals(fresh.base, now.stops) || fresh.routeVersion != now.reroutes)) {
      return false;
    }
    // The fresh quote's route starts where the vehicle is: taken as it is.
    return await _change(RerouteReason.stops, stops: fresh.stops, known: fresh.plan);
  }

  /// Takes [stop] out of the stops ahead; of equal stops, the one that
  /// [copiesAfter] equal stops follow ([stopIndexFromEnd]). True when it is
  /// no longer on the route, also when it was passed meanwhile.
  Future<bool> removeStop(RouteStop stop, {int copiesAfter = 0}) async {
    final s = state;
    if (s == null) return false;
    final at = stopIndexFromEnd(s.stops, stop, after: copiesAfter);
    if (at == null) return true;
    return await _change(RerouteReason.stops, stops: [...s.stops]..removeAt(at));
  }

  /// Puts [stop] back after it was taken out of [before], where [copiesAfter]
  /// equal stops followed it: in its place when the other stops are still
  /// those, else where it lengthens the trip the least.
  Future<bool> restoreStop(RouteStop stop, List<RouteStop> before, {int copiesAfter = 0}) async {
    final s = state;
    final fix = s?.lastFix;
    if (s == null || fix == null) return false;
    final at = stopIndexFromEnd(before, stop, after: copiesAfter);
    // Passed before it was taken out: nothing to put back. On the route as
    // many times as before (the removal did not go through): nothing either.
    // Counted, not looked for: an equal stop left on the route is another
    // copy, this one is still out.
    if (at == null || _copies(s.stops, stop) >= _copies(before, stop)) return true;
    if (s.stops.length >= maxRouteStops) return false;
    final others = [...before]..removeAt(at);
    final stops = listEquals(others, s.stops)
        ? before
        : insertStop(
            s.stops,
            bestInsertion(
              origin: fix.position,
              stops: s.stops,
              destination: s.target.destination,
              stop: stop.position,
            ),
            stop,
          );
    return await _change(RerouteReason.stops, stops: stops);
  }

  static int _copies(List<RouteStop> stops, RouteStop stop) => stops.where((s) => s == stop).length;

  /// A new route straight to [target], without stops unless [stops] are
  /// given (to put a destination back, with its stops).
  Future<bool> goTo(RouteTarget target, {List<RouteStop> stops = const []}) =>
      _change(RerouteReason.destination, stops: stops, target: target);

  Future<bool> _change(
    RerouteReason reason, {
    required List<RouteStop> stops,
    RouteTarget? target,
    RoutePlan? known,
  }) async {
    final fix = state?.lastFix;
    if (fix == null || _rerouting || !_current(_generation)) return false;
    final before = state!.reroutes;
    await _reroute(reason, fix, stops: stops, target: target, known: known);
    return ref.mounted && state != null && state!.reroutes > before;
  }

  RouteRequest _request(
    Fix fix,
    GuidanceSession s, {
    List<RouteStop>? stops,
    RouteTarget? target,
  }) => RouteRequest(
    origin: fix.position,
    destination: (target ?? s.target).destination,
    vehicle: s.plan.applied.vehicle,
    avoid: s.plan.applied.avoid,
    language: s.plan.applied.language,
    headingDeg: fix.courseDeg,
    fromVehicle: true,
    stops: [for (final stop in stops ?? s.stops) stop.position],
  );

  /// Closes the notice of a missing voice until the guidance ends.
  void closeVoiceNotice() {
    final s = state;
    if (s != null) state = s.copyWith(voiceNoticeClosed: true);
  }

  /// Opens the system's voice installer, then tries the voice again.
  Future<void> installVoices() async {
    final voice = _voice;
    if (voice == null) return;
    await voice.installVoices();
    if (!ref.mounted || state == null) return;
    final readiness = await voice.prepare(state!.plan.applied.language);
    if (!ref.mounted || state == null) return;
    _speech?.ready = readiness == VoiceReadiness.ready;
    state = state!.copyWith(voice: readiness);
  }

  void _release() {
    _generation++;
    unawaited(_fixes?.cancel());
    _fixes = null;
    _fixRetry?.cancel();
    _fixRetry = null;
    _lostCheck?.cancel();
    _lostCheck = null;
    _noFixSinceError = false;
    _poll?.cancel();
    _poll = null;
    _enforcementPoll?.cancel();
    _enforcementPoll = null;
    _aids = null;
    _track?.dispose();
    _track = null;
    _spoken.clear();
    _warned.clear();
    _reroutedFor.clear();
    _announced.clear();
    _eventCalls.clear();
    _reroutesAsked = 0;
    _positionLosses = 0;
    _toldMoves.clear();
    _deferred = null;
    _fixRetries = 0;
    _offRoute = 0;
    _joined = false;
    _joinFrom = null;
    _lastReroute = null;
    _lastEventCheck = null;
    // The events stay known across guidances (the cursor goes on); what a
    // guidance acted on does not.
    _events.resetHandled();
    _backoff = _minBackoff;
    _rerouting = false;
    // Held since the start: the release also runs when the provider is
    // disposed, where no other provider may be read.
    final speech = _speech;
    final wake = _wake;
    _voice = null;
    _speech = null;
    _wake = null;
    speech?.close();
    if (wake != null) unawaited(wake.keepOn(on: false));
  }

  /// Whether the guidance of [generation] is still the one running, short
  /// of its arrival.
  bool _current(int generation) =>
      ref.mounted &&
      generation == _generation &&
      state != null &&
      state!.phase != GuidancePhase.arrived;

  /// Hands [text] to the voice as a sentence of [kind], named by [key]: the
  /// voice mode, the order and the chime are the queue's.
  void _say(String text, SpeechKind kind, String key) => _speech?.say(text, kind: kind, key: key);

  void _listenFixes() {
    final words = _words;
    if (words == null) return;
    unawaited(_fixes?.cancel());
    final s = state;
    final feed = ref.read(demoDriveProvider) && s != null
        // The debug demonstration drives the route it starts on at 50 km/h,
        // on the app's clock so the arrival time reads true. A new route
        // (a stop added) does not move it to the new line: it is a show,
        // never a guidance.
        ? SimulatedFeed(path: s.route.line, speedMps: 13.9, start: ref.read(clockProvider)())
        : ref.read(locationFeedProvider);
    _fixes = feed.guidance(words.notice).listen(_onFix, onError: _onPositionError);
  }

  @visibleForTesting
  void onFix(Fix fix) => _onFix(fix);

  /// The position stream failed: location turned off, or its permission
  /// taken back. geolocator ends its updates then, so the stream is asked
  /// for again, with the app in front, until fixes come back. The screen
  /// says the position is lost once none came for [positionLostAfter].
  void _onPositionError(Object e) {
    _log.warning('position stream: $e');
    final generation = _generation;
    if (!_current(generation)) return;
    _noFixSinceError = true;
    _lostCheck ??= Timer(positionLostAfter, () {
      _lostCheck = null;
      if (!_current(generation) || !_noFixSinceError) return;
      // Said once when it goes, not again while it stays lost. A position
      // only late (a tunnel) is no loss: the screen tells its age.
      if (!state!.positionLost) {
        _positionLosses++;
        if (_words case final words?) {
          _say(words.positionLost, SpeechKind.alert, 'position-lost:$_positionLosses');
        }
      }
      state = state!.copyWith(positionLost: true);
    });
    _fixRetry?.cancel();
    // 10 s, then longer while location stays off: each try starts and
    // stops the service and its notification.
    final wait = _fixRetryAfter * math.min(1 << _fixRetries, 12);
    _fixRetries++;
    _fixRetry = Timer(wait, () async {
      await ref.read(appForegroundProvider).resumed();
      if (_current(generation) && _noFixSinceError) _listenFixes();
    });
  }

  void _onFix(Fix fix) {
    final track = _track;
    final s = state;
    if (track == null || s == null || s.phase == GuidancePhase.arrived) return;
    final snap = track.update(fix);
    var next = s.copyWith(
      snapshot: snap,
      lastFix: fix,
      lastFixAt: ref.read(clockProvider)(),
      positionLost: false,
    );
    _fixRetries = 0;
    _noFixSinceError = false;
    _lostCheck?.cancel();
    _lostCheck = null;
    if (snap.status == GuidanceStatus.arrived) {
      // The position is no longer needed: the stream and the poll stop;
      // the screen stays on for the arrival card.
      unawaited(_fixes?.cancel());
      _fixes = null;
      _fixRetry?.cancel();
      _poll?.cancel();
      _poll = null;
      _enforcementPoll?.cancel();
      _enforcementPoll = null;
      state = next.copyWith(
        phase: GuidancePhase.arrived,
        ahead: const [],
        eventAlerts: const [],
        alert: () => null,
        aids: DrivingAids.none,
      );
      _say(_words!.arrived, SpeechKind.maneuver, 'arrived');
      return;
    }
    // A stop is behind once the vehicle has been there, or has driven past
    // where the route comes nearest to it: a point off the road is reached
    // where the router put it on the road.
    if (next.stops.isNotEmpty && _passed(next.stops.first, fix, snap, next.route)) {
      next = next.copyWith(stops: next.stops.sublist(1));
    }
    final instruction = snap.instruction;
    if (instruction != null && _spoken.add(instruction.id)) {
      _say(instruction.text, SpeechKind.maneuver, 'maneuver:${instruction.id}');
    }
    final ahead = _ahead(snap, next.route.warnings);
    for (final w in ahead) {
      final key = '${w.warning.externalId}@${w.warning.distanceFromStartM}';
      final stage = warningCallsM.lastIndexWhere((d) => w.aheadM <= d) + 1;
      if (stage > (_warned[key] ?? 0)) {
        _warned[key] = stage;
        _say(_words!.warningAhead(w.warning, w.aheadM), SpeechKind.alert, 'warning:$key:$stage');
      }
    }
    next = next.copyWith(ahead: ahead);
    if (_aids?.update(
          fix: fix,
          snap: snap,
          route: next.route,
          totalWeightT: totalWeightOf(next.plan.applied.vehicle),
        )
        case final aids?) {
      // A zone or a camera coming is an alert, said as the voice mode
      // allows. The reminder of the road's limit only when the user asked
      // for it, and never for a limit the user hid: the sign speaks for
      // itself.
      if (aids.calls.isNotEmpty) {
        final settings = ref.read(drivingAidsSettingsControllerProvider).value;
        final reminders = (settings?.speedSound ?? false) && settings!.showSpeedLimit;
        for (final call in aids.calls) {
          if (call.word.alert) {
            _say(_words!.aid(call, aids), SpeechKind.alert, 'aid:${call.key}');
          } else if (reminders) {
            _say(_words!.aid(call, aids), SpeechKind.info, 'aid:${call.key}');
          }
        }
      }
      next = next.copyWith(aids: aids);
    }
    if (next.alert != null && !fix.at.isBefore(next.alert!.until)) {
      next = next.copyWith(alert: () => null);
    }
    if (_offRouteNow(snap, fix)) {
      _offRoute++;
      if (!_rerouting) next = next.copyWith(phase: GuidancePhase.offRoute);
    } else {
      _offRoute = 0;
      if (!_rerouting) next = next.copyWith(phase: GuidancePhase.navigating);
    }
    state = next;
    if (_shouldReroute(fix)) {
      unawaited(_reroute(RerouteReason.offRoute, fix));
    } else if (_lastEventCheck == null || fix.at.difference(_lastEventCheck!) >= _eventCheckEvery) {
      // The events known stay put while the vehicle moves on: their
      // distances, and whether one now lies ahead, follow it.
      _checkEvents();
    }
    _tellRoadEvents();
  }

  /// Says the road events coming that do not stop the vehicle: those of
  /// the route (lanes closed, a closure not placed for sure) and those
  /// learnt since (works, a size limit the vehicle clears). Once from the
  /// first of [roadEventCallsM], a size limit once more from the second;
  /// never an event of mere information (works beside the road), nor one
  /// that stops the vehicle, which has its own sentences.
  void _tellRoadEvents() {
    final s = state;
    final words = _words;
    final along = s?.snapshot?.distanceAlongM;
    if (s == null || words == null || along == null) return;
    // The new route, once it lands, is the one worth telling.
    if (_rerouting || s.phase == GuidancePhase.arrived) return;
    final stopping = {
      ..._reroutedFor,
      ..._announced,
      for (final f in s.eventAlerts)
        if (f.blocking) f.event.id,
    };
    final ahead = <String, ({RoadEvent event, double aheadM})>{};
    void add(RoadEvent event, double aheadM) {
      if (stopping.contains(event.id) || aheadM <= 0 || aheadM > roadEventCallsM.first) return;
      if (ahead[event.id] case final known? when known.aheadM <= aheadM) return;
      ahead[event.id] = (event: event, aheadM: aheadM);
    }

    for (final e in s.route.roadEvents) {
      if (e.weight == RoadEventWeight.warning) add(e.event, e.distanceFromStartM - along);
    }
    for (final f in s.eventAlerts) {
      // From where the route meets it, as the vehicle moves between checks.
      if (!f.blocking) add(f.event, f.hit.startM - along);
    }
    for (final (:event, :aheadM) in ahead.values) {
      final calls = event.eventClass == RoadEventClass.vehicleLimit ? roadEventCallsM.length : 1;
      final call = math.min(calls, roadEventCallsM.lastIndexWhere((d) => aheadM <= d) + 1);
      if (call > (_eventCalls[event.id] ?? 0)) {
        _eventCalls[event.id] = call;
        _say(words.roadEventAhead(event, aheadM), SpeechKind.alert, 'event:${event.id}:$call');
      }
    }
  }

  /// Whether [snap] puts the vehicle off the route for the guidance: before
  /// it first reaches the route, only once it has gone [_joinWithinM] from
  /// where it started, so a start from a car park is neither shown nor said
  /// as a wrong turn.
  bool _offRouteNow(GuidanceSnapshot snap, Fix fix) {
    // Joined once the fix lies on the route itself: an engine may not call
    // its very first fix off the route, wherever it is.
    if (fix.position.distanceTo(snap.position) <= _onRouteM) _joined = true;
    if (!snap.offRoute) return false;
    if (_joined) return true;
    final from = _joinFrom ??= fix.position;
    return fix.position.distanceTo(from) > _joinWithinM;
  }

  static bool _passed(RouteStop stop, Fix fix, GuidanceSnapshot snap, RouteOption route) {
    if (fix.position.distanceTo(stop.position) < _stopReachedM) return true;
    final near = nearestOnLine(stop.position, route.line);
    return near != null && snap.distanceAlongM >= near.alongM;
  }

  /// The restrictions of the route within [warningReachM] ahead.
  static List<WarningAhead> _ahead(GuidanceSnapshot snap, List<RouteWarning> warnings) => [
    for (final w in warnings)
      if (w.distanceFromStartM - snap.distanceAlongM case final d
          when d >= -20 && d <= warningReachM)
        WarningAhead(warning: w, aheadM: math.max(0, d)),
  ]..sort((a, b) => a.aheadM.compareTo(b.aheadM));

  bool _shouldReroute(Fix fix) {
    if (_rerouting || _offRoute < _offRouteFixes) return false;
    final speed = fix.speedMps;
    if (speed != null && speed < _movingMps) return false;
    return !_waiting(fix);
  }

  /// Whether the last recalculation is too recent to ask for another.
  bool _waiting(Fix fix) {
    final last = _lastReroute;
    return last != null && fix.at.difference(last) < _backoff;
  }

  Future<void> _reroute(
    RerouteReason reason,
    Fix fix, {
    RoadEventFinding? cause,
    List<RouteStop>? stops,
    RouteTarget? target,
    RoutePlan? known,
  }) async {
    final s = state;
    final words = _words;
    final generation = _generation;
    if (_rerouting || words == null || !_current(generation)) return;
    _rerouting = true;
    _lastReroute = fix.at;
    _reroutesAsked++;
    final alertUntil = fix.at.add(_alertFor);
    state = s!.copyWith(
      phase: GuidancePhase.rerouting,
      alert: () => cause == null ? s.alert : ClosureAheadAlert(finding: cause, until: alertUntil),
    );
    // A closure is said once; a new try after a failure goes quietly, its
    // notice on screen.
    if (cause != null) {
      if (_announced.add(cause.event.id)) {
        _say(words.closureAhead(cause), SpeechKind.alert, 'closure:${cause.event.id}');
      }
    } else if (reason == RerouteReason.offRoute) {
      _say(words.rerouting, SpeechKind.alert, 'rerouting:$_reroutesAsked');
    }
    Duration? extra;
    var landed = false;
    var moved = const <MovedStop>[];
    final asked = stops ?? s.stops;
    try {
      final plan =
          known ??
          await ref
              .read(routeServiceProvider)
              .route(_request(fix, s, stops: stops, target: target));
      if (!_current(generation)) return;
      final engine = await ref.read(guidanceEngineProvider.future);
      if (!_current(generation)) return;
      final json = plan.osrmJson;
      if (plan.status != RouteStatus.ok || json == null || engine == null || plan.routes.isEmpty) {
        _failed(null, fix, cause: cause);
        return;
      }
      final track = engine.start(json, plan.routes.first.index);
      _track?.dispose();
      _track = track;
      _warned.clear();
      _offRoute = 0;
      _joined = false;
      _joinFrom = fix.position;
      _backoff = _minBackoff;
      _events.resetHandled();
      final before = state!.snapshot?.durationRemainingS;
      final snap = track.update(fix);
      extra = before == null ? null : Duration(seconds: (snap.durationRemainingS - before).round());
      moved = _untoldMoves(plan, asked, (target ?? s.target).destination);
      state = state!.copyWith(
        target: target,
        stops: stops,
        // The moves read with the stops the route was asked with.
        moves: StopMoves.of(plan, asked),
        plan: plan,
        routeIndex: plan.routes.first.index,
        snapshot: snap,
        phase: _offRouteNow(snap, fix) ? GuidancePhase.offRoute : GuidancePhase.navigating,
        reroutes: state!.reroutes + 1,
        alert: () => ReroutedAlert(reason: reason, extra: extra, until: alertUntil),
        // The zones were measured along the old route; the next fix
        // measures them along this one.
        aids: state!.aids.withZones(const []),
      );
      // The route a closure set aside is gone: its moves with it.
      _deferred = null;
      landed = true;
    } on RouteFailure catch (f) {
      if (_current(generation)) _failed(f, fix, cause: cause);
    } on Object catch (e, st) {
      // An answer the engine cannot guide, or one this app cannot read:
      // the route kept, as after a failure.
      _log.warning('the new route could not be guided', e, st);
      if (_current(generation)) {
        _failed(const RouteFailure(RouteFailureKind.unavailable), fix, cause: cause);
      }
    } finally {
      if (generation == _generation) _rerouting = false;
    }
    if (!landed || !_current(generation)) return;
    // A new route may cross other countries: their zones are asked for.
    unawaited(_pollEnforcement());
    // The new route is checked at once, against every event known by now:
    // the server may not have known the closure, and a route back through
    // it is no detour.
    final noDetour = _checkEvents(afterReroute: cause != null);
    // A closure on the new route asked for another one at once: that one
    // says "new route" and tells the stops it moves; should it fail, the
    // route kept tells them (_failed).
    final destination = (target ?? s.target).destination;
    if (_rerouting) {
      _deferred = (moved: moved, stops: asked, destination: destination);
      return;
    }
    _deferred = null;
    if (!noDetour) {
      _say(words.rerouted(extra), SpeechKind.alert, 'rerouted:${state!.reroutes}');
    }
    _tellMoves(moved, asked, destination);
    // What the new route meets comes after the words of the new route.
    _tellRoadEvents();
  }

  /// Tells [moved], the moves of the route in use for [stops] and
  /// [destination], under the message on screen ("new route", "no other
  /// way", a failure that keeps this route) and aloud after it; from then
  /// on they count as told. Nothing on screen to show them under: left
  /// for the next message.
  void _tellMoves(List<MovedStop> moved, List<RouteStop> stops, LatLng destination) {
    final s = state;
    final alert = s?.alert;
    final words = _words;
    if (moved.isEmpty || s == null || alert == null || words == null) return;
    final lastStop = stops.length + 1;
    state = s.copyWith(alert: () => alert.withMoves(moved, lastStop));
    for (final m in moved) {
      final at = _askedAt(m.stopIndex, stops, destination);
      _say(words.moved(m, lastStop: lastStop), SpeechKind.alert, 'moved:$at>${m.position}');
    }
    _tell(moved, stops, destination);
  }

  /// The moves of [plan], asked with [stops] and [destination], that the
  /// driver has not been told of: a stop moved for the first time, or
  /// moved elsewhere than before.
  List<MovedStop> _untoldMoves(RoutePlan plan, List<RouteStop> stops, LatLng destination) => [
    for (final m in plan.movedStops)
      if (_askedAt(m.stopIndex, stops, destination) case final at?)
        if (_toldMoves[at] case final told
            when told == null || told.distanceTo(m.position) > _sameMoveM)
          m,
  ];

  void _tell(List<MovedStop> moves, List<RouteStop> stops, LatLng destination) {
    for (final m in moves) {
      if (_askedAt(m.stopIndex, stops, destination) case final at?) _toldMoves[at] = m.position;
    }
  }

  /// The point the user asked for at [index] of a route asked from the
  /// vehicle through [stops] to [destination]; null for the vehicle.
  static LatLng? _askedAt(int index, List<RouteStop> stops, LatLng destination) {
    if (index == stops.length + 1) return destination;
    if (index >= 1 && index <= stops.length) return stops[index - 1].position;
    return null;
  }

  void _failed(RouteFailure? failure, Fix fix, {RoadEventFinding? cause}) {
    final doubled = Duration(
      milliseconds: math.min(_backoff.inMilliseconds * 2, _maxBackoff.inMilliseconds),
    );
    final asked = failure?.retryAfter;
    _backoff = asked != null && asked > doubled ? asked : doubled;
    final noRoute = failure == null;
    if (cause != null && !noRoute) {
      // No answer is not "no other way": the closure is asked about again
      // once the wait is over, and shows meanwhile.
      _events.unmarkHandled(cause.event.id);
      _reroutedFor.remove(cause.event.id);
    }
    final s = state!;
    final until = fix.at.add(_alertFor * 3);
    state = s.copyWith(
      phase: _offRoute > 0 ? GuidancePhase.offRoute : GuidancePhase.navigating,
      eventAlerts: cause == null
          ? null
          : [cause, ...s.eventAlerts.where((e) => e.event.id != cause.event.id)],
      alert: () => cause != null && noRoute
          ? NoDetourAlert(finding: cause, until: until)
          : RerouteFailedAlert(failure: failure, cause: cause, until: until),
    );
    if (cause != null && noRoute) {
      _say(_words!.noDetour(cause), SpeechKind.alert, 'no-detour:${cause.event.id}');
    }
    // The route kept may have moved stops a closure kept from being told
    // (_reroute): told now, under this message, by the stops it was asked
    // with (a stop passed since leaves the list, not the route).
    if (_deferred case final d?) {
      _deferred = null;
      _tellMoves(d.moved, d.stops, d.destination);
    }
  }

  /// Asks for the road events now rather than at the next poll: when the
  /// network comes back, and in tests.
  Future<void> refreshRoadEvents() => _pollEvents();

  /// Brings the speed camera data of the route's countries up to date
  /// (the countries only leave the device, never a position), hands it to
  /// the aids, and asks again at the server's rhythm. Offline, the data
  /// kept from an earlier trip serves.
  Future<void> _pollEnforcement() async {
    final generation = _generation;
    final aids = _aids;
    final s = state;
    if (aids == null || s == null) return;
    _enforcementPoll?.cancel();
    final countries = aids.countriesOf(s.route.line);
    // A poll that could not reach the server (offline, a refusal, a store
    // that failed) is tried again sooner than the server's rhythm.
    var wait = const Duration(minutes: 10);
    try {
      final known = await ref
          .read(enforcementFeedProvider)
          .refresh(countries, ref.read(clockProvider)());
      if (!_current(generation) || !identical(aids, _aids)) return;
      aids.setData(rules: known.rules, items: known.items, sources: known.sources);
      final polled = known.polledAt;
      if (polled != null && ref.read(clockProvider)().difference(polled) < known.pollInterval) {
        wait = known.pollInterval;
      }
    } on Object catch (e) {
      _log.fine('speed camera data not refreshed: $e');
      if (!_current(generation) || !identical(aids, _aids)) return;
    }
    _enforcementPoll = Timer(wait, () => unawaited(_pollEnforcement()));
  }

  void _schedulePoll(Duration wait) {
    _poll?.cancel();
    _poll = Timer(wait, () => unawaited(_pollEvents()));
  }

  /// One poll of the road events, then the next one scheduled: at the
  /// server's rhythm when it gives one, after its wait when it asks for one.
  /// No position goes with the request.
  Future<void> _pollEvents() async {
    final generation = _generation;
    var wait = ref.read(roadEventsPollProvider);
    try {
      final source = ref.read(roadEventsSourceProvider);
      // The pages of a first load follow one another at once; a bound
      // keeps a misbehaving server from holding the loop.
      for (var page = 0; page < 20; page++) {
        final delta = await source.delta(cursor: _events.cursor);
        if (!_current(generation)) return;
        _events.apply(delta);
        wait = delta.pollInterval ?? wait;
        if (!delta.hasMore) break;
      }
      _checkEvents();
      _tellRoadEvents();
    } on RoadEventsUnavailable catch (e) {
      if (e.cursorRefused) _events.restart();
      wait = e.retryAfter ?? wait;
      _log.fine('road events: $e');
    } on Object catch (e) {
      // The last events stay valid; the next poll tries again.
      _log.info('road events poll failed: $e');
    } finally {
      if (_current(generation)) _schedulePoll(wait);
    }
  }

  /// Checks the route ahead against the road events; true when an event
  /// stops the vehicle on it and no new route is asked for (there is none:
  /// [afterReroute], or the event already caused one).
  bool _checkEvents({bool afterReroute = false}) {
    final s = state;
    final track = _track;
    final fix = s?.lastFix;
    // While a new route is on its way, the old one is not worth checking:
    // the new one is, when it lands.
    if (_rerouting || s == null || track == null || fix == null) return false;
    if (s.phase == GuidancePhase.arrived) return false;
    final snap = s.snapshot;
    _lastEventCheck = fix.at;
    final found = _events.check(
      track: track,
      alongM: snap?.distanceAlongM ?? 0,
      vehicle: s.plan.applied.vehicle,
      now: ref.read(clockProvider)(),
      // The time to reach an event, at the router's pace for this route.
      secondsPerMetre: snap == null || snap.distanceRemainingM <= 0
          ? 0
          : snap.durationRemainingS / snap.distanceRemainingM,
    );
    final blocking = found.blocking;
    final shown = [...blocking, ...found.alerts]..sort((a, b) => a.aheadM.compareTo(b.aheadM));
    final next = s.copyWith(eventAlerts: shown);
    if (blocking.isEmpty) {
      state = next;
      return false;
    }
    final first = blocking.first;
    // "No other way" only for an event a new route was asked for already;
    // another one met on the new route gets its own try.
    if (_reroutedFor.contains(first.event.id)) {
      _events.markHandled(blocking.map((f) => f.event.id));
      state = next.copyWith(
        alert: () => NoDetourAlert(finding: first, until: fix.at.add(_alertFor * 3)),
      );
      _say(_words!.noDetour(first), SpeechKind.alert, 'no-detour:${first.event.id}');
      return true;
    }
    if (_backoff > _minBackoff && _waiting(fix)) {
      // A recalculation failed lately: the next waits its turn, the
      // closure on screen meanwhile.
      state = next;
      return false;
    }
    _events.markHandled([first.event.id]);
    _reroutedFor.add(first.event.id);
    state = next;
    unawaited(_reroute(RerouteReason.roadEvent, fix, cause: first));
    return false;
  }
}
