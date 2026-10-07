import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
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
    this.plan,
    super.key,
  });

  final RouteTarget target;
  final List<RouteMarker> markers;

  /// The map without its marks and their callbacks.
  final RouteMapProps base;

  /// A place, a station or a stop was tapped.
  final ValueChanged<String> onPointTap;

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
    _focus.hover({?hover?.mark});
  }

  void _onTap(String id, {Offset? at}) {
    final marker = _byId[id];
    if (marker == null) return;
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
    final flown = flight == null ? null : [for (final id in flight) ?_byId[id]];
    final props = RouteMapProps(
      style: b.style,
      dark: b.dark,
      lines: b.lines,
      camera: b.camera,
      padding: b.padding,
      vehicle: b.vehicle,
      marks: [for (final m in widget.markers) m.mark],
      highlighted: focus.lit,
      focus: flown == null || flown.isEmpty
          ? null
          : RouteMapFocus(
              marks: [for (final m in flown) m.id],
              position: flown.first.mark.position,
              serial: focus.flightSerial,
            ),
      onLineTap: b.onLineTap,
      onLongPress: b.onLongPress,
      onMarkTap: _onTap,
      onMarkHover: _onHover,
      // A tap beside an open callout closes it, nothing more (bareTapAt):
      // the next one may open the point under it.
      onEmptyTap: (at, zoom) {
        if (_callout != null) {
          _close();
          return;
        }
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
        Positioned.fill(child: ref.watch(routeMapBuilderProvider)(context, props)),
        if (shown != null)
          Positioned.fill(
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
        // scrolls the legend rather than clipping it.
        Positioned(
          top: pad.top + Space.s,
          right: pad.right + Space.s,
          bottom: pad.bottom + Space.s,
          child: Align(
            alignment: Alignment.topRight,
            child: MarkLegend(rows: legendRows(props.marks)),
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

/// The legend: a chip "Légende" above the map that opens the kinds of marks
/// present on this route, each with its badge. Open the first time, folded
/// afterwards: the route settings remember it was seen.
class MarkLegend extends ConsumerStatefulWidget {
  const new({required this.rows, super.key});

  final List<LegendRow> rows;

  @override
  ConsumerState<MarkLegend> createState() => _MarkLegendState();
}

class _MarkLegendState extends ConsumerState<MarkLegend> {
  /// Null until the settings are read: the first preview opens it.
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(routeSettingsControllerProvider).value;
    if (widget.rows.isEmpty || settings == null) return const SizedBox.shrink();
    final open = _open ??= !settings.legendSeen;
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
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
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
                            onPressed: () => setState(() => _open = false),
                            icon: const Icon(AppIcons.close),
                          ),
                        ],
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [for (final row in widget.rows) _LegendLine(row)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ActionChip(
              mouseCursor: WidgetStateMouseCursor.clickable,
              avatar: const Icon(AppIcons.about),
              label: Text(t.navigation.marks.legend),
              onPressed: () => setState(() => _open = true),
              backgroundColor: scheme.surfaceContainerLowest,
              elevation: 2,
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
    final kind = row.kind;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.hair),
      child: Row(
        children: [
          ExcludeSemantics(child: RouteBadgeView(row.badge, text: row.label, scale: 0.8)),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              kind == null ? t.navigation.marks.groupLegend : markKindName(t, kind),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
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
