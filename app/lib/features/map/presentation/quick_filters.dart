import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/layout/pointer_input.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/filters_sheet.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_chips.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_height_entry.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// The one row of chips under the search, at every width, a pane's
/// included: the button to the full filters with the count of those
/// active, then what matters most on the road first ([order]). One row
/// rather than several leaves the map and the list the room (in a pane,
/// the filters over their own lines and the shops in a row took three
/// lines, the PO's decision of 2026-10-10); it scrolls sideways and fades
/// at its edges, so a chip cut by the screen edge reads as "more this way"
/// rather than as a mistake, and its arrows bring each chip in whole.
class QuickFilters extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero, this.floating = true, super.key});

  /// A chip's height to a finger; 8 less to a mouse.
  static const double chipTouchHeight = 48;

  /// The height the row takes, for the map's top padding.
  static double heightOf(BuildContext context) =>
      controlHeight(context, chipTouchHeight) + Space.s * 2;

  /// The chips after "Filters", by what a motorhome needs on the road: fuel
  /// first (a heavy van burns 10 to 15 l per 100 km, and not every station
  /// takes its height), then water and the dump station (every two or three
  /// days), then the night (every evening), the vehicle's height (a barrier
  /// ends a detour), the price, then food shopping and somewhere to eat,
  /// health and services, what there is to see, and the vending machines
  /// last. Once the vehicle's height is known, [orderFor] puts its chip
  /// first.
  static const List<QuickChip> order = [
    PoiChip(PoiCategory.fuel),
    PoiChip(PoiCategory.water),
    PlaceChip.night,
    PlaceChip.vehicle,
    PlaceChip.free,
    PoiChip(PoiCategory.groceries),
    PoiChip(PoiCategory.food),
    PoiChip(PoiCategory.health),
    PoiChip(PoiCategory.services),
    PoiChip(PoiCategory.sights),
    PoiChip(PoiCategory.vending),
  ];

  /// [order], with the vehicle's chip first once its height is known: the
  /// filter is then on by default, and whether it is on shows without
  /// scrolling the row (the PO's decision of 2026-10-10).
  static List<QuickChip> orderFor({required bool vehicleKnown}) =>
      vehicleKnown ? [PlaceChip.vehicle, ...order.where((c) => c != PlaceChip.vehicle)] : order;

  final EdgeInsets padding;

  /// Over the map, chips float with a shadow; in a pane they sit flat.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a search lists its results the chips give way: below the results
    // they would float at the bottom of the screen, cut from their row.
    if (ref.watch(searchQueryProvider).trim().isNotEmpty) return const SizedBox.shrink();
    final t = context.t;
    final filter = ref.watch(placeFilterProvider);
    final settings = ref.read(settingsProvider.notifier);
    final stored = ref.watch(vehicleProvider);
    final vehicle = stored.value;
    // While the vehicle is still being read at launch, the filter being on
    // stands for its height: the chip is first from the first frame rather
    // than jumping there a moment later.
    final vehicleFirst = stored.hasValue ? vehicle?.heightM != null : filter.fitsMyVehicle;

    Future<void> apply(PlaceFilter next) async {
      Haptics.select();
      await settings.setFilter(next);
    }

    Widget place(PlaceChip chip) => switch (chip) {
      .night => MapChip(
        leading: const NightBadge(OvernightStatus.allowed),
        label: t.filters.nightPossible,
        selected: filter.nightOk,
        floating: floating,
        onTap: () => apply(filter.withNightOk(on: !filter.nightOk)),
      ),
      .free => MapChip(
        icon: AppIcons.free,
        label: t.filters.freeOnly,
        selected: filter.freeOnly,
        floating: floating,
        onTap: () => apply(filter.copyWith(freeOnly: !filter.freeOnly)),
      ),
      .vehicle => MapChip(
        icon: AppIcons.vehicleFits,
        label: vehicle?.heightM == null
            ? t.filters.myVehicleFits
            : t.filters.myVehicleFitsHeight(height: t.metres(vehicle!.heightM!)),
        selected: filter.fitsMyVehicle,
        floating: floating,
        onTap: () async {
          if (!filter.fitsMyVehicle && vehicle?.heightM == null) {
            // First use: the filter needs the vehicle's height, asked once
            // in two fields rather than the whole vehicle. The height stored
            // turns the filter on (`Settings.vehicleDescribed`).
            await showVehicleHeightSheet(context);
            return;
          }
          await apply(filter.copyWith(fitsMyVehicle: !filter.fitsMyVehicle));
        },
      ),
    };

    final filters = MapChip(
      icon: AppIcons.filters,
      label: t.map.filters,
      count: filter.activeCount,
      semanticsLabel: filter.activeCount == 0 ? null : t.filters.active(n: filter.activeCount),
      floating: floating,
      onTap: () => showFiltersSheet(context),
    );
    final chips = <Widget>[
      filters,
      // The shops and services next to one another form one group for a
      // screen reader, which says what they are.
      for (final group in _runs(orderFor(vehicleKnown: vehicleFirst)))
        if (group.first is PoiChip)
          _PoiGroup(
            label: t.poi.chipsLabel,
            chips: [
              for (final c in group)
                ...poiCategoryChip(context, ref, (c as PoiChip).category, floating: floating),
            ],
          )
        else
          for (final c in group) place(c as PlaceChip),
    ];
    return SidewaysRow(
      floating: floating,
      // Room for the chips' shadows inside the faded strip.
      padding: padding.add(const EdgeInsets.symmetric(vertical: Space.s)),
      child: Row(
        children: [
          for (final c in chips)
            // The categories' group pads its own chips.
            if (c is _PoiGroup)
              c
            else
              Padding(
                padding: const EdgeInsets.only(right: Space.s),
                child: SidewaysStop(child: c),
              ),
        ],
      ),
    );
  }
}

/// A row that scrolls sideways under a finger, and under a mouse too: the
/// wheel, which turns vertically, moves it sideways, and a drag with the
/// button held moves it as a finger would. Without both, the chips past the
/// edge of a desktop pane were out of reach of a mouse.
///
/// A side with more to see fades out wide, so a chip cut there reads as
/// "more this way"; with a mouse, a round arrow on that side brings the
/// next item cut at that edge ([SidewaysStop]) in whole past the other
/// fade, or scrolls by most of the row's width when it has none, the wheel
/// and the drag not being things a mouse user guesses.
class SidewaysRow extends StatefulWidget {
  const new({required this.child, this.padding = EdgeInsets.zero, this.floating = true, super.key});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Over the map, the arrows float with a shadow; in a pane they sit flat.
  final bool floating;

  /// How wide a side with more to see fades out.
  static const double moreFade = Space.giant;

  @override
  State<SidewaysRow> createState() => _SidewaysRowState();
}

class _SidewaysRowState extends State<SidewaysRow> {
  final _scroll = ScrollController();

  /// The row's visible part, for where its items stand.
  final GlobalKey _viewport = GlobalKey();

  /// Whether some of the row lies past each edge.
  var _before = false;
  var _after = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    // The first layout tells whether the row overflows at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position;
    final before = p.pixels > p.minScrollExtent + 0.5;
    final after = p.pixels < p.maxScrollExtent - 0.5;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    // A trackpad's sideways swipe is the row's own; only the vertical
    // turn of a wheel is turned sideways.
    final delta = event.scrollDelta.dy;
    if (delta == 0 || event.scrollDelta.dx != 0) return;
    // As the user's own scroll (pointerScroll bounds it and says so to
    // the row's listeners), not one of the app's.
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _scroll.position.pointerScroll(delta),
    );
  }

  /// Where the row's items ([SidewaysStop]) stand in its visible part,
  /// from its start, in their order.
  List<(double, double)> _stops() {
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return const [];
    final out = <(double, double)>[];
    void visit(RenderObject o) {
      if (o is _RenderSidewaysStop) {
        if (o.hasSize) {
          final start = o.localToGlobal(Offset.zero, ancestor: viewport).dx;
          out.add((start, start + o.size.width));
        }
        return;
      }
      o.visitChildren(visit);
    }

    viewport.visitChildren(visit);
    return out..sort((a, b) => a.$1.compareTo(b.$1));
  }

  /// Towards the end when [forward]: the first item cut at that end, or
  /// past it, comes in whole just past the fade at the other; towards the
  /// start, the last one cut there comes in whole before the fade at the
  /// end. Without items, or one wider than the room between the fades,
  /// most of the row's width.
  Future<void> _page({required bool forward}) async {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final view = p.viewportDimension;
    const fade = SidewaysRow.moreFade;
    double? target;
    final stops = _stops();
    if (forward) {
      for (final (start, end) in stops) {
        if (end > view - fade + 0.5) {
          target = p.pixels + start - fade;
          break;
        }
      }
    } else {
      for (final (start, end) in stops.reversed) {
        if (start < fade - 0.5) {
          target = p.pixels + end - (view - fade);
          break;
        }
      }
    }
    final step = view * 0.8;
    if (target == null || (forward ? target <= p.pixels : target >= p.pixels)) {
      target = p.pixels + (forward ? step : -step);
    }
    final to = target.clamp(p.minScrollExtent, p.maxScrollExtent);
    final duration = Motion.of(context, Motion.medium);
    // With less motion asked, a jump: an animation needs a duration.
    if (duration == Duration.zero) {
      _scroll.jumpTo(to);
      return;
    }
    await _scroll.animateTo(to, duration: duration, curve: Motion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final row = NotificationListener<ScrollMetricsNotification>(
      // The row's width changes with its chips and the window: what lies
      // past each edge is measured again.
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _measure();
        });
        return false;
      },
      child: Listener(
        key: _viewport,
        onPointerSignal: _onSignal,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            clipBehavior: Clip.none,
            child: widget.child,
          ),
        ),
      ),
    );
    final start = _before ? SidewaysRow.moreFade : Space.s;
    final end = _after ? SidewaysRow.moreFade : Space.s;
    final faded = ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, (start / rect.width).clamp(0, 0.5), 1 - (end / rect.width).clamp(0, 0.5), 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: row,
    );
    if (!pointerPlatform) return faded;
    return Stack(
      alignment: Alignment.center,
      children: [
        faded,
        if (_before)
          Positioned(
            left: 0,
            child: _Arrow(
              tooltip: t.filters.scrollPrevious,
              backwards: true,
              floating: widget.floating,
              onPressed: () => _page(forward: false),
            ),
          ),
        if (_after)
          Positioned(
            right: 0,
            child: _Arrow(
              tooltip: t.filters.scrollNext,
              backwards: false,
              floating: widget.floating,
              onPressed: () => _page(forward: true),
            ),
          ),
      ],
    );
  }
}

/// An item of a [SidewaysRow], a chip: its arrows bring one in whole
/// rather than by a width that may cut it at the other edge.
class SidewaysStop extends SingleChildRenderObjectWidget {
  const new({super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSidewaysStop();
}

/// Marks an item's box for [_SidewaysRowState._stops].
class _RenderSidewaysStop extends RenderProxyBox;

/// A round arrow at an edge of [SidewaysRow], for a mouse.
class _Arrow extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.backwards,
    required this.floating,
    required this.onPressed,
  });

  final String tooltip;

  /// Points to the start of the row.
  final bool backwards;
  final bool floating;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final size = controlHeight(context, QuickFilters.chipTouchHeight);
    return OverMap(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: floating ? tokens.floatingSurface : scheme.surfaceContainerHigh,
          border: floating ? null : Border.all(color: scheme.outlineVariant),
          boxShadow: floating ? tokens.floatingShadow : null,
        ),
        child: SizedBox.square(
          dimension: size,
          child: IconButton(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            icon: Transform.flip(
              flipX: backwards,
              child: Icon(AppIcons.chevron, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip of the row after "Filters": a filter of the places, or a category
/// of the shops and services around.
sealed class QuickChip {
  const new();
}

/// A filter of the places themselves.
enum PlaceChip implements QuickChip { night, vehicle, free }

/// A category of the shops and services around.
@immutable
final class PoiChip extends QuickChip {
  const new(this.category);

  final PoiCategory category;

  @override
  bool operator ==(Object other) => other is PoiChip && other.category == category;

  @override
  int get hashCode => category.hashCode;
}

/// [chips] cut into runs of the same kind, in order.
List<List<QuickChip>> _runs(List<QuickChip> chips) {
  final runs = <List<QuickChip>>[];
  for (final c in chips) {
    if (runs.isNotEmpty && (runs.last.last is PoiChip) == (c is PoiChip)) {
      runs.last.add(c);
    } else {
      runs.add([c]);
    }
  }
  return runs;
}

/// The categories of shops and services in the row, one group for a screen
/// reader, each chip padded as the others.
class _PoiGroup extends StatelessWidget {
  const new({required this.label, required this.chips});

  final String label;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Row(
      children: [
        for (final c in chips)
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: SidewaysStop(child: c),
          ),
      ],
    ),
  );
}

/// A chip over the map: a floating pill, amber-tinted when on. Shared with
/// the row of the points of interest (`features/poi`).
class MapChip extends StatelessWidget {
  const new({
    required this.label,
    required this.onTap,
    required this.floating,
    this.icon,
    this.iconColor,
    this.leading,
    this.selected = false,
    this.count = 0,
    this.semanticsLabel,
    super.key,
  });

  final IconData? icon;

  /// The icon's colour; the theme's text colour by default.
  final Color? iconColor;
  final Widget? leading;
  final String label;
  final bool selected;
  final int count;
  final bool floating;
  final String? semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final background = selected
        ? scheme.primaryContainer
        : floating
        ? tokens.floatingSurface
        : scheme.surfaceContainerHigh;
    return OverMap(
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticsLabel == null ? null : '$label, $semanticsLabel',
        // With its own label the chip excludes its children, the ink's tap
        // among them: the node carries the tap again.
        onTap: semanticsLabel == null ? null : onTap,
        excludeSemantics: semanticsLabel != null,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.short),
          // 48 dp: the smallest touch target of the design rules; 40 with a
          // mouse, which aims finer.
          height: controlHeight(context, 48),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (floating ? Colors.transparent : scheme.outlineVariant),
              width: 1.5,
            ),
            boxShadow: floating ? tokens.floatingShadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.ml),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?leading,
                    if (icon != null) Icon(icon, size: 20, color: iconColor ?? scheme.onSurface),
                    const SizedBox(width: Space.s),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge,
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: Space.s),
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$count',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: scheme.onPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
