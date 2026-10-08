import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/presentation/locate_flow.dart';
import 'package:lunaway/features/map/presentation/web_map_pointer.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/preview_zones.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/application/route_mark_focus.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/fuel_sheet.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_point_card.dart';
import 'package:lunaway/features/navigation/presentation/route_points.dart';
import 'package:lunaway/features/navigation/presentation/widgets/avoid_chips.dart';
import 'package:lunaway/features/navigation/presentation/widgets/ferry_section.dart';
import 'package:lunaway/features/navigation/presentation/widgets/no_route_view.dart';
import 'package:lunaway/features/navigation/presentation/widgets/preview_parts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/road_events_section.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_marks_overlay.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_option_card.dart';
import 'package:lunaway/features/navigation/presentation/widgets/stops_strip.dart';
import 'package:lunaway/features/navigation/presentation/widgets/warning_tile.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The route to a place or a point, before setting off: the route on the
/// map with its alternatives, its time and length, what it uses, the limits
/// to watch along it, the vehicle it was computed for (editable in place),
/// the options to avoid, the data's date and the disclaimer; then "C'est
/// parti !" starts the guidance, on every platform the app ships on.
class RoutePreviewScreen extends ConsumerStatefulWidget {
  const new({required this.target, super.key});

  /// Null when the link held no valid point.
  final RouteTarget? target;

  @override
  ConsumerState<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends ConsumerState<RoutePreviewScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The router writes its instructions in the app's language.
    final code = context.t.$meta.locale.languageCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(routeLanguageCodeProvider.notifier).set(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final target = widget.target;
    if (target == null) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          title: t.navigation.states.refusedTitle,
          hint: t.navigation.states.refusedHint,
          mood: SceneMood.error,
        ),
      );
    }
    final size = WindowSize.of(context);
    final preview = ref.watch(routePreviewControllerProvider(target));
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final panel = _Panel(target: target, preview: preview, units: units);
    // A failed recalculation keeps the previous route as its value: only a
    // route of the current vehicle and options may start.
    final action = _ActionBar(
      target: target,
      preview: preview.value,
      computing: preview is! AsyncData<RoutePreview> || preview.isLoading,
    );
    if (size == WindowSize.compact) {
      return Scaffold(
        body: LayoutBuilder(
          builder: (context, box) {
            const sheet = 0.48;
            final bottom = box.maxHeight * sheet;
            // Raised to the top, the sheet stops under the back button and
            // the status bar: neither covers its title.
            final top = MediaQuery.paddingOf(context).top + 48 + Space.s * 2 + Space.xs;
            final max = (1 - top / box.maxHeight).clamp(sheet, 0.94);
            return Stack(
              children: [
                Positioned.fill(
                  child: _PreviewMap(
                    target: target,
                    preview: preview.value,
                    padding: EdgeInsets.only(
                      bottom: bottom,
                      top: MediaQuery.paddingOf(context).top,
                    ),
                  ),
                ),
                DraggableScrollableSheet(
                  initialChildSize: sheet,
                  minChildSize: 0.22,
                  maxChildSize: max,
                  snap: true,
                  snapSizes: const [sheet],
                  builder: (context, scroll) => _SheetFrame(
                    child: CustomScrollView(
                      controller: scroll,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(_wholePanel),
                      slivers: [
                        const SliverToBoxAdapter(child: _Handle()),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.huge),
                          sliver: panel,
                        ),
                      ],
                    ),
                  ),
                ),
                const Positioned(top: 0, left: 0, child: SafeArea(child: _BackButton())),
              ],
            );
          },
        ),
        bottomNavigationBar: action,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: size == WindowSize.expanded ? 440 : 380,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                right: false,
                child: Column(
                  children: [
                    const Align(alignment: Alignment.centerLeft, child: _BackButton()),
                    Expanded(
                      child: CustomScrollView(
                        scrollCacheExtent: const ScrollCacheExtent.pixels(_wholePanel),
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
                            sliver: panel,
                          ),
                        ],
                      ),
                    ),
                    action,
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _PreviewMap(target: target, preview: preview.value, padding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}

/// The panel is built whole, off screen too: a mark on the map can then
/// bring any of its rows into view. Its sections are few, the long ones
/// (the roadbook) folded.
const _wholePanel = 100000.0;

class _BackButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Space.s),
      child: IconButton.filledTonal(
        tooltip: context.t.navigation.preview.back,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 48),
        ),
        onPressed: () => context.canPop() ? context.pop() : context.go('/map'),
        icon: const Icon(AppIcons.back),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 5,
      margin: const EdgeInsets.symmetric(vertical: Space.m),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
        boxShadow: LunaTokens.of(context).sheetShadow,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// The map of the preview: the routes, the limits along the chosen one,
/// the start and the destination.
class _PreviewMap extends ConsumerStatefulWidget {
  const new({required this.target, required this.preview, required this.padding});

  final RouteTarget target;
  final RoutePreview? preview;
  final EdgeInsets padding;

  @override
  ConsumerState<_PreviewMap> createState() => _PreviewMapState();
}

class _PreviewMapState extends ConsumerState<_PreviewMap> {
  /// A tap on bare map waits to know it is no double tap, which zooms.
  final _gate = DoubleTapGate();

  @override
  void dispose() {
    _gate.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final preview = widget.preview;
    final padding = widget.padding;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(
      basemapStyleProvider(dark: dark, language: Localizations.localeOf(context).languageCode),
    );
    final p = preview;
    final plan = p?.plan;
    final selected = p?.route;
    final lines = [
      for (final r in plan?.routes ?? const <RouteOption>[])
        RouteMapLine(index: r.index, points: r.line, selected: r.index == p?.selected),
    ];
    final line = selected?.line ?? const <LatLng>[];
    final places = line.length < 2
        ? const <PlaceSummary>[]
        : ref.watch(placesNearRouteProvider(line)).value ?? const <PlaceSummary>[];
    final stops = p?.stops ?? const <RouteStop>[];
    final points = RoutePoints(
      places: places,
      stations: ref.watch(shownFuelOffersProvider(line)),
      stops: stops,
      movedTo: RoutePoints.movedWaypoints(plan, stops.length),
    );
    final now = ref.watch(clockProvider)();
    final t = context.t;
    // Road events met on the way, and the closures the route goes round:
    // seen on the map, the detour explains itself. A stop the server moved
    // shows where the route starts or ends.
    final markers = previewMarkers(
      t: t,
      destination: plan?.movedTo(stops.length + 1) ?? target.destination,
      destinationLabel: target.label,
      points: points.markers(t),
      origin: plan?.movedTo(0) ?? p?.origin,
      route: selected,
      plan: plan,
      noRouteReasons: p?.noRouteReasons ?? const [],
    );
    // Another route chosen: what was lit or asked for belongs to the old one.
    ref.listen(
      routePreviewControllerProvider(target).select((v) => v.value?.selected),
      (_, _) => ref.read(routeMarkFocusProvider(target).notifier).clear(),
    );

    // Every route in view, so an alternative can be compared and tapped;
    // choosing one leaves the camera where it is.
    final routeBounds = [
      for (final r in plan?.routes ?? const <RouteOption>[])
        if (r.bounds case final b?) ...[LatLng(b.south, b.west), LatLng(b.north, b.east)],
    ];
    final bounds = routeBounds.isNotEmpty
        ? GeoBounds.around(routeBounds)
        : GeoBounds.around([
            target.destination,
            ?p?.origin,
            for (final b in plan?.blockers ?? const <RouteWarning>[]) b.position,
            ...blockingPositions(p?.noRouteReasons ?? const []),
          ]);
    return RouteMarksMap(
      target: target,
      markers: markers,
      plan: plan,
      base: RouteMapProps(
        style: style,
        dark: dark,
        lines: lines,
        camera: FitCamera(_atLeast(bounds!)),
        padding: padding,
        zones: _zonesOf(ref, selected, p?.origin).spans,
        onLineTap: (i) {
          _gate.cancel();
          ref.read(routePreviewControllerProvider(target).notifier).select(i);
        },
        onLongPress: (at) {
          _gate.cancel();
          unawaited(openPreviewPoint(context, ref, target, RoutePoint(position: at)));
        },
        // At street level a tap on bare map opens the same card as a long
        // press: the point as a stop, or as the destination. A callout open
        // over the map takes the tap for itself (RouteMarksMap).
        onEmptyTap: (at, zoom) => _gate.tap(window: freeTapWindow(), () {
          if (!mounted || bareTapAt(zoom: zoom, open: false) != BareTap.freePoint) return;
          unawaited(openPreviewPoint(context, ref, target, RoutePoint(position: at)));
        }),
      ),
      onAnyMarkTap: _gate.cancel,
      onPointTap: (id) {
        if (points.pointOf(id, context.t, now) case final point?) {
          unawaited(openPreviewPoint(context, ref, target, point));
        }
      },
    );
  }

  /// A box around one point (the destination alone, before a route) is
  /// widened to a few streets, so the camera does not zoom to the maximum.
  static GeoBounds _atLeast(GeoBounds b) {
    const half = 0.004;
    if (b.north - b.south >= half && b.east - b.west >= half) return b;
    final c = b.center;
    return GeoBounds(
      south: c.lat - half,
      west: c.lon - half,
      north: c.lat + half,
      east: c.lon + half,
    );
  }
}

/// The danger zones the preview draws on [route] from [origin]; none
/// before both are known or while they load.
PreviewZones _zonesOf(WidgetRef ref, RouteOption? route, LatLng? origin) =>
    route == null || origin == null
    ? noPreviewZones
    : ref.watch(previewZonesProvider(route, origin)).value ?? noPreviewZones;

/// The lists the danger zones on the map come from, with their date: the
/// French list asks to be cited with its date (docs/speed-cameras.md).
class _ZonesNote extends ConsumerWidget {
  const new({required this.route, required this.origin});

  final RouteOption? route;
  final LatLng? origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = _zonesOf(ref, route, origin);
    if (zones.spans.isEmpty) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in zones.sources)
          Text(
            t.navigation.marks.zonesFrom(
              source: s.name,
              date: t.dayMonth((s.listUpdatedAt ?? s.fetchedAt).toLocal()),
            ),
            style: muted,
          ),
      ],
    );
  }
}

/// The panel's content, one sliver list, the same on a phone's sheet and in
/// a tablet's side panel.
class _Panel extends ConsumerWidget {
  const new({required this.target, required this.preview, required this.units});

  final RouteTarget target;
  final AsyncValue<RoutePreview> preview;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final label = target.label;
    final title = label == null
        ? t.navigation.preview.titlePoint
        : t.navigation.preview.titleTo(name: label);
    void retry() => ref.invalidate(routePreviewControllerProvider(target));
    final body = switch (preview) {
      AsyncData(:final value) => _body(context, ref, value),
      AsyncError(:final error) => [_Failure(error: error, onRetry: retry)],
      _ => [const _Computing()],
    };
    return SliverList.list(
      children: [
        Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
        // A bare point has no name: its coordinates say which one it is, in
        // the format the user copies them in.
        if (label == null)
          Text(
            ref.watch(settingsProvider.select((s) => s.copyFormat)).format(target.destination),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        const SizedBox(height: Space.m),
        StopsStrip(target: target),
        if (ref.watch(routeStopsControllerProvider(target)).isNotEmpty)
          const SizedBox(height: Space.m),
        ...body,
      ],
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, RoutePreview p) {
    final t = context.t;
    if (!p.vehicle.ready) {
      final missing = p.vehicle.missing;
      final out = p.vehicle.outOfBounds;
      return [
        _Prompt(
          title: t.navigation.states.vehicleTitle,
          body: [
            t.navigation.states.vehicleHint,
            if (missing.isNotEmpty && missing.length < 4)
              t.navigation.states.vehicleMissing(list: t.dimensionList(missing)),
            if (out.isNotEmpty) t.navigation.states.vehicleOutOfBounds(list: t.dimensionList(out)),
          ],
          action: t.navigation.states.describeVehicle,
          onAction: () => showVehicleEditor(context),
        ),
      ];
    }
    if (p.origin == null) {
      return [
        _Prompt(
          title: t.navigation.states.originTitle,
          body: [t.navigation.states.originHint],
          action: t.navigation.states.locate,
          onAction: () async {
            if (await ensureLocationAccess(context, ref)) {
              await ref.read(previewOriginProvider.notifier).refresh();
            }
          },
        ),
      ];
    }
    if (p.unreachable.isNotEmpty) {
      // Told on the device: no request went out.
      return [
        NoRouteExplanation(
          reasons: p.unreachable,
          target: target,
          stops: p.stops,
          avoid: ref.watch(routeSettingsControllerProvider).value?.avoid ?? const AvoidOptions(),
          coveredCountries: p.coveredCountries,
        ),
      ];
    }
    final plan = p.plan!;
    final avoid = AvoidSection(
      onChanged: (a) => ref.read(routeSettingsControllerProvider.notifier).setAvoid(a),
    );
    return switch (plan.status) {
      RouteStatus.ok => [
        if (plan.movedStops.isNotEmpty) ...[
          _MovedStops(plan: plan, lastStop: p.stops.length + 1, units: units),
          const SizedBox(height: Space.m),
        ],
        _Routes(plan: plan, selected: p.selected, target: target, units: units),
        if (p.route case final route?)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showFuelSheet(
                context,
                line: route.line,
                fromM: 0,
                onAdd: (offer) async => addPreviewStop(
                  context,
                  ref,
                  target,
                  RouteStop(
                    position: offer.position,
                    label: offer.name ?? offer.brand ?? t.navigation.fuel.station,
                    poiId: offer.poiId,
                  ),
                ),
              ),
              icon: const Icon(AppIcons.fuel),
              label: Text(t.navigation.fuel.action),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ),
        if (p.route case final route? when route.ferries.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          FerrySection(route: route, avoided: plan.applied.avoid.ferries, units: units),
        ],
        const SizedBox(height: Space.l),
        _Warnings(route: p.route, units: units, target: target),
        const SizedBox(height: Space.l),
        RoadEventsSection(plan: plan, route: p.route, units: units, target: target),
        const SizedBox(height: Space.l),
        const VehicleLine(),
        const SizedBox(height: Space.m),
        avoid,
        if (p.route != null) ...[
          const SizedBox(height: Space.s),
          Roadbook(steps: p.route!.steps, units: units, ferries: p.route!.ferries),
        ],
        const SizedBox(height: Space.l),
        RouteDataNote(graph: plan.graph),
        _ZonesNote(route: p.route, origin: p.origin),
      ],
      RouteStatus.noSafeRoute => [
        _NoSafeRoute(plan: plan, units: units, target: target),
        const SizedBox(height: Space.l),
        const VehicleLine(),
        const SizedBox(height: Space.m),
        avoid,
        const SizedBox(height: Space.l),
        RouteDataNote(graph: plan.graph),
      ],
      RouteStatus.noRoute || RouteStatus.offNetwork when plan.noRouteReasons.isNotEmpty => [
        NoRouteExplanation(
          reasons: plan.noRouteReasons,
          target: target,
          stops: p.stops,
          avoid: plan.applied.avoid,
          coveredCountries: p.coveredCountries,
        ),
        const SizedBox(height: Space.l),
        const VehicleLine(),
        const SizedBox(height: Space.m),
        avoid,
      ],
      // An API that does not tell why, or could not in time.
      RouteStatus.noRoute || RouteStatus.offNetwork => [
        _Prompt(
          title: plan.status == RouteStatus.noRoute
              ? t.navigation.states.noRouteTitle
              : t.navigation.states.offNetworkTitle,
          body: [
            if (plan.status == RouteStatus.noRoute)
              t.navigation.states.noRouteHint
            else
              t.navigation.states.offNetworkHint,
            if (plan.applied.avoid.unpaved) t.navigation.states.allowUnpaved,
          ],
        ),
        const SizedBox(height: Space.m),
        avoid,
      ],
    };
  }
}

/// The card of a point of the preview's map: add it as a stop (its detour
/// computed first), go there instead, or open the place.
Future<void> openPreviewPoint(
  BuildContext context,
  WidgetRef ref,
  RouteTarget target,
  RoutePoint point,
) async {
  final t = context.t;
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Turning the phone or the window can rebuild the map under the open
  // card: what is read after it goes through the container.
  final container = ProviderScope.containerOf(context, listen: false);
  // The navigator's own context outlives the map's: the place opens from it.
  final pageContext = Navigator.of(context).context;
  final stops = container.read(routeStopsControllerProvider(target));
  final controller = container.read(routePreviewControllerProvider(target).notifier);
  final choice = await showRoutePointCard(
    context,
    point: point,
    quote: controller.quoteStop,
    stopsFull: stops.length >= maxRouteStops,
  );
  switch (choice) {
    case AddStopChoice(:final quote):
      changeStopsIn(container, messenger, t, target, quote.stops, t.navigation.stops.added);
    case RemoveStopChoice(:final stop):
      // The marks are those of the route on screen, the list may have
      // moved on since: the stop is taken out of the list as it is now.
      final now = container.read(routeStopsControllerProvider(target));
      if (now.contains(stop)) {
        changeStopsIn(
          container,
          messenger,
          t,
          target,
          [...now]..remove(stop),
          t.navigation.stops.removed,
        );
      }
    case GoDirectlyChoice():
      unawaited(
        router.pushReplacement<void>(
          NavigationRoutes.previewOf(
            RouteTarget(destination: point.position, label: point.title, placeId: point.placeId),
          ),
        ),
      );
    case OpenCardChoice():
      if (point.placeId case final id? when pageContext.mounted) {
        unawaited(showPlaceCard(pageContext, id));
      }
    case null:
  }
}

/// Adds [stop] where it lengthens the trip the least, in one tap (a fuel
/// station picked from the list), with the way back.
void addPreviewStop(BuildContext context, WidgetRef ref, RouteTarget target, RouteStop stop) {
  final preview = ref.read(routePreviewControllerProvider(target)).value;
  final origin = preview?.origin;
  final stops = ref.read(routeStopsControllerProvider(target));
  if (stops.length >= maxRouteStops) {
    showMessage(ScaffoldMessenger.maybeOf(context), context.t.navigation.stops.full);
    return;
  }
  if (origin == null) return;
  final at = bestInsertion(
    origin: origin,
    stops: stops,
    destination: target.destination,
    stop: stop.position,
  );
  changeStops(context, target, insertStop(stops, at, stop), context.t.navigation.stops.added);
}

/// The avoid options, read and written in the route settings: a change
/// computes the route again.
class AvoidSection extends ConsumerWidget {
  const new({required this.onChanged, super.key});

  final ValueChanged<AvoidOptions> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avoid = ref.watch(routeSettingsControllerProvider).value?.avoid ?? const AvoidOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t.navigation.preview.avoid, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.s),
        AvoidChips(value: avoid, onChanged: onChanged),
      ],
    );
  }
}

class _Routes extends ConsumerWidget {
  const new({
    required this.plan,
    required this.selected,
    required this.target,
    required this.units,
  });

  final RoutePlan plan;
  final int selected;
  final RouteTarget target;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, r) in plan.routes.indexed) ...[
        if (i > 0) const SizedBox(height: Space.s),
        RouteOptionCard(
          route: r,
          ordinal: i,
          selected: r.index == selected,
          units: units,
          onTap: () => ref.read(routePreviewControllerProvider(target).notifier).select(r.index),
        ),
      ],
      // The times depend on the driver's own speed: say which.
      if (plan.applied.cruiseShownKph case final kmh?) ...[
        const SizedBox(height: Space.s),
        Row(
          children: [
            Icon(AppIcons.hours, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                context.t.navigation.preview.cruise(speed: context.t.speedLimit(kmh, units)),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

/// The stops the server moved to a road the vehicle can reach: said first,
/// the moved points stand on the map where the route starts or ends.
class _MovedStops extends StatelessWidget {
  const new({required this.plan, required this.lastStop, required this.units});

  final RoutePlan plan;
  final int lastStop;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in plan.movedStops)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.address, color: theme.colorScheme.tertiary),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    t.movedStop(m, lastStop: lastStop, units: units),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Warnings extends StatelessWidget {
  const new({required this.route, required this.units, required this.target});

  final RouteOption? route;
  final DistanceUnits units;
  final RouteTarget target;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final warnings = route?.warnings ?? const <RouteWarning>[];
    if (warnings.isEmpty) {
      return Row(
        children: [
          Icon(AppIcons.checkCircle, color: theme.colorScheme.secondary),
          const SizedBox(width: Space.s),
          Expanded(child: Text(t.navigation.preview.noWarnings, style: theme.textTheme.bodyMedium)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.navigation.preview.warnings(n: warnings.length), style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        for (final (i, w) in warnings.indexed)
          MarkLinkedRow(
            target: target,
            marks: [warningMarkId(route!.index, i)],
            child: WarningTile(warning: w, units: units),
          ),
      ],
    );
  }
}

/// No safe route: what stopped every route, the vehicle's figures, and
/// what the user can change.
class _NoSafeRoute extends StatelessWidget {
  const new({required this.plan, required this.units, required this.target});

  final RoutePlan plan;
  final DistanceUnits units;
  final RouteTarget target;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = plan.applied.vehicle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(AppIcons.error, color: scheme.error),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(t.navigation.states.noSafeTitle, style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(t.navigation.states.noSafeHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Space.xs),
        for (final (i, b) in plan.blockers.indexed)
          MarkLinkedRow(
            target: target,
            marks: [blockerMarkId(i)],
            child: WarningTile(warning: b, units: units),
          ),
        if (plan.roadEventBlockers.isNotEmpty) RoadEventBlockers(plan: plan, target: target),
        const SizedBox(height: Space.m),
        Text(t.navigation.states.whatToDo, style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        _Bullet(
          t.navigation.states.checkVehicle(
            height: t.metres(v.heightM),
            weight: t.tonnes(v.weightT),
          ),
        ),
        _Bullet(t.navigation.states.pickOtherPoint),
        if (plan.applied.avoid.unpaved) _Bullet(t.navigation.states.allowUnpaved),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
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

class _Prompt extends StatelessWidget {
  const new({required this.title, required this.body, this.action, this.onAction});

  final String title;
  final List<String> body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.xs),
        for (final line in body)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(line, style: theme.textTheme.bodyMedium),
          ),
        if (action != null && onAction != null) ...[
          const SizedBox(height: Space.s),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    );
  }
}

class _Computing extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.t.navigation.preview.computing, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Space.m),
        const LinearProgressIndicator(),
        const SizedBox(height: Space.l),
        // The size of a route card, so nothing jumps when it arrives.
        const Skeleton(height: 104, radius: LunaTokens.radiusL),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const new({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final failure = error is RouteFailure ? error as RouteFailure : null;
    final (title, hint) = switch (failure?.kind) {
      RouteFailureKind.offline => (
        t.navigation.states.offlineTitle,
        t.navigation.states.offlineHint,
      ),
      RouteFailureKind.rateLimited => (
        t.navigation.states.rateLimitedTitle,
        t.navigation.states.rateLimitedHint(seconds: '${failure?.retryAfter?.inSeconds ?? 60}'),
      ),
      RouteFailureKind.refused => (
        t.navigation.states.refusedTitle,
        t.navigation.states.refusedHint,
      ),
      _ => (t.navigation.states.unavailableTitle, t.navigation.states.unavailableHint),
    };
    return MessageView(
      title: title,
      hint: hint,
      mood: failure?.kind == RouteFailureKind.offline ? SceneMood.offline : SceneMood.error,
      action: context.t.common.retry,
      onAction: onRetry,
      compact: true,
    );
  }
}

/// The foot of the preview: "C'est parti !", and the navigation apps a
/// step aside ("Ouvrir dans...").
class _ActionBar extends ConsumerStatefulWidget {
  const new({required this.target, required this.preview, required this.computing});

  final RouteTarget target;
  final RoutePreview? preview;

  /// A route is being computed: the one on screen is that of the vehicle
  /// or the options before the change, not to be started.
  final bool computing;

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _starting = false;

  RouteTarget get target => widget.target;
  RoutePreview? get preview => widget.preview;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final engineState = ref.watch(guidanceEngineProvider);
    final engine = engineState.value;
    final plan = preview?.plan;
    final ready =
        !widget.computing &&
        !_starting &&
        plan != null &&
        plan.status == RouteStatus.ok &&
        plan.osrmJson != null;
    // Where Lunaway found no road the vehicle may take, the other apps,
    // which know nothing of its size, are not offered a tap away; the
    // place's directions still lead to them. Where Lunaway computes no
    // route at all (a country it does not cover, a trip too long), they
    // are the way left.
    final reasons = preview?.noRouteReasons ?? const <NoRouteReason>[];
    final elsewhere =
        reasons.isNotEmpty &&
        reasons.every(
          (r) =>
              r.kind == NoRouteReasonKind.outsideCoverage ||
              r.kind == NoRouteReasonKind.tripTooLong,
        );
    if (!elsewhere && plan != null && plan.status != RouteStatus.ok) {
      return const SizedBox.shrink();
    }
    if (!elsewhere && (preview?.unreachable.isNotEmpty ?? false)) return const SizedBox.shrink();
    final others = TextButton(
      onPressed: () => openInOtherApp(context, ref, target.destination, label: target.label),
      onLongPress: () =>
          openInOtherApp(context, ref, target.destination, label: target.label, choose: true),
      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
      child: Text(t.navigation.preview.otherApps),
    );
    return LiftsMessages(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // While the engine loads, the button holds its place.
                if (elsewhere)
                  const SizedBox.shrink()
                else if (engine != null || engineState.isLoading)
                  FilledButton.icon(
                    onPressed: ready && engine != null
                        ? () => _start(plan, preview!.selected, preview!.stops)
                        : null,
                    icon: const Icon(AppIcons.directions),
                    label: Text(t.navigation.preview.start),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                  )
                else
                  Text(
                    t.navigation.guidance.unavailable,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                others,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(RoutePlan plan, int selected, List<RouteStop> stops) async {
    setState(() => _starting = true);
    try {
      await _startGuidance(plan, selected, stops);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startGuidance(RoutePlan plan, int selected, List<RouteStop> stops) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.of(context);
    final settings = ref.read(routeSettingsControllerProvider).value ?? const NavigationSettings();
    if (settings.acceptedDisclaimer != plan.disclaimerKey) {
      final accepted = await showDisclaimer(context);
      if (!accepted || !mounted) return;
      await ref.read(routeSettingsControllerProvider.notifier).acceptDisclaimer(plan.disclaimerKey);
      if (!mounted) return;
    }
    if (!await ensureLocationAccess(context, ref) || !mounted) return;
    await ref.read(notificationAccessProvider).ask();
    if (!mounted) return;
    final started = await ref
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: selected,
          target: target,
          words: TranslatedWording(t, settings.units),
          stops: stops,
        );
    if (!started) {
      showMessage(messenger, t.navigation.guidance.unavailable);
      return;
    }
    // An "undo" of the preview's stops has nothing left to undo once the
    // guidance runs with them.
    messenger?.clearSnackBars();
    unawaited(router.pushReplacement<void>(NavigationRoutes.guidance));
  }
}

/// The disclaimer before the first guidance; true once the user read it.
Future<bool> showDisclaimer(BuildContext context) async {
  final t = context.t;
  final accepted = await showSheet<bool>(
    context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(AppIcons.inAppNavigation, size: 36, color: theme.colorScheme.secondary),
              const SizedBox(height: Space.m),
              Text(t.navigation.guidance.firstTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Space.s),
              Text(t.navigation.preview.disclaimer, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.navigation.guidance.firstAccept),
              ),
            ],
          ),
        ),
      );
    },
  );
  return accepted ?? false;
}
