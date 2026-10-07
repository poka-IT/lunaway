import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/presentation/place_form.dart';
import 'package:lunaway/features/navigation/presentation/road_report_sheet.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/poi/presentation/add_vending.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// A point the user long-pressed on the map: its coordinates to copy, and the
/// way there.
class PointDetails extends StatelessWidget {
  const new({
    required this.position,
    this.scrollController,
    this.onClose,
    this.actions = false,
    this.bottomPadding = Space.huge,
    super.key,
  });

  final LatLng position;
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  /// The action bar at the foot of the content (a panel).
  final bool actions;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, bottomPadding),
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(52 * 0.32),
              ),
              child: Icon(AppIcons.point, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: Space.ml),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(t.map.pointTitle, style: theme.textTheme.headlineSmall),
                  ),
                  Text(
                    t.map.pointHint,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: t.common.close,
                onPressed: onClose,
                style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                icon: const Icon(AppIcons.close, size: 20),
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        // A point on the map is where a missing place goes: the second
        // gesture of adding one (the first was the long press).
        Consumer(
          // Outlined: the route below stays the one primary action.
          builder: (context, ref, _) => OutlinedButton.icon(
            onPressed: () => startAddPlace(context, ref, position),
            icon: const Icon(AppIcons.addPlace),
            label: Text(t.contribute.addPlaceHere),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ),
        const SizedBox(height: Space.l),
        VendingQuickAdd(position: position),
        const SizedBox(height: Space.l),
        CoordinatesCard(position: position),
        const SizedBox(height: Space.l),
        // What is seen on the road there: a closure, works, a low bridge.
        OutlinedButton.icon(
          onPressed: () => reportOnRoad(context, position: position),
          icon: const Icon(AppIcons.report),
          label: Text(t.roadReport.fromMap),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    );
    if (!actions) return body;
    return Column(
      children: [
        Expanded(child: body),
        PointActionBar(position: position),
      ],
    );
  }
}

/// The actions of a point: the route there, and its coordinates to copy.
class PointActionBar extends ConsumerWidget {
  const new({required this.position, this.floating = false, super.key});

  final LatLng position;
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => openDirections(context, position),
              onLongPress: () => openInOtherApp(context, ref, position, choose: true),
              icon: const Icon(AppIcons.directions),
              label: Text(t.place.directions, maxLines: 2, textAlign: TextAlign.center),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => copyCoordinates(context, ref, position),
              icon: const Icon(AppIcons.copy),
              label: Text(t.place.copyShort, maxLines: 2, textAlign: TextAlign.center),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
            ),
          ),
        ],
      ),
    );
    if (!floating) {
      return LiftsMessages(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(top: false, child: row),
        ),
      );
    }
    return LiftsMessages(
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: Space.s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
              boxShadow: LunaTokens.of(context).floatingShadow,
            ),
            child: Material(type: MaterialType.transparency, child: row),
          ),
        ),
      ),
    );
  }
}
