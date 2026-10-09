import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/rich_marks_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/road_reports.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/guidance_places_sheet.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/on_the_way_sheet.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/road_report_sheet.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_point_card.dart';
import 'package:lunaway/features/navigation/presentation/route_points.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/features/navigation/presentation/widgets/lanes_row.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/on_the_way_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/panels_beside_buttons.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/features/navigation/presentation/widgets/warning_tile.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/centred_clear.dart';
import 'package:lunaway/shared/widgets/measured.dart';

final _log = Logger('guidance_screen');

/// The guidance, full screen: the next maneuver large at the top, with its
/// lanes; the restrictions coming up; a calm map that follows the vehicle
/// along its route; the arrival time, the time and distance left and the
/// speed at the bottom. Off the route, or when a road event closes it
/// ahead, a new route comes by itself and the banner says why.
///
/// The screen stands only on a guidance: without one it leaves for the map
/// (leaveForMap), whether the guidance just ended here or never ran there
/// (the browser came back or forward to this page after its guidance
/// ended, a link). A guidance that cannot start says so on the preview,
/// before this screen opens.
class GuidanceScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends ConsumerState<GuidanceScreen> {
  /// The page asked to leave: once is enough (in a browser the page goes
  /// when the history has moved, a moment later).
  bool _leaving = false;

  /// Leaves for the map after the frame: no navigation while the widgets
  /// build.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) leaveForMap(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(guidanceControllerProvider);
    if (session == null) {
      // Only while this page is the one shown: one popped by the system's
      // back is leaving already, and a page pushed over it is not the one
      // to leave (this one is built again when that page goes).
      if (ModalRoute.isCurrentOf(context) ?? true) _leave();
      // Nothing to show on the way out: the map comes back.
      return const Scaffold();
    }
    // The map follows the vehicle and never rests: each new position checks
    // whether the basemap's host still answers, at most every 30 s, so the
    // downloaded map takes over soon after the network goes.
    ref.listen(guidanceControllerProvider.select((s) => s?.lastFix), (_, _) {
      unawaited(ref.read(basemapReachabilityProvider.notifier).probeIfStale());
    });
    // Watched here, above both layouts: a free map stays free when the
    // phone turns and the map is built again in the other one.
    ref.listen(guidanceCameraProvider, (_, _) {});
    final arrived = session.phase == GuidancePhase.arrived;
    return PopScope(
      // In a browser the page leaves through the history (leaveForMap),
      // never by a pop of the app.
      canPop: arrived && ref.watch(browserProvider) == null,
      // Every back comes here while the guidance runs: the system's, the
      // browser's (keepGuidance) and Escape. A driver who meant the map
      // would otherwise lose the route and its voice without a word.
      onPopInvokedWithResult: (popped, _) async {
        // Back from the arrival card ends the guidance as "Terminer" does:
        // the screen may sleep again.
        if (popped) {
          ref.read(guidanceControllerProvider.notifier).stop();
        } else if (arrived || await _confirmStop(context) && context.mounted) {
          _end(ref);
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
        },
        // The page holds the focus from its first frame, for Escape; the
        // keyboard never stops on it.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: SnackBarTheme(
            data: SnackBarTheme.of(context).copyWith(insetPadding: _messageInsets(context)),
            child: Scaffold(
              body: OrientationBuilder(
                builder: (context, orientation) => orientation == Orientation.landscape
                    ? _Landscape(session: session)
                    : _Portrait(session: session),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ends the guidance; its screen then leaves for the map.
void _end(WidgetRef ref) => ref.read(guidanceControllerProvider.notifier).stop();

/// Where a message floats on a phone on its side: centred on the map beside
/// the panel, not across the panel's bar, and clear of the buttons' column
/// at the foot of the right edge. Upright, across the screen as everywhere
/// (null: the theme's).
EdgeInsets? _messageInsets(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width <= size.height) return null;
  final safe = MediaQuery.paddingOf(context);
  return messageInsets(
    context,
    left: safe.left + _sidePanel,
    right: size.width,
    maxWidth: 440,
    clear: EdgeInsets.only(right: safe.right + _buttonsColumn),
  );
}

/// Asked by "Terminer".
Future<bool> _confirmEnd(BuildContext context) => _ask(
  context,
  title: context.t.navigation.guidance.endTitle,
  confirm: context.t.navigation.guidance.endConfirm,
);

/// Asked by a back: the driver may have wanted the map, not the end.
Future<bool> _confirmStop(BuildContext context) => _ask(
  context,
  title: context.t.navigation.guidance.stopTitle,
  confirm: context.t.navigation.guidance.stopConfirm,
);

Future<bool> _ask(BuildContext context, {required String title, required String confirm}) async {
  final t = context.t;
  final end = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.navigation.guidance.endKeep),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirm)),
      ],
    ),
  );
  return end ?? false;
}

class _Portrait extends ConsumerStatefulWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  ConsumerState<_Portrait> createState() => _PortraitState();
}

class _PortraitState extends ConsumerState<_Portrait> {
  /// The bottom bar's height as it was laid out: large text makes it taller,
  /// and the map buttons, "Recentrer" and the vehicle stay above it.
  double _bar = 140;

  /// The banner's and the notices' heights as laid out: the places drawn
  /// large keep below them.
  double _banner = 0;
  double _notices = 0;

  /// Where the buttons' column and "Recentrer" stand, as laid out.
  final _over = _OverTheMap();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final arrived = session.phase == GuidancePhase.arrived;
    final above = _bar + Space.s;
    final safe = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final free = ref.watch(guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.free));
    return Stack(
      children: [
        Positioned.fill(
          child: _GuidanceMap(
            session: session,
            padding: EdgeInsets.only(top: 220, bottom: _bar),
            clear: EdgeInsets.fromLTRB(
              safe.left,
              safe.top + Space.s + _banner + (_notices > 0 ? Space.s + _notices : 0),
              safe.right,
              above,
            ),
            obstacles: arrived
                ? const []
                : _over.rects(
                    free: free,
                    // At the bottom right, over the bar.
                    buttons: (size) => Rect.fromLTWH(
                      screen.width - safe.right - Space.s - size.width,
                      screen.height - above - size.height,
                      size.width,
                      size.height,
                    ),
                    // Centred on the screen over the bar, aside only as far
                    // as the column requires, as its CentredClear places it.
                    recenter: (size) {
                      final span = centredSpan(
                        centre: screen.width / 2,
                        width: size.width,
                        lo: safe.left,
                        hi: screen.width - safe.right - _buttonsColumn,
                      );
                      return Rect.fromLTWH(
                        span.left,
                        screen.height - above - size.height,
                        span.width,
                        size.height,
                      );
                    },
                  ),
          ),
        ),
        // On a small phone with large text the buttons rise to the banner:
        // a notice that reaches them steps aside rather than lose its edge.
        Positioned.fill(
          child: PanelsBesideButtons(
            padding: EdgeInsets.fromLTRB(
              safe.left + Space.s,
              safe.top + Space.s,
              safe.right + Space.s,
              above,
            ),
            gap: Space.s,
            banner: arrived
                ? null
                : ReportsHeight(
                    onHeight: (height) {
                      if (mounted && height != _banner) setState(() => _banner = height);
                    },
                    child: _ManeuverBanner(session: session),
                  ),
            notices: ReportsHeight(
              onHeight: (height) {
                if (mounted && height != _notices) setState(() => _notices = height);
              },
              child: _Notices(session: session),
            ),
            buttons: arrived
                ? null
                : ReportsRect(
                    onRect: (rect) => setState(() => _over.buttons = rect.size),
                    child: _MapButtons(session: session),
                  ),
          ),
        ),
        // In the middle of the screen, level with the foot of the buttons'
        // column: large text or a long word moves it aside only by what it
        // would cover of them.
        if (!arrived)
          Positioned(
            left: 0,
            right: 0,
            bottom: above,
            child: CentredClear(
              obstacles: [SideRoom.left(safe.left), SideRoom.right(safe.right + _buttonsColumn)],
              child: ReportsRect(
                onRect: (rect) => setState(() => _over.recenter = rect.size),
                child: const _RecenterButton(),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: arrived
              ? _ArrivalCard(session: session)
              : ReportsHeight(
                  onHeight: (height) {
                    if (mounted && height != _bar) setState(() => _bar = height);
                  },
                  child: _BottomBar(session: session),
                ),
        ),
      ],
    );
  }
}

/// The width of the panel of a wide window, on the left of the map.
const double _sidePanel = 380;

/// The room a sheet over the guidance leaves on the left: the panel of the
/// maneuver, the screen on its side; none upright. Read again when the
/// phone turns under the sheet.
double guidanceSheetInset(BuildContext context) =>
    MediaQuery.orientationOf(context) == Orientation.landscape
    ? MediaQuery.paddingOf(context).left + _sidePanel
    : 0;

class _Landscape extends ConsumerStatefulWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  ConsumerState<_Landscape> createState() => _LandscapeState();
}

class _LandscapeState extends ConsumerState<_Landscape> {
  /// The bottom bar's height as laid out: large text makes it taller, and
  /// the maneuver and the notices stay above it.
  double _bar = 120;

  /// Where the buttons' column and "Recentrer" stand, as laid out.
  final _over = _OverTheMap();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final arrived = session.phase == GuidancePhase.arrived;
    final safe = MediaQuery.paddingOf(context);
    final left = safe.left + _sidePanel;
    final free = ref.watch(guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.free));
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          // The map takes the whole window; its insets keep the vehicle
          // and the route right of the panel.
          Positioned.fill(
            child: _GuidanceMap(
              session: session,
              padding: EdgeInsets.only(left: left),
              clear: EdgeInsets.fromLTRB(left, safe.top, safe.right, safe.bottom),
              obstacles: arrived
                  ? const []
                  : _over.rects(
                      free: free,
                      buttons: (size) => Rect.fromLTWH(
                        box.maxWidth - safe.right - Space.s - size.width,
                        box.maxHeight - safe.bottom - Space.l - size.height,
                        size.width,
                        size.height,
                      ),
                      // At the top left of the map.
                      recenter: (size) => Rect.fromLTWH(
                        left + Space.s,
                        safe.top + Space.s,
                        size.width,
                        size.height,
                      ),
                    ),
            ),
          ),
          // The maneuver and the notices at the top of the panel, the bar at
          // its foot, both over the map: between them, the map rather than
          // an empty panel. A phone on its side with large text has less
          // height than they need: the top scrolls rather than run under the
          // bar.
          Positioned(
            left: safe.left + Space.s,
            top: safe.top + Space.s,
            width: _sidePanel - 2 * Space.s,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, box.maxHeight - safe.vertical - _bar - 3 * Space.s),
              ),
              // Placed clear of the system's insets already: none inside.
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                removeTop: true,
                removeRight: true,
                removeBottom: true,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!arrived) _ManeuverBanner(session: session),
                      _Notices(session: session),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: safe.left + Space.s,
            bottom: safe.bottom + Space.s,
            width: _sidePanel - 2 * Space.s,
            child: ReportsHeight(
              onHeight: (height) {
                if (mounted && height != _bar) setState(() => _bar = height);
              },
              // The bar keeps the system's insets on a phone held upright;
              // placed clear of them here, it takes none again.
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                removeTop: true,
                removeRight: true,
                removeBottom: true,
                child: arrived ? _ArrivalCard(session: session) : _BottomBar(session: session),
              ),
            ),
          ),
          if (!arrived)
            Positioned(
              right: safe.right + Space.s,
              bottom: safe.bottom + Space.l,
              child: ReportsRect(
                onRect: (rect) => setState(() => _over.buttons = rect.size),
                child: _MapButtons(session: session),
              ),
            ),
          // At the top left of the map, which nothing covers on this side:
          // the right edge is the buttons' column, and a narrow map has no
          // room beside it.
          if (!arrived)
            Positioned(
              left: left + Space.s,
              right: safe.right + _buttonsColumn,
              top: Space.s,
              // The right inset is in the position already.
              child: SafeArea(
                left: false,
                right: false,
                bottom: false,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ReportsRect(
                    onRect: (rect) => setState(() => _over.recenter = rect.size),
                    child: const _RecenterButton(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The map: the route ahead, its restrictions, the places of the user's
/// choice, the vehicle; turned with the road and tilted, where the user
/// moved it, or the whole route in the overview. The guidance goes on the
/// same whatever the map shows.
class _GuidanceMap extends ConsumerWidget {
  const new({
    required this.session,
    required this.padding,
    required this.clear,
    this.obstacles = const [],
  });

  final GuidanceSession session;
  final EdgeInsets padding;

  /// The edges of the map the banner, the notices, the bar or the side
  /// panel cover: no place drawn large lies under them.
  final EdgeInsets clear;

  /// The buttons and "Recentrer" over the map: no place drawn large under
  /// them either.
  final List<Rect> obstacles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(
      basemapStyleProvider(dark: dark, language: Localizations.localeOf(context).languageCode),
    );
    final route = session.route;
    final snap = session.snapshot;
    final vehicle = snap == null
        ? null
        : VehiclePuck(
            position: snap.offRoute ? session.lastFix!.position : snap.position,
            course: snap.courseDeg ?? session.lastFix?.courseDeg,
          );
    final whole =
        route.bounds ?? GeoBounds.around([session.target.destination, ?session.lastFix?.position])!;
    final view = ref.watch(guidanceCameraProvider);
    final cameraModes = ref.read(guidanceCameraProvider.notifier);
    // The whole route stays clear of the column of buttons on the right:
    // the arrival under "Couper la voix" could not be seen.
    final overview = FitCamera(whole, room: const EdgeInsets.only(right: _buttonsColumn));
    final camera = switch (view.mode) {
      GuidanceCameraMode.free => FreeCamera(view: view.rest),
      GuidanceCameraMode.overview => overview,
      GuidanceCameraMode.follow when vehicle == null => overview,
      GuidanceCameraMode.follow => FollowCamera(
        position: vehicle!.position,
        course: vehicle.course,
        speedMps: session.lastFix?.speedMps,
        ease: view.ease,
        request: view.follows,
      ),
    };
    final choice =
        ref.watch(routeSettingsControllerProvider).value?.guidancePlaces ?? const GuidancePlaces();
    final mapFilter = ref.watch(effectiveFilterProvider);
    // Online the places and the points come from the main map's tiles;
    // offline, the places the device holds along the route.
    final fromTiles = ref.watch(placesFromTilesProvider);
    final tiles = fromTiles
        ? RouteMapPlaces(
            placeTileJsonUrl: ref.watch(placeTileJsonUrlProvider),
            poiTileJsonUrl: ref.watch(poiTileJsonUrlProvider),
            placeFilter: guidancePlaceFilter(choice, mapFilter),
            poiFilter: guidancePoiFilter(choice),
          )
        : null;
    final places = fromTiles || route.line.length < 2
        ? const <PlaceSummary>[]
        : [
            for (final p
                in ref.watch(guidancePlacesNearRouteProvider(route.line)).value ??
                    const <PlaceSummary>[])
              if (guidanceKeepsPlace(choice, mapFilter, p)) p,
          ];
    final points = RoutePoints(
      places: places,
      stations: ref.watch(shownFuelOffersProvider(route.line)),
      stops: session.stops,
      movedTo: {for (final (i, stop) in session.stops.indexed) i: ?session.moves.stops[stop]},
    );
    // A destination the server moved: the route ends there.
    final destination = session.moves.destination ?? session.target.destination;
    final now = ref.watch(clockProvider)();
    final marks = richMarksFor(MediaQuery.sizeOf(context));

    return ref.watch(routeMapBuilderProvider)(
      context,
      RouteMapProps(
        style: style,
        dark: dark,
        lines: [RouteMapLine(index: route.index, points: route.line, selected: true)],
        marks: [
          for (final m in points.markers(context.t)) m.mark,
          RouteMapMark(
            id: 'destination',
            position: destination,
            kind: RouteMarkKind.destination,
            badge: RouteBadge.destination,
          ),
          for (final (i, w) in route.warnings.indexed)
            warningMarker(warningMarkId(route.index, i), w, context.t).mark,
          for (final e in session.eventAlerts)
            if (eventLook(e.event, blocking: false) case (final kind, final badge))
              RouteMapMark(
                id: 'alert:${e.event.id}',
                position: e.hit.at,
                kind: kind,
                badge: badge,
                minor: kind == RouteMarkKind.lanes,
              ),
        ],
        vehicle: vehicle,
        camera: camera,
        padding: padding,
        guiding: true,
        // Only what the rule of the country the vehicle is in allows while
        // driving: zones in France, nothing in Germany or Switzerland.
        zones: session.aids.zones,
        places: tiles,
        rich: RouteMapRich(
          style: RichStyle(
            look: choice.look,
            words: RichWords.of(context.t),
            online: fromTiles,
            // The places' tiles carry the photos' credit.
            credited: fromTiles,
            muted: ref.watch(mutedAuthorIdsProvider),
            labelScale: richLabelScale(MediaQuery.textScalerOf(context)),
          ),
          art: ref.watch(richArtProvider),
          // Online the tiles' places in view, offline the device's.
          tiles: fromTiles,
          places: places,
          clear: clear,
          obstacles: obstacles,
          limit: marks.limit,
          sizes: marks.sizes,
          yielding: richMarksYield(
            maneuverType: snap?.banner?.maneuverType,
            modifier: snap?.banner?.modifier,
            distanceM: snap?.distanceToManeuverM ?? double.infinity,
            speedMps: session.lastFix?.speedMps,
          ),
          vehicleAlongM: snap == null || snap.offRoute ? null : snap.distanceAlongM,
          speedMps: session.lastFix?.speedMps,
        ),
        onMarkTap: (id, {at}) {
          if (points.pointOf(id, context.t, now) case final point?) {
            unawaited(openGuidancePoint(context, ref, point));
          }
        },
        onPlaceTap: (place) => unawaited(
          openGuidancePoint(
            context,
            ref,
            RoutePoint(
              position: place.position,
              title: context.t.summaryTitle(place),
              subtitle: context.t.kind(place.kind),
              placeId: place.id,
            ),
          ),
        ),
        onPoiTap: (poi) => unawaited(
          openGuidancePoint(
            context,
            ref,
            RoutePoint(
              position: poi.position,
              title: poi.name ?? context.t.poiKind(poi.kind),
              // A point without a name is titled by its kind already.
              subtitle: poi.name == null ? null : context.t.poiKind(poi.kind),
              poiId: poi.id,
              credit: context.t.navigation.preview.attributionOsm,
            ),
          ),
        ),
        onLongPress: (at) => unawaited(openGuidancePoint(context, ref, RoutePoint(position: at))),
        onGesture: cameraModes.moved,
        onTouch: (down) => cameraModes.touching(down: down),
        // The magnet: a view the user brought back near the driver's snaps
        // into it.
        onRest: (rest) {
          if (ref.read(guidanceCameraProvider).mode != GuidanceCameraMode.free) return;
          cameraModes.rested(rest);
          final now = ref.read(guidanceControllerProvider);
          if (magnetHolds(
            rest,
            padding: padding,
            followZoom: followZoom(now?.lastFix?.speedMps),
            course: vehicle?.course,
            followTilt: followTiltDeg,
          )) {
            cameraModes.snap();
          }
        },
      ),
    );
  }
}

/// The room the map buttons' column takes from the right edge of the map.
const double _buttonsColumn = Space.s + 56 + Space.s;

/// The sizes of what stands over the guidance map besides its edges, as
/// laid out: no place drawn large under them.
final class _OverTheMap {
  Size? buttons;

  /// "Recentrer", empty while the map follows.
  Size? recenter;

  /// Their rooms on the map, placed by the layout's anchors.
  List<Rect> rects({
    required bool free,
    required Rect Function(Size size) buttons,
    required Rect Function(Size size) recenter,
  }) => [
    if (this.buttons case final size?) buttons(size),
    if (this.recenter case final size? when free && !size.isEmpty) recenter(size),
  ];
}

/// Back behind the vehicle, shown as soon as the map was moved away from it:
/// its icon and its word, or the icon alone (the word in its tooltip) where
/// the map is too narrow for both.
class _RecenterButton extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final free = ref.watch(guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.free));
    final scheme = Theme.of(context).colorScheme;
    final label = context.t.navigation.guidance.recenter;
    void recenter() => ref.read(guidanceCameraProvider.notifier).recenter();
    return LayoutBuilder(
      builder: (context, box) {
        // The word's width as the button draws it, with the icon and the
        // padding around them.
        final theme = Theme.of(context);
        final style = theme.filledButtonTheme.style?.textStyle?.resolve(const {});
        final words = TextPainter(
          text: TextSpan(text: label, style: style ?? theme.textTheme.labelLarge),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final wide = box.maxWidth >= words.width + 24 + Space.s + 2 * Space.m + Space.s;
        words.dispose();
        final colors = (background: scheme.primary, foreground: scheme.onPrimary);
        final shown = !free
            ? const SizedBox.shrink(key: ValueKey('following'))
            : wide
            ? FilledButton.icon(
                key: const ValueKey('recenter'),
                onPressed: recenter,
                icon: const Icon(AppIcons.locateActive),
                label: Text(label),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  elevation: 3,
                  backgroundColor: colors.background,
                  foregroundColor: colors.foreground,
                ).copyWith(side: focusRingIn(colors.foreground)),
              )
            : IconButton.filled(
                key: const ValueKey('recenter-icon'),
                tooltip: label,
                onPressed: recenter,
                icon: const Icon(AppIcons.locateActive),
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  elevation: 3,
                  backgroundColor: colors.background,
                  foregroundColor: colors.foreground,
                ).copyWith(side: focusRingIn(colors.foreground)),
              );
        return AnimatedSwitcher(
          duration: Motion.of(context, Motion.short),
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: shown,
        );
      },
    );
  }
}

/// The card of a point of the guidance's map: add it as a stop (its detour
/// computed from where the vehicle is), go there instead, or open the place;
/// each change with the way back.
Future<void> openGuidancePoint(BuildContext context, WidgetRef ref, RoutePoint point) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Turning the phone rebuilds the map under the open card: what is read
  // after the card goes through the container, which outlives the map.
  final container = ProviderScope.containerOf(context, listen: false);
  // The navigator's own context outlives the map's: the place opens from it.
  final pageContext = Navigator.of(context).context;
  final controller = container.read(guidanceControllerProvider.notifier);
  final opened = container.read(guidanceControllerProvider);
  if (opened == null) return;
  // The map stays where the user found the point while its card is open.
  final release = container.read(guidanceCameraProvider.notifier).hold();
  final RoutePointChoice? choice;
  try {
    choice = await showRoutePointCard(
      context,
      point: point,
      quote: controller.quoteStop,
      stopsFull: opened.stops.length >= maxRouteStops,
    );
  } finally {
    release();
  }
  // The vehicle went on while the card was open: a stop may be behind now.
  // Each change, and its way back, works on the stops of its own moment.
  final session = container.read(guidanceControllerProvider);
  if (session == null) return;
  switch (choice) {
    case AddStopChoice(:final quote):
      await _said(
        messenger,
        t,
        action: () => controller.applyQuote(quote),
        done: t.navigation.stops.added,
        undo: () => controller.removeStop(quote.stop),
      );
    case RemoveStopChoice(:final stop):
      final before = session.stops;
      await _said(
        messenger,
        t,
        action: () => controller.removeStop(stop),
        done: t.navigation.stops.removed,
        undo: () => controller.restoreStop(stop, before),
      );
    case GoDirectlyChoice():
      final (target, stops) = (session.target, session.stops);
      await _said(
        messenger,
        t,
        action: () => controller.goTo(
          RouteTarget(destination: point.position, label: point.title, placeId: point.placeId),
        ),
        done: t.navigation.stops.destinationChanged,
        undo: () => controller.goTo(target, stops: stops),
      );
    case OpenCardChoice():
      if (point.placeId case final id? when pageContext.mounted) {
        // The place's own card holds the map as its short card did.
        final release = container.read(guidanceCameraProvider.notifier).hold();
        unawaited(showPlaceCard(pageContext, id).whenComplete(release));
      }
    case null:
  }
}

/// "On the way" during the guidance: at half height, the maneuver in sight
/// above it. The map stays where it is while the sheet is open. Turning the
/// phone rebuilds the screen under the sheet: what it adds goes through
/// the container, the messenger and the words of the moment it opened.
Future<void> openOnTheWay(BuildContext context, GuidanceSession session) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final release = container.read(guidanceCameraProvider.notifier).hold();
  try {
    await showOnTheWaySheet(
      context,
      trip: session.target,
      route: session.route,
      fromM: session.snapshot?.distanceAlongM ?? 0,
      driving: true,
      startInset: guidanceSheetInset,
      onAdd: (stop) => addGuidanceStop(container, messenger, t, stop),
    );
  } finally {
    release();
  }
}

/// Adds [stop] in one tap (an item of "On the way"): its detour from
/// where the vehicle is, then the route through it.
Future<void> addGuidanceStop(
  ProviderContainer container,
  ScaffoldMessengerState? messenger,
  Translations t,
  RouteStop stop,
) async {
  final controller = container.read(guidanceControllerProvider.notifier);
  final before = container.read(guidanceControllerProvider)?.stops ?? const <RouteStop>[];
  if (before.length >= maxRouteStops) {
    showMessage(messenger, t.navigation.stops.full);
    return;
  }
  await _said(
    messenger,
    t,
    action: () async {
      final quote = await controller.quoteStop(stop);
      return quote != null && quote.extraS != null && await controller.applyQuote(quote);
    },
    done: t.navigation.stops.added,
    undo: () => controller.removeStop(stop),
  );
}

/// Runs [action], then says it is [done] with its [undo], or why it failed:
/// no network is told apart from a route that could not be changed.
Future<void> _said(
  ScaffoldMessengerState? messenger,
  Translations t, {
  required Future<bool> Function() action,
  required String done,
  required Future<bool> Function() undo,
}) async {
  Future<String?> attempt(Future<bool> Function() run) async {
    try {
      // A change asked while a new route is on its way is refused: false,
      // and the message says the route was not changed.
      return await run() ? null : t.navigation.stops.failed;
    } on RouteFailure catch (f) {
      return f.kind == RouteFailureKind.offline
          ? t.navigation.stops.offline
          : t.navigation.stops.failed;
    } on Object catch (e, st) {
      // An answer this app cannot read: said like any other failure.
      _log.warning('a change of the stops failed', e, st);
      return t.navigation.stops.failed;
    }
  }

  final problem = await attempt(action);
  if (problem != null) {
    showMessage(messenger, problem);
    return;
  }
  showMessage(
    messenger,
    done,
    action: SnackBarAction(
      label: t.common.undo,
      onPressed: () async {
        if (await attempt(undo) case final problem?) showMessage(messenger, problem);
      },
    ),
  );
}

/// How far past a community report the guidance asks about it, metres:
/// once the road was seen, while it is still in mind.
const _askPassedWithinM = 600.0;

/// The community report of the route just passed, within
/// [_askPassedWithinM] behind the vehicle: only someone who has seen the
/// road answers whether it is still there, and the answers move other
/// people's routes. The route's own events only: one that appeared during
/// the guidance has no place along this route to be passed.
RouteRoadEvent? passedCommunityReport(RouteOption route, double along) =>
    route.roadEvents.where((e) {
      final behind = along - (e.distanceFromStartM + e.lengthM);
      return e.event.source == communityRoadSource && behind >= 0 && behind <= _askPassedWithinM;
    }).lastOrNull;

/// The colours of the guidance's banner and bar: the brand's navy by day
/// (the dock's), a deep navy at night where a cream panel would glare.
({Color surface, Color text}) _panelColors(BuildContext context) {
  final tokens = LunaTokens.of(context);
  final scheme = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.light
      ? (surface: tokens.dockSurface, text: tokens.dockForeground)
      : (surface: tokens.floatingSurface, text: scheme.onSurface);
}

/// The next maneuver: its arrow, the distance to it, the road to take, the
/// lanes, and the one after when it follows closely.
class _ManeuverBanner extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final colors = _panelColors(context);
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final snap = session.snapshot;
    final banner = snap?.banner;
    final steps = session.route.steps;
    final index = snap?.stepIndex ?? 0;
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final after = index + 2 < steps.length ? steps[index + 2] : null;
    final maneuver = bannerManeuver(banner: banner, steps: steps, stepIndex: index);
    final lanes = banner?.lanes.isNotEmpty ?? false
        ? banner!.lanes
        : session.step?.lanes ?? const [];
    final road = banner?.primary ?? next?.roadName ?? next?.instruction ?? '';
    final distance = snap == null ? null : t.routeDistance(snap.distanceToManeuverM, units);
    final thenClose = after != null && next != null && next.distanceM < 150;
    // Off the route, the maneuver is that of a road the vehicle left: it
    // fades until the new route replaces it, the notice below says why.
    final stale =
        session.phase == GuidancePhase.offRoute || session.phase == GuidancePhase.rerouting;
    return Semantics(
      liveRegion: true,
      // The arrow is a picture: the instruction says the turn in words.
      label: [?distance, next?.instruction ?? road].join(', '),
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        elevation: 4,
        child: AnimatedOpacity(
          opacity: stale ? 0.4 : 1,
          duration: Motion.of(context, Motion.medium),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ManeuverIcon(maneuver: maneuver, size: 76, color: colors.text),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (distance != null)
                            Text(
                              distance,
                              style: theme.textTheme.displaySmall?.copyWith(color: colors.text),
                            ),
                          Text(
                            road,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(color: colors.text),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (lanes.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Center(
                    child: LanesRow(lanes: lanes, color: colors.text),
                  ),
                ],
                if (thenClose) ...[
                  const SizedBox(height: Space.s),
                  Row(
                    children: [
                      Text(
                        t.navigation.guidance.then,
                        style: theme.textTheme.titleSmall?.copyWith(color: colors.text),
                      ),
                      const SizedBox(width: Space.s),
                      ManeuverIcon(maneuver: after.maneuver, size: 28, color: colors.text),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a road event comes from and how recent its data is: the source's
/// credit line (shorter than its full name), else its name, else its id, so
/// the origin always shows; the day as well when the data is not of today.
/// Every road event notice and the route preview name a source this way.
String _eventSource(Translations t, RoadEventSourceStatus? source, String id, DateTime now) =>
    t.roadDataSource(
      source?.attribution ?? source?.name ?? id,
      source?.dataAt ?? source?.lastReadAt,
      now,
    );

/// What the driver should know besides the next maneuver: a new route and
/// why, a closure ahead, off the route, the restriction coming up, the
/// voice that is missing.
class _Notices extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final alert = session.alert;
    // The event an alert already speaks of is not repeated below it.
    final alertEvent = switch (alert) {
      ClosureAheadAlert(:final finding) || NoDetourAlert(:final finding) => finding.event.id,
      RerouteFailedAlert(:final cause?) => cause.event.id,
      _ => null,
    };
    final now = ref.watch(clockProvider)().toLocal();
    // Turns over each minute: how old the last position is.
    final wall = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final along = session.snapshot?.distanceAlongM ?? 0;
    final notices = <Widget>[
      if (ref.watch(demoDriveProvider))
        _Notice(icon: AppIcons.inAppNavigation, text: t.navigation.guidance.demoDrive),
      if (session.aids.alert case final alert?) EnforcementNotice(alert: alert, units: units),
      if (session.positionLost)
        _Notice(icon: AppIcons.error, text: t.navigation.guidance.positionLost, strong: true)
      // Arrived, the position is no longer asked for: its age says nothing.
      else if (session.phase != GuidancePhase.arrived &&
          session.lastFixAt != null &&
          wall.difference(session.lastFixAt!) >= positionStaleAfter)
        _Notice(
          icon: AppIcons.error,
          text: t.navigation.guidance.positionStale(
            minutes: '${wall.difference(session.lastFixAt!).inMinutes}',
          ),
        ),
      if (alert != null)
        _Notice(
          icon: switch (alert) {
            ReroutedAlert() => AppIcons.sync,
            _ => AppIcons.error,
          },
          text: [
            switch (alert) {
              // Rounded as the voice rounds them: 90 seconds are 2 minutes.
              ReroutedAlert(:final extra) => switch (extra == null
                  ? 0
                  : (extra.inSeconds / 60).round()) {
                final minutes when minutes >= 1 => t.navigation.guidance.reroutedLonger(
                  minutes: '$minutes',
                ),
                _ => t.navigation.guidance.rerouted,
              },
              ClosureAheadAlert(:final finding) => t.navigation.guidance.closureAhead(
                distance: t.routeDistance(finding.aheadM, units),
              ),
              NoDetourAlert(:final finding) => t.navigation.guidance.noDetour(
                distance: t.routeDistance(finding.aheadM, units),
              ),
              RerouteFailedAlert(:final failure, :final cause?) =>
                failure?.kind == RouteFailureKind.offline
                    ? t.navigation.guidance.closureOffline(
                        distance: t.routeDistance(cause.aheadM, units),
                      )
                    : t.navigation.guidance.closureFailed(
                        distance: t.routeDistance(cause.aheadM, units),
                      ),
              RerouteFailedAlert(:final failure) =>
                failure?.kind == RouteFailureKind.offline
                    ? t.navigation.guidance.rerouteOffline
                    : t.navigation.guidance.rerouteFailed,
            },
            // The stops the route in use moved, under whichever message
            // tells of it.
            for (final m in alert.moved) t.movedStop(m, lastStop: alert.lastStop, units: units),
          ].join('\n'),
          strong: alert is! ReroutedAlert,
        )
      else if (session.phase == GuidancePhase.rerouting)
        _Notice(icon: AppIcons.sync, text: t.navigation.guidance.rerouting)
      else if (session.phase == GuidancePhase.offRoute)
        _Notice(icon: AppIcons.error, text: t.navigation.guidance.offRoute, strong: true),
      if (session.ahead.isNotEmpty) _WarningAhead(ahead: session.ahead.first, units: units),
      for (final e in session.eventAlerts.where((e) => e.event.id != alertEvent).take(1))
        _Notice(
          icon: AppIcons.error,
          strong: e.event.eventClass == RoadEventClass.closure,
          text: [
            switch (e.event.eventClass) {
              RoadEventClass.closure => t.navigation.guidance.eventClosure(
                distance: t.routeDistance(e.aheadM, units),
              ),
              RoadEventClass.vehicleLimit => t.navigation.guidance.eventLimit(
                distance: t.routeDistance(e.aheadM, units),
              ),
              _ => t.navigation.guidance.eventAhead(distance: t.routeDistance(e.aheadM, units)),
            },
            _eventSource(t, e.source, e.event.source, now),
          ].join('\n'),
        ),
      // The road events of the route itself (lanes closed ahead), each with
      // its source and the age of its data.
      for (final ahead in roadEventsAhead(
        session.route,
        along,
      ).where((a) => !session.eventAlerts.any((e) => e.event.id == a.event.event.id)).take(1))
        _Notice(
          icon: AppIcons.roadEvent(ahead.event.event.eventClass),
          text: [
            t.navigation.guidance.roadEventAhead(
              what: [
                ?ahead.event.event.road,
                t.roadEventWhat(ahead.event.event.eventClass),
              ].join(' · '),
              distance: t.routeDistance(ahead.aheadM, units),
            ),
            if (session.plan.sourceOf(ahead.event.event.source) case final source)
              t.roadDataSource(
                source?.attribution ?? source?.name ?? ahead.event.event.source,
                ahead.event.dataAt ?? source?.dataAt ?? source?.lastReadAt,
                now,
              ),
          ].join('\n'),
        ),
      // A community report just passed: still there, or over?
      if (passedCommunityReport(session.route, along) case final passed?)
        Builder(
          builder: (context) {
            // The page's context: the answer outlives a turn of the phone
            // that rebuilds this notice in the other layout.
            final page = Navigator.of(context, rootNavigator: true).context;
            return _Notice(
              icon: AppIcons.roadEvent(passed.event.eventClass),
              text: t.roadReport.passed(
                what: [?passed.event.road, t.roadEventWhat(passed.event.eventClass)].join(' · '),
              ),
              below: CommunityReportActions(
                onStillThere: () =>
                    unawaited(confirmRoadReport(page, passed.event, at: passed.position)),
                onOver: () => unawaited(clearRoadReport(page, passed.event)),
              ),
            );
          },
        ),
      // At the start, the closures the route was planned around.
      if (alert == null && session.plan.avoidedRoadEvents.isNotEmpty && along < 1500)
        _Notice(
          icon: AppIcons.roadEvent(RoadEventClass.closure),
          text: [
            t.navigation.guidance.avoidedClosures(n: session.plan.avoidedRoadEvents.length),
            for (final id in {for (final e in session.plan.avoidedRoadEvents) e.source})
              _eventSource(t, session.plan.sourceOf(id), id, now),
          ].join('\n'),
        ),
      if (session.voiceOn && session.voice != VoiceReadiness.ready && !session.voiceNoticeClosed)
        _VoiceNotice(session: session),
    ];
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notices)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: n,
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const new({required this.icon, required this.text, this.strong = false, this.action, this.below});

  final IconData icon;
  final String text;
  final bool strong;
  final Widget? action;

  /// Answers under the text (a community report's).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = strong ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = strong ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                  ),
                  ?action,
                ],
              ),
              if (below case final below?) ...[const SizedBox(height: Space.s), below],
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningAhead extends StatelessWidget {
  const new({required this.ahead, required this.units});

  final WarningAhead ahead;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xxs),
        child: WarningTile(warning: ahead.warning, units: units, aheadM: ahead.aheadM),
      ),
    );
  }
}

class _VoiceNotice extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final language = t.languageName(session.plan.applied.language.name);
    final missing = session.voice == VoiceReadiness.missingData;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return _Notice(
      icon: AppIcons.offline,
      text: [
        if (missing)
          t.navigation.guidance.missingVoice(language: language)
        else
          t.navigation.guidance.noVoice(language: language),
        if (ios) t.navigation.guidance.voiceSettingsIos,
      ].join(' '),
      // Said once is enough: the driver may close it for the trip.
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (missing && !ios)
            TextButton(
              onPressed: () => ref.read(guidanceControllerProvider.notifier).installVoices(),
              child: Text(t.navigation.guidance.installVoice),
            ),
          IconButton(
            tooltip: t.common.close,
            onPressed: () => ref.read(guidanceControllerProvider.notifier).closeVoiceNotice(),
            icon: const Icon(AppIcons.close),
          ),
        ],
      ),
    );
  }
}

class _MapButtons extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(guidanceControllerProvider.notifier);
    final overview = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.overview),
    );
    final placesShown =
        ref.watch(routeSettingsControllerProvider).value?.guidancePlaces.shown ?? true;
    final style = IconButton.styleFrom(
      backgroundColor: scheme.surfaceContainerLowest,
      foregroundColor: scheme.onSurface,
      minimumSize: const Size(56, 56),
      elevation: 3,
    );
    return Column(
      children: [
        IconButton(
          tooltip: session.voiceOn ? t.navigation.guidance.voiceOff : t.navigation.guidance.voiceOn,
          style: style,
          onPressed: () => controller.setVoice(on: !session.voiceOn),
          icon: Icon(session.voiceOn ? AppIcons.voiceOn : AppIcons.voiceOff),
        ),
        const SizedBox(height: Space.s),
        IconButton(
          // The tooltip is also what a screen reader says: it tells the state.
          tooltip: placesShown
              ? t.navigation.guidance.places.button
              : t.navigation.guidance.places.buttonHidden,
          style: style,
          onPressed: () =>
              unawaited(showGuidancePlacesSheet(context, startInset: guidanceSheetInset)),
          icon: Icon(placesShown ? AppIcons.point : AppIcons.address),
        ),
        const SizedBox(height: Space.s),
        IconButton(
          tooltip: t.navigation.onTheWay.title,
          style: style,
          onPressed: () => unawaited(openOnTheWay(context, session)),
          icon: const OnTheWayIcon(),
        ),
        const SizedBox(height: Space.s),
        // What is seen on the road, where the vehicle is now.
        IconButton(
          tooltip: t.roadReport.actionHint,
          style: style,
          // No position yet: nothing to place a report at.
          onPressed: session.lastFix == null
              ? null
              : () {
                  final fix = session.lastFix;
                  final snap = session.snapshot;
                  final at = snap != null && !snap.offRoute ? snap.position : fix?.position;
                  if (at == null) return;
                  unawaited(
                    reportOnRoad(
                      context,
                      position: at,
                      headingDeg: fix?.courseDeg ?? snap?.courseDeg,
                    ),
                  );
                },
          icon: const Icon(AppIcons.report),
        ),
        const SizedBox(height: Space.s),
        IconButton(
          tooltip: overview ? t.navigation.guidance.recenter : t.navigation.guidance.overview,
          style: style,
          onPressed: () => ref.read(guidanceCameraProvider.notifier).toggleOverview(),
          icon: Icon(overview ? AppIcons.locateActive : AppIcons.map),
        ),
      ],
    );
  }
}

/// The arrival time, the time and distance left, the speed and its limit,
/// and the way out.
class _BottomBar extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final colors = _panelColors(context);
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    // Each minute too: with no new position, the arrival time still moves
    // on with the clock rather than slide into the past.
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final snap = session.snapshot;
    final left = snap?.durationRemainingS ?? session.route.durationS;
    final eta = arrivalAt(now: now, lastFixAt: session.lastFixAt, leftS: left).toLocal();
    final remaining = snap?.distanceRemainingM ?? session.route.distanceM;
    final speed = session.lastFix?.speedMps;
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusXl)),
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
          child: Row(
            children: [
              SpeedAndLimit(speedMps: speed, aids: session.aids, units: units, color: colors.text),
              const SizedBox(width: Space.m),
              Expanded(
                child: Semantics(
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.navigation.guidance.arrival(time: t.clockTime(eta)),
                        style: theme.textTheme.headlineSmall?.copyWith(color: colors.text),
                      ),
                      Text(
                        '${t.routeDuration(left)} · ${t.routeDistance(remaining, units)}',
                        style: theme.textTheme.titleMedium?.copyWith(color: colors.text),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: t.navigation.guidance.end,
                iconSize: 28,
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  foregroundColor: colors.text,
                ).copyWith(side: focusRingIn(colors.text)),
                onPressed: () async {
                  if (await _confirmEnd(context) && context.mounted) _end(ref);
                },
                icon: const Icon(AppIcons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The arrival: the place reached, what the app may ask about it (when a
/// contribution flow registered), and the way back to the map.
class _ArrivalCard extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final confirmation = ref.watch(arrivalConfirmationProvider);
    final placeId = session.target.placeId;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ManeuverIcon(
                    maneuver: const Maneuver(type: 'arrive'),
                    size: 44,
                    color: scheme.secondary,
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            t.navigation.guidance.arrivedTitle,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        if (session.target.label != null)
                          Text(session.target.label!, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              if (confirmation != null && placeId != null) ...[
                OutlinedButton(
                  onPressed: () => unawaited(confirmation.confirm(placeId)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  child: Text(confirmation.label(t.$meta.locale.languageCode)),
                ),
                const SizedBox(height: Space.s),
              ],
              FilledButton(
                onPressed: () => _end(ref),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                child: Text(t.navigation.guidance.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
