import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_legs.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/guidance_notices.dart';
import 'package:lunaway/features/navigation/presentation/guidance_places_sheet.dart';
import 'package:lunaway/features/navigation/presentation/guidance_stops.dart';
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
import 'package:lunaway/features/navigation/presentation/widgets/lanes_row.dart';
import 'package:lunaway/features/navigation/presentation/widgets/legs_strip.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/on_the_way_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/panels_beside_buttons.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/centred_clear.dart';
import 'package:lunaway/shared/widgets/measured.dart';
import 'package:lunaway/shared/widgets/notice_views.dart';

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

class _GuidanceScreenState extends ConsumerState<GuidanceScreen> implements MessageSink {
  /// The page asked to leave: once is enough (in a browser the page goes
  /// when the history has moved, a moment later).
  bool _leaving = false;

  /// The guidance's notices: those the guidance tells of, and the app's
  /// messages while the page is up ([MessageSink]), at the top under the
  /// maneuver; a message at the foot would cover the driver's bar.
  final _notices = NoticeBoard();
  void Function()? _unredirect;
  ScaffoldMessengerState? _messenger;

  /// The last message shown here with its undo, and how many were told.
  PassingNotice? _told;
  int _tells = 0;

  /// The lines of moved stops told under [_told].
  List<String> _toldLines = const [];

  /// The notice of the stops the new route of the user's own change moved,
  /// with their lines: the message about that change, coming next, takes
  /// them under its words rather than replace them.
  ({PassingNotice notice, List<String> lines})? _movedByChange;

  @override
  void initState() {
    super.initState();
    // Kept for the page's life, above both layouts: a notice shown goes on
    // when the phone turns.
    ref.listenManual(guidanceControllerProvider.select((s) => s?.alert), (before, alert) {
      if (alert != null && !identical(alert, before)) _sayAlert(alert);
    });
    ref.listenManual(guidanceControllerProvider.select((s) => s?.phase), (before, phase) {
      if (phase == GuidancePhase.rerouting) {
        _say(searchingNotice(context.t));
      } else if (before == GuidancePhase.rerouting) {
        _notices.withdraw(searchingNoticeId);
      }
    });
    ref.listenManual(guidanceControllerProvider.select((s) => s?.plan), (before, plan) {
      if (plan != null && !identical(plan, before)) _sayAvoided(plan);
    });
    // The route the guidance starts on: its closures gone round, once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(guidanceControllerProvider)?.plan case final plan? when mounted) {
        _sayAvoided(plan);
      }
    });
  }

  DistanceUnits get _units =>
      ref.read(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;

  void _sayAvoided(RoutePlan plan) {
    final notice = avoidedNotice(context.t, plan, ref.read(clockProvider)().toLocal());
    if (notice != null) _say(notice);
  }

  void _say(PassingNotice notice) {
    if (mounted) _notices.say(notice);
  }

  void _sayAlert(GuidanceAlert alert) {
    if (!mounted) return;
    final t = context.t;
    final notice = alertNotice(t, _units, alert);
    final byUser =
        alert is ReroutedAlert &&
        (alert.reason == RerouteReason.stops || alert.reason == RerouteReason.destination);
    if (!byUser || alert.moved.isEmpty) {
      _say(notice);
      return;
    }
    final lines = [
      for (final m in alert.moved) t.movedStop(m, lastStop: alert.lastStop, units: _units),
    ];
    // The user's own change said first (a stop taken out, with its undo):
    // the stops its new route moved go under its words, its undo kept.
    if (_told case final told? when identical(_notices.current, told)) {
      _toldLines = [..._toldLines, ...lines];
      _say(
        _told = PassingNotice(
          id: told.id,
          text: [told.text, ...lines].join('\n'),
          icon: told.icon,
          action: told.action,
        ),
      );
      return;
    }
    _movedByChange = (notice: notice, lines: lines);
    _say(notice);
  }

  @override
  void tell(String text, {SnackBarAction? action}) {
    // The change the new route was for, said after it (a stop added): the
    // moves it told stay, under the change's words.
    final moved = _movedByChange;
    _movedByChange = null;
    final under = [
      if (moved != null && identical(_notices.current, moved.notice)) ...moved.lines,
      // Two changes in a row (a stop out, then one added at once): the
      // moves the second one's route told under the first one's notice
      // go on under this one's.
      if (action != null && _told != null && identical(_notices.current, _told)) ..._toldLines,
    ];
    final notice = PassingNotice(
      id: ('told', ++_tells),
      text: [text, ...under].join('\n'),
      action: action == null
          ? null
          : NoticeAction(label: action.label, onPressed: action.onPressed),
    );
    if (action != null) {
      _told = notice;
      _toldLines = under;
    }
    _say(notice);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notices.assisted = MediaQuery.accessibleNavigationOf(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!identical(messenger, _messenger)) {
      _unredirect?.call();
      _messenger = messenger;
      _unredirect = messenger == null ? null : redirectMessages(messenger, this);
    }
  }

  @override
  void dispose() {
    forgetGuidanceLegs();
    _unredirect?.call();
    _notices.dispose();
    super.dispose();
  }

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
          // The app's messages show here with the guidance's own notices,
          // under the maneuver ([MessageSink]): no message floats at the
          // foot, over the driver's bar.
          child: NoticeScope(
            board: _notices,
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
            stripBottom: above - _bar,
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
              child: GuidanceNotices(session: session),
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
        // The stops of the trip, in the overview: one line over the bar,
        // centred on the screen, aside only as far as the buttons' column
        // requires.
        if (!arrived)
          Positioned(
            left: 0,
            right: 0,
            bottom: above,
            child: CentredClear(
              obstacles: [
                SideRoom.left(safe.left + Space.s),
                SideRoom.right(safe.right + _buttonsColumn),
              ],
              child: GuidanceLegsStrip(session: session),
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
              stripBottom: safe.bottom + Space.s,
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
                      GuidanceNotices(session: session),
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
          // The stops of the trip, in the overview: at the foot of the map,
          // centred on the map beside the panel, aside only as far as the
          // buttons' column requires.
          if (!arrived)
            Positioned(
              left: left,
              right: 0,
              bottom: safe.bottom + Space.s,
              child: CentredClear(
                obstacles: [
                  const SideRoom.left(Space.s),
                  SideRoom.right(safe.right + _buttonsColumn),
                ],
                child: GuidanceLegsStrip(session: session),
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
    required this.stripBottom,
    required this.clear,
    this.obstacles = const [],
  });

  final GuidanceSession session;
  final EdgeInsets padding;

  /// How far above the bottom of [padding] the strip of the stops stands,
  /// when the overview shows it.
  final double stripBottom;

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
    // The whole route, or the leg chosen in the strip of the stops, stays
    // clear of the column of buttons on the right (the arrival under
    // "Couper la voix" could not be seen) and of the strip.
    final legs = view.mode == GuidanceCameraMode.overview && session.stops.isNotEmpty
        ? guidanceLegs(session)
        : const <RouteLeg>[];
    final framed = legs.where((l) => l.to == view.legTo).firstOrNull;
    final overview = FitCamera(
      framed?.bounds ?? whole,
      room: EdgeInsets.only(
        right: _buttonsColumn,
        bottom: legs.isEmpty ? 0 : stripBottom + GuidanceLegsStrip.heightOf(context),
      ),
    );
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
      await saidChange(
        messenger,
        t,
        action: () => controller.applyQuote(quote),
        done: t.navigation.stops.added,
        undo: () => controller.removeStop(quote.stop),
      );
    case RemoveStopChoice(:final stop):
      await removeGuidanceStop(container, messenger, t, stop);
    case GoDirectlyChoice():
      final (target, stops) = (session.target, session.stops);
      await saidChange(
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
  await saidChange(
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
    final type = banner?.maneuverType ?? next?.maneuverType;
    final modifier = banner?.modifier ?? next?.modifier;
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
                    ManeuverIcon(
                      type: type,
                      modifier: modifier,
                      roundaboutExitDegrees: banner?.roundaboutExitDegrees,
                      size: 76,
                      color: colors.text,
                    ),
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
                      ManeuverIcon(
                        type: after.maneuverType,
                        modifier: after.modifier,
                        size: 28,
                        color: colors.text,
                      ),
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
                  ManeuverIcon(type: 'arrive', modifier: null, size: 44, color: scheme.secondary),
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
