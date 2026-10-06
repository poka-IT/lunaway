import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The road events of a route in its preview: the closures it was planned
/// around, then those met on the way, each with its road, how far from the
/// start, its source and the time of that source's data. None known says so,
/// as the limits of the vehicle do.
class RoadEventsSection extends ConsumerWidget {
  const new({required this.plan, required this.route, required this.units, super.key});

  final RoutePlan plan;
  final RouteOption? route;
  final DistanceUnits units;

  /// Rows shown before "and N more": a long trip crosses many works.
  static const shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(clockProvider)().toLocal();
    final met = route?.roadEvents ?? const <RouteRoadEvent>[];
    final avoided = plan.avoidedRoadEvents;
    if (met.isEmpty && avoided.isEmpty) {
      // A server without road events says nothing of them; sources gone
      // stale make "none known" a weak promise, and say so.
      if (plan.roadEventSources.isEmpty) return const SizedBox.shrink();
      final fresh = plan.roadEventSources.any((s) => s.freshAt(now.toUtc()));
      return Row(
        children: [
          Icon(
            fresh ? AppIcons.checkCircle : AppIcons.warning,
            color: fresh ? scheme.secondary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              fresh ? t.navigation.roadEvents.none : t.navigation.roadEvents.stale,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }
    String sourceLine(String id, DateTime? at) {
      final status = plan.sourceOf(id);
      return t.roadDataSource(
        status?.attribution ?? status?.name ?? id,
        at ?? status?.dataAt ?? status?.lastReadAt,
        now,
      );
    }

    final names = {for (final e in avoided) e.road ?? t.roadEventWhat(e.eventClass)}.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(t.navigation.roadEvents.title, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: Space.xs),
        if (avoided.isNotEmpty)
          _EventRow(
            icon: AppIcons.roadEvent(RoadEventClass.closure),
            title: t.navigation.roadEvents.avoided(n: avoided.length, names: names),
            detail: {for (final e in avoided) sourceLine(e.source, null)}.join('\n'),
          ),
        for (final e in met.take(shown))
          _EventRow(
            icon: AppIcons.roadEvent(e.event.eventClass),
            strong: e.weight != RoadEventWeight.info,
            title: [
              [?e.event.road, t.roadEventWhat(e.event.eventClass)].join(' · '),
              ?t.roadEventQualifier(e.reason),
            ].join(', '),
            detail: [
              t.navigation.roadEvents.atDistance(
                distance: t.routeDistance(e.distanceFromStartM, units),
              ),
              sourceLine(e.event.source, e.dataAt),
            ].join(' · '),
          ),
        if (met.length > shown)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Text(
              t.navigation.roadEvents.more(n: met.length - shown),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// The road events that stopped every route, under "no safe route".
class RoadEventBlockers extends ConsumerWidget {
  const new({required this.plan, super.key});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final now = ref.watch(clockProvider)().toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in plan.roadEventBlockers)
          _EventRow(
            icon: AppIcons.roadEvent(e.event.eventClass),
            strong: true,
            title: [
              [?e.event.road, t.roadEventWhat(e.event.eventClass)].join(' · '),
              ?t.roadEventQualifier(e.reason),
            ].join(', '),
            detail: t.roadDataSource(
              plan.sourceOf(e.event.source)?.attribution ?? e.event.source,
              e.dataAt,
              now,
            ),
          ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const new({required this.icon, required this.title, required this.detail, this.strong = false});

  final IconData icon;
  final String title;
  final String detail;

  /// Worth a look on the way, rather than for information.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: strong ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(LunaTokens.radiusM),
            ),
            child: Icon(
              icon,
              size: 20,
              color: strong ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: Space.hair),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
