import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/community/presentation/place_form.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/road_report_sheet.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/address_labels.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/add_vending.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The card of a bare point of the map, tapped at street level or held at
/// any zoom, or of an address the search found: "Here" or the address with
/// its source, what can be done there, its coordinates. A point saved in
/// the favourites shows the name the user gave it and its note. Compact:
/// the way there, the save and the copy sit in the action bar, the new place
/// right under the title; an address offers the places around it first.
class PointDetails extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final address = this.address;
    final savedId = savedPointIdAt(position);
    // Opened from the favourites, the point is named at once; the saved
    // copy takes over once read.
    final savedRead = ref.watch(savedPointProvider(savedId));
    final saved = savedRead.hasValue
        ? savedRead.value
        : switch (ref.watch(selectionProvider)) {
            PointSelection(:final saved?) when saved.id == savedId => saved,
            _ => null,
          };
    final title = saved?.name ?? address?.name ?? t.map.pointTitle;
    // Under the title, where it is: what the search found, else what was
    // saved with the point.
    final hint = switch (address) {
      final a? when a.detail.isNotEmpty => a.detail,
      final a? => addressKindLabel(t, a.kind),
      null when saved?.address != null => saved!.address!,
      null when saved != null => savedPointKindLabel(t, saved),
      null => t.map.pointHint,
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
              child: Icon(switch ((saved, address)) {
                (final s?, _) => savedPointIcon(s),
                (null, null) => AppIcons.point,
                (null, final a?) => addressIcon(a.kind),
              }, color: scheme.onPrimaryContainer),
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
        SavedPointBlock(id: savedId, shownName: title, initial: saved),
        const SizedBox(height: Space.l),
        if (address != null) ...[
          // The map steps back so the places around the address show, the
          // address still marked.
          OutlinedButton.icon(
            onPressed: () => ref.read(mapControllerProvider)?.moveTo(position, zoom: 12),
            icon: const Icon(AppIcons.list),
            label: Text(t.map.placesAround),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
          const SizedBox(height: Space.l),
        ],
        StartHereButton(
          position: position,
          label: saved?.name ?? (address == null ? null : [address.name, ?address.city].join(', ')),
        ),
        const SizedBox(height: Space.l),
        // A point on the map is where a missing place goes: the placement
        // and the form follow. Outlined: the route in the action bar stays
        // the one primary action.
        OutlinedButton.icon(
          onPressed: () => startAddPlace(context, ref, position),
          icon: const Icon(AppIcons.addPlace),
          label: Text(t.contribute.addPlaceHere),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: Space.l),
        CoordinatesCard(position: position),
        const SizedBox(height: Space.l),
        VendingQuickAdd(position: position),
        const SizedBox(height: Space.l),
        // What is seen on the road there: a closure, works, a low bridge;
        // never offered where the reports are refused. Asked only once the
        // list scrolls this far: the answer costs a request.
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
        PointActionBar(position: position, address: address, here: true),
      ],
    );
  }
}

/// "Partir d'ici": a trip prepared from [position], the routes previewed
/// next start from this point rather than from the device's position,
/// named [label] when it has a name.
class StartHereButton extends ConsumerWidget {
  const new({required this.position, this.label, super.key});

  final LatLng position;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return OutlinedButton.icon(
      onPressed: () {
        ref
            .read(chosenDepartureProvider.notifier)
            .choose(RouteDeparture(position: position, label: label));
        showMessage(ScaffoldMessenger.maybeOf(context), t.map.departureChosen);
      },
      icon: const Icon(AppIcons.departure),
      label: Text(t.map.startHere),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
    );
  }
}

/// The actions of a point: the route there, saving it in the favourites
/// (as a place is saved), and its coordinates to copy.
class PointActionBar extends ConsumerWidget {
  const new({
    required this.position,
    this.address,
    this.poi,
    this.floating = false,
    this.here = false,
    super.key,
  });

  final LatLng position;

  /// The address the search found there, which names the point saved.
  final AddressMatch? address;

  /// The shop or the service it is.
  final PoiFeature? poi;
  final bool floating;

  /// A bare point of the map rather than a shop or a service: the buttons
  /// say "here".
  final bool here;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final poi = this.poi;
    final id = poi == null ? savedPointIdAt(position) : savedPoiPointId(poi.id);
    final saved = ref.watch(savedPointProvider(id)).value;
    // Made when the user saves, so a bare point is named after that day.
    SavedPoint draft() => poi == null
        ? pointDraft(t, position, now: ref.read(clockProvider)(), address: address)
        : poiDraft(t, poi, address: ref.read(poiPageProvider(poi.id)).value?.value?.poi.address);
    final directionsLabel = here ? t.map.directionsHere : t.place.directions;
    return ActionsBar(
      directions: FilledButton.icon(
        onPressed: () => openDirections(context, position, label: saved?.name),
        onLongPress: () => openInOtherApp(context, ref, position, label: saved?.name, choose: true),
        icon: const Icon(AppIcons.directions),
        label: Text(directionsLabel, maxLines: 2, textAlign: TextAlign.center),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
        ),
      ),
      directionsLabel: directionsLabel,
      tiles: [
        SavePointTile(id: id, draft: draft),
        ActionTile(
          icon: AppIcons.copy,
          label: t.place.copyShort,
          hint: t.map.copyCoordinates,
          onPressed: () => copyCoordinates(context, ref, position),
        ),
      ],
      labels: [t.place.save, t.place.saved, t.place.copyShort],
      floating: floating,
    );
  }
}
