import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/perf/timeline_mark.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/rich_marks_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
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
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/features/navigation/presentation/widgets/guidance_panels.dart';
import 'package:lunaway/features/navigation/presentation/widgets/legs_strip.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/on_the_way_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/panels_beside_buttons.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_marks_overlay.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/features/navigation/presentation/widgets/voice_mode_icon.dart';
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
    timelineMark('lunaway-guidance-screen');
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
    // The end of a danger zone or a section just left, and the rule of a
    // country just entered: news of a moment, each told once. The end goes
    // at once when another alert takes the screen before its time is over.
    ref.listenManual(guidanceControllerProvider.select((s) => s?.aids.exit), (before, exit) {
      if (exit != null) {
        if (mounted) _say(alertExitNotice(context.t, exit));
      } else if (before != null && ref.read(guidanceControllerProvider)?.aids.alert != null) {
        // Another alert took the screen: the end of the last one is old news.
        _notices.withdraw(alertExitNoticeId(before));
      }
    });
    ref.listenManual(guidanceControllerProvider.select((s) => s?.aids.ruleChange), (
      before,
      change,
    ) {
      if (change != null && mounted) _say(ruleChangeNotice(context.t, change));
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
        } else if (!arrived &&
            ref.read(guidanceCameraProvider).mode == GuidanceCameraMode.overview) {
          // A back from the whole route closes that view, as "Recentrer"
          // does: the guidance goes on, so nothing is asked.
          ref.read(guidanceCameraProvider.notifier).recenter();
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

/// Asked by the cross and by a back alike, in the same words: a back may
/// have meant the map, a touch of the cross may have missed another button.
Future<bool> _confirmStop(BuildContext context) async {
  final t = context.t;
  final end = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.navigation.guidance.stopTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.navigation.guidance.endKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.navigation.guidance.stopConfirm),
        ),
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
  /// The bottom bar's height as it was laid out: large text and its options
  /// make it taller, and what stands over the map stays above it.
  double _bar = 140;

  /// The arrival's card's height as laid out: the map's credit stands
  /// above it.
  double _card = 0;

  /// The banner's and the notices' heights as laid out: the places drawn
  /// large keep below them.
  double _banner = 0;
  double _notices = 0;

  /// The tallest the notices have stood since "Tout le trajet" opened: the
  /// route framed below them stays put while a message comes and goes.
  double _overviewNotices = 0;

  /// Where the buttons' column and the foot of the map stand, as laid out.
  final _over = _OverTheMap();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final arrived = session.phase == GuidancePhase.arrived;
    final above = (arrived ? _card : _bar) + Space.s;
    final safe = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final overview = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.overview),
    );
    _overviewNotices = overview ? math.max(_overviewNotices, _notices) : 0;
    final padding = EdgeInsets.only(top: 220, bottom: _bar);
    // The foot of the map on the left (the credit over the speed, or
    // "Recentrer"), left of the road behind the vehicle: under the
    // maneuver, the credit covered the road ahead.
    final footLeft = safe.left + Space.s;
    final following = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.follow),
    );
    // Away from following, the vehicle is elsewhere: "Recentrer" may run
    // up to the buttons.
    final footRight = following
        ? math.max(safe.right + Space.s, screen.width - _vehicleColumn(screen, padding))
        : safe.right + _buttonsColumn;
    final pill = arrived ? Size.zero : _over.pill ?? Size.zero;
    // The credit keeps left of the road behind the vehicle, wherever the
    // map is.
    final creditRight = math.max(
      safe.right + Space.s,
      screen.width - _vehicleColumn(screen, padding),
    );
    // The middle of the foot (the road's name, or the stops' strip of the
    // overview), centred on the screen, aside only as far as the pill and
    // the column require, as its CentredClear places it.
    final middleFrom = pill.width > 0 ? footLeft + pill.width + Space.s : safe.left + Space.s;
    Rect middle(Size size) {
      final span = centredSpan(
        centre: screen.width / 2,
        width: size.width,
        lo: middleFrom,
        hi: screen.width - safe.right - _buttonsColumn,
      );
      return Rect.fromLTWH(span.left, screen.height - above - size.height, span.width, size.height);
    }

    Rect atFoot(Size size) =>
        Rect.fromLTWH(footLeft, screen.height - above - size.height, size.width, size.height);
    // The map's credit over the pill, and over the middle where it reaches
    // under the credit (the stops' strip of the overview).
    var creditBottom = arrived
        ? _card + Space.xs
        : above + (pill.height > 0 ? pill.height + Space.xs : 0);
    if ((_over.middle, _over.credit) case (final size?, final credit?) when !size.isEmpty) {
      if (middle(size).left < footLeft + credit.width + Space.s) {
        creditBottom = math.max(creditBottom, above + size.height + Space.xs);
      }
    }
    Rect creditRect(Size size) => Rect.fromLTWH(
      footLeft,
      screen.height - creditBottom - size.height,
      size.width,
      size.height,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: _GuidanceMap(
            session: session,
            padding: padding,
            stripBottom: above - _bar,
            // "Recentrer" at the foot of the whole route.
            footRoom: above - _bar + (pill.height > 0 ? pill.height + Space.s : 0),
            clear: EdgeInsets.fromLTRB(
              safe.left,
              safe.top + Space.s + _banner + (_notices > 0 ? Space.s + _notices : 0),
              safe.right,
              above,
            ),
            // Only "Tout le trajet" holds its room: the fit before the first
            // position follows the notices as they are.
            overviewTop: overview
                ? safe.top +
                      Space.s +
                      _banner +
                      (_overviewNotices > 0 ? Space.s + _overviewNotices : 0)
                : null,
            obstacles: arrived
                ? [if (_over.credit case final size?) creditRect(size)]
                : _over.rects(
                    // At the bottom right, over the bar.
                    buttons: (size) => Rect.fromLTWH(
                      screen.width - safe.right - Space.s - size.width,
                      screen.height - above - size.height,
                      size.width,
                      size.height,
                    ),
                    pill: atFoot,
                    credit: creditRect,
                    middle: middle,
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
                    child: ManeuverPanel(session: session),
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
        Positioned(
          left: footLeft,
          right: creditRight,
          bottom: creditBottom,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: ReportsRect(
              onRect: (rect) {
                if (rect.size != _over.credit) setState(() => _over.credit = rect.size);
              },
              child: const _MapSideCredit(photosCredited: true),
            ),
          ),
        ),
        if (!arrived)
          Positioned(
            left: footLeft,
            right: footRight,
            bottom: above,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: ReportsRect(
                onRect: (rect) {
                  if (rect.size != _over.pill) setState(() => _over.pill = rect.size);
                },
                child: _FootPill(session: session),
              ),
            ),
          ),
        // The road the vehicle is on, under it; the stops of the trip in the
        // overview.
        if (!arrived)
          Positioned(
            left: 0,
            right: 0,
            bottom: above,
            child: CentredClear(
              obstacles: [SideRoom.left(middleFrom), SideRoom.right(safe.right + _buttonsColumn)],
              child: ReportsRect(
                onRect: (rect) {
                  if (rect.size != _over.middle) setState(() => _over.middle = rect.size);
                },
                child: _FootMiddle(session: session),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: arrived
              ? ReportsHeight(
                  onHeight: (height) {
                    if (mounted && height != _card) setState(() => _card = height);
                  },
                  child: _ArrivalCard(session: session),
                )
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

/// How the guidance's map draws the places drawn large, read by the map and
/// by its credit alike: photos while the user chose them, the API answers
/// and the layout writes their sources ([credited], [_MapSideCredit]).
RichStyle _richStyle(BuildContext context, WidgetRef ref, {bool credited = true}) {
  final fromTiles = ref.watch(placesFromTilesProvider);
  return RichStyle(
    look:
        (ref.watch(routeSettingsControllerProvider).value?.guidancePlaces ?? const GuidancePlaces())
            .look,
    words: RichWords.of(context.t),
    online: fromTiles,
    credited: credited,
    muted: ref.watch(mutedAuthorIdsProvider),
    labelScale: richLabelScale(MediaQuery.textScalerOf(context)),
  );
}

/// The map's credit ([MapCredit]), over the map at its foot: upright, just
/// above the bar (or the arrival's card), which it made taller when it
/// stood in it; on a screen on its side, beside the panel, which has no
/// height to spare. Left of the road behind the vehicle either way: under
/// the maneuver, it covered the road ahead. Folded since the run's first
/// map, it is the "(i)" alone; in full, it adds the photos' line while a
/// place may show its photo ([RichStyle.photos]). A caption only: a stray
/// touch while driving opens nothing.
class _MapSideCredit extends ConsumerWidget {
  const new({required this.photosCredited});

  /// The layout has room for the photos' line ([_GuidanceMap.photosCredited]).
  final bool photosCredited;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MapCredit(photos: _richStyle(context, ref, credited: photosCredited).photos, caption: true);
}

/// The width of the panel of a wide window, on the left of the map.
const double _sidePanel = 380;

/// The left edge of the column under the vehicle the camera follows over
/// [map] with panels over [padding], with a margin: the arrow is 30 px
/// across, turned whichever way. The road behind the vehicle runs down that
/// column to the foot of the map.
double _vehicleColumn(Size map, EdgeInsets padding) => followAnchor(map, padding).dx - 15 - Space.s;

/// The least room the foot of the map leaves the strip of the stops between
/// the side panel and the buttons' column. A phone on its side leaves 384 at
/// 844 x 390, where "Tout" and one chip showed: the strip goes over the bar
/// there, from the panel's edge to the column (764 at 844 x 390). A tablet
/// on its side keeps the foot of the map (720 at 1180 x 820).
const double _legsBesidePanelMin = 560;

/// The least room the map's credit takes left of the vehicle's column, on a
/// screen on its side: about the line "© OpenStreetMap" or the photos' line
/// at the text's size. A phone on its side leaves 201 at 844 x 390, 99 at
/// 640 x 360, where the credit runs up to the buttons instead.
const double _creditBesideVehicle = 160;

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

  /// The maneuver's height as laid out: the strip of the stops goes over
  /// the bar only where it leaves the maneuver its room.
  double _banner = 0;

  /// Where the buttons' column and "Recentrer" stand, as laid out.
  final _over = _OverTheMap();

  /// Where the map's credit over [map] ends, from the window's right edge:
  /// short of the buttons' column, and short of the column under the
  /// vehicle the camera follows, where the road behind it runs down to the
  /// foot of the map. Up to the buttons, the credit lay over that road in 8
  /// of 12 captures of a phone on its side (844 x 390). A map too narrow to
  /// leave the credit [_creditBesideVehicle] there keeps the room up to the
  /// buttons.
  double _creditRight(Size map, double left) {
    final safe = MediaQuery.paddingOf(context);
    final buttons = safe.right + _buttonsColumn + Space.s;
    final vehicle = _vehicleColumn(map, EdgeInsets.only(left: left));
    return vehicle - left - Space.s >= _creditBesideVehicle
        ? math.max(buttons, map.width - vehicle)
        : buttons;
  }

  /// Whether the map's credit over [map], at its foot, ending [right] from
  /// the window's right edge, keeps clear of the vehicle the camera follows
  /// with the photos' line. Left of the vehicle's column it does at any
  /// height; across it, a narrow map beside the panel with large text wraps
  /// it up to the arrow. Without the room the line goes, and the photos with
  /// it (pictograms need no credit). The credit is taken at the map's foot,
  /// where it stands while the camera follows; in the overview it may stand
  /// higher, over the strip of the stops, but the camera follows no vehicle
  /// there.
  bool _photosRoom(BuildContext context, Size map, double left, double right) {
    // Half a pixel for the rounding of map.width - right.
    if (map.width - right <= _vehicleColumn(map, EdgeInsets.only(left: left)) + 0.5) {
      return true;
    }
    final safe = MediaQuery.paddingOf(context);
    final width = map.width - left - Space.s - right;
    final top =
        map.height - safe.bottom - Space.s - MapCredit.heightOf(context, width, photos: true);
    // The arrow is 30 px across, turned whichever way.
    return top >= followAnchor(map, EdgeInsets.only(left: left)).dy + 15 + Space.s;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final arrived = session.phase == GuidancePhase.arrived;
    final safe = MediaQuery.paddingOf(context);
    final left = safe.left + _sidePanel;
    final mode = ref.watch(guidanceCameraProvider.select((v) => v.mode));
    final overview = mode == GuidanceCameraMode.overview;
    final following = mode == GuidanceCameraMode.follow;
    // The strip of the stops at the foot of the map beside the panel, unless
    // the column of buttons leaves it too little room there: then over the
    // bar, from the panel's edge to the column, as upright, when the panel
    // keeps the maneuver and a notice under it (the stop taken out, with
    // its undo) above the strip.
    final screen = MediaQuery.sizeOf(context);
    final legsHeight = GuidanceLegsStrip.heightOf(context);
    final legsOverBar =
        screen.width - left - Space.s - safe.right - _buttonsColumn < _legsBesidePanelMin &&
        screen.height - safe.vertical - 3 * Space.s - _bar - legsHeight >=
            _banner + Space.s + legsHeight;
    final legsBottom = legsOverBar ? safe.bottom + Space.s + _bar + Space.s : safe.bottom + Space.s;
    final legsFrom = legsOverBar ? safe.left + Space.s : left + Space.s;
    // The notices end above the strip over the bar.
    final legsAbove = legsOverBar && GuidanceLegsStrip.shows(session, overview: overview)
        ? legsHeight
        : 0.0;
    // The foot of the map (the credit over the speed or "Recentrer") at
    // the foot of the map, over the strip when it runs there: the panel of
    // a phone on its side has no height to spare.
    final footBottom = !legsOverBar && GuidanceLegsStrip.shows(session, overview: overview)
        ? legsBottom + legsHeight + Space.xs
        : safe.bottom + Space.s;
    final pill = arrived ? Size.zero : _over.pill ?? Size.zero;
    // The credit at the foot, the pill over it: beside the panel the map may
    // be narrow, and the credit then runs up to the buttons under the
    // vehicle, where the pill would not fit.
    final creditBottom = footBottom;
    final credit = _over.credit;
    final pillBottom =
        footBottom + (credit == null || credit.isEmpty ? 0 : credit.height + Space.xs);
    return LayoutBuilder(
      builder: (context, box) {
        final creditRight = _creditRight(box.biggest, left);
        // Measured once: the map and the credit read the same answer.
        final photos = _photosRoom(context, box.biggest, left, creditRight);
        // The road's name at the foot of the map, centred on it beside the
        // panel, clear of the foot and of the column.
        // The credit shares the foot's line with it; the pill is over it.
        final footWidth = math.max(pill.width, credit?.width ?? 0);
        final roadFrom = Space.s + (footWidth > 0 ? footWidth + Space.s : 0);
        Rect road(Size size) {
          final span = centredSpan(
            centre: (left + box.maxWidth) / 2,
            width: size.width,
            lo: left + roadFrom,
            hi: box.maxWidth - safe.right - _buttonsColumn,
          );
          return Rect.fromLTWH(
            span.left,
            box.maxHeight - safe.bottom - Space.s - size.height,
            span.width,
            size.height,
          );
        }

        Rect atFoot(Size size) => Rect.fromLTWH(
          left + Space.s,
          box.maxHeight - pillBottom - size.height,
          size.width,
          size.height,
        );
        Rect creditRect(Size size) => Rect.fromLTWH(
          left + Space.s,
          box.maxHeight - creditBottom - size.height,
          size.width,
          size.height,
        );
        return Stack(
          children: [
            // The map takes the whole window; its insets keep the vehicle
            // and the route right of the panel.
            Positioned.fill(
              child: _GuidanceMap(
                session: session,
                padding: EdgeInsets.only(left: left),
                stripBottom: legsBottom,
                // "Recentrer" at the foot of the whole route.
                footRoom: pillBottom + (pill.height > 0 ? pill.height + Space.s : 0),
                photosCredited: photos,
                clear: EdgeInsets.fromLTRB(left, safe.top, safe.right, safe.bottom),
                obstacles: arrived
                    // The credit stays over the map at the arrival.
                    ? [if (_over.credit case final size?) creditRect(size)]
                    : _over.rects(
                        buttons: (size) => Rect.fromLTWH(
                          box.maxWidth - safe.right - Space.s - size.width,
                          box.maxHeight - safe.bottom - Space.l - size.height,
                          size.width,
                          size.height,
                        ),
                        pill: atFoot,
                        credit: creditRect,
                        road: road,
                        // As its CentredClear places it.
                        middle: (size) {
                          final span = centredSpan(
                            centre: legsOverBar ? box.maxWidth / 2 : (left + box.maxWidth) / 2,
                            width: size.width,
                            lo: legsFrom,
                            hi: box.maxWidth - safe.right - _buttonsColumn,
                          );
                          return Rect.fromLTWH(
                            span.left,
                            box.maxHeight - legsBottom - size.height,
                            span.width,
                            size.height,
                          );
                        },
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
                  maxHeight: math.max(
                    0,
                    box.maxHeight - safe.vertical - _bar - 3 * Space.s - legsAbove,
                  ),
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
                        if (!arrived)
                          ReportsHeight(
                            onHeight: (height) {
                              if (mounted && height != _banner) setState(() => _banner = height);
                            },
                            child: ManeuverPanel(session: session),
                          ),
                        GuidanceNotices(session: session),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The foot of the map beside the panel, left of the road behind
            // the vehicle ([_creditRight]); the places drawn large keep off it.
            Positioned(
              left: left + Space.s,
              right: creditRight,
              bottom: creditBottom,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: ReportsRect(
                  onRect: (rect) {
                    if (rect.size != _over.credit) setState(() => _over.credit = rect.size);
                  },
                  child: _MapSideCredit(photosCredited: photos),
                ),
              ),
            ),
            if (!arrived)
              Positioned(
                left: left + Space.s,
                // Left of the vehicle while the map follows it; away from
                // following, "Recentrer" may run up to the buttons.
                right: following
                    ? math.max(
                        safe.right + Space.s,
                        box.maxWidth - _vehicleColumn(box.biggest, EdgeInsets.only(left: left)),
                      )
                    : safe.right + _buttonsColumn,
                bottom: pillBottom,
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: ReportsRect(
                    onRect: (rect) {
                      if (rect.size != _over.pill) setState(() => _over.pill = rect.size);
                    },
                    child: _FootPill(session: session),
                  ),
                ),
              ),
            if (!arrived)
              Positioned(
                left: left,
                right: 0,
                bottom: safe.bottom + Space.s,
                child: CentredClear(
                  obstacles: [SideRoom.left(roadFrom), SideRoom.right(safe.right + _buttonsColumn)],
                  child: ReportsRect(
                    onRect: (rect) {
                      if (rect.size != _over.road) setState(() => _over.road = rect.size);
                    },
                    child: _RoadIfFollowing(session: session),
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
            // centred on the map beside the panel, or over the bar, centred on
            // the window; aside only as far as the buttons' column requires.
            if (!arrived)
              Positioned(
                left: legsOverBar ? 0 : left,
                right: 0,
                bottom: legsBottom,
                child: CentredClear(
                  obstacles: [
                    SideRoom.left(legsOverBar ? legsFrom : Space.s),
                    SideRoom.right(safe.right + _buttonsColumn),
                  ],
                  child: ReportsRect(
                    onRect: (rect) => setState(() => _over.middle = rect.size),
                    child: GuidanceLegsStrip(session: session),
                  ),
                ),
              ),
          ],
        );
      },
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
    this.footRoom = 0,
    this.overviewTop,
    this.obstacles = const [],
    this.photosCredited = true,
  });

  final GuidanceSession session;
  final EdgeInsets padding;

  /// The layout writes the photos' sources ([_MapSideCredit]): without that
  /// line, no photo.
  final bool photosCredited;

  /// How far above the bottom of [padding] the strip of the stops stands,
  /// when the overview shows it.
  final double stripBottom;

  /// How far above the bottom of [padding] the foot of the map stands in
  /// the overview ("Recentrer"): the whole route keeps clear of it.
  final double footRoom;

  /// The edges of the map the banner, the notices, the bar or the side
  /// panel cover: no place drawn large lies under them.
  final EdgeInsets clear;

  /// How far down the whole route's fit keeps clear of the banner and the
  /// notices; [clear]'s top when null.
  final double? overviewTop;

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
    final aim = ref.watch(guidanceAimProvider);
    final cameraModes = ref.read(guidanceCameraProvider.notifier);
    // The whole route, or the leg chosen in the strip of the stops, stays
    // clear of the column of buttons on the right (the arrival under the
    // voice button could not be seen), of the strip, and of the banner with
    // its notices, which can reach below the map's fixed top (a zone's
    // notice covered the vehicle and a stop).
    final legs = view.mode == GuidanceCameraMode.overview && session.stops.isNotEmpty
        ? guidanceLegs(session)
        : const <RouteLeg>[];
    final framed = legs.where((l) => l.to == view.legTo).firstOrNull;
    final overview = FitCamera(
      framed?.bounds ?? whole,
      room: EdgeInsets.only(
        top: math.max(0, (overviewTop ?? clear.top) - padding.top),
        right: _buttonsColumn,
        bottom: math.max(
          footRoom,
          legs.isEmpty ? 0 : stripBottom + GuidanceLegsStrip.heightOf(context),
        ),
      ),
    );
    final camera = switch (view.mode) {
      GuidanceCameraMode.free => FreeCamera(view: view.rest),
      GuidanceCameraMode.overview => overview,
      GuidanceCameraMode.follow when vehicle == null => overview,
      GuidanceCameraMode.follow => FollowCamera(
        position: vehicle!.position,
        course: vehicle.course,
        zoom: aim.zoom,
        tilt: aim.tilt,
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
            poiTileJsonUrl: ref.watch(
              poiTileJsonUrlProvider(all: guidanceReadsEveryCategory(choice)),
            ),
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
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    // Only where the rule of the country the vehicle is in shows points
    // while driving, and the camera's own: never in France unless asked.
    final cameras = {
      for (final m in [
        for (final c in session.aids.cameras) ?cameraMarker(c, context.t, units: units),
      ])
        m.id: m,
    };
    final marks = richMarksFor(MediaQuery.sizeOf(context));
    // Where the vehicle is along the route, for the marks that count from
    // it; none off the route, where a distance along it means nothing.
    final alongOnRoute = snap == null || snap.offRoute ? null : snap.distanceAlongM;

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
          for (final c in cameras.values) c.mark,
        ],
        vehicle: vehicle,
        camera: camera,
        padding: padding,
        guiding: true,
        // Only what the rule of the country the vehicle is in allows while
        // driving: zones in France, nothing in Germany or Switzerland.
        zones: session.aids.zones,
        traveledM: alongOnRoute,
        arrow: ref.watch(guidanceArrowProvider),
        places: tiles,
        rich: RouteMapRich(
          style: _richStyle(context, ref, credited: photosCredited),
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
          vehicleAlongM: alongOnRoute,
          speedMps: session.lastFix?.speedMps,
        ),
        onMarkTap: (id, {at}) {
          if (cameras[id] case final camera?) {
            unawaited(
              showMarkCard(
                context,
                camera,
                units: units,
                now: now,
                // Off the route its distance along means nothing: the card
                // then says where the camera is from the start.
                alongM: alongOnRoute,
              ),
            );
          } else if (points.pointOf(id, context.t, now) case final point?) {
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
          if (magnetHolds(
            rest,
            padding: padding,
            followZoom: ref.read(guidanceAimProvider).zoom,
            course: vehicle?.course,
            followTilt: ref.read(guidanceAimProvider).tilt,
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

  /// At the foot of the map on the left: the speed or "Recentrer"
  /// ([_FootPill]), the map's credit over it.
  Size? pill;
  Size? credit;

  /// The middle of the foot: the road's name and the stops' strip upright,
  /// the stops' strip on a screen on its side.
  Size? middle;

  /// The road's name on a screen on its side.
  Size? road;

  /// Their rooms on the map, placed by the layout's anchors.
  List<Rect> rects({
    required Rect Function(Size size) buttons,
    required Rect Function(Size size) pill,
    required Rect Function(Size size) credit,
    required Rect Function(Size size) middle,
    Rect Function(Size size)? road,
  }) => [
    if (this.buttons case final size?) buttons(size),
    if (this.pill case final size? when !size.isEmpty) pill(size),
    if (this.credit case final size? when !size.isEmpty) credit(size),
    if (this.middle case final size? when !size.isEmpty) middle(size),
    if ((this.road, road) case (final size?, final place?) when !size.isEmpty) place(size),
  ];
}

/// At the foot of the map on the left, as a driver's app sets it: the
/// speed and its limit while the map follows the vehicle, "Recentrer" once
/// the user moved the map or opened the whole route; the speed gives way
/// to the way back. In the overview with stops ahead, their strip takes the
/// foot and the bar's button leads back.
class _FootPill extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(guidanceCameraProvider.select((v) => v.mode));
    final strip = GuidanceLegsStrip.shows(session, overview: mode == GuidanceCameraMode.overview);
    final (key, below) = switch (mode) {
      GuidanceCameraMode.follow => ('foot: speed', _SpeedNow(session: session)),
      GuidanceCameraMode.overview when strip => ('foot: none', null),
      _ => ('foot: recenter', const _RecenterButton()),
    };
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.short),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) =>
          Stack(alignment: AlignmentDirectional.bottomStart, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          alignment: Alignment.bottomLeft,
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(key),
        child: switch (below) {
          null => const SizedBox.shrink(),
          // A map a few dozen pixels wide (a window on its side beside the
          // panel) draws the speed smaller, whole; "Recentrer" turns to
          // its icon by itself.
          _SpeedNow() => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.bottomStart,
            child: below,
          ),
          _ => below,
        },
      ),
    );
  }
}

/// The middle of the foot of the map upright: the strip of the stops in the
/// overview, else the road the vehicle is on while the map follows it.
class _FootMiddle extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GuidanceLegsStrip(session: session),
      _RoadIfFollowing(session: session),
    ],
  );
}

/// The road the vehicle is on ([RoadNamePill]), while the map follows it.
class _RoadIfFollowing extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.follow),
    );
    return following ? RoadNamePill(session: session) : const SizedBox.shrink();
  }
}

/// Back behind the vehicle, at the foot of the map once the user moved it
/// away or opened the whole route: its icon and its word on a pill, or the
/// icon alone (the word in its tooltip) where the room is too narrow for
/// both.
class _RecenterButton extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = LunaTokens.of(context);
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
        final wide = box.maxWidth >= words.width + 24 + Space.s + 2 * Space.l + Space.s;
        words.dispose();
        final colors = (background: tokens.floatingSurface, foreground: tokens.guidanceTime);
        return wide
            ? FilledButton.icon(
                key: const ValueKey('recenter'),
                onPressed: recenter,
                icon: const Icon(AppIcons.locateActive),
                label: Text(label),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  elevation: 3,
                  shape: const StadiumBorder(),
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
      // The stop's number names one of equal stops.
      final at = point.stopIndex;
      await removeGuidanceStop(
        container,
        messenger,
        t,
        stop,
        copiesAfter: at != null && at < opened.stops.length && opened.stops[at] == stop
            ? equalStopsAfter(opened.stops, at)
            : 0,
      );
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

/// The voice mode, moved on by each tap: full, alerts only, muted, full
/// again, with nothing to open or confirm. The icon shows the mode, the
/// tooltip names it, and a screen reader hears what the new one does.
class _VoiceModeButton extends ConsumerWidget {
  const new({required this.mode, required this.style});

  final VoiceMode mode;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    // One node for the screen reader: the mode as its label, what a tap
    // does as its hint. The full path of each key: the translation gate
    // finds them so.
    return MergeSemantics(
      child: Semantics(
        hint: switch (mode.next) {
          VoiceMode.full => t.navigation.guidance.voiceMode.toFull,
          VoiceMode.alerts => t.navigation.guidance.voiceMode.toAlerts,
          VoiceMode.muted => t.navigation.guidance.voiceMode.toMuted,
        },
        child: IconButton(
          tooltip: switch (mode) {
            VoiceMode.full => t.navigation.guidance.voiceMode.full,
            VoiceMode.alerts => t.navigation.guidance.voiceMode.alerts,
            VoiceMode.muted => t.navigation.guidance.voiceMode.muted,
          },
          style: style,
          onPressed: () {
            final next = ref.read(guidanceControllerProvider.notifier).cycleVoiceMode();
            if (next == null) return;
            unawaited(
              SemanticsService.sendAnnouncement(View.of(context), switch (next) {
                VoiceMode.full => t.navigation.guidance.voiceMode.saysFull,
                VoiceMode.alerts => t.navigation.guidance.voiceMode.saysAlerts,
                VoiceMode.muted => t.navigation.guidance.voiceMode.saysMuted,
              }, Directionality.of(context)),
            );
          },
          icon: VoiceModeIcon(mode),
        ),
      ),
    );
  }
}

/// The map's buttons on the right, over the bar: the voice, the places on
/// the map, what lies on the way, a report of the road. The whole route is
/// on the bar.
class _MapButtons extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final style = IconButton.styleFrom(
      backgroundColor: tokens.floatingSurface,
      foregroundColor: scheme.onSurface,
      minimumSize: const Size(56, 56),
      elevation: 3,
    );
    final placesShown =
        ref.watch(routeSettingsControllerProvider).value?.guidancePlaces.shown ?? true;
    return Column(
      children: [
        _VoiceModeButton(mode: session.voiceMode, style: style),
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
          onPressed: _reportAt(session) == null ? null : () => _report(context, session),
          icon: const Icon(AppIcons.report),
        ),
      ],
    );
  }
}

/// Where a report of the road stands: the vehicle on the route, else its
/// last fix; null before any.
LatLng? _reportAt(GuidanceSession session) {
  final snap = session.snapshot;
  return snap != null && !snap.offRoute ? snap.position : session.lastFix?.position;
}

void _report(BuildContext context, GuidanceSession session) {
  final at = _reportAt(session);
  if (at == null) return;
  unawaited(
    reportOnRoad(
      context,
      position: at,
      headingDeg: session.lastFix?.courseDeg ?? session.snapshot?.courseDeg,
    ),
  );
}

/// The foot of the guidance, as a driver's app sets it: the way out on the
/// left, the time left large in the middle with the distance and the
/// arrival under it, the whole route on the right. A tap on the middle, or
/// a swipe up, opens the guidance's options under it: what lies on the
/// way, the places on the map, a report.
class _BottomBar extends ConsumerStatefulWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  ConsumerState<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends ConsumerState<_BottomBar> {
  bool _open = false;

  void _show({required bool open}) {
    if (open != _open) setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = LunaTokens.of(context);
    final session = widget.session;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    // Each minute too: with no new position, the arrival time still moves
    // on with the clock rather than slide into the past.
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final snap = session.snapshot;
    final left = snap?.durationRemainingS ?? session.route.durationS;
    final eta = t.clockTime(
      arrivalAt(now: now, lastFixAt: session.lastFixAt, leftS: left).toLocal(),
    );
    final remaining = t.routeDistance(snap?.distanceRemainingM ?? session.route.distanceM, units);
    final overview = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.overview),
    );
    // A ring round each of the bar's two buttons, the keyboard's focus
    // ring in its place.
    final ring =
        IconButton.styleFrom(
          minimumSize: const Size(56, 56),
          foregroundColor: scheme.onSurface,
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (s) => keyboardFocused(s)
                ? focusRing(scheme.onSurface)
                : BorderSide(color: scheme.outline, width: 1.5),
          ),
        );
    void toggle() => _show(open: !_open);
    return Material(
      color: tokens.floatingSurface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusXl)),
      elevation: 6,
      child: SafeArea(
        top: false,
        // A swipe up opens the options, a swipe down closes them.
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            final speed = details.primaryVelocity ?? 0;
            if (speed < -150) _show(open: true);
            if (speed > 150) _show(open: false);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The handle says the bar opens; the middle of the bar and a
                // swipe open it, a finger's size.
                ExcludeSemantics(
                  child: SizedBox(
                    height: 22,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: t.navigation.guidance.end,
                      iconSize: 28,
                      style: ring,
                      onPressed: () async {
                        if (await _confirmStop(context) && context.mounted) _end(ref);
                      },
                      icon: const Icon(AppIcons.close),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: InkWell(
                        onTap: toggle,
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        borderRadius: BorderRadius.circular(LunaTokens.radiusM),
                        child: Semantics(
                          container: true,
                          button: true,
                          expanded: _open,
                          hint: t.navigation.guidance.options,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.routeDuration(left),
                                  maxLines: 1,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    color: tokens.guidanceTime,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Semantics(
                                  label: '$remaining, ${t.navigation.guidance.arrival(time: eta)}',
                                  excludeSemantics: true,
                                  child: Text(
                                    '$remaining · $eta',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    IconButton(
                      tooltip: overview
                          ? t.navigation.guidance.recenter
                          : t.navigation.guidance.overview,
                      style: ring,
                      onPressed: () => ref.read(guidanceCameraProvider.notifier).toggleOverview(),
                      icon: Icon(overview ? AppIcons.locateActive : AppIcons.map),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: Motion.of(context, Motion.medium),
                  curve: Motion.standard,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? _BarOptions(session: session, onChosen: () => _show(open: false))
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The guidance's options, under the time left once the bar is opened:
/// what lies on the way, the places on the map, a report of the road. A
/// choice closes them.
class _BarOptions extends ConsumerWidget {
  const new({required this.session, required this.onChosen});

  final GuidanceSession session;
  final VoidCallback onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final placesShown =
        ref.watch(routeSettingsControllerProvider).value?.guidancePlaces.shown ?? true;
    Widget option(Widget icon, String label, VoidCallback? onTap) => ListTile(
      leading: icon,
      title: Text(label),
      minTileHeight: 56,
      enabled: onTap != null,
      onTap: onTap == null
          ? null
          : () {
              onChosen();
              onTap();
            },
    );
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          option(
            const OnTheWayIcon(),
            t.navigation.onTheWay.title,
            () => unawaited(openOnTheWay(context, session)),
          ),
          option(
            Icon(placesShown ? AppIcons.point : AppIcons.address),
            placesShown
                ? t.navigation.guidance.places.button
                : t.navigation.guidance.places.buttonHidden,
            () => unawaited(showGuidancePlacesSheet(context, startInset: guidanceSheetInset)),
          ),
          option(
            const Icon(AppIcons.report),
            t.roadReport.actionHint,
            _reportAt(session) == null ? null : () => _report(context, session),
          ),
        ],
      ),
    );
  }
}

/// The speed and its limit, the speed while its position is fresh
/// ([speedShown]): with no position for a few seconds the figure goes, and
/// comes back with the next one.
class _SpeedNow extends ConsumerStatefulWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  ConsumerState<_SpeedNow> createState() => _SpeedNowState();
}

class _SpeedNowState extends ConsumerState<_SpeedNow> {
  /// Rebuilds when the speed shown goes stale: no new position rebuilds
  /// the foot then.
  Timer? _stale;

  @override
  void dispose() {
    _stale?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final now = ref.watch(clockProvider)();
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final speed = speedShown(fix: session.lastFix, cameAt: session.lastFixAt, now: now);
    _stale?.cancel();
    final cameAt = session.lastFixAt;
    if (speed != null && cameAt != null) {
      _stale = Timer(cameAt.add(speedStaleAfter).difference(now), () {
        if (mounted) setState(() {});
      });
    }
    return SpeedAndLimit(speedMps: speed, aids: session.aids, units: units);
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
