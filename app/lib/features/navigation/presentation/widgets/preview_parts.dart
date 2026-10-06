import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
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
  const new({required this.steps, required this.units, super.key});

  final List<RouteStep> steps;
  final DistanceUnits units;

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
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.navigation.preview.roadbook, style: theme.textTheme.titleMedium),
          trailing: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? AppIcons.zoomOut : AppIcons.chevronDown),
            label: Text(
              _open ? t.navigation.preview.roadbookHide : t.navigation.preview.roadbookShow,
            ),
          ),
        ),
        if (_open)
          for (final step in widget.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManeuverIcon(
                    type: step.maneuverType,
                    modifier: step.modifier,
                    size: 32,
                    color: scheme.secondary,
                  ),
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
      ],
    );
  }
}

/// Where the route's data comes from and when it was read, the sources'
/// attribution, and the disclaimer every route carries: the text of the
/// API's key `routing.disclaimer.v1`, the one this app knows. A newer key
/// from a newer server still shows this text, the same warning in its
/// earlier words, rather than none.
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
        Text(t.navigation.preview.disclaimer, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Space.s),
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
