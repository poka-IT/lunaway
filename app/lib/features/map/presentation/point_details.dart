import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/presentation/place_form.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/road_report_sheet.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/address_labels.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/poi/presentation/add_vending.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The card of a bare point of the map, tapped at street level or held at
/// any zoom, or of an address the search found: "Here" or the address with
/// its source, what can be done there, its coordinates. Compact: the way
/// there and the copy sit in the action bar, the new place right under the
/// title; an address offers the places around it first.
class PointDetails extends StatelessWidget {
  const new({
    required this.position,
    this.address,
    this.scrollController,
    this.onClose,
    this.actions = false,
    this.bottomPadding = Space.huge,
    super.key,
  });

  final LatLng position;

  /// The address the search found there, when the point came from it.
  final AddressMatch? address;
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
    final address = this.address;
    final title = address?.name ?? t.map.pointTitle;
    final hint = switch (address) {
      null => t.map.pointHint,
      final a when a.detail.isEmpty => addressKindLabel(t, a.kind),
      final a => a.detail,
    };
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
              child: Icon(
                address == null ? AppIcons.point : addressIcon(address.kind),
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: Space.ml),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
                  Text(
                    hint,
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
        if (address != null) ...[
          const SizedBox(height: Space.s),
          Text(
            t.map.addressSource(attribution: address.attribution),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Space.l),
        if (address != null) ...[
          // The list of the places around the address in place of its card,
          // in every layout, and the map stepped back around it.
          Consumer(
            builder: (context, ref, _) => OutlinedButton.icon(
              onPressed: () {
                ref.read(mapFlowProvider.notifier).showPlacesAround();
                unawaited(ref.read(mapControllerProvider)?.moveTo(position, zoom: 12));
              },
              icon: const Icon(AppIcons.list),
              label: Text(t.map.placesAround),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ),
          const SizedBox(height: Space.l),
        ],
        // A trip prepared from here: the routes previewed next start from
        // this point rather than from the device's position.
        Consumer(
          builder: (context, ref, _) => OutlinedButton.icon(
            onPressed: () {
              ref
                  .read(chosenDepartureProvider.notifier)
                  .choose(
                    RouteDeparture(
                      position: position,
                      label: address == null ? null : addressRouteLabel(address),
                    ),
                  );
              showMessage(ScaffoldMessenger.maybeOf(context), t.map.departureChosen);
            },
            icon: const Icon(AppIcons.departure),
            label: Text(t.map.startHere),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ),
        const SizedBox(height: Space.l),
        // A point on the map is where a missing place goes: the placement
        // and the form follow.
        Consumer(
          // Outlined: the route in the action bar stays the one primary
          // action.
          builder: (context, ref, _) => OutlinedButton.icon(
            onPressed: () => startAddPlace(context, ref, position),
            icon: const Icon(AppIcons.addPlace),
            label: Text(t.contribute.addPlaceHere),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ),
        const SizedBox(height: Space.l),
        CoordinatesCard(position: position),
        const SizedBox(height: Space.l),
        VendingQuickAdd(position: position),
        const SizedBox(height: Space.l),
        // What is seen on the road there: a closure, works, a low bridge;
        // never offered where the reports are refused.
        Consumer(
          builder: (context, ref, _) =>
              ref.watch(roadReportOfferedProvider(position)).value ?? false
              ? OutlinedButton.icon(
                  onPressed: () => reportOnRoad(context, position: position),
                  icon: const Icon(AppIcons.report),
                  label: Text(t.roadReport.fromMap),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
    if (!actions) return body;
    return Column(
      children: [
        Expanded(child: body),
        PointActionBar(
          position: position,
          here: true,
          label: address == null ? null : addressRouteLabel(address),
        ),
      ],
    );
  }
}

/// The actions of a point: the route there, and its coordinates to copy.
class PointActionBar extends ConsumerWidget {
  const new({
    required this.position,
    this.floating = false,
    this.here = false,
    this.label,
    super.key,
  });

  final LatLng position;
  final bool floating;

  /// A bare point of the map rather than a shop or a service: the buttons
  /// say "here".
  final bool here;

  /// What the route's preview calls the point (an address the search found,
  /// a shop's name); a bare point has none and shows its coordinates.
  final String? label;

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
              onPressed: () => openDirections(context, position, label: label),
              onLongPress: () => openInOtherApp(context, ref, position, label: label, choose: true),
              icon: const Icon(AppIcons.directions),
              label: Text(
                here ? t.map.directionsHere : t.place.directions,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => copyCoordinates(context, ref, position),
              icon: const Icon(AppIcons.copy),
              label: Text(
                here ? t.map.copyCoordinates : t.place.copyShort,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
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
