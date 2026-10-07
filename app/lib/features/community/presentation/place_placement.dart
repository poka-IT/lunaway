import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/map/pin_painter.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';

final _log = Logger('community');

/// The zoom of the placement: a car park's own lanes, so the spot is set to
/// the metre.
const double placementZoom = 17;

/// Within this distance an existing place may well be the one the user
/// means to add: asked before the form.
const double duplicateRadiusM = 50;

/// Where the user set the new place, and the places the map showed around
/// it then.
typedef Placement = ({LatLng position, List<PlaceSummary> around});

/// The nearest of [candidates] within [radius] metres of [at], with its
/// distance; null when none is that close.
({PlaceSummary place, double metres})? nearestPlace(
  Iterable<PlaceSummary> candidates,
  LatLng at, {
  double radius = duplicateRadiusM,
}) {
  ({PlaceSummary place, double metres})? best;
  for (final p in candidates) {
    final d = p.position.distanceTo(at);
    if (d <= radius && (best == null || d < best.metres)) best = (place: p, metres: d);
  }
  return best;
}

/// Opens the placement over the whole window: the map at [start], zoomed to
/// the street's detail, moves under a fixed crosshair. Null when the user
/// leaves without choosing.
Future<Placement?> pickPlacement(BuildContext context, LatLng start) =>
    Navigator.of(context, rootNavigator: true).push<Placement>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlacePlacement(start: start)),
    );

/// The places of the device around [at], whatever the filter: the map of
/// the placement may not have drawn them all (offline, a filter on).
Future<List<PlaceSummary>> localPlacesAround(WidgetRef ref, LatLng at) async {
  if (!ref.read(keepsPlacesProvider)) return const [];
  // About 110 m each way: more than the radius of a duplicate.
  const span = 0.001;
  try {
    return await ref
        .read(placesRepositoryProvider)
        .watchInBounds(
          GeoBounds(
            south: at.lat - span,
            west: at.lon - span * 1.5,
            north: at.lat + span,
            east: at.lon + span * 1.5,
          ),
          PlaceFilter.none,
          center: at,
          limit: 20,
        )
        .first;
  } on Object catch (e) {
    _log.info('the places around a new one were not read: $e');
    return const [];
  }
}

/// The placement of a new place: the map moves, the crosshair stays in the
/// middle and marks the spot. The existing places stay drawn, so a place
/// already there is seen before the form.
class PlacePlacement extends ConsumerStatefulWidget {
  const new({required this.start, super.key});

  final LatLng start;

  @override
  ConsumerState<PlacePlacement> createState() => _PlacePlacementState();
}

class _PlacePlacementState extends ConsumerState<PlacePlacement> {
  late LatLng _center = widget.start;
  LunaMapController? _map;
  List<PlaceSummary> _around = const [];

  void _done() => Navigator.of(context).pop<Placement>((position: _center, around: _around));

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final language = Localizations.localeOf(context).languageCode;
    final fromTiles = ref.watch(placesFromTilesProvider);
    final map = ref.watch(lunaMapBuilderProvider)(
      context,
      LunaMapProps(
        style: ref.watch(basemapStyleProvider(dark: dark, language: language)),
        dark: dark,
        initialCenter: widget.start,
        initialZoom: placementZoom,
        places: fromTiles
            ? const <PlaceSummary>[]
            : ref.watch(mapPlacesProvider).value ?? const <PlaceSummary>[],
        // Every place, whatever the filter of the main map (the view's
        // default): a car park hidden by a chip is still a place that exists.
        placeTiles: fromTiles
            ? PlaceTilesView(tileJsonUrl: ref.watch(placeTileJsonUrlProvider))
            : null,
        selectedPlace: null,
        // A pin tapped here brings the crosshair onto it: the next step asks
        // whether it is the same place.
        onPlaceTap: (id, {hint}) {
          if (hint != null) unawaited(_map?.moveTo(hint.position));
        },
        onLongPress: (p) => unawaited(_map?.moveTo(p)),
        onViewportChanged: (v) => _center = v.center,
        onMapReady: (c) => _map = c,
        onPlacesInView: (places, _, {failed = false}) => _around = places,
        language: language,
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): _done,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              map,
              // The crosshair marks the middle of the map, which is the
              // camera's centre: what is under it is the spot.
              const IgnorePointer(child: Center(child: _Crosshair())),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.m),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: FloatingSurface(
                          radius: LunaTokens.radiusL,
                          color: scheme.surface,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          t.placement.title,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                      ),
                                      Text(
                                        t.placement.hint,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: t.common.cancel,
                                  icon: const Icon(AppIcons.close),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: Space.m),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.m),
                        child: FilledButton.icon(
                          onPressed: _done,
                          icon: const Icon(AppIcons.check),
                          label: Text(t.placement.confirm),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The marker of the spot, its tip on the middle of the map, over a thin
/// cross that shows the middle itself.
class _Crosshair extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(width: 1.5, height: 28, color: scheme.onSurface),
          Container(width: 28, height: 1.5, color: scheme.onSurface),
          // Raised so the marker's tip, not its image's middle, meets the
          // cross.
          Transform.translate(
            offset: Offset(0, -(pointMarkerTip - pointMarkerSize.height / 2)),
            child: const CustomPaint(size: pointMarkerSize, painter: _MarkerPainter()),
          ),
        ],
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  const new();

  @override
  void paint(Canvas canvas, Size size) => paintPointMarker(canvas);

  @override
  bool shouldRepaint(_MarkerPainter oldDelegate) => false;
}

/// Asks whether [place], [metres] away from the new spot, is the place the
/// user meant to add. True opens its card, false goes on to the form, null
/// (dismissed) stops.
Future<bool?> askSamePlace(BuildContext context, PlaceSummary place, double metres) {
  final t = context.t;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.placement.duplicate(name: t.summaryTitle(place), distance: t.distance(metres))),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.placement.notSame),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.placement.same),
        ),
      ],
    ),
  );
}
