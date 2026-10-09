import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_legs.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/guidance_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// The legs of the guidance's route still ahead: to each stop ahead, then
/// to the destination, with the arrival time and distance at each; the
/// moves of the server counted (a stop is reached where the route passes).
List<RouteLeg> guidanceLegs(GuidanceSession session) {
  // The map and the strip ask for the same moment's legs in one frame: a
  // walk along the whole line, once.
  final last = _lastLegs;
  if (last != null &&
      identical(last.route, session.route) &&
      identical(last.stops, session.stops) &&
      identical(last.moves, session.moves) &&
      identical(last.snapshot, session.snapshot) &&
      identical(last.fix, session.lastFix)) {
    return last.legs;
  }
  final legs = _legsOf(session);
  _lastLegs = (
    route: session.route,
    stops: session.stops,
    moves: session.moves,
    snapshot: session.snapshot,
    fix: session.lastFix,
    legs: legs,
  );
  return legs;
}

/// Drops the legs kept for the last moment: the guidance is over.
void forgetGuidanceLegs() => _lastLegs = null;

({
  RouteOption route,
  List<RouteStop> stops,
  StopMoves moves,
  GuidanceSnapshot? snapshot,
  Fix? fix,
  List<RouteLeg> legs,
})?
_lastLegs;

List<RouteLeg> _legsOf(GuidanceSession session) {
  final snap = session.snapshot;
  final destination = session.target.destination;
  return routeLegs(
    route: session.route,
    stops: [
      for (final s in session.stops)
        (asked: s.position, reached: session.moves.stops[s] ?? s.position),
    ],
    destination: (asked: destination, reached: session.moves.destination ?? destination),
    alongM: snap?.distanceAlongM ?? 0,
    leftM: snap?.distanceRemainingM ?? session.route.distanceM,
    leftS: snap?.durationRemainingS ?? session.route.durationS,
    vehicle: session.lastFix?.position,
  );
}

/// The stops of the trip in the overview, one line of chips over the map:
/// "Tout" first, then each leg named by where it leads, its stop's number
/// as on the map, its arrival time and distance. A chip frames the map on
/// its leg, "Tout" on the whole route; the choice lasts as long as the
/// overview. A stop's cross, or a swipe up on its chip, takes it out at
/// once, with the way back in the notice that says so.
class GuidanceLegsStrip extends ConsumerStatefulWidget {
  const new({required this.session, super.key});

  final GuidanceSession session;

  /// The height the strip takes over the map, its chips' shadows included:
  /// the overview keeps the route clear of it.
  static double heightOf(BuildContext context) => controlHeight(context, 48) + 2 * Space.s;

  /// Whether the strip shows: in the overview, while stops lie ahead and
  /// the destination is not reached.
  static bool shows(GuidanceSession session, {required bool overview}) =>
      overview && session.stops.isNotEmpty && session.phase != GuidancePhase.arrived;

  @override
  ConsumerState<GuidanceLegsStrip> createState() => _GuidanceLegsStripState();
}

class _GuidanceLegsStripState extends ConsumerState<GuidanceLegsStrip> {
  /// The chips of the stops taken out whose new route has not landed yet,
  /// by id: they go at once, and come back if the route could not be
  /// changed.
  final _removing = <Object>{};

  /// The chips' ids in the order of the last build, and a key to find each
  /// chip laid out.
  var _order = const <Object>[];
  final _chipKeys = <Object, GlobalKey>{};

  /// The user moved the row since a stop was last taken out: the new route
  /// then leaves it where it is.
  var _userScrolled = false;

  void _remove(RouteStop stop, Object id) {
    final camera = ref.read(guidanceCameraProvider.notifier);
    if (ref.read(guidanceCameraProvider).legTo == stop.position) {
      camera.frameLeg(null);
    } else {
      camera.touched();
    }
    // The chip after it takes its place, from the edge the row was scrolled
    // to: wider, it ran past the strip's end, cut. Shown whole once the
    // row has its new width, and again once the new route has given the
    // chips their new times and distances, which change their widths.
    final at = _order.indexOf(id);
    final next = at < 0 || at + 1 >= _order.length ? null : _order[at + 1];
    void reveal() {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(next);
      });
    }

    _userScrolled = false;
    reveal();
    setState(() => _removing.add(id));
    final container = ProviderScope.containerOf(context, listen: false);
    final removal = removeGuidanceStop(
      container,
      ScaffoldMessenger.maybeOf(context),
      context.t,
      stop,
    );
    // Out or not, it is no longer waited for: out, the stops no longer
    // hold it; not out, its chip comes back. Put back later by the undo,
    // its chip shows again.
    unawaited(
      removal.then((_) {
        if (!mounted) return;
        setState(() => _removing.remove(id));
        if (!_userScrolled) reveal();
      }),
    );
  }

  /// A stop's chip, by the stop and how many equal stops come before it:
  /// nothing stops the same place being added twice, and two chips with one
  /// key would be one.
  static Object _stopId(RouteStop stop, int earlier) => ('leg', stop, earlier);

  /// The ids of the chips of [stops].
  static Set<Object> _stopIds(List<RouteStop> stops) {
    final earlier = <RouteStop, int>{};
    return {
      for (final stop in stops)
        _stopId(stop, earlier.update(stop, (n) => n + 1, ifAbsent: () => 0)),
    };
  }

  /// Scrolls the row as little as shows the chip [id] whole, clear of the
  /// fade at each edge; nothing when it is.
  void _reveal(Object id) {
    final chip = _chipKeys[id]?.currentContext;
    final box = chip?.findRenderObject();
    if (chip == null || box is! RenderBox || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final position = Scrollable.maybeOf(chip)?.position;
    if (viewport == null || position == null || !position.hasContentDimensions) {
      return;
    }
    // Clear of the fade (and of the arrow, with a mouse) a side with more
    // to see draws; the row's own ends have none.
    const fade = SidewaysRow.moreFade;
    final room = Rect.fromLTWH(-fade, 0, box.size.width + 2 * fade, box.size.height);
    double offset(double alignment) => viewport
        .getOffsetToReveal(box, alignment, rect: room)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final endAtEnd = offset(1);
    final startAtStart = offset(0);
    // Too wide by no more than its own padding before its words: its end,
    // only that padding under the fade; wider, its start, number and name.
    final over = endAtEnd - startAtStart;
    final to = over <= 0
        ? position.pixels.clamp(endAtEnd, startAtStart)
        : over <= _chipStart
        ? endAtEnd
        : startAtStart;
    if ((to - position.pixels).abs() < 0.5) return;
    final duration = Motion.of(context, Motion.medium);
    if (duration == Duration.zero) {
      position.jumpTo(to);
    } else {
      unawaited(position.animateTo(to, duration: duration, curve: Motion.standard));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    // A stop out of the route, or passed, is no longer waited for.
    _removing.retainWhere(_stopIds(session.stops).contains);
    final overview = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.overview),
    );
    final shown = GuidanceLegsStrip.shows(session, overview: overview);
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      child: shown ? _strip(context, session) : const SizedBox.shrink(),
    );
  }

  Widget _strip(BuildContext context, GuidanceSession session) {
    final t = context.t;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final legs = guidanceLegs(session);
    final legTo = ref.watch(guidanceCameraProvider.select((v) => v.legTo));
    final framed = legs.any((l) => l.to == legTo) ? legTo : null;
    final camera = ref.read(guidanceCameraProvider.notifier);
    String timeOf(RouteLeg leg) =>
        t.clockTime(arrivalAt(now: now, lastFixAt: session.lastFixAt, leftS: leg.toS).toLocal());
    final chips = <(Object, Widget)>[
      (
        'leg:all',
        _LegChip(
          key: const ValueKey('leg:all'),
          label: t.navigation.legs.all,
          said: t.navigation.guidance.overview,
          selected: framed == null,
          onTap: () => camera.frameLeg(null),
        ),
      ),
    ];
    final earlier = <RouteStop, int>{};
    for (final leg in legs) {
      final time = timeOf(leg);
      final i = leg.stop;
      if (i == null) {
        final name = session.target.label ?? t.navigation.stops.point;
        chips.add((
          'leg:arrival',
          _LegChip(
            key: const ValueKey('leg:arrival'),
            leading: const _ArrivalDisc(),
            label: t.navigation.legs.arrival(name: name, time: time),
            said: t.navigation.legs.arrivalSaid(name: name, time: time),
            selected: framed == leg.to,
            onTap: () => camera.frameLeg(leg.to),
          ),
        ));
        continue;
      }
      final stop = session.stops[i];
      final id = _stopId(stop, earlier.update(stop, (n) => n + 1, ifAbsent: () => 0));
      if (_removing.contains(id)) continue;
      final name = stop.label ?? t.navigation.stops.point;
      final distance = t.routeDistance(leg.toM, units);
      chips.add((
        id,
        _LegChip(
          key: ValueKey(id),
          leading: _StopDisc(number: i + 1),
          label: t.navigation.legs.stop(name: name, time: time, distance: distance),
          said: t.navigation.legs.stopSaid(
            number: '${i + 1}',
            name: name,
            time: time,
            distance: distance,
          ),
          selected: framed == leg.to,
          onTap: () => camera.frameLeg(leg.to),
          onRemove: () => _remove(stop, id),
          removeTooltip: t.navigation.legs.remove(number: '${i + 1}', name: name),
        ),
      ));
    }
    _order = [for (final (id, _) in chips) id];
    _chipKeys.removeWhere((id, _) => !_order.contains(id));
    // As wide as its chips, up to the room the screen places it in
    // (CentredClear): from its start, scrolling, when they do not fit.
    return KeyedSubtree(
      key: const ValueKey('legs'),
      child: Semantics(
        container: true,
        label: t.navigation.stops.title,
        // The row draws past its edges for its chips' shadows (over the
        // map's chip row, the screen's edge clips it): here it stops at
        // the strip, which the panel or the buttons border.
        child: ClipRect(
          // Scrolling the chips is a touch of the view: the overview stays
          // while the user reads them.
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if ((n is ScrollStartNotification && n.dragDetails != null) ||
                  n is UserScrollNotification) {
                _userScrolled = true;
              }
              if (n is ScrollUpdateNotification) camera.touched();
              return false;
            },
            child: SidewaysRow(
              // Room for the chips' shadows inside the faded strip.
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, (id, c)) in chips.indexed)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : Space.s),
                      child: KeyedSubtree(key: _chipKeys.putIfAbsent(id, GlobalKey.new), child: c),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip of the strip: a floating pill like the map's, its leg framed when
/// chosen; a stop's has a small cross at its end.
class _LegChip extends StatefulWidget {
  const new({
    required this.label,
    required this.said,
    required this.selected,
    required this.onTap,
    this.leading,
    this.onRemove,
    this.removeTooltip,
    super.key,
  });

  final String label;

  /// What a screen reader says of it, in words rather than dots.
  final String said;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final VoidCallback? onRemove;
  final String? removeTooltip;

  @override
  State<_LegChip> createState() => _LegChipState();
}

/// The room before a chip's disc or words.
const double _chipStart = Space.ml;

/// A swipe up past this many logical pixels, more up than sideways,
/// removes a stop.
const double _swipeUpBy = 24;

class _LegChipState extends State<_LegChip> {
  /// Where the finger came down on the chip.
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final height = controlHeight(context, 48);
    final selected = widget.selected;
    final remove = widget.onRemove;
    final pill = BorderRadius.circular(LunaTokens.radiusPill);
    return OverMap(
      // A finger's swipe, read from the pointer: it takes no part in the
      // row's sideways scroll nor in the chip's tap, which a swipe cancels
      // by itself. A mouse has the cross; a screen reader too.
      child: Listener(
        onPointerDown: (e) =>
            _down = remove == null || e.kind == PointerDeviceKind.mouse ? null : e.position,
        onPointerCancel: (_) => _down = null,
        onPointerUp: (e) {
          final down = _down;
          _down = null;
          if (down == null || remove == null) return;
          final moved = e.position - down;
          if (moved.dy <= -_swipeUpBy && moved.dy.abs() > moved.dx.abs()) remove();
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.short),
          height: height,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : tokens.floatingSurface,
            borderRadius: pill,
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
            boxShadow: tokens.floatingShadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  container: true,
                  button: true,
                  selected: selected,
                  label: widget.said,
                  onTap: widget.onTap,
                  child: _NamedByAttribute(
                    child: ExcludeSemantics(
                      child: InkWell(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        borderRadius: pill,
                        onTap: widget.onTap,
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: _chipStart,
                            end: remove == null ? Space.ml : Space.xxs,
                          ),
                          child: SizedBox(
                            height: height,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.leading case final leading?) ...[
                                  leading,
                                  const SizedBox(width: Space.s),
                                ],
                                Text(
                                  widget.label,
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                                  ),
                                  textScaler: MediaQuery.textScalerOf(context)
                                      .clamp(maxScaleFactor: 1.6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (remove != null)
                  IconButton(
                    tooltip: widget.removeTooltip,
                    onPressed: remove,
                    // A small cross, a whole finger's room around it.
                    iconSize: 18,
                    constraints: BoxConstraints.tightFor(width: height, height: height),
                    padding: EdgeInsets.zero,
                    icon: _NamedByAttribute(child: Icon(AppIcons.close, color: scheme.onSurface)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] with an empty semantics node of its own over it, inside the
/// named node around it.
///
/// Flutter web writes a named node with children's name to an
/// `aria-label`, but a leaf's as text laid out in its own box. In a 48 dp
/// cross, "Retirer l'étape 1, Aire de Viviers" wrapped into a column of
/// words taller than the strip, which overflowed the strip's scrolling
/// element downwards; and Flutter web (3.47, `SemanticScrollable.update`)
/// writes a sideways scroll's offset to that element's `scrollTop`, which
/// the browser grants up to the overflow: once the row scrolled, every
/// chip's node stood that much above its chip (54 to 82 px measured in
/// Chromium, by the stops' names and the window), where a finger exploring
/// the screen looks for them. With the names in attributes nothing
/// overflows the strip, and the `scrollTop` written stays 0.
class _NamedByAttribute extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      child,
      // Nothing to say, no action: it only gives the node around a child.
      Positioned.fill(child: Semantics(container: true, child: const SizedBox.expand())),
    ],
  );
}

/// A stop's number on the teal disc of its mark on the map.
class _StopDisc extends StatelessWidget {
  const new({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    padding: const EdgeInsets.symmetric(horizontal: Space.xxs),
    decoration: const BoxDecoration(color: Palette.sarcelleProfonde, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(
      '$number',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Palette.white),
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
    ),
  );
}

/// The destination's chequered flag on the navy disc of its mark.
class _ArrivalDisc extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: const BoxDecoration(color: Palette.minuit, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Icon(PhosphorFill.flagCheckered, size: 14, color: Palette.white),
  );
}
