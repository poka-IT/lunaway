import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
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

  /// "Route fermée dans 2 kilomètres. Nouvel itinéraire."
  String closureAhead(RoadEventFinding finding);

  /// "Route fermée dans 2 kilomètres, aucun autre chemin."
  String noDetour(RoadEventFinding finding);

  /// "Attention, pont à 3,20 mètres dans 2 kilomètres."
  String warningAhead(RouteWarning warning, double aheadM);

  /// What the aids say when their word is due ([DrivingAids.wordKind]):
  /// "Vitesse limitée à 90.", "Zone de danger dans 800 mètres."
  String aid(DrivingAids aids);

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
  const new({required this.until});

  /// When it goes, in the fixes' time.
  final DateTime until;
}

/// A new route was computed.
final class ReroutedAlert extends GuidanceAlert {
  const new({required this.reason, required super.until, this.extra});

  final RerouteReason reason;

  /// How much longer than the remaining route before, when known.
  final Duration? extra;
}

/// A road event ahead stops the vehicle; a new route is being computed.
final class ClosureAheadAlert extends GuidanceAlert {
  const new({required this.finding, required super.until});

  final RoadEventFinding finding;
}

/// A road event ahead stops the vehicle and no other route avoids it.
final class NoDetourAlert extends GuidanceAlert {
  const new({required this.finding, required super.until});

  final RoadEventFinding finding;
}

/// A recalculation failed; the guidance keeps the route it had.
final class RerouteFailedAlert extends GuidanceAlert {
  const new({required this.failure, required super.until, this.cause});

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

/// One guidance, from the start to the arrival.
@immutable
final class GuidanceSession {
  const new({
    required this.target,
    required this.plan,
    required this.routeIndex,
    required this.phase,
    required this.voiceOn,
    required this.voice,
    this.snapshot,
    this.lastFix,
    this.alert,
    this.ahead = const [],
    this.eventAlerts = const [],
    this.reroutes = 0,
    this.overview = false,
    this.positionLost = false,
    this.stops = const [],
    this.aids = DrivingAids.none,
  });

  final RouteTarget target;
  final RoutePlan plan;
  final int routeIndex;
  final GuidancePhase phase;
  final bool voiceOn;
  final VoiceReadiness voice;
  final GuidanceSnapshot? snapshot;
  final Fix? lastFix;
  final GuidanceAlert? alert;

  /// The restrictions within reach ahead, nearest first.
  final List<WarningAhead> ahead;

  /// Road events ahead worth a word, nearest first: those in force that do
  /// not stop the vehicle (a lane closed), and the closures it meets still
  /// (no other way, or a new route not found yet).
  final List<RoadEventFinding> eventAlerts;

  final int reroutes;

  /// The whole route on the map instead of the vehicle.
  final bool overview;

  /// The position stopped coming: location turned off, or its permission
  /// taken back. The next fix clears it.
  final bool positionLost;

  /// The stops still ahead, in order.
  final List<RouteStop> stops;

  /// The limit, the excess, and the danger zone or camera ahead, where the
  /// rule of the country the vehicle is in allows it.
  final DrivingAids aids;

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
    bool? voiceOn,
    VoiceReadiness? voice,
    GuidanceSnapshot? snapshot,
    Fix? lastFix,
    GuidanceAlert? Function()? alert,
    List<WarningAhead>? ahead,
    List<RoadEventFinding>? eventAlerts,
    int? reroutes,
    bool? overview,
    bool? positionLost,
    List<RouteStop>? stops,
    DrivingAids? aids,
  }) => GuidanceSession(
    target: target ?? this.target,
    plan: plan ?? this.plan,
    routeIndex: routeIndex ?? this.routeIndex,
    phase: phase ?? this.phase,
    voiceOn: voiceOn ?? this.voiceOn,
    voice: voice ?? this.voice,
    snapshot: snapshot ?? this.snapshot,
    lastFix: lastFix ?? this.lastFix,
    alert: alert == null ? this.alert : alert(),
    ahead: ahead ?? this.ahead,
    eventAlerts: eventAlerts ?? this.eventAlerts,
    reroutes: reroutes ?? this.reroutes,
    overview: overview ?? this.overview,
    positionLost: positionLost ?? this.positionLost,
    stops: stops ?? this.stops,
    aids: aids ?? this.aids,
  );
}

/// Restrictions are shown from this far ahead, metres.
const warningReachM = 3000.0;

/// And announced at these distances, once each.
const warningCallsM = [2000.0, 500.0];

/// The least time between two recalculations, doubled after each failure up
/// to [_maxBackoff]: the API allows 30 routes in ten minutes, and a vehicle
/// that parks off the route must not use them up.
const _minBackoff = Duration(seconds: 20);
const _maxBackoff = Duration(minutes: 2);

/// Fixes off the route before a recalculation: one is noise.
const _offRouteFixes = 2;

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

/// How often the route ahead is checked again against the known events as
/// the vehicle moves.
const _eventCheckEvery = Duration(seconds: 10);

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
  GuidanceWording? _words;
  VoiceOutput? _voice;
  ScreenWake? _wake;
  final _events = RoadEventsTracker();
  final Set<String> _spoken = {};
  final Map<String, int> _warned = {};
  final Set<String> _reroutedFor = {};
  final Set<String> _announced = {};
  int _fixRetries = 0;
  int _offRoute = 0;
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
    state = GuidanceSession(
      target: target,
      plan: plan,
      routeIndex: routeIndex,
      phase: GuidancePhase.navigating,
      voiceOn: settings.voice,
      voice: VoiceReadiness.none,
      stops: stops,
    );
    final readiness = await voice.prepare(plan.applied.language);
    if (!ref.mounted || generation != _generation) return false;
    state = state!.copyWith(voice: readiness);
    await wake.keepOn(on: true);
    if (!ref.mounted || generation != _generation) return false;
    await ref.read(appForegroundProvider).resumed();
    if (!ref.mounted || generation != _generation) return false;
    final locator = await ref.read(countryLocatorProvider.future);
    if (!ref.mounted || generation != _generation) return false;
    _aids = DrivingAidsEngine(locator: locator);
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

  Future<void> setVoice({required bool on}) async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(voiceOn: on);
    final voice = _voice;
    if (!on && voice != null) await voice.stop();
    if (!ref.mounted) return;
    await ref.read(routeSettingsControllerProvider.notifier).setVoice(on: on);
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

  /// Takes [stop] out of the stops ahead. True when it is no longer on the
  /// route, also when it was passed meanwhile.
  Future<bool> removeStop(RouteStop stop) async {
    final s = state;
    if (s == null) return false;
    if (!s.stops.contains(stop)) return true;
    return await _change(RerouteReason.stops, stops: [...s.stops]..remove(stop));
  }

  /// Puts [stop] back after it was taken out of [before]: in its place when
  /// the other stops are still those, else where it lengthens the trip the
  /// least.
  Future<bool> restoreStop(RouteStop stop, List<RouteStop> before) async {
    final s = state;
    final fix = s?.lastFix;
    if (s == null || fix == null) return false;
    // Passed before it was taken out: nothing to put back.
    if (s.stops.contains(stop) || !before.contains(stop)) return true;
    if (s.stops.length >= maxRouteStops) return false;
    final others = [...before]..remove(stop);
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
    stops: [for (final stop in stops ?? s.stops) stop.position],
  );

  void setOverview({required bool on}) {
    final s = state;
    if (s != null) state = s.copyWith(overview: on);
  }

  /// Opens the system's voice installer, then tries the voice again.
  Future<void> installVoices() async {
    final voice = _voice;
    if (voice == null) return;
    await voice.installVoices();
    if (!ref.mounted || state == null) return;
    final readiness = await voice.prepare(state!.plan.applied.language);
    if (ref.mounted && state != null) state = state!.copyWith(voice: readiness);
  }

  void _release() {
    _generation++;
    unawaited(_fixes?.cancel());
    _fixes = null;
    _fixRetry?.cancel();
    _fixRetry = null;
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
    _fixRetries = 0;
    _offRoute = 0;
    _lastReroute = null;
    _lastEventCheck = null;
    // The events stay known across guidances (the cursor goes on); what a
    // guidance acted on does not.
    _events.resetHandled();
    _backoff = _minBackoff;
    _rerouting = false;
    // Held since the start: the release also runs when the provider is
    // disposed, where no other provider may be read.
    final voice = _voice;
    final wake = _wake;
    _voice = null;
    _wake = null;
    if (voice != null) unawaited(voice.stop());
    if (wake != null) unawaited(wake.keepOn(on: false));
  }

  /// Whether the guidance of [generation] is still the one running, short
  /// of its arrival.
  bool _current(int generation) =>
      ref.mounted &&
      generation == _generation &&
      state != null &&
      state!.phase != GuidancePhase.arrived;

  void _say(String text, {bool queue = false}) {
    final s = state;
    final voice = _voice;
    if (voice != null && s != null && s.voiceOn && s.voice == VoiceReadiness.ready) {
      unawaited(voice.say(text, queue: queue));
    }
  }

  void _listenFixes() {
    final words = _words;
    if (words == null) return;
    unawaited(_fixes?.cancel());
    _fixes = ref
        .read(locationFeedProvider)
        .guidance(words.notice)
        .listen(_onFix, onError: _onPositionError);
  }

  @visibleForTesting
  void onFix(Fix fix) => _onFix(fix);

  /// The position stream failed: location turned off, or its permission
  /// taken back. geolocator ends its updates then, so the stream is asked
  /// for again, with the app in front, until fixes come back.
  void _onPositionError(Object e) {
    _log.warning('position stream: $e');
    final generation = _generation;
    if (!_current(generation)) return;
    state = state!.copyWith(positionLost: true);
    _fixRetry?.cancel();
    // 10 s, then longer while location stays off: each try starts and
    // stops the service and its notification.
    final wait = _fixRetryAfter * math.min(1 << _fixRetries, 12);
    _fixRetries++;
    _fixRetry = Timer(wait, () async {
      await ref.read(appForegroundProvider).resumed();
      if (_current(generation) && state!.positionLost) _listenFixes();
    });
  }

  void _onFix(Fix fix) {
    final track = _track;
    final s = state;
    if (track == null || s == null || s.phase == GuidancePhase.arrived) return;
    final snap = track.update(fix);
    var next = s.copyWith(snapshot: snap, lastFix: fix, positionLost: false);
    _fixRetries = 0;
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
      _say(_words!.arrived);
      return;
    }
    // A stop is behind once the vehicle has been there, or has driven past
    // where the route comes nearest to it: a point off the road is reached
    // where the router put it on the road.
    if (next.stops.isNotEmpty && _passed(next.stops.first, fix, snap, next.route)) {
      next = next.copyWith(stops: next.stops.sublist(1));
    }
    final instruction = snap.instruction;
    var said = false;
    if (instruction != null && _spoken.add(instruction.id)) {
      _say(instruction.text);
      said = true;
    }
    final ahead = _ahead(snap, next.route.warnings);
    for (final w in ahead) {
      final key = '${w.warning.externalId}@${w.warning.distanceFromStartM}';
      final stage = warningCallsM.lastIndexWhere((d) => w.aheadM <= d) + 1;
      if (stage > (_warned[key] ?? 0)) {
        _warned[key] = stage;
        // After a maneuver just said, the warning waits its turn.
        _say(_words!.warningAhead(w.warning, w.aheadM), queue: said);
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
      // The words of the aids only when the user asked for them: the
      // banners and the sign speak for themselves. A limit the user hid is
      // not spoken either.
      if (aids.words > next.aids.words) {
        final settings = ref.read(drivingAidsSettingsControllerProvider).value;
        if ((settings?.speedSound ?? false) &&
            (aids.wordKind != AidWord.overSpeed || settings!.showSpeedLimit)) {
          _say(_words!.aid(aids), queue: said);
        }
      }
      next = next.copyWith(aids: aids);
    }
    if (next.alert != null && !fix.at.isBefore(next.alert!.until)) {
      next = next.copyWith(alert: () => null);
    }
    if (snap.offRoute) {
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
    final alertUntil = fix.at.add(_alertFor);
    state = s!.copyWith(
      phase: GuidancePhase.rerouting,
      alert: () => cause == null ? s.alert : ClosureAheadAlert(finding: cause, until: alertUntil),
    );
    // A closure is said once; a new try after a failure goes quietly, its
    // notice on screen.
    if (cause != null) {
      if (_announced.add(cause.event.id)) _say(words.closureAhead(cause));
    } else if (reason == RerouteReason.offRoute) {
      _say(words.rerouting);
    }
    Duration? extra;
    var landed = false;
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
      _backoff = _minBackoff;
      _events.resetHandled();
      final before = state!.snapshot?.durationRemainingS;
      final snap = track.update(fix);
      extra = before == null ? null : Duration(seconds: (snap.durationRemainingS - before).round());
      state = state!.copyWith(
        target: target,
        stops: stops,
        plan: plan,
        routeIndex: plan.routes.first.index,
        snapshot: snap,
        phase: snap.offRoute ? GuidancePhase.offRoute : GuidancePhase.navigating,
        reroutes: state!.reroutes + 1,
        alert: () => ReroutedAlert(reason: reason, extra: extra, until: alertUntil),
      );
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
    // A closure on the new route asks for another one at once: "new route"
    // waits for that one.
    if (!_checkEvents(afterReroute: cause != null) && !_rerouting) _say(words.rerouted(extra));
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
      phase: (s.snapshot?.offRoute ?? false) ? GuidancePhase.offRoute : GuidancePhase.navigating,
      eventAlerts: cause == null
          ? null
          : [cause, ...s.eventAlerts.where((e) => e.event.id != cause.event.id)],
      alert: () => cause != null && noRoute
          ? NoDetourAlert(finding: cause, until: until)
          : RerouteFailedAlert(failure: failure, cause: cause, until: until),
    );
    if (cause != null && noRoute) _say(_words!.noDetour(cause));
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
      _say(_words!.noDetour(first));
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
