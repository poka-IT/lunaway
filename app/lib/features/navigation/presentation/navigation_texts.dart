import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/location_feed.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
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

  /// The figure of a restriction as the voice says it: "3,5 tonnes",
  /// "12 mètres", never a symbol it would spell out.
  String spokenLimitFigure(RouteWarningKind kind, double value) => switch (kind) {
    RouteWarningKind.tooHeavy ||
    RouteWarningKind.axleLoad ||
    RouteWarningKind.goodsVehicleWeight => spokenTonnes(value),
    _ => spokenSize(value),
  };

  /// "Low bridge 2.70 m", "Height bar 1.90 m", "No motorhomes"; a limit
  /// that spares local access says so ("Accès riverains (desserte) :
  /// interdit aux plus de 3,5 t sauf pour rejoindre votre destination").
  /// [spoken] writes the figure as the voice says it.
  String warningTitle(RouteWarning w, {bool spoken = false}) {
    final value = w.limit;
    final limit = value == null
        ? ''
        : spoken
        ? spokenLimitFigure(w.kind, value)
        : limitFigure(w.kind, value);
    if (w.exceptDestination && w.limit != null) {
      final localAccess = switch (w.kind) {
        RouteWarningKind.tooHeavy => _t.navigation.warning.localAccess.weight(limit: limit),
        RouteWarningKind.axleLoad => _t.navigation.warning.localAccess.axleLoad(limit: limit),
        RouteWarningKind.narrow => _t.navigation.warning.localAccess.width(limit: limit),
        RouteWarningKind.tooLong => _t.navigation.warning.localAccess.length(limit: limit),
        _ => null,
      };
      if (localAccess != null) return localAccess;
    }
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

  /// What keeps the vehicle out, mid-sentence: "pont à 3,20 m", "poids
  /// limité à 1,5 t", "route non revêtue".
  String blockingLimit(BlockingLimit l) {
    final value = l.limit;
    if (value == null) {
      return switch (l.kind) {
        VehicleLimitKind.height => _t.navigation.noRoute.limit.heightUnknown,
        VehicleLimitKind.width => _t.navigation.noRoute.limit.widthUnknown,
        VehicleLimitKind.length => _t.navigation.noRoute.limit.lengthUnknown,
        VehicleLimitKind.weight => _t.navigation.noRoute.limit.weightUnknown,
        VehicleLimitKind.unpaved => _t.navigation.noRoute.limit.unpaved,
      };
    }
    final limit = blockingFigure(l.kind, value);
    if (l.restriction?.exceptDestination ?? false) {
      final localAccess = switch (l.kind) {
        VehicleLimitKind.weight => _t.navigation.noRoute.limit.weightLocalAccess(limit: limit),
        VehicleLimitKind.width => _t.navigation.noRoute.limit.widthLocalAccess(limit: limit),
        VehicleLimitKind.length => _t.navigation.noRoute.limit.lengthLocalAccess(limit: limit),
        VehicleLimitKind.height || VehicleLimitKind.unpaved => null,
      };
      if (localAccess != null) return localAccess;
    }
    return switch (l.kind) {
      VehicleLimitKind.height => switch (l.restriction?.place) {
        RestrictionPlace.underpass => _t.navigation.noRoute.limit.underpass(limit: limit),
        RestrictionPlace.tunnel => _t.navigation.noRoute.limit.tunnel(limit: limit),
        RestrictionPlace.buildingPassage => _t.navigation.noRoute.limit.buildingPassage(
          limit: limit,
        ),
        RestrictionPlace.bridge => _t.navigation.noRoute.limit.bridge(limit: limit),
        RestrictionPlace.barrier => _t.navigation.noRoute.limit.barrier(limit: limit),
        RestrictionPlace.road || null => _t.navigation.noRoute.limit.height(limit: limit),
      },
      VehicleLimitKind.width => _t.navigation.noRoute.limit.width(limit: limit),
      VehicleLimitKind.length => _t.navigation.noRoute.limit.length(limit: limit),
      VehicleLimitKind.weight => _t.navigation.noRoute.limit.weight(limit: limit),
      VehicleLimitKind.unpaved => _t.navigation.noRoute.limit.unpaved,
    };
  }

  /// A blocking figure in its own unit: tonnes for a weight, metres else.
  String blockingFigure(VehicleLimitKind kind, double value) =>
      kind == VehicleLimitKind.weight ? tonnes(value) : metres(value);

  /// The headline of a reason a trip has no route, naming the stop: the
  /// origin is stop 0, the destination [lastStop], the waypoints between.
  String noRouteTitle(NoRouteReason r, {required int lastStop}) {
    final at = r.stopIndex;
    final origin = at == 0;
    final destination = at == null || at >= lastStop;
    final n = '${at ?? 0}';
    final limits = r.limits.map(blockingLimit).join(', ');
    final by = limits.isNotEmpty;
    return switch (r.kind) {
      NoRouteReasonKind.originUnreachable =>
        by
            ? _t.navigation.noRoute.originUnreachableBy(limit: limits)
            : _t.navigation.noRoute.originUnreachable,
      NoRouteReasonKind.destinationUnreachable =>
        by
            ? _t.navigation.noRoute.destinationUnreachableBy(limit: limits)
            : _t.navigation.noRoute.destinationUnreachable,
      NoRouteReasonKind.waypointUnreachable =>
        by
            ? _t.navigation.noRoute.waypointUnreachableBy(n: n, limit: limits)
            : _t.navigation.noRoute.waypointUnreachable(n: n),
      NoRouteReasonKind.blockedOnTheWay =>
        by
            ? _t.navigation.noRoute.blockedOnTheWayBy(limit: limits)
            : _t.navigation.noRoute.blockedOnTheWay,
      NoRouteReasonKind.notConnected =>
        at == null
            ? _t.navigation.noRoute.notConnectedTrip
            : origin
            ? _t.navigation.noRoute.notConnectedOrigin
            : destination
            ? _t.navigation.noRoute.notConnectedDestination
            : _t.navigation.noRoute.notConnectedWaypoint(n: n),
      NoRouteReasonKind.outsideCoverage =>
        origin
            ? _t.navigation.noRoute.outsideOrigin
            : destination
            ? _t.navigation.noRoute.outsideDestination
            : _t.navigation.noRoute.outsideWaypoint(n: n),
      NoRouteReasonKind.noRoadNearby =>
        origin
            ? _t.navigation.noRoute.noRoadOrigin
            : destination
            ? _t.navigation.noRoute.noRoadDestination
            : _t.navigation.noRoute.noRoadWaypoint(n: n),
      NoRouteReasonKind.tripTooLong => _t.navigation.noRoute.tooLong,
    };
  }

  /// Countries by name, in the reader's alphabetical order. The
  /// territories inside or beside a listed country (Åland, Svalbard,
  /// Gibraltar, Monaco, San Marino, the Vatican) are left out: a list read
  /// at arm's length names the countries a trip is planned by.
  String countryList(Iterable<String> codes) {
    final names =
        codes
            .where((c) => !_withinAnother.contains(c.toUpperCase()))
            .map(countryName)
            .toSet()
            .toList()
          ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
    return names.join(', ');
  }

  /// "Ferry Nice - Ajaccio", or "Ferry" for a line without a name.
  String ferryTitle(FerryCrossing f) => switch (f.name) {
    final name? when name.trim().isNotEmpty => _t.navigation.ferry.named(name: name.trim()),
    _ => _t.navigation.ferry.unnamed,
  };

  /// The ports and countries of a crossing, each line when known.
  List<String> ferryDetails(FerryCrossing f, DistanceUnits units) {
    final from = f.fromCountry;
    final to = f.toCountry;
    return [
      if (f.ports.isNotEmpty) _t.navigation.ferry.ports(ports: f.ports.join(', ')),
      if (from != null && to != null && from != to)
        _t.navigation.ferry.countries(from: countryName(from), to: countryName(to))
      else if (from ?? to case final one?)
        _t.navigation.ferry.country(country: countryName(one)),
      _t.navigation.ferry.where(
        distance: routeDistance(f.distanceFromStartM, units),
        sea: routeDistance(f.distanceM, units),
        duration: routeDuration(f.durationS),
      ),
    ];
  }

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
    // The plural follows the whole metres: "1 mètre 90", "3 mètres 20".
    if (cm == 0) return _t.navigation.voice.sizeWhole(count: whole, metres: '$whole');
    return _t.navigation.voice.size(
      count: whole,
      metres: '$whole',
      cm: cm.toString().padLeft(2, '0'),
    );
  }

  /// The arrival time, "15:42" or "3:42 PM".
  String clockTime(DateTime at) => DateFormat.jm(_locale).format(at);

  /// "6 oct.", "Oct 6".
  String dayMonth(DateTime at) => DateFormat.MMMd(_locale).format(at);

  /// "Délégation à la sécurité routière, liste du 6 oct.": a list of speed
  /// cameras by its licensor ([listName]), with the date it gives of its
  /// last update, else of its last read (the Licence Ouverte of the French
  /// list asks for both); its year as well when it is not this year's
  /// ("liste du 30 déc. 2025"). For the guidance banner and a camera's
  /// callout, where the lists hold one line: the full attributions
  /// ([EnforcementSource.credit]) stay in the route preview.
  String enforcementSource(EnforcementSource s, {required DateTime now}) =>
      _t.navigation.guidance.enforcementSource(
        source: listName(s),
        date: listDate(s, now: now),
      );

  /// The name of a list of speed cameras in the app's language: its
  /// licensor, named as in the credits (a proper name stays as written);
  /// the name the API gives (in French) for a list this app does not know
  /// yet.
  String listName(EnforcementSource s) => switch (s.id) {
    'securite-routiere' => _t.navigation.enforcement.listSecuriteRoutiere,
    'fr-dsr' => _t.navigation.enforcement.listDsr,
    'pl-canard' => _t.navigation.enforcement.listGitd,
    'lu-pch-radars' => _t.navigation.enforcement.listPontsEtChaussees,
    'be-bru-radars' => _t.navigation.enforcement.listBrusselsMobility,
    'no-nvdb-atk' => _t.navigation.enforcement.listStatensVegvesen,
    'ie-garda' => _t.navigation.enforcement.listGarda,
    'osm' => _t.navigation.enforcement.listOsm,
    _ => s.name,
  };

  /// The date a list of speed cameras gives of its last update, else of
  /// its last read: "6 oct.", with its year when it is not [now]'s ("30
  /// déc. 2025"), both read on this device's calendar.
  String listDate(EnforcementSource s, {required DateTime now}) {
    final at = (s.listUpdatedAt ?? s.fetchedAt).toLocal();
    return at.year == now.toLocal().year ? dayMonth(at) : DateFormat.yMMMd(_locale).format(at);
  }

  /// "Radar fixe", "Radar tronçon": what a camera controls; "Radar" for a
  /// kind this app does not know.
  String cameraKind(CameraCategory? category) => switch (category) {
    CameraCategory.fixed => _t.navigation.enforcement.fixed,
    CameraCategory.redLight => _t.navigation.enforcement.redLight,
    CameraCategory.levelCrossing => _t.navigation.enforcement.levelCrossing,
    CameraCategory.section => _t.navigation.enforcement.section,
    null => _t.navigation.marks.kindCamera,
  };

  /// "Radar fixe · 90 km/h", "Radar tronçon · moyenne 110 km/h": a camera
  /// and the limit it controls, in the user's units.
  String cameraTitle(EnforcementItem item, DistanceUnits units) {
    final kind = cameraKind(item.cameraCategory);
    final limit = item.controlledLimitKmh;
    if (limit == null) return kind;
    final speed = speedLimit(limit, units);
    return '$kind · ${item.isSection ? _t.navigation.enforcement.average(limit: speed) : speed}';
  }

  /// What the banner of the aids names: a zone, or a camera by its kind.
  String alertKind(EnforcementAlert alert) => alert.kind == EnforcementKind.zone
      ? _t.navigation.enforcement.zone
      : cameraKind(alert.category);

  /// "Espagne : radars": the rule of the country the vehicle just entered.
  String ruleChange(RuleChange change) {
    final country = countryName(change.country);
    return switch (change.mode) {
      EnforcementMode.exact => _t.navigation.enforcement.ruleExact(country: country),
      EnforcementMode.zones => _t.navigation.enforcement.ruleZones(country: country),
      EnforcementMode.off ||
      EnforcementMode.offWhileDriving => _t.navigation.enforcement.ruleOff(country: country),
    };
  }

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

  /// "Point d'arrivée déplacé de 120 m vers la rue accessible la plus
  /// proche": a stop the server moved, the origin being stop 0 and the
  /// destination [lastStop].
  String movedStop(MovedStop m, {required int lastStop, required DistanceUnits units}) {
    final distance = routeDistance(m.distanceM, units);
    if (m.stopIndex == 0) return _t.navigation.preview.moved.origin(distance: distance);
    if (m.stopIndex >= lastStop) {
      return _t.navigation.preview.moved.destination(distance: distance);
    }
    return _t.navigation.preview.moved.stop(n: '${m.stopIndex}', distance: distance);
  }

  /// "3,5 tonnes", as spoken.
  String spokenTonnes(double value) {
    // The plural follows the figure said, to the tenth: 1.04 is "1 tonne".
    final said = (value * 10).round() / 10;
    return _t.navigation.voice.tonnes(count: said, n: NumberFormat('0.#', _locale).format(said));
  }

  /// "1,789 €/L": to the tenth of a cent, as stations show it.
  String litrePrice(double euros) =>
      _t.navigation.fuel.price(price: NumberFormat('0.000', _locale).format(euros));

  /// "1,789 €": a price beside its station on the map, where the litre
  /// goes without saying.
  String shortPrice(double euros) =>
      _t.navigation.marks.price(price: NumberFormat('0.000', _locale).format(euros));

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
  String moved(MovedStop move, {required int lastStop}) {
    final distance = t.spokenDistance(move.distanceM, units);
    return move.stopIndex >= lastStop
        ? t.navigation.voice.moved.destination(distance: distance)
        : t.navigation.voice.moved.stop(n: '${move.stopIndex}', distance: distance);
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
    if (warning.exceptDestination && limit != null) {
      // The full path of each key: the translation gate finds them so.
      final said = switch (warning.kind) {
        RouteWarningKind.tooHeavy => t.navigation.voice.localAccess.weight(
          distance: distance,
          limit: t.spokenTonnes(limit),
        ),
        RouteWarningKind.axleLoad => t.navigation.voice.localAccess.axleLoad(
          distance: distance,
          limit: t.spokenTonnes(limit),
        ),
        RouteWarningKind.narrow => t.navigation.voice.localAccess.width(
          distance: distance,
          limit: t.spokenSize(limit),
        ),
        RouteWarningKind.tooLong => t.navigation.voice.localAccess.length(
          distance: distance,
          limit: t.spokenSize(limit),
        ),
        _ => null,
      };
      if (said != null) return said;
    }
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
      _ => t.navigation.voice.limit(
        what: t.warningTitle(warning, spoken: true),
        distance: distance,
      ),
    };
  }

  @override
  String get arrived => t.navigation.voice.arrived;

  @override
  String roadEventAhead(RoadEvent event, double aheadM) {
    final distance = t.spokenDistance(aheadM, units);
    // An event that stops the vehicle has its own sentences: a closure
    // said here is one the server could not place for sure, or outside
    // its hours.
    return switch (event.eventClass) {
      RoadEventClass.works => t.navigation.voice.roadEvent.works(distance: distance),
      RoadEventClass.laneRestriction => t.navigation.voice.roadEvent.lanes(distance: distance),
      RoadEventClass.vehicleLimit => t.navigation.voice.roadEvent.vehicleLimit(distance: distance),
      RoadEventClass.closure => t.navigation.voice.roadEvent.closure(distance: distance),
      RoadEventClass.detour => t.navigation.voice.roadEvent.detour(distance: distance),
    };
  }

  @override
  String get positionLost => t.navigation.voice.positionLost;

  @override
  String aid(AidCall call, DrivingAids aids) {
    final alert = call.alert;
    if (alert == null) {
      return switch (call.word) {
        AidWord.overSpeed => t.navigation.voice.overSpeed(
          limit: switch (aids.limit) {
            null => '',
            final l => '${t.speedIn(l.kmh, units)}',
          },
        ),
        _ => '',
      };
    }
    final distance = t.spokenDistance(alert.aheadM, units);
    final limit = switch (alert.limitKmh) {
      final kmh? when !alert.limitEstimated => '${t.speedIn(kmh, units)}',
      _ => null,
    };
    return switch (call.word) {
      AidWord.overSpeed => t.navigation.voice.overSpeed(limit: limit ?? ''),
      // Entered, or about to be: "Zone de danger.", never "in 0 metres".
      AidWord.zone =>
        alert.inside || alert.aheadM < atHandM
            ? t.navigation.voice.inDangerZone
            : t.navigation.voice.dangerZone(distance: distance),
      AidWord.section when alert.inside => t.navigation.voice.camera.inSection,
      AidWord.section || AidWord.camera => switch ((limit, alert.cameraLimit)) {
        (final l?, true) when alert.isSection => t.navigation.voice.camera.sectionLimit(
          what: _spokenKind(alert.category),
          distance: distance,
          limit: l,
        ),
        (final l?, true) => t.navigation.voice.camera.radarLimit(
          what: _spokenKind(alert.category),
          distance: distance,
          limit: l,
        ),
        _ => t.navigation.voice.camera.radar(what: _spokenKind(alert.category), distance: distance),
      },
      AidWord.slowDown => switch ((limit, alert.cameraLimit)) {
        (final l?, true) => t.navigation.voice.camera.slowDownRadar(limit: l),
        (final l?, false) => t.navigation.voice.camera.slowDownRoad(limit: l),
        (null, _) => '',
      },
    };
  }

  /// A camera's kind as it falls in a spoken sentence.
  String _spokenKind(CameraCategory? category) => switch (category) {
    CameraCategory.fixed => t.navigation.voice.camera.kind.fixed,
    CameraCategory.redLight => t.navigation.voice.camera.kind.redLight,
    CameraCategory.levelCrossing => t.navigation.voice.camera.kind.levelCrossing,
    CameraCategory.section => t.navigation.voice.camera.kind.section,
    null => t.navigation.voice.camera.kind.other,
  };
}

/// Territories named with the country they lie in or beside.
const _withinAnother = {'AX', 'SJ', 'GI', 'MC', 'SM', 'VA'};
