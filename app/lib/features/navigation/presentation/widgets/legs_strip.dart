import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_legs.dart';
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

  @override
  ConsumerState<GuidanceLegsStrip> createState() => _GuidanceLegsStripState();
}

class _GuidanceLegsStripState extends ConsumerState<GuidanceLegsStrip> {
  /// The stops taken out whose new route has not landed yet: their chips
  /// go at once, and come back if the route could not be changed.
  final _removing = <RouteStop>{};

  void _remove(RouteStop stop) {
    final camera = ref.read(guidanceCameraProvider.notifier);
    if (ref.read(guidanceCameraProvider).legTo == stop.position) camera.frameLeg(null);
    setState(() => _removing.add(stop));
    final container = ProviderScope.containerOf(context, listen: false);
    final removal = removeGuidanceStop(
      container,
      ScaffoldMessenger.maybeOf(context),
      context.t,
      stop,
    );
    unawaited(
      removal.then((out) {
        if (!out && mounted) setState(() => _removing.remove(stop));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final overview = ref.watch(
      guidanceCameraProvider.select((v) => v.mode == GuidanceCameraMode.overview),
    );
    final shown = overview && session.stops.isNotEmpty && session.phase != GuidancePhase.arrived;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      child: shown ? _strip(context, session) : const SizedBox.shrink(),
    );
  }

  Widget _strip(BuildContext context, GuidanceSession session) {
    final t = context.t;
    // A stop out of the route, or passed, is no longer waited for.
    _removing.retainWhere(session.stops.contains);
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final legs = guidanceLegs(session);
    final legTo = ref.watch(guidanceCameraProvider.select((v) => v.legTo));
    final framed = legs.any((l) => l.to == legTo) ? legTo : null;
    final camera = ref.read(guidanceCameraProvider.notifier);
    String timeOf(RouteLeg leg) =>
        t.clockTime(arrivalAt(now: now, lastFixAt: session.lastFixAt, leftS: leg.toS).toLocal());
    final chips = <Widget>[
      _LegChip(
        key: const ValueKey('leg:all'),
        label: t.navigation.legs.all,
        said: t.navigation.guidance.overview,
        selected: framed == null,
        onTap: () => camera.frameLeg(null),
      ),
    ];
    for (final leg in legs) {
      final time = timeOf(leg);
      final i = leg.stop;
      if (i == null) {
        final name = session.target.label ?? t.navigation.stops.point;
        chips.add(
          _LegChip(
            key: const ValueKey('leg:arrival'),
            leading: const _ArrivalDisc(),
            label: t.navigation.legs.arrival(name: name, time: time),
            said: t.navigation.legs.arrivalSaid(name: name, time: time),
            selected: framed == leg.to,
            onTap: () => camera.frameLeg(leg.to),
          ),
        );
        continue;
      }
      final stop = session.stops[i];
      if (_removing.contains(stop)) continue;
      final name = stop.label ?? t.navigation.stops.point;
      final distance = t.routeDistance(leg.toM, units);
      chips.add(
        _LegChip(
          key: ValueKey(('leg', stop)),
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
          onRemove: () => _remove(stop),
          removeTooltip: t.navigation.stops.remove,
        ),
      );
    }
    return Semantics(
      key: const ValueKey('legs'),
      container: true,
      label: t.navigation.stops.title,
      child: SidewaysRow(
        // Room for the chips' shadows inside the faded strip.
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Row(
          children: [
            for (final c in chips)
              Padding(
                padding: const EdgeInsets.only(right: Space.s),
                child: c,
              ),
          ],
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
                  button: true,
                  selected: selected,
                  label: widget.said,
                  onTap: widget.onTap,
                  excludeSemantics: true,
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: pill,
                    onTap: widget.onTap,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: Space.ml,
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
                              style: Theme.of(context).textTheme.labelLarge,
                              textScaler: MediaQuery.textScalerOf(context)
                                  .clamp(maxScaleFactor: 1.6),
                            ),
                          ],
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
                    icon: Icon(AppIcons.close, color: scheme.onSurface),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
