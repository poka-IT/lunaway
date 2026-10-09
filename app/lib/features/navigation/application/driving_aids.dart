import 'dart:math' as math;

import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/country_locator.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'driving_aids.g.dart';

/// The user's choices about the limit and the alerts, in the user
/// database's `settings` table.
final class DrivingAidsStore {
  new(this._load, this._save);

  final Future<String?> Function() _load;
  final Future<void> Function(String value) _save;

  Future<DrivingAidsSettings> load() async => DrivingAidsSettings.decode(await _load());

  Future<void> save(DrivingAidsSettings settings) => _save(settings.encode());
}

// keepAlive: a store over the app-wide database.
@Riverpod(keepAlive: true)
DrivingAidsStore drivingAidsStore(Ref ref) {
  final db = ref.watch(userDatabaseProvider);
  const key = 'driving_aids';
  return DrivingAidsStore(
    () async =>
        (await (db.select(db.settings)..where((s) => s.id.equals(key))).getSingleOrNull())?.value,
    (value) => db
        .into(db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(id: key, value: value)),
  );
}

/// Whether the limit shows, whether it is said, and where the cameras'
/// positions were asked for.
// keepAlive: the guidance reads it at every fix, the profile edits it.
@Riverpod(keepAlive: true)
class DrivingAidsSettingsController extends _$DrivingAidsSettingsController {
  @override
  Future<DrivingAidsSettings> build() => ref.watch(drivingAidsStoreProvider).load();

  Future<void> setShowSpeedLimit({required bool on}) =>
      _update((s) => s.copyWith(showSpeedLimit: on));

  Future<void> setSpeedSound({required bool on}) => _update((s) => s.copyWith(speedSound: on));

  /// Asks for the cameras' exact positions in [country], or withdraws the
  /// choice: then what the device holds of them goes at once, from every
  /// trip, offline too.
  Future<void> setExactPositions(String country, {required bool on}) async {
    final key = country.toUpperCase();
    await _update(
      (s) => s.copyWith(
        exactIn: on
            ? {...s.exactIn, key}
            : {
                for (final c in s.exactIn)
                  if (c != key) c,
              },
      ),
    );
    if (!on && ref.mounted) {
      try {
        await ref.read(enforcementFeedProvider).purge();
      } on Object {
        // Not logged: the line would tell the choice. What the purge left
        // is never handed out (EnforcementSync.refresh filters it), and
        // the next answer for France replaces it.
      }
    }
  }

  Future<void> _update(DrivingAidsSettings Function(DrivingAidsSettings) change) async {
    // The stored settings first: a change made while they load would be
    // overwritten by them.
    final current = await future.catchError((Object _) => const DrivingAidsSettings());
    if (!ref.mounted) return;
    final next = change(current);
    state = AsyncData(next);
    await ref.read(drivingAidsStoreProvider).save(next);
  }
}

// keepAlive: a store over the app-wide database.
@Riverpod(keepAlive: true)
EnforcementStore enforcementStore(Ref ref) => EnforcementStore(ref.watch(cacheDatabaseProvider));

/// The speed camera data, through the routing client: no position goes
/// with it, only the countries of the trip and, among them, those where
/// the user asked for the positions.
// keepAlive: one instance for the run: its queue orders a purge after the
// poll in flight and keeps two polls' pages apart, which two instances
// would not.
@Riverpod(keepAlive: true)
EnforcementFeed enforcementFeed(Ref ref) => EnforcementSync(
  client: ref.watch(routingClientProvider),
  store: ref.watch(enforcementStoreProvider),
  chosen: () async => (await ref.read(drivingAidsSettingsControllerProvider.future)).exactIn,
);

/// The lists of speed cameras as the API last described them, for the
/// credits: a list the app does not know yet is cited in its own words.
@riverpod
Future<List<EnforcementSource>> heldEnforcementSources(Ref ref) async =>
    (await ref.watch(enforcementStoreProvider).state()).sources;

/// The countries around a position, read on the device by the guidance
/// library; where it is not loaded, none (every rule then reads as off).
// keepAlive: the library loads once per run.
@Riverpod(keepAlive: true)
Future<CountryLocator> countryLocator(Ref ref) async =>
    await ref.watch(guidanceEngineProvider.future) == null
    ? const NoCountryLocator()
    : const BridgeCountryLocator();

/// The countries [line] runs through and those within a kilometre of it,
/// a point every [stepM] metres and its ends: what the delta is asked for,
/// a list of countries and never a position.
Set<String> countriesAlong(CountryLocator locator, List<LatLng> line, {double stepM = 5000}) {
  final out = <String>{};
  var since = double.infinity;
  for (var i = 0; i < line.length; i++) {
    if (i > 0) since += line[i - 1].distanceTo(line[i]);
    if (since >= stepM || i == line.length - 1) {
      out.addAll(locator.around(line[i]).near);
      since = 0;
    }
  }
  return out;
}

/// How far ahead a zone or a camera shows, metres, by the limit where the
/// vehicle drives: about 20 s at that speed (plan/research/28, 4.4: 800 m
/// on a motorway, 400 m on other roads, 150 m in town, figures to adjust
/// on the road).
double alertReachM(int? limitKmh) => switch (limitKmh) {
  null => 400,
  >= 110 => 800,
  >= 70 => 400,
  _ => 200,
};

/// How far past its end an alert holds, metres: the position wavers by
/// some 20 m, and an alert that went and came back at its edge would be
/// noise (a camera's point is passed at once, a stretch less sharply).
const cameraMarginM = 30.0;
const stretchMarginM = 50.0;

/// Two danger zones closer than this along the route are one stretch of
/// road for the driver: one alert, no end between them.
const zoneGapM = 300.0;

/// Cameras of one kind closer than this along the route are one camera for
/// the driver: one per lane on a gantry (the A2 between Amsterdam and
/// Utrecht maps six), or the same one mapped twice. The radius the server
/// merges a camera of its sources within.
const sameCameraM = 50.0;

/// How long the engine holds the end of a zone or a section, and the
/// rule of a country just entered: the screen tells each as a passing
/// notice, for the time notices take (`NoticeTimes`), and takes the end
/// back when another alert comes within this.
const exitShownFor = Duration(seconds: 4);
const ruleShownFor = Duration(seconds: 8);

/// The distance a section's average needs before it means anything.
const averageAfterM = 200.0;

/// The limit, the excess and the zones or cameras of a guidance, worked
/// out at each fix from the route, the vehicle's speed and the rule of the
/// country it is in. A plain object the guidance controller holds, so it
/// runs with the guidance, screen off as well.
///
/// An alert comes into reach about 20 s ahead and stays until the vehicle
/// has passed its end by a margin, whatever the reach does meanwhile (a
/// limit that drops shortens it). It is entered only at its real start,
/// and left only on a precise fix past its end: a tunnel's position
/// neither ends it nor changes the rule. Each zone, camera and section is
/// said once, and its excess once, for the whole guidance, a new route
/// included.
final class DrivingAidsEngine {
  new({required this.locator, EnforcementRules? rules, DrivingAidsSettings Function()? choices})
    : _base = rules ?? locator.builtIn,
      _choices = choices ?? _defaults;

  static DrivingAidsSettings _defaults() => const DrivingAidsSettings();

  final CountryLocator locator;

  /// The user's choices, read at each fix: the road's limit shown or not,
  /// the countries whose positions were asked for.
  final DrivingAidsSettings Function() _choices;

  /// The rules as received (or built in), and as the choices make them.
  EnforcementRules _base;
  EnforcementRules? _rulesOf;
  Set<String> _chosen = const {};
  EnforcementRules _rules = EnforcementRules.none;

  EnforcementIndex _index = EnforcementIndex(const []);
  Map<String, EnforcementSource> _sources = const {};
  List<LatLng>? _line;
  List<ItemOnRoute> _onRoute = const [];
  final _tracker = RuleTracker();
  final _speed = OverSpeedWatch();
  var _overSpeedCalls = 0;
  String? _country;

  /// The rule and its country after the last precise fix; null before the
  /// first, which sets the rule without telling it.
  ({EnforcementMode mode, String? country, EnforcementRules rules})? _lastRule;
  ({RuleChange change, DateTime until})? _ruleChange;

  /// What the map draws and what is alerted, worked out again only when
  /// the items on the route or the rule change: the same lists otherwise,
  /// cheap to compare.
  ({List<ItemOnRoute> onRoute, EnforcementMode mode, EnforcementRules rules})? _drawnFor;
  List<RouteSpan> _zones = const [];
  List<CameraOnRoute> _cameras = const [];
  List<_Stretch> _stretches = const [];

  /// The keys of the items said, for the whole guidance.
  final Set<String> _said = {};

  /// The stretches in reach or around the vehicle, and those it entered,
  /// by key; those passed on the current route.
  final Map<String, _Stretch> _engaged = {};
  final Set<String> _entered = {};
  final Set<String> _passed = {};

  /// The route [_passed] was measured on.
  List<LatLng>? _passedOn;
  ({AlertExit exit, DateTime until})? _exit;

  /// The excess of the alert shown, watched apart from the road's.
  String? _watched;
  OverSpeedWatch _alertSpeed = OverSpeedWatch();

  /// The section the vehicle drives through, from its start.
  _Average? _average;

  /// The rules the API sent (or those the app was built with) and the
  /// items of the trip's countries.
  void setData({
    required EnforcementRules? rules,
    required List<EnforcementItem> items,
    List<EnforcementSource> sources = const [],
  }) {
    _base = rules ?? locator.builtIn;
    _index = EnforcementIndex(items);
    _sources = {for (final s in sources) s.id: s};
    _line = null;
  }

  /// The rules in force: the table with the user's choices.
  EnforcementRules get rules => _rules;

  /// The countries [line] runs through and those within a kilometre of
  /// it ([countriesAlong]).
  Set<String> countriesOf(List<LatLng> line, {double stepM = 5000}) =>
      countriesAlong(locator, line, stepM: stepM);

  /// The aids after [fix], on [route] at [snap], for a vehicle of
  /// [totalWeightT] with its trailer.
  DrivingAids update({
    required Fix fix,
    required GuidanceSnapshot snap,
    required RouteOption route,
    required double totalWeightT,
  }) {
    final choices = _choices();
    _applyChoices(choices.exactIn);
    // An imprecise fix (a tunnel, a town's canyons) decides nothing about
    // the country: the last rule stands, and so does the alert.
    final precise = fix.accuracyM <= 100;
    if (precise) _readRule(fix);
    final mode = _tracker.mode;
    final along = snap.distanceAlongM;
    final limit = limitAt(
      spans: route.speedLimits,
      alongM: along,
      postedKmh: snap.speedLimitKmh,
      totalWeightT: totalWeightT,
    );
    final speed = fix.speedMps == null ? null : fix.speedMps! * 3.6;
    final over = _speed.update(speedKmh: speed, limit: limit, at: fix.at);
    if (!identical(_line, route.line)) {
      _line = route.line;
      _onRoute = _index.onRoute(route.line);
    }
    // Passed on the old route says nothing of the new one; the stretch the
    // vehicle is in goes on, said already.
    if (!identical(_passedOn, route.line)) {
      _passedOn = route.line;
      _passed.clear();
    }
    final drawn = _drawnFor;
    if (drawn == null ||
        !identical(drawn.onRoute, _onRoute) ||
        drawn.mode != mode ||
        !identical(drawn.rules, _rules)) {
      _drawnFor = (onRoute: _onRoute, mode: mode, rules: _rules);
      _zones = mode.shows ? zoneSpans(_onRoute, here: mode, rules: _rules) : const [];
      _cameras = [
        for (final r in camerasOnRoute(_onRoute, here: mode, rules: _rules))
          CameraOnRoute(onRoute: r, sources: _sourcesOf(r.item)),
      ];
      _stretches = mode.shows ? _stretchesOf(_onRoute, mode) : const [];
    }

    final calls = <AidCall>[];
    // The road's limit as the alerts may use it: never one the user hid.
    final road = choices.showSpeedLimit ? limit : null;
    final reach = alertReachM(limit?.kmh);
    final current = {for (final s in _stretches) s.key: s};

    // A stretch the rule or the route no longer holds goes without an end
    // told: the vehicle did not drive out of it.
    for (final key in _engaged.keys.toList()) {
      final now = current[key];
      if (now == null) {
        _drop(key);
      } else {
        _engaged[key] = now;
      }
    }

    // Past the end by the margin, on a precise fix only.
    final left = <_Stretch>[];
    if (precise) {
      for (final s in _engaged.values.toList()) {
        if (along <= s.endM + s.margin) continue;
        if (_entered.contains(s.key) && s.kind != _StretchKind.camera) left.add(s);
        _drop(s.key);
        _passed.add(s.key);
      }
    }

    // Into reach, once per route.
    final startedInside = <String>{};
    for (final s in _stretches) {
      if (s.startM - along > reach) break;
      if (_engaged.containsKey(s.key) || _passed.contains(s.key) || along > s.endM) continue;
      _engaged[s.key] = s;
      if (along >= s.startM) startedInside.add(s.key);
      if (!s.ids.any(_said.contains)) {
        _said.addAll(s.ids);
        final alert = _alertOf(s, along: along, road: road, over: false, inside: along >= s.startM);
        calls.add(AidCall(word: s.word, key: 'aid:${s.word.name}:${s.key}', alert: alert));
      }
    }

    // Entered at its real start only; a waver back across it changes
    // nothing.
    for (final s in _engaged.values) {
      if (along < s.startM || !_entered.add(s.key)) continue;
      // Its average means something only from its start: a guidance or a
      // reach that begins inside does not know when the vehicle entered.
      if (s.kind == _StretchKind.section && !startedInside.contains(s.key)) {
        _average = _Average(s.key, fix.at, along, route.line, fix.position);
      }
    }

    final shown = _shown(along);
    final average = switch (_average) {
      final a? when a.key == shown?.key => a.update(fix, along, route.line),
      _ => null,
    };
    EnforcementAlert? alert;
    if (shown != null) {
      if (_watched != shown.key) {
        _watched = shown.key;
        _alertSpeed = OverSpeedWatch();
      }
      final relevant = _limitOf(shown, road);
      final watch = _alertSpeed.update(
        speedKmh: average ?? speed,
        limit: relevant?.limit,
        at: fix.at,
      );
      alert = _alertOf(
        shown,
        along: along,
        road: road,
        over: watch.over,
        inside: _entered.contains(shown.key),
        average: average,
      );
      if (watch.over && relevant != null && _said.add('slow:${shown.key}')) {
        calls.add(AidCall(word: AidWord.slowDown, key: 'aid:slow:${shown.key}', alert: alert));
      }
    } else {
      _watched = null;
    }

    // The end, unless another alert takes the screen at once.
    if (left.isNotEmpty && shown == null) {
      final last = left.last;
      _exit = (
        exit: AlertExit(id: last.key, section: last.kind == _StretchKind.section),
        until: fix.at.add(exitShownFor),
      );
    }
    if (shown != null || (_exit != null && !fix.at.isBefore(_exit!.until))) _exit = null;
    if (_ruleChange != null && !fix.at.isBefore(_ruleChange!.until)) _ruleChange = null;

    // The road's reminder stays quiet while an alert over its own limit
    // speaks: "radar limité à 90" and "vitesse limitée à 110" would
    // contradict each other.
    if (over.sound && !(alert?.over ?? false)) {
      calls.add(AidCall(word: AidWord.overSpeed, key: 'aid:over:${++_overSpeedCalls}'));
    }
    return DrivingAids(
      limit: limit,
      overSpeed: over.over,
      alert: alert,
      exit: _exit?.exit,
      ruleChange: _ruleChange?.change,
      mode: mode,
      country: _country,
      calls: calls,
      zones: _zones,
      cameras: _cameras,
    );
  }

  void _applyChoices(Set<String> chosen) {
    if (identical(_rulesOf, _base) && _sameSet(_chosen, chosen)) return;
    _rulesOf = _base;
    _chosen = chosen;
    _rules = _base.withChoices(chosen);
  }

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  /// The rule after a precise [fix]; a change of rule into another
  /// country, past the first fix, is told on screen.
  void _readRule(Fix fix) {
    final around = locator.around(fix.position);
    _country = around.at;
    final mode = _tracker.update(_rules.strictestOf(around.near), fix.at);
    final last = _lastRule;
    if (last != null && mode == last.mode) return;
    final country = _rules.governingOf(around.near, at: around.at);
    _lastRule = (mode: mode, country: country, rules: _rules);
    // A choice made in the settings, or a new table, changes the rule where
    // the vehicle is, near a border the country whose rule applies too:
    // no border was crossed when the rules read before still hold here.
    final byRules =
        last != null &&
        !identical(last.rules, _rules) &&
        last.rules.strictestOf(around.near) == last.mode;
    if (last == null || byRules || country == null || country == last.country) return;
    _ruleChange = (
      change: RuleChange(country: country, mode: mode),
      until: fix.at.add(ruleShownFor),
    );
  }

  void _drop(String key) {
    _engaged.remove(key);
    _entered.remove(key);
    if (_average?.key == key) _average = null;
  }

  /// The stretch the banner shows: a camera's point ahead first (it comes
  /// sooner than the end of a stretch), else the stretch the vehicle is
  /// in, else the nearest one ahead.
  _Stretch? _shown(double along) {
    _Stretch? camera;
    _Stretch? inside;
    _Stretch? ahead;
    for (final s in _engaged.values) {
      if (s.kind == _StretchKind.camera && along < s.startM) {
        if (camera == null || s.startM < camera.startM) camera = s;
      } else if (_entered.contains(s.key) && s.kind != _StretchKind.camera) {
        inside ??= s;
      } else if (ahead == null || s.startM < ahead.startM) {
        ahead = s;
      }
    }
    return camera ?? inside ?? ahead;
  }

  /// The limit that matters for [s]: the camera's own, else the road's
  /// where the vehicle is. A red light or a level crossing camera does not
  /// measure speed: its own limit is never used, the road's stands.
  ({ShownLimit limit, bool camera})? _limitOf(_Stretch s, ShownLimit? road) {
    final own = s.limitKmh;
    if (own != null) {
      return (limit: ShownLimit(kmh: own, source: SpeedLimitSource.posted), camera: true);
    }
    if (road == null) return null;
    return (limit: road, camera: false);
  }

  /// The alert of [s] at [along]: [inside] once the vehicle has reached
  /// its start, whatever the position says after (it wavers).
  EnforcementAlert _alertOf(
    _Stretch s, {
    required double along,
    required ShownLimit? road,
    required bool over,
    required bool inside,
    double? average,
  }) {
    final limit = _limitOf(s, road);
    final entered = inside && s.kind != _StretchKind.camera;
    return EnforcementAlert(
      id: s.key,
      kind: s.kind == _StretchKind.zone ? EnforcementKind.zone : EnforcementKind.camera,
      category: s.category,
      aheadM: entered ? 0 : math.max(0, s.startM - along),
      remainingM: entered ? math.max(0, s.endM - along) : 0,
      limitKmh: limit?.limit.kmh,
      limitEstimated: limit?.limit.estimated ?? false,
      cameraLimit: limit?.camera ?? false,
      sectionM: s.kind == _StretchKind.section ? s.endM - s.startM : null,
      averageKmh: average,
      over: over,
      sources: [
        for (final id in {for (final i in s.items) ...i.sourceIds}) ?_sources[id],
      ],
    );
  }

  List<EnforcementSource> _sourcesOf(EnforcementItem item) => [
    for (final id in item.sourceIds) ?_sources[id],
  ];

  /// What is alerted on the route under [mode]: its zones, those closer
  /// than [zoneGapM] made one; its sections; its cameras' points, those of
  /// one kind closer than [sameCameraM] made one.
  List<_Stretch> _stretchesOf(List<ItemOnRoute> onRoute, EnforcementMode mode) {
    final out = <_Stretch>[];
    _Stretch? zone;
    // The last camera of each kind: a red light between two cameras of a
    // gantry leaves them one.
    final cameras = <CameraCategory?, _Stretch>{};
    for (final r in onRoute) {
      final item = r.item;
      if (!item.shownUnder(mode, _rules)) continue;
      if (item.kind == EnforcementKind.zone) {
        if (r.endM <= r.startM) continue;
        if (zone != null && r.startM - zone.endM < zoneGapM) {
          zone.extend(r);
          continue;
        }
        out.add(zone = _Stretch(_StretchKind.zone, r));
      } else if (item.isSection && r.endM > r.startM) {
        out.add(_Stretch(_StretchKind.section, r));
      } else {
        final same = cameras[item.cameraCategory];
        if (same != null && r.startM - same.endM < sameCameraM) {
          same.extend(r);
          continue;
        }
        out.add(cameras[item.cameraCategory] = _Stretch(_StretchKind.camera, r));
      }
    }
    // A camera stands at a point; the stretches start where they start.
    return out..sort((a, b) => a.startM.compareTo(b.startM));
  }
}

enum _StretchKind { zone, section, camera }

/// What one alert stands for along the route: a camera's point, a
/// section, or danger zones close enough to be one stretch of road.
final class _Stretch {
  new(this.kind, ItemOnRoute first)
    : startM = first.startM,
      endM = kind == _StretchKind.camera ? first.startM : first.endM,
      items = [first.item];

  final _StretchKind kind;
  final double startM;
  double endM;
  final List<EnforcementItem> items;

  /// Its first item's id: what names it from fix to fix and route to
  /// route.
  String get key => items.first.id;

  Iterable<String> get ids => items.map((i) => i.id);

  double get margin => kind == _StretchKind.camera ? cameraMarginM : stretchMarginM;

  CameraCategory? get category => kind == _StretchKind.zone ? null : items.first.cameraCategory;

  /// A camera's own limit, when it measures speed, the lowest its lists
  /// give for cameras made one; a zone takes the road's.
  int? get limitKmh {
    if (kind == _StretchKind.zone) return null;
    int? lowest;
    for (final i in items) {
      if (i.controlledLimitKmh case final l? when lowest == null || l < lowest) lowest = l;
    }
    return lowest;
  }

  AidWord get word => switch (kind) {
    _StretchKind.zone => AidWord.zone,
    _StretchKind.section => AidWord.section,
    _StretchKind.camera => AidWord.camera,
  };

  void extend(ItemOnRoute next) {
    items.add(next.item);
    endM = math.max(endM, next.endM);
  }
}

/// The vehicle's average speed through a section since its start: the
/// metres driven along the route, or between fixes across a new route.
final class _Average {
  new(this.key, this.since, this._along, this._line, this._at);

  final String key;
  final DateTime since;
  double _along;
  List<LatLng> _line;
  LatLng _at;
  double _metres = 0;

  /// The average after [fix], km/h; null before [averageAfterM].
  double? update(Fix fix, double along, List<LatLng> line) {
    _metres += identical(line, _line) ? math.max(0, along - _along) : fix.position.distanceTo(_at);
    _along = along;
    _line = line;
    _at = fix.position;
    final seconds = fix.at.difference(since).inMilliseconds / 1000;
    if (_metres < averageAfterM || seconds <= 0) return null;
    return _metres / seconds * 3.6;
  }
}

/// The weight the vehicle's limits follow: the vehicle and its trailer.
double totalWeightOf(VehicleProfile vehicle) => vehicle.weightT + (vehicle.trailer?.weightT ?? 0);
