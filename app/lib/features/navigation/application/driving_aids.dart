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

/// Whether the limit shows, and whether the aids speak.
// keepAlive: the guidance reads it at every fix, the profile edits it.
@Riverpod(keepAlive: true)
class DrivingAidsSettingsController extends _$DrivingAidsSettingsController {
  @override
  Future<DrivingAidsSettings> build() => ref.watch(drivingAidsStoreProvider).load();

  Future<void> setShowSpeedLimit({required bool on}) =>
      _update((s) => s.copyWith(showSpeedLimit: on));

  Future<void> setSpeedSound({required bool on}) => _update((s) => s.copyWith(speedSound: on));

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

/// The speed camera delta, through the routing client: no position goes
/// with it, only the countries of the trip.
// keepAlive: a stateless service, wired once.
@Riverpod(keepAlive: true)
EnforcementFeed enforcementFeed(Ref ref) => EnforcementSync(
  client: ref.watch(routingClientProvider),
  store: ref.watch(enforcementStoreProvider),
);

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

/// The limit, the excess and the zones or cameras of a guidance, worked
/// out at each fix from the route, the vehicle's speed and the rule of the
/// country it is in. A plain object the guidance controller holds, so it
/// runs with the guidance, screen off as well.
final class DrivingAidsEngine {
  new({required this.locator, EnforcementRules? rules}) : _rules = rules ?? locator.builtIn;

  final CountryLocator locator;
  EnforcementRules _rules;
  EnforcementIndex _index = EnforcementIndex(const []);
  Map<String, EnforcementSource> _sources = const {};
  List<LatLng>? _line;
  List<ItemOnRoute> _onRoute = const [];
  final _tracker = RuleTracker();
  final _speed = OverSpeedWatch();
  final Set<String> _announced = {};
  var _words = 0;
  AidWord? _wordKind;
  String? _country;

  /// The zones the map draws, worked out again only when the items on the
  /// route or the rule change: the same list otherwise, cheap to compare.
  List<RouteSpan> _zones = const [];
  ({List<ItemOnRoute> onRoute, EnforcementMode mode, EnforcementRules rules})? _zonesFor;

  /// The rules the API sent (or those the app was built with) and the
  /// items of the trip's countries.
  void setData({
    required EnforcementRules? rules,
    required List<EnforcementItem> items,
    List<EnforcementSource> sources = const [],
  }) {
    _rules = rules ?? locator.builtIn;
    _index = EnforcementIndex(items);
    _sources = {for (final s in sources) s.id: s};
    _line = null;
  }

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
    // An imprecise fix (a tunnel, a town's canyons) decides nothing about
    // the country: the last rule stands.
    if (fix.accuracyM <= 100) {
      final around = locator.around(fix.position);
      _country = around.at;
      _tracker.update(_rules.strictestOf(around.near), fix.at);
    }
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
    if (over.sound) _word(AidWord.overSpeed);

    EnforcementAlert? alert;
    var zones = const <RouteSpan>[];
    if (mode.showsWhileDriving) {
      if (!identical(_line, route.line)) {
        _line = route.line;
        _onRoute = _index.onRoute(route.line);
      }
      final key = _zonesFor;
      if (key == null ||
          !identical(key.onRoute, _onRoute) ||
          key.mode != mode ||
          !identical(key.rules, _rules)) {
        _zonesFor = (onRoute: _onRoute, mode: mode, rules: _rules);
        _zones = zoneSpans(_onRoute, here: mode, rules: _rules, driving: true);
      }
      zones = _zones;
      final reach = alertReachM(limit?.kmh);
      for (final r in _onRoute) {
        if (r.endM < along) continue;
        if (r.startM - along > reach) break;
        if (!r.item.shownUnder(mode, _rules)) continue;
        alert = EnforcementAlert(
          id: r.item.id,
          kind: r.item.kind,
          aheadM: math.max(0, r.startM - along),
          remainingM: along >= r.startM ? r.endM - along : 0,
          limitKmh: r.item.kind == EnforcementKind.camera ? r.item.limitKmh : null,
          sources: [for (final id in r.item.sourceIds) ?_sources[id]],
        );
        break;
      }
      if (alert != null && _announced.add(alert.id)) {
        _word(alert.kind == EnforcementKind.zone ? AidWord.zone : AidWord.camera);
      }
    }
    return DrivingAids(
      limit: limit,
      overSpeed: over.over,
      alert: alert,
      mode: mode,
      country: _country,
      words: _words,
      wordKind: _wordKind,
      zones: zones,
    );
  }

  void _word(AidWord kind) {
    _words++;
    _wordKind = kind;
  }
}

/// The weight the vehicle's limits follow: the vehicle and its trailer.
double totalWeightOf(VehicleProfile vehicle) => vehicle.weightT + (vehicle.trailer?.weightT ?? 0);
