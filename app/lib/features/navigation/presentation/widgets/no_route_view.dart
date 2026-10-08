import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_marks_overlay.dart';
import 'package:lunaway/features/navigation/presentation/widgets/stops_strip.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Why a trip has no route, stop by stop, in plain words: which stop the
/// vehicle cannot reach and what keeps it out ("Destination inaccessible
/// avec votre véhicule : pont à 3,20 m"), with the vehicle's own figure;
/// then what helps, the first action as the screen's primary one.
class NoRouteExplanation extends ConsumerWidget {
  const new({
    required this.reasons,
    required this.target,
    required this.stops,
    required this.avoid,
    required this.coveredCountries,
    super.key,
  });

  final List<NoRouteReason> reasons;
  final RouteTarget target;

  /// The waypoints the trip was asked with, in order.
  final List<RouteStop> stops;

  /// The options the trip was asked with.
  final AvoidOptions avoid;

  /// The countries routes cover, named when a stop lies outside them.
  final List<String> coveredCountries;

  /// The index of the destination: the origin is 0, the waypoints follow.
  int get _last => stops.length + 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final actions = _actions(context, ref);
    final hints = _hints(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in reasons.indexed) ...[
          if (i > 0) const SizedBox(height: Space.l),
          // Tied to the marks of what keeps the vehicle out, where the
          // server placed them.
          switch ([
            for (final l in r.limits)
              if (l.restriction case final w?) limitMarkId(w),
          ]) {
            final List<String> marks when marks.isNotEmpty => MarkLinkedRow(
              target: target,
              marks: marks,
              child: _Reason(
                reason: r,
                lastStop: _last,
                stops: stops,
                coveredCountries: coveredCountries,
              ),
            ),
            _ => _Reason(
              reason: r,
              lastStop: _last,
              stops: stops,
              coveredCountries: coveredCountries,
            ),
          },
        ],
        if (actions.isNotEmpty || hints.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Text(t.navigation.states.whatToDo, style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.s),
          for (final (i, (label, onPressed)) in actions.indexed) ...[
            if (i > 0) const SizedBox(height: Space.s),
            // One primary action: the one most likely to help.
            if (i == 0)
              FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(label, textAlign: TextAlign.center),
              )
            else
              OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(label, textAlign: TextAlign.center),
              ),
          ],
          if (hints.isNotEmpty) const SizedBox(height: Space.s),
          for (final h in hints) _Hint(h),
        ],
      ],
    );
  }

  bool _vehicleKind(NoRouteReasonKind k) =>
      k == NoRouteReasonKind.originUnreachable ||
      k == NoRouteReasonKind.destinationUnreachable ||
      k == NoRouteReasonKind.waypointUnreachable ||
      k == NoRouteReasonKind.blockedOnTheWay;

  /// The reasons of the stops [which] picks by index.
  Iterable<NoRouteReason> _at(bool Function(int index) which) =>
      reasons.where((r) => r.stopIndex != null && which(r.stopIndex!));

  List<(String, VoidCallback)> _actions(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final out = <(String, VoidCallback)>[];
    final sizes = reasons.any(
      (r) =>
          _vehicleKind(r.kind) &&
          (r.limits.isEmpty || r.limits.any((l) => l.kind != VehicleLimitKind.unpaved)),
    );
    final unpaved =
        avoid.unpaved &&
        reasons.any(
          (r) =>
              r.limits.any((l) => l.kind == VehicleLimitKind.unpaved) ||
              (_vehicleKind(r.kind) && r.limits.isEmpty) ||
              r.kind == NoRouteReasonKind.noRoadNearby,
        );
    if (sizes) out.add((t.navigation.noRoute.editVehicle, () => showVehicleEditor(context)));
    if (unpaved) {
      out.add((
        t.navigation.noRoute.allowUnpaved,
        () => unawaited(
          ref
              .read(routeSettingsControllerProvider.notifier)
              .setAvoid(avoid.copyWith(unpaved: false)),
        ),
      ));
    }
    // A waypoint that cannot be reached is taken out in one tap, with the
    // way back the message offers.
    final waypoints = {for (final r in _at((i) => i > 0 && i < _last)) r.stopIndex!};
    for (final i in waypoints.toList()..sort()) {
      final stop = stops[i - 1];
      out.add((
        switch (stop.label) {
          final name? => t.navigation.noRoute.removeStopNamed(name: name),
          null => t.navigation.noRoute.removeStop(n: '$i'),
        },
        () => changeStops(context, target, [...stops]..remove(stop), t.navigation.stops.removed),
      ));
    }
    final destination = _at((i) => i >= _last)
        .any((r) => r.kind != NoRouteReasonKind.outsideCoverage);
    if (destination) {
      out.add((t.navigation.noRoute.placesAround, () => _placesAround(context, ref)));
    }
    return out;
  }

  List<String> _hints(Translations t) {
    final destination = _at((i) => i >= _last);
    return [
      if (destination.any((r) => r.kind != NoRouteReasonKind.outsideCoverage))
        t.navigation.noRoute.moveDestination,
      if (destination.any((r) => r.kind == NoRouteReasonKind.outsideCoverage) &&
          coveredCountries.isNotEmpty)
        t.navigation.noRoute.pickInside,
      if (_at((i) => i > 0 && i < _last).isNotEmpty) t.navigation.noRoute.moveStop,
      if (_at((i) => i == 0).any((r) => r.kind != NoRouteReasonKind.outsideCoverage))
        t.navigation.noRoute.moveOrigin,
      if (reasons.any((r) => r.kind == NoRouteReasonKind.tripTooLong)) t.navigation.noRoute.shorter,
    ];
  }

  /// The map around the destination, its list of places nearby with it.
  void _placesAround(BuildContext context, WidgetRef ref) {
    // Read before leaving: this screen's ref goes with it.
    final map = ref.read(mapControllerProvider);
    leaveForMap(context);
    unawaited(map?.moveTo(target.destination, zoom: 12));
  }
}

/// One reason: the stop and what keeps it out, then the figures behind it.
class _Reason extends StatelessWidget {
  const new({
    required this.reason,
    required this.lastStop,
    required this.stops,
    required this.coveredCountries,
  });

  final NoRouteReason reason;
  final int lastStop;
  final List<RouteStop> stops;
  final List<String> coveredCountries;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final at = reason.stopIndex;
    final label = at != null && at > 0 && at < lastStop ? stops[at - 1].label : null;
    final lines = <String>[
      ?label,
      ...switch (reason.kind) {
        NoRouteReasonKind.blockedOnTheWay => [t.navigation.noRoute.blockedHint],
        NoRouteReasonKind.notConnected => [t.navigation.noRoute.notConnectedHint],
        NoRouteReasonKind.noRoadNearby => [t.navigation.noRoute.noRoadHint],
        NoRouteReasonKind.outsideCoverage => [
          if (coveredCountries.isEmpty)
            t.navigation.noRoute.outsideHintUnknown
          else
            t.navigation.noRoute.outsideHint(countries: t.countryList(coveredCountries)),
        ],
        NoRouteReasonKind.tripTooLong => [
          t.navigation.noRoute.tooLongHint(
            trip: t.distance((reason.tripKm ?? 0) * 1000),
            max: t.distance((reason.maxKm ?? 0) * 1000),
          ),
        ],
        _ => const <String>[],
      },
    ];
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                child: Icon(_icon(reason), color: scheme.onError, size: 22),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  t.noRouteTitle(reason, lastStop: lastStop),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
          for (final l in reason.limits)
            if (l.vehicleValue != null || l.restriction != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (l.vehicleValue case final value?)
                      Text(
                        t.navigation.noRoute.vehicleValue(value: t.blockingFigure(l.kind, value)),
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (l.restriction case final r?)
                      Text([?r.name, t.warningSource(r)].join(' · '), style: muted),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static IconData _icon(NoRouteReason r) {
    final kind = r.limits.firstOrNull?.kind;
    return switch (r.kind) {
      NoRouteReasonKind.outsideCoverage || NoRouteReasonKind.tripTooLong => AppIcons.map,
      NoRouteReasonKind.noRoadNearby || NoRouteReasonKind.notConnected => AppIcons.gone,
      _ => switch (kind) {
        VehicleLimitKind.height => AppIcons.height,
        VehicleLimitKind.width => AppIcons.width,
        VehicleLimitKind.length => AppIcons.length,
        VehicleLimitKind.weight => AppIcons.weight,
        VehicleLimitKind.unpaved || null => AppIcons.vehicle,
      },
    };
  }
}

class _Hint extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Icon(AppIcons.chevron, size: 18, color: theme.colorScheme.secondary),
          ),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// The places the map should mark for a trip without a route: each known
/// restriction that keeps the vehicle out.
List<LatLng> blockingPositions(List<NoRouteReason> reasons) => [
  for (final r in reasons)
    for (final l in r.limits)
      if (l.restriction case final w?) w.position,
];
