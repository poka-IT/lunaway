import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

const _metresPerMile = 1609.344;
const _feetPerMetre = 3.28084;

/// How the navigation reads distances, durations and restrictions.
extension NavigationTexts on Translations {
  String get _locale => $meta.locale.languageCode;

  // The full path of every key, `_t.navigation...`: the translation gate
  // finds a key by its dotted path.
  Translations get _t => this;

  /// A speed limit in the user's units, rounded as a sign shows it: 90
  /// km/h reads 56 in miles per hour.
  int speedIn(int kmh, DistanceUnits units) =>
      units == DistanceUnits.metric ? kmh : (kmh * 1000 / _metresPerMile).round();

  /// "90 km/h", or "56 mph" in [DistanceUnits.imperial].
  String speedLimit(int kmh, DistanceUnits units) =>
      '${speedIn(kmh, units)} ${units == DistanceUnits.metric ? _t.navigation.units.kmh : _t.navigation.units.mph}';

  /// "350 m", "2.4 km", "48 km"; "500 ft", "1.2 mi" in [DistanceUnits.imperial].
  String routeDistance(double metres, DistanceUnits units) {
    if (units == DistanceUnits.metric) return distance(metres);
    final miles = metres / _metresPerMile;
    if (miles < 0.1) {
      final feet = (metres * _feetPerMetre / 50).round() * 50;
      return _t.navigation.units.ft(n: '$feet');
    }
    final format = NumberFormat(miles < 9.95 ? '0.0' : '0', _locale);
    return _t.navigation.units.mi(n: format.format(miles));
  }

  /// "12 min", "1 h 05".
  String routeDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return _t.navigation.units.minutes(m: '${minutes < 1 ? 1 : minutes}');
    final m = minutes % 60;
    return _t.navigation.units.hoursMinutes(h: '${minutes ~/ 60}', m: m.toString().padLeft(2, '0'));
  }

  /// The figure of a restriction in its own unit: metres for a size, tonnes
  /// for a mass. French road signs are metric, whatever the app's units.
  String limitFigure(RouteWarningKind kind, double value) => switch (kind) {
    RouteWarningKind.tooHeavy ||
    RouteWarningKind.axleLoad ||
    RouteWarningKind.goodsVehicleWeight => tonnes(value),
    _ => metres(value),
  };

  /// "Low bridge 2.70 m", "Height bar 1.90 m", "No motorhomes".
  String warningTitle(RouteWarning w) {
    final limit = w.limit == null ? '' : limitFigure(w.kind, w.limit!);
    return switch (w.kind) {
      RouteWarningKind.lowClearance => switch (w.place) {
        RestrictionPlace.underpass => _t.navigation.warning.lowClearance.underpass(limit: limit),
        RestrictionPlace.tunnel => _t.navigation.warning.lowClearance.tunnel(limit: limit),
        RestrictionPlace.buildingPassage => _t.navigation.warning.lowClearance.buildingPassage(
          limit: limit,
        ),
        RestrictionPlace.bridge => _t.navigation.warning.lowClearance.bridge(limit: limit),
        RestrictionPlace.barrier => _t.navigation.warning.lowClearance.barrier(limit: limit),
        RestrictionPlace.road => _t.navigation.warning.lowClearance.road(limit: limit),
      },
      RouteWarningKind.unknownClearance => _t.navigation.warning.unknownClearance,
      RouteWarningKind.narrow => _t.navigation.warning.narrow(limit: limit),
      RouteWarningKind.tooLong => _t.navigation.warning.tooLong(limit: limit),
      RouteWarningKind.tooHeavy => _t.navigation.warning.tooHeavy(limit: limit),
      RouteWarningKind.axleLoad => _t.navigation.warning.axleLoad(limit: limit),
      RouteWarningKind.motorhomeBan => _t.navigation.warning.motorhomeBan,
      RouteWarningKind.trailerBan => _t.navigation.warning.trailerBan,
      RouteWarningKind.goodsVehicleWeight => _t.navigation.warning.goodsVehicleWeight(limit: limit),
    }.trim();
  }

  /// "your vehicle: 3.30 m", when the restriction was compared with a figure.
  String? warningVehicle(RouteWarning w) => w.vehicleValue == null
      ? null
      : _t.navigation.warning.yours(value: limitFigure(w.kind, w.vehicleValue!));

  String warningSource(RouteWarning w) => switch (w.source) {
    RestrictionSource.osm => _t.navigation.warning.osm,
    RestrictionSource.ign => _t.navigation.warning.ign,
    RestrictionSource.community => _t.navigation.warning.community,
    RestrictionSource.dialog => _t.navigation.warning.dialog,
  };

  /// A distance as spoken: rounded the way a driver counts ("500 metres",
  /// "2 kilometres", "1.5 kilometres").
  String spokenDistance(double metres, DistanceUnits units) {
    if (units == DistanceUnits.imperial) {
      final miles = metres / _metresPerMile;
      if (miles < 0.2) {
        return _t.navigation.voice.feet(n: '${(metres * _feetPerMetre / 100).round() * 100}');
      }
      final half = _half(miles);
      return _t.navigation.voice.miles(count: half, n: NumberFormat('0.#', _locale).format(half));
    }
    final step = metres < 200 ? 10 : 50;
    final rounded = (metres / step).round() * step;
    // 990 m is said "1 kilomètre", not "1000 mètres".
    if (rounded < 1000) return _t.navigation.voice.metres(n: '$rounded');
    // French counts 1.5 kilometres in the singular, English in the plural:
    // the plural rule of each language decides.
    final half = _half(metres / 1000);
    return _t.navigation.voice.kilometres(
      count: half,
      n: NumberFormat('0.#', _locale).format(half),
    );
  }

  /// A height or a width as spoken: "3 mètres 20", "3.20 metres".
  String spokenSize(double metres) {
    // From whole centimetres: 2.996 m is "3 mètres", not "2 mètres 100".
    final total = (metres * 100).round();
    final whole = total ~/ 100;
    final cm = total % 100;
    if (cm == 0) return _t.navigation.voice.sizeWhole(metres: '$whole');
    return _t.navigation.voice.size(metres: '$whole', cm: cm.toString().padLeft(2, '0'));
  }

  /// The arrival time, "15:42" or "3:42 PM".
  String clockTime(DateTime at) => DateFormat.jm(_locale).format(at);

  /// "6 oct.", "Oct 6".
  String dayMonth(DateTime at) => DateFormat.MMMd(_locale).format(at);

  /// What a road event does, as a driver reads it: "Route fermée".
  String roadEventWhat(RoadEventClass c) => switch (c) {
    RoadEventClass.closure => _t.navigation.roadEvents.classClosure,
    RoadEventClass.works => _t.navigation.roadEvents.classWorks,
    RoadEventClass.laneRestriction => _t.navigation.roadEvents.classLaneRestriction,
    RoadEventClass.vehicleLimit => _t.navigation.roadEvents.classVehicleLimit,
    RoadEventClass.detour => _t.navigation.roadEvents.classDetour,
  };

  /// What the reason adds to the class, when it says more: an uncertain
  /// place, a stale source, a single report.
  String? roadEventQualifier(RoadEventReason r) => switch (r) {
    RoadEventReason.unmatched => _t.navigation.roadEvents.reasonUnmatched,
    RoadEventReason.stale => _t.navigation.roadEvents.reasonStale,
    RoadEventReason.outsideAssumedHours => _t.navigation.roadEvents.reasonOutsideHours,
    RoadEventReason.goodsVehiclesOnly => _t.navigation.roadEvents.reasonGoodsVehicles,
    RoadEventReason.unconfirmed => _t.navigation.roadEvents.reasonUnconfirmed,
    RoadEventReason.aged => _t.navigation.roadEvents.reasonAged,
    RoadEventReason.alreadyInside => _t.navigation.roadEvents.reasonInside,
    RoadEventReason.nearLimit => _t.navigation.roadEvents.reasonNearLimit,
    RoadEventReason.limitExceeded => _t.navigation.roadEvents.reasonOverLimit,
    RoadEventReason.closed ||
    RoadEventReason.laneRestriction ||
    RoadEventReason.works ||
    RoadEventReason.detour => null,
  };

  /// Where road data comes from and how recent it is: "DIR, données de
  /// 22:37", the day as well when the data is not of [now]'s day.
  String roadDataSource(String source, DateTime? at, DateTime now) {
    final local = at?.toLocal();
    if (local == null) return source;
    final today = local.year == now.year && local.month == now.month && local.day == now.day;
    return today
        ? _t.navigation.guidance.eventSource(source: source, time: clockTime(local))
        : _t.navigation.guidance.eventSourceOn(
            source: source,
            day: dayMonth(local),
            time: clockTime(local),
          );
  }

  /// "1,789 €/L": to the tenth of a cent, as stations show it.
  String litrePrice(double euros) =>
      _t.navigation.fuel.price(price: NumberFormat('0.000', _locale).format(euros));

  /// "1,812 €/L avec le détour".
  String litrePriceWithDetour(double euros) =>
      _t.navigation.fuel.withDetour(price: NumberFormat('0.000', _locale).format(euros));

  /// "il y a 40 min", "il y a 3 h", "il y a 2 j": how old a price is.
  String priceAge(DateTime at, DateTime now) {
    final age = now.difference(at);
    if (age.inMinutes < 60) {
      return _t.navigation.fuel.minutesAgo(n: '${math.max(1, age.inMinutes)}');
    }
    if (age.inHours < 48) return _t.navigation.fuel.hoursAgo(n: '${age.inHours}');
    return _t.navigation.fuel.daysAgo(n: '${age.inDays}');
  }

  /// "+1,2 km · +2 min", or "sur le trajet" for a station by the road.
  String detour(double metres, double seconds, DistanceUnits units) => metres < 100
      ? _t.navigation.fuel.onRoute
      : _t.navigation.fuel.detour(
          distance: routeDistance(metres, units),
          minutes: '${math.max(1, (seconds / 60).round())}',
        );

  /// What the "add a stop" button says once the detour is known.
  String addStop(StopQuote? quote, {required bool quoting}) {
    if (quoting) return _t.navigation.stops.quoting;
    final extra = quote?.extraS;
    if (extra == null) return _t.navigation.stops.add;
    final minutes = (extra / 60).round();
    return minutes < 1
        ? _t.navigation.stops.addFree
        : _t.navigation.stops.addCost(minutes: '$minutes');
  }

  /// "Fourgon aménagé · H 2,65 m · l 2,05 m · L 6,0 m · 3,5 t": the vehicle
  /// a route is computed for, as the user entered it.
  String vehicleSummary(Vehicle v) {
    final type = switch (v.type) {
      VehicleType.van => vehicle.types.van,
      VehicleType.campervan => vehicle.types.campervan,
      VehicleType.lowProfile => vehicle.types.lowProfile,
      VehicleType.overcab => vehicle.types.overcab,
      VehicleType.integrated => vehicle.types.integrated,
    };
    final parts = [
      type,
      if (v.heightM != null) vehicle.heightShort(value: metres(v.heightM!)),
      if (v.widthM != null) vehicle.widthShort(value: metres(v.widthM!)),
      if (v.lengthM != null)
        vehicle.lengthShort(value: '${NumberFormat('0.0', _locale).format(v.lengthM)} m'),
      if (v.weightT != null) tonnes(v.weightT!),
    ];
    // A figure never breaks from its unit at the end of a line.
    final line = parts.map((p) => p.replaceAll(' ', '\u00a0')).join(' · ');
    return v.towing == Towing.none ? line : _t.navigation.preview.vehicleTowing(vehicle: line);
  }

  /// "height, width": the figures a route still needs.
  String dimensionList(Set<MissingDimension> dims) => [
    for (final d in MissingDimension.values)
      if (dims.contains(d))
        switch (d) {
          MissingDimension.height => _t.navigation.states.dimension.height,
          MissingDimension.width => _t.navigation.states.dimension.width,
          MissingDimension.length => _t.navigation.states.dimension.length,
          MissingDimension.weight => _t.navigation.states.dimension.weight,
        },
  ].join(', ');
}

double _half(double v) => (v * 2).round() / 2;

/// The guidance's sentences from the app's translations.
final class TranslatedWording implements GuidanceWording {
  const new(this.t, this.units);

  final Translations t;
  final DistanceUnits units;

  @override
  BackgroundNotice get notice => BackgroundNotice(
    title: t.navigation.guidance.notificationTitle,
    text: t.navigation.guidance.notificationText,
    channel: t.navigation.guidance.notificationChannel,
  );

  @override
  String get rerouting => t.navigation.voice.rerouting;

  @override
  String rerouted(Duration? extra) {
    final minutes = extra == null ? 0 : (extra.inSeconds / 60).round();
    return minutes >= 1
        ? t.navigation.voice.reroutedLonger(minutes: minutes)
        : t.navigation.voice.rerouted;
  }

  @override
  String closureAhead(RoadEventFinding finding) =>
      t.navigation.voice.closureAhead(distance: t.spokenDistance(finding.aheadM, units));

  @override
  String noDetour(RoadEventFinding finding) =>
      t.navigation.voice.noDetour(distance: t.spokenDistance(finding.aheadM, units));

  @override
  String warningAhead(RouteWarning warning, double aheadM) {
    final distance = t.spokenDistance(aheadM, units);
    final limit = warning.limit;
    return switch (warning.kind) {
      RouteWarningKind.lowClearance when limit != null => t.navigation.voice.clearance(
        height: t.spokenSize(limit),
        distance: distance,
      ),
      RouteWarningKind.unknownClearance => t.navigation.voice.unknownClearance(distance: distance),
      RouteWarningKind.narrow when limit != null => t.navigation.voice.narrow(
        width: t.spokenSize(limit),
        distance: distance,
      ),
      _ => t.navigation.voice.limit(what: t.warningTitle(warning), distance: distance),
    };
  }

  @override
  String get arrived => t.navigation.voice.arrived;

  @override
  String aid(DrivingAids aids) {
    final alert = aids.alert;
    return switch (aids.wordKind) {
      AidWord.overSpeed => t.navigation.voice.overSpeed(
        limit: switch (aids.limit) {
          null => '',
          final l => '${t.speedIn(l.kmh, units)}',
        },
      ),
      AidWord.camera when alert != null => t.navigation.voice.camera(
        distance: t.spokenDistance(alert.aheadM, units),
      ),
      AidWord.zone when alert != null =>
        alert.inside
            ? t.navigation.voice.inDangerZone
            : t.navigation.voice.dangerZone(distance: t.spokenDistance(alert.aheadM, units)),
      _ => '',
    };
  }
}
