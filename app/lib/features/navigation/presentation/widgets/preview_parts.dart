import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/ferry_section.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The vehicle the route is computed for, editable in place: the route
/// follows the vehicle, so a change computes it again.
class VehicleLine extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vehicle = ref.watch(vehicleProvider).value;
    return Row(
      children: [
        Icon(AppIcons.vehicle, color: scheme.onSurfaceVariant),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.navigation.preview.vehicle, style: theme.textTheme.labelMedium),
              Text(
                vehicle == null ? t.vehicle.none : t.vehicleSummary(vehicle),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => showVehicleEditor(context),
          child: Text(t.navigation.preview.editVehicle),
        ),
      ],
    );
  }
}

/// The steps of a route, folded by default: the map tells most of it, the
/// list is there for those who like to read the road ahead.
class Roadbook extends StatefulWidget {
  const new({required this.steps, required this.units, this.ferries = const [], super.key});

  final List<RouteStep> steps;
  final DistanceUnits units;

  /// The route's crossings, each shown among the steps where it begins.
  final List<FerryCrossing> ferries;

  @override
  State<Roadbook> createState() => _RoadbookState();
}

class _RoadbookState extends State<Roadbook> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The whole line opens and closes the list. The label goes under
        // the title when both do not fit side by side, so a long title
        // ("Routebeschrijving") is never cut in two, at any text size.
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(LunaTokens.radiusM),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Space.s,
                    runSpacing: Space.xxs,
                    children: [
                      Text(t.navigation.preview.roadbook, style: theme.textTheme.titleMedium),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _open
                                  ? t.navigation.preview.roadbookHide
                                  : t.navigation.preview.roadbookShow,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                            ),
                          ),
                          const SizedBox(width: Space.xs),
                          AnimatedRotation(
                            turns: _open ? 0.5 : 0,
                            duration: Motion.of(context, Motion.short),
                            child: Icon(AppIcons.chevronDown, color: scheme.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_open)
          for (final (step, crossings) in _withCrossings()) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManeuverIcon(maneuver: step.maneuver, size: 32, color: scheme.secondary),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.instruction, style: theme.textTheme.bodyMedium),
                        if (step.distanceM > 0)
                          Text(
                            t.routeDistance(step.distanceM, widget.units),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final f in crossings) FerryTile(crossing: f, units: widget.units, iconSize: 32),
          ],
      ],
    );
  }

  /// Each step with the crossings that begin along its road: a step runs
  /// from its maneuver over [RouteStep.distanceM]. The boarding falls on
  /// the start of the ferry's own step; a few metres of rounding between
  /// the two sums would put it on the step before, hence the margin.
  List<(RouteStep, List<FerryCrossing>)> _withCrossings() {
    final steps = widget.steps;
    final left = [...widget.ferries]
      ..sort((a, b) => a.distanceFromStartM.compareTo(b.distanceFromStartM));
    final out = <(RouteStep, List<FerryCrossing>)>[];
    var start = 0.0;
    for (final (i, step) in steps.indexed) {
      final end = start + step.distanceM;
      final last = i == steps.length - 1;
      final here = [
        for (final f in left)
          if (last || f.distanceFromStartM < end - 5) f,
      ];
      left.removeWhere(here.contains);
      out.add((step, here));
      start = end;
    }
    return out;
  }
}

/// Where the route's data comes from and when it was read, with the
/// sources' attribution. What the data may miss is said once, in the
/// profile's "About", not before every trip.
class RouteDataNote extends StatelessWidget {
  const new({required this.graph, super.key});

  final RoutingGraphInfo graph;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = DateFormat.yMMMMd(t.$meta.locale.languageCode);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.navigation.preview.dataOf(date: date.format(graph.osmDataAt.toLocal())),
          style: muted,
        ),
        Text(t.navigation.preview.attributionOsm, style: muted),
        if (graph.ignEdition != null)
          Text(
            t.navigation.preview.attributionIgn(date: date.format(graph.ignEdition!)),
            style: muted,
          ),
      ],
    );
  }
}
