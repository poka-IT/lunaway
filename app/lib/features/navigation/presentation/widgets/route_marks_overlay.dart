import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_mark_focus.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/measured.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

final _log = Logger('route_marks');

/// The preview's map with its marks explained: a tooltip under the pointer,
/// a callout pinned to a tapped mark, the legend of the kinds on this
/// route, and the link both ways between the marks and the list's rows
/// ([RouteMarkFocus]).
///
/// A mouse hovers: the tooltip says what a mark is, a click on a mark the
/// list shows brings its row into view. A finger does not: a tap opens the
/// callout, with "Voir dans la liste". A place, a station or a stop opens
/// its own card in both cases, as before ([onPointTap]).
class RouteMarksMap extends ConsumerStatefulWidget {
  const new({
    required this.target,
    required this.markers,
    required this.base,
    required this.onPointTap,
    this.onAnyMarkTap,
    this.plan,
    super.key,
  });

  final RouteTarget target;
  final List<RouteMarker> markers;

  /// The map without its marks and their callbacks.
  final RouteMapProps base;

  /// A place, a station or a stop was tapped.
  final ValueChanged<String> onPointTap;

  /// Any mark was tapped: a tap on bare map that waits is no longer one.
  final VoidCallback? onAnyMarkTap;

  /// The answer the marks come from, for the sources of road events.
  final RoutePlan? plan;

  @override
  ConsumerState<RouteMarksMap> createState() => _RouteMarksMapState();
}

class _RouteMarksMapState extends ConsumerState<RouteMarksMap> {
  /// Under the pointer.
  RouteMapHover? _tip;

  /// Pinned by a tap, until a tap elsewhere or a move of the map.
  ({String id, Offset at})? _callout;

  /// What the route is framed clear of: the legend's card while it stands
  /// open by itself (the first preview), its chip while it is folded.
  Size? _legend;

  final _fit = LegendFit();

  /// The legend's card, measured in the frame new bounds came with.
  final GlobalKey _legendCard = GlobalKey();

  /// The bounds whose legend has been measured, and a measure due.
  GeoBounds? _measuredFor;
  bool _measuring = false;

  /// The map's size, once laid out.
  Size _size = Size.zero;

  /// The camera the map gets: the screen's, a fit kept clear of the legend
  /// open by itself on a map of [size] ([LegendFit]). New bounds come with
  /// new marks, so new rows in the legend: while it stands open by itself,
  /// their fit waits for the frame that lays the legend out with them, then
  /// takes its size, and follows it as it grows until the user takes the
  /// map ([_takeMap]).
  RouteCamera _camera(RouteCamera camera, Size size, {required bool legendShown}) {
    if (camera is! FitCamera) return camera;
    final legend = size.isEmpty || !legendShown ? null : _legend;
    final kept = _fit.current;
    if (legend != null &&
        kept != null &&
        kept.bounds != camera.bounds &&
        _measuredFor != camera.bounds) {
      _measureLegend(camera.bounds);
      return kept;
    }
    return _fit.fit(camera, map: size, padding: widget.base.padding, legend: legend);
  }

  /// The user took the map: a gesture, a tap on it, a long press, or a
  /// flight to a mark asked from the list. The camera is theirs from then
  /// on; a legend that grows after leaves it be.
  void _takeMap() => _fit.hold();

  /// The flight to marks last seen, to tell a new one.
  int? _flightSeen;

  void _measureLegend(GeoBounds bounds) {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (!mounted) return;
      final card = _legendCard.currentContext?.findRenderObject();
      setState(() {
        _measuredFor = bounds;
        // No card laid out: the legend is not open any more.
        if (_legend != null) _legend = card is RenderBox && card.hasSize ? card.size : null;
      });
    });
  }

  late Map<String, RouteMarker> _byId = _index(widget.markers);

  static Map<String, RouteMarker> _index(List<RouteMarker> markers) => {
    for (final m in markers) m.id: m,
  };

  RouteMarkFocus get _focus => ref.read(routeMarkFocusProvider(widget.target).notifier);

  @override
  void didUpdateWidget(RouteMarksMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.markers, widget.markers)) {
      _byId = _index(widget.markers);
      // A mark gone (another route chosen) takes its tooltip with it.
      if (_tip?.mark case final id? when !_byId.containsKey(id)) _tip = null;
      if (_callout case (:final id, at: _) when !_byId.containsKey(id)) _callout = null;
    }
  }

  void _onHover(RouteMapHover? hover) {
    setState(() => _tip = hover);
    _focus.hover({?hover?.mark}, onMap: true);
  }

  void _onTap(String id, {Offset? at}) {
    _takeMap();
    final marker = _byId[id];
    if (marker == null) return;
    widget.onAnyMarkTap?.call();
    switch (marker.subject) {
      case PlaceSubject() || FuelSubject() || StopSubject():
        setState(() => _callout = null);
        widget.onPointTap(id);
      // The pointer was on it: a mouse, which has the tooltip already. The
      // click shows its row.
      case final subject when _tip?.mark == id:
        if (subject.listed) _focus.reveal(id);
      case _:
        setState(() => _callout = at == null ? null : (id: id, at: at));
        _focus.select(id);
    }
  }

  void _close() {
    if (_callout == null) return;
    setState(() => _callout = null);
    _focus.select(null);
  }

  @override
  Widget build(BuildContext context) {
    // The choice cleared elsewhere (another route chosen): the callout of
    // the old one goes with it.
    ref.listen(routeMarkFocusProvider(widget.target).select((f) => f.selected), (_, selected) {
      if (_callout case (:final id, at: _) when id != selected) setState(() => _callout = null);
    });
    final focus = ref.watch(routeMarkFocusProvider(widget.target));
    final b = widget.base;
    final flight = focus.flight;
    // A row of the list flew the map to its marks: the camera is the user's.
    if (flight != null && focus.flightSerial != _flightSeen) {
      _flightSeen = focus.flightSerial;
      _takeMap();
    }
    final flown = flight == null ? null : [for (final id in flight) ?_byId[id]];
    final marks = [for (final m in widget.markers) m.mark];
    final props = RouteMapProps(
      style: b.style,
      dark: b.dark,
      lines: b.lines,
      camera: _camera(
        b.camera,
        _size,
        legendShown: legendRows(marks).isNotEmpty || b.zones.isNotEmpty,
      ),
      padding: b.padding,
      vehicle: b.vehicle,
      zones: b.zones,
      rich: b.rich,
      marks: marks,
      highlighted: focus.litOnMap,
      focus: flown == null || flown.isEmpty
          ? null
          : RouteMapFocus(
              marks: [for (final m in flown) m.id],
              position: flown.first.mark.position,
              serial: focus.flightSerial,
            ),
      // Null stays null: an engine leaves the lines and the long press to
      // the map when nobody listens.
      onLineTap: switch (b.onLineTap) {
        final tap? => (index) {
          _takeMap();
          tap(index);
        },
        null => null,
      },
      onLongPress: switch (b.onLongPress) {
        final press? => (at) {
          _takeMap();
          press(at);
        },
        null => null,
      },
      onGesture: _takeMap,
      onMarkTap: _onTap,
      onMarkHover: _onHover,
      // A tap beside an open callout closes it, nothing more (bareTapAt):
      // the next one may open the point under it.
      onEmptyTap: (at, zoom) {
        _takeMap();
        if (_callout != null) {
          _close();
          return;
        }
        // A mark clicked with a mouse goes back to rest with its row.
        _focus.select(null);
        b.onEmptyTap?.call(at, zoom);
      },
      onCameraMove: _close,
    );
    final t = context.t;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final now = ref.watch(clockProvider)();
    MarkWords? words(String id) => switch (_byId[id]) {
      final m? => markWords(m, t, units: units, now: now, plan: widget.plan),
      null => null,
    };
    final tip = _tip;
    final callout = _callout;
    final (shown, at, marker) = switch ((callout, tip)) {
      ((:final id, :final at), _) => (words(id), at, _byId[id]),
      (_, RouteMapHover(:final mark?, :final at)) => (words(mark), at, _byId[mark]),
      (_, RouteMapHover(:final group?, :final at)) => (groupWords(t, group), at, null),
      _ => (null, Offset.zero, null),
    };
    final pad = b.padding;
    return Stack(
      children: [
        Positioned.fill(
          child: ReportsRect(
            onRect: (rect) {
              if (mounted && rect.size != _size) setState(() => _size = rect.size);
            },
            child: ref.watch(routeMapBuilderProvider)(context, props),
          ),
        ),
        if (shown != null)
          Positioned.fill(
            key: const ValueKey('tip'),
            child: CustomSingleChildLayout(
              delegate: _TipLayout(anchor: at, padding: pad),
              child: MarkTip(
                words: shown,
                badge: marker?.mark.badge,
                label: marker?.mark.label,
                // Only a finger needs the way to the list: a mouse clicks.
                action: callout != null && (marker?.subject.listed ?? false)
                    ? (
                        label: t.navigation.marks.showInList,
                        onPressed: () {
                          final id = callout.id;
                          _close();
                          _focus.reveal(id);
                        },
                      )
                    : null,
                onClose: callout == null ? null : _close,
              ),
            ),
          ),
        // Never taller than the map left free: a phone held sideways
        // scrolls the legend rather than clipping it. Keyed: a tip that comes
        // or goes before it in the stack must not make it anew (folded).
        Positioned(
          key: const ValueKey('legend'),
          top: pad.top + Space.s,
          right: pad.right + Space.s,
          bottom: pad.bottom + Space.s,
          child: Align(
            alignment: Alignment.topRight,
            child: MarkLegend(
              cardKey: _legendCard,
              rows: legendRows(props.marks),
              zones: props.zones.isNotEmpty,
              onShownByItself: (size) {
                if (size != _legend) setState(() => _legend = size);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Places the tip above its mark, or below it near the top, always inside
/// the part of the map no panel covers.
class _TipLayout extends SingleChildLayoutDelegate {
  new({required this.anchor, required this.padding});

  final Offset anchor;
  final EdgeInsets padding;

  static const _gap = 22.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: (constraints.maxWidth - padding.horizontal - 2 * Space.s).clamp(0, 300),
    maxHeight: (constraints.maxHeight - padding.vertical - 2 * Space.s).clamp(0, double.infinity),
  );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = (anchor.dx - child.width / 2).clamp(
      padding.left + Space.s,
      (size.width - padding.right - Space.s - child.width).clamp(
        padding.left + Space.s,
        size.width,
      ),
    );
    final above = anchor.dy - _gap - child.height;
    final top = above >= padding.top + Space.s ? above : anchor.dy + _gap;
    final maxTop = size.height - padding.bottom - Space.s - child.height;
    return Offset(left, top.clamp(padding.top + Space.s, maxTop < 0 ? 0 : maxTop));
  }

  @override
  bool shouldRelayout(_TipLayout old) => old.anchor != anchor || old.padding != padding;
}

/// What a mark is, in a few lines: its kind, which one, where on the route,
/// and for a road event its source and the age of the data.
class MarkTip extends StatelessWidget {
  const new({required this.words, this.badge, this.label, this.action, this.onClose, super.key});

  final MarkWords words;
  final RouteBadge? badge;
  final String? label;
  final ({String label, VoidCallback onPressed})? action;

  /// A callout closes; a tooltip goes with the pointer.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final card = Material(
      color: scheme.surfaceContainerLowest,
      elevation: 3,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(LunaTokens.radiusM),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge case final b?) ...[
              Padding(
                padding: const EdgeInsets.only(top: Space.xxs),
                child: RouteBadgeView(b, text: label, scale: 0.85),
              ),
              const SizedBox(width: Space.s),
            ],
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      words.category,
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Text(words.title, style: theme.textTheme.titleSmall),
                    for (final line in words.lines) Text(line, style: theme.textTheme.bodySmall),
                    if (words.source case final source?) Text(source, style: muted),
                    if (action case final a?)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: a.onPressed,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                          ),
                          child: Text(a.label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: context.t.common.close,
                onPressed: onClose,
                icon: const Icon(AppIcons.close),
              ),
          ],
        ),
      ),
    );
    // A tooltip never takes the pointer from the map under it.
    return onClose == null
        ? IgnorePointer(child: Semantics(liveRegion: true, child: card))
        : Semantics(container: true, child: card);
  }
}

/// The card of [marker] in a sheet, where the map has no callout of its
/// own (the guidance's): what it is, which one, where on the route from
/// the vehicle at [alongM], and where it comes from.
Future<void> showMarkCard(
  BuildContext context,
  RouteMarker marker, {
  required DistanceUnits units,
  required DateTime now,
  RoutePlan? plan,
  double? alongM,
}) {
  final words = markWords(marker, context.t, units: units, now: now, plan: plan, alongM: alongM);
  return showSheet<void>(
    context,
    // A phone on its side with large text: the card scrolls.
    isScrollControlled: true,
    builder: (context) =>
        MarkCard(words: words, badge: marker.mark.badge, label: marker.mark.label),
  );
}

/// The body of [showMarkCard], public for the tests.
class MarkCard extends StatelessWidget {
  const new({required this.words, required this.badge, this.label, super.key});

  final MarkWords words;
  final RouteBadge badge;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: RouteBadgeView(badge, text: label),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    words.category,
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  Semantics(
                    header: true,
                    child: Text(words.title, style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: Space.xxs),
                  for (final line in words.lines) Text(line, style: theme.textTheme.bodyMedium),
                  if (words.source case final source?) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      source,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview's fit, kept clear of the legend open by itself. For a set of
/// bounds the room follows the legend as it grows, however late: the rows
/// of the zones and of the places near the route come after the route, a
/// while after on a slow network. A legend that shrinks or closes leaves
/// the camera where it is, and once the user takes the map ([hold]) the
/// room holds whatever the legend does. New bounds fit again and follow
/// anew.
final class LegendFit {
  FitCamera? _fit;
  Size? _sizedFor;
  bool _held = false;

  /// The last fit sent.
  FitCamera? get current => _fit;

  /// The user took the map: the room holds from now until new bounds.
  void hold() => _held = true;

  /// The fit to send for [camera] on a map of [map] whose panels cover
  /// [padding], the legend [legend] in size when it stands open by itself.
  FitCamera fit(
    FitCamera camera, {
    required Size map,
    required EdgeInsets padding,
    required Size? legend,
  }) {
    final kept = _fit;
    final sized = _sizedFor;
    if (kept != null && kept.bounds == camera.bounds) {
      final within =
          sized != null &&
          legend != null &&
          legend.width <= sized.width &&
          legend.height <= sized.height;
      if (_held || legend == null || within) return kept;
    } else {
      _held = false;
    }
    _sizedFor = legend;
    final room = legend == null
        ? EdgeInsets.zero
        : legendRoom(bounds: camera.bounds, map: map, padding: padding, legend: legend);
    return _fit = FitCamera(camera.bounds, room: camera.room + room);
  }
}

/// The room a fitted route keeps clear of the legend of [legend]'s size,
/// open in the top right corner of a map of [map] whose panels cover
/// [padding]: beside it or below it, whichever leaves the route the larger
/// on screen (the closer zoom).
EdgeInsets legendRoom({
  required GeoBounds bounds,
  required Size map,
  required EdgeInsets padding,
  required Size legend,
}) {
  final beside = EdgeInsets.only(right: legend.width + Space.s);
  final below = EdgeInsets.only(top: legend.height + Space.s);
  // The engines fit within 48 px more on each side.
  double zoom(EdgeInsets room) =>
      cameraForBounds(bounds, map, padding + room + const EdgeInsets.all(48)).zoom;
  return zoom(below) >= zoom(beside) ? below : beside;
}

/// The legend: a chip "Légende" above the map that opens the kinds of marks
/// present on this route, each with its badge. Open the first time, folded
/// afterwards: the route settings remember it was seen.
class MarkLegend extends ConsumerStatefulWidget {
  const new({
    required this.rows,
    this.zones = false,
    this.onShownByItself,
    this.cardKey,
    super.key,
  });

  final List<LegendRow> rows;

  /// The open card or the chip, whichever shows, for whoever measures it.
  final Key? cardKey;

  /// The route crosses danger zones: their band has its row.
  final bool zones;

  /// What the map frames the route clear of: the card's size while it
  /// stands open by itself (nobody asked for it), the chip's while it is
  /// folded (it sits on the map's corner, over an arrival there); null
  /// while the user holds it open, which frames nothing again.
  final ValueChanged<Size?>? onShownByItself;

  @override
  ConsumerState<MarkLegend> createState() => _MarkLegendState();
}

class _MarkLegendState extends ConsumerState<MarkLegend> {
  /// Null until the settings are read: the first preview opens it.
  bool? _open;

  /// Open by itself, the user has done nothing with it yet.
  bool _byItself = false;

  void _set({required bool open}) {
    setState(() {
      _open = open;
      _byItself = false;
    });
    widget.onShownByItself?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(routeSettingsControllerProvider).value;
    if ((widget.rows.isEmpty && !widget.zones) || settings == null) return const SizedBox.shrink();
    final open = _open ??= _byItself = !settings.legendSeen;
    if (open && !settings.legendSeen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref.read(routeSettingsControllerProvider.notifier).legendShown().catchError((
            Object e,
            StackTrace st,
          ) {
            // Not saved: it opens again next time, nothing worse.
            _log.warning('the legend could not be marked as seen', e, st);
          }),
        );
      });
    }
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      alignment: Alignment.topRight,
      child: open
          ? ReportsRect(
              // The size it settles at, not the one it grows through.
              onRect: (rect) {
                if (_byItself) widget.onShownByItself?.call(rect.size);
              },
              child: ConstrainedBox(
                key: widget.cardKey,
                constraints: BoxConstraints(
                  maxWidth: WindowSize.of(context) == WindowSize.compact ? 220 : 280,
                  maxHeight: 360,
                ),
                child: Material(
                  color: scheme.surfaceContainerLowest,
                  elevation: 3,
                  shadowColor: scheme.shadow,
                  borderRadius: BorderRadius.circular(LunaTokens.radiusM),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.m, Space.xxs, Space.xxs, Space.s),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  t.navigation.marks.legend,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: t.navigation.marks.legendHide,
                              onPressed: () => _set(open: false),
                              icon: const Icon(AppIcons.close),
                            ),
                          ],
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final row in widget.rows) _LegendLine(row),
                                if (widget.zones) const _ZoneLegendLine(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : ReportsRect(
              onRect: (rect) => widget.onShownByItself?.call(rect.size),
              child: KeyedSubtree(
                key: widget.cardKey,
                child: ActionChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  avatar: const Icon(AppIcons.about),
                  label: Text(t.navigation.marks.legend),
                  onPressed: () => _set(open: true),
                  backgroundColor: scheme.surfaceContainerLowest,
                  elevation: 2,
                ),
              ),
            ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const new(this.row);

  final LegendRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // On a phone the legend sits over the little map the sheet leaves: a
    // denser one hides less of the route.
    final compact = WindowSize.of(context) == WindowSize.compact;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.hair),
      child: Row(
        children: [
          ExcludeSemantics(
            child: RouteBadgeView(row.badge, text: row.label, scale: compact ? 0.62 : 0.8),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(legendText(t, row), style: compact ? text.bodySmall : text.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// The legend's row of the danger zones: their band under a piece of
/// route, as the map draws it.
class _ZoneLegendLine extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final compact = WindowSize.of(context) == WindowSize.compact;
    final text = Theme.of(context).textTheme;
    final scale = compact ? 0.62 : 0.8;
    final side = RouteBadge.destination.extent * scale;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.hair),
      child: Row(
        children: [
          ExcludeSemantics(
            child: CustomPaint(
              size: Size(side, side),
              painter: _ZoneSwatch(
                scale,
                dark: Theme.of(context).brightness == Brightness.dark,
                ratio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
              ),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              context.t.navigation.marks.zoneLegend,
              style: compact ? text.bodySmall : text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// [logical] logical pixels rounded to whole device pixels at [ratio], one
/// at the least: a band drawn on a fraction of a pixel smears its edges.
@visibleForTesting
double wholeDevicePixels(double logical, double ratio) =>
    math.max(1, (logical * ratio).roundToDouble()) / ratio;

class _ZoneSwatch extends CustomPainter {
  new(this.scale, {required this.dark, required this.ratio});

  final double scale;
  final bool dark;

  /// The device's pixels per logical pixel: each band takes a whole number
  /// of them, on the pixel grid; a fraction of a pixel smears its edges
  /// into a grey seam against the band under it.
  final double ratio;

  double _snap(double logical) => wholeDevicePixels(logical, ratio);

  Color _hex(String hex) => Color(int.parse('ff${hex.substring(1)}', radix: 16));

  @override
  void paint(Canvas canvas, Size size) {
    void stroke(String color, double logicalWidth, {double opacity = 1}) {
      final width = _snap(logicalWidth);
      // The band's edges on the grid: its centre on a pixel's edge for an
      // even count of pixels, on a pixel's middle for an odd one.
      final pixels = (width * ratio).round();
      final centre = ((size.height / 2) * ratio).floorToDouble() + (pixels.isOdd ? 0.5 : 0);
      final y = centre / ratio;
      canvas.drawLine(
        Offset(width / 2, y),
        Offset(size.width - width / 2, y),
        Paint()
          ..color = _hex(color).withValues(alpha: opacity)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    stroke(RouteLook.zone, RouteLook.zoneWidth * scale, opacity: RouteLook.zoneOpacity);
    stroke(RouteLook.casing(dark: dark), RouteLook.casingWidth * scale);
    stroke(RouteLook.line(dark: dark), RouteLook.lineWidth * scale);
  }

  @override
  bool shouldRepaint(_ZoneSwatch old) =>
      old.scale != scale || old.dark != dark || old.ratio != ratio;
}

/// A row of the preview's list tied to its marks on the map: the pointer
/// over the row lights them, the pointer over one of them lights the row, a
/// tap on the row flies the map to them, and a mark that asks for its row
/// ("Voir dans la liste", a click) brings it into view.
class MarkLinkedRow extends ConsumerStatefulWidget {
  const new({required this.target, required this.marks, required this.child, super.key});

  final RouteTarget target;
  final List<String> marks;
  final Widget child;

  @override
  ConsumerState<MarkLinkedRow> createState() => _MarkLinkedRowState();
}

class _MarkLinkedRowState extends ConsumerState<MarkLinkedRow> {
  RouteMarkFocus get _focus => ref.read(routeMarkFocusProvider(widget.target).notifier);

  bool _mine(String? id) => id != null && widget.marks.contains(id);

  void _show() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.standard,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Built because a mark asked for it (a list that grew to show it).
    if (_mine(ref.read(routeMarkFocusProvider(widget.target)).reveal)) _show();
  }

  @override
  Widget build(BuildContext context) {
    final provider = routeMarkFocusProvider(widget.target);
    ref.listen(provider.select((f) => (f.reveal, f.revealSerial)), (before, now) {
      if (_mine(now.$1) && before?.$2 != now.$2) _show();
    });
    final lit = ref.watch(provider.select((f) => f.lit.any(widget.marks.contains)));
    final scheme = Theme.of(context).colorScheme;
    final ids = widget.marks.toSet();
    return MouseRegion(
      onEnter: (_) => _focus.hover(ids),
      onExit: (_) => _focus.leave(ids),
      child: Semantics(
        onTapHint: context.t.navigation.marks.onMap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.short),
          decoration: BoxDecoration(
            color: lit ? scheme.secondaryContainer : scheme.secondaryContainer.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          ),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
            onTap: () => _focus.fly(widget.marks),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
