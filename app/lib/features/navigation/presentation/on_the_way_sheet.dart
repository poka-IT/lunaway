import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart' show SidewaysRow;
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/on_the_way_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_point_card.dart';
import 'package:lunaway/features/places/application/place_digests.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/features/poi/domain/poi.dart' hide FuelOffer;
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/images/retrying_image.dart';
import 'package:lunaway/shared/images/thumbhash.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

final _log = Logger('on_the_way');

/// "On the way": fuel, a night, water, a shop... ahead on [route] from
/// [fromM], one chip per kind of stop, fuel first. The chip chosen holds
/// for the trip [trip]. One tap on "Add" makes an item a stop through
/// [onAdd]; a tap on the row opens its page. While [driving], the sheet
/// opens at half height, the maneuver in sight above it. [startInset] is
/// the room the sheet leaves on the left for a panel ([showSheet]): the
/// guidance's maneuver, the phone on its side.
Future<void> showOnTheWaySheet(
  BuildContext context, {
  required RouteTarget trip,
  required RouteOption route,
  required double fromM,
  required Future<void> Function(RouteStop stop) onAdd,
  bool driving = false,
  double Function(BuildContext context)? startInset,
}) => showSheet<void>(
  context,
  isScrollControlled: true,
  startInset: startInset,
  builder: (context) => _OnTheWayHeight(
    driving: driving,
    builder: (context, scroll) => OnTheWaySheet(
      trip: trip,
      route: route,
      fromM: fromM,
      onAdd: onAdd,
      driving: driving,
      scrollController: scroll,
    ),
  ),
);

/// The sheet's height, as tall as the window asks: a phone on its side, or
/// large text in a short window, has half the height hold the chips and
/// nothing of the list, so the sheet stands nearly whole there, the header
/// on one line. Turned while open, the sheet takes the height of the new
/// window, dragged or not.
class _OnTheWayHeight extends StatefulWidget {
  const new({required this.driving, required this.builder});

  final bool driving;
  final ScrollableWidgetBuilder builder;

  @override
  State<_OnTheWayHeight> createState() => _OnTheWayHeightState();
}

class _OnTheWayHeightState extends State<_OnTheWayHeight> {
  final _controller = DraggableScrollableController();
  bool _short = false;
  bool _measured = false;

  double get _initial => _short ? 0.94 : (widget.driving ? 0.5 : 0.72);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final short = isShortForOnTheWay(context);
    final turned = _measured && short != _short;
    _short = short;
    _measured = true;
    if (!turned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.isAttached) _controller.jumpTo(_initial);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    controller: _controller,
    expand: false,
    initialChildSize: _initial,
    minChildSize: widget.driving ? 0.3 : 0.4,
    maxChildSize: 0.94,
    builder: widget.builder,
  );
}

/// Whether the window is too short for the sheet's header above half a
/// list: under 520 dp of height once the text size is counted.
bool isShortForOnTheWay(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  return height / MediaQuery.textScalerOf(context).scale(1) < 520;
}

/// The body of the sheet, public for the tests.
class OnTheWaySheet extends ConsumerStatefulWidget {
  const new({
    required this.trip,
    required this.route,
    required this.fromM,
    required this.onAdd,
    this.driving = false,
    this.scrollController,
    super.key,
  });

  final RouteTarget trip;
  final RouteOption route;
  final double fromM;
  final Future<void> Function(RouteStop stop) onAdd;
  final bool driving;
  final ScrollController? scrollController;

  @override
  ConsumerState<OnTheWaySheet> createState() => _OnTheWaySheetState();
}

class _OnTheWaySheetState extends ConsumerState<OnTheWaySheet> {
  /// The lists read while the sheet is open, kept so a chip tapped again
  /// shows its list at once rather than asking the server again.
  final _visited = <OnTheWayQuery>{};

  /// The user asked to choose another fuel than the vehicle's.
  bool _fuelChoice = false;

  /// "Further on" unfolded, for the chip it was unfolded on.
  OnTheWayCategory? _furtherOpen;

  /// One key per chip, each on its own chip for the sheet's life: a key
  /// that followed the choice would rebuild the chips it passed over, and
  /// the chip just pressed would lose the keyboard and screen reader focus.
  final Map<OnTheWayCategory, GlobalKey> _chipKeys = {
    for (final c in OnTheWayCategory.values) c: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    // The chip chosen when the sheet opens, brought into sight once: a
    // choice kept from earlier in the trip may lie past the row's edge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final opening = ref.read(onTheWayChoicesProvider.notifier).of(widget.trip).category;
      final chip = _chipKeys[opening]?.currentContext;
      if (chip != null && chip.mounted) {
        Scrollable.ensureVisible(chip, alignment: 0.5);
      }
    });
  }

  /// Brings the chip of [category] whole into sight, clear of the fade and
  /// of the arrow at the row's edge: a chip chosen there stayed cut.
  void _reveal(OnTheWayCategory category) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _chipKeys[category]?.currentContext;
      if (!mounted || chip == null || !chip.mounted) return;
      final box = chip.findRenderObject() as RenderBox?;
      final row = Scrollable.maybeOf(chip);
      final view = row?.context.findRenderObject() as RenderBox?;
      if (box == null || view == null || !box.hasSize || !view.hasSize) return;
      final left = box.localToGlobal(Offset.zero, ancestor: view).dx;
      const clear = SidewaysRow.moreFade;
      if (row == null || (left >= clear && left + box.size.width <= view.size.width - clear)) {
        return;
      }
      // The row's own position only: the sheet's list under it stays where
      // the reader left it.
      row.position.ensureVisible(
        box,
        alignment: 0.5,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.standard,
      );
    });
  }

  OnTheWayChoice _choice() {
    ref.watch(onTheWayChoicesProvider);
    return ref.read(onTheWayChoicesProvider.notifier).of(widget.trip);
  }

  void _add(RouteStop stop) {
    Navigator.pop(context);
    unawaited(widget.onAdd(stop));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final choice = _choice();
    final category = choice.category;
    for (final q in _visited) {
      ref.listen(onTheWayListProvider(q), (_, _) {});
    }
    final background =
        theme.bottomSheetTheme.modalBackgroundColor ??
        theme.bottomSheetTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerLow;
    final body = category == OnTheWayCategory.fuel ? _fuel(choice) : _list(category);
    final short = isShortForOnTheWay(context);
    final title = Semantics(
      header: true,
      child: Text(t.navigation.onTheWay.title, style: theme.textTheme.titleLarge),
    );
    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        PinnedHeaderSliver(
          child: ColoredBox(
            color: background,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!short)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                    child: title,
                  ),
                // One row that scrolls: the list keeps its height on a
                // phone turned sideways with large text, where the title
                // leads the row. The map's row of chips: it fades where
                // more lies past an edge, and a mouse scrolls it by its
                // wheel, a drag or the arrows.
                SidewaysRow(
                  floating: false,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Row(
                    children: [
                      if (short)
                        Padding(
                          padding: const EdgeInsets.only(right: Space.m),
                          child: title,
                        ),
                      for (final c in OnTheWayCategory.values)
                        Padding(
                          key: _chipKeys[c],
                          padding: const EdgeInsets.only(right: Space.s),
                          child: ChoiceChip(
                            mouseCursor: WidgetStateMouseCursor.clickable,
                            showCheckmark: false,
                            avatar: Icon(categoryIcon(c), size: 18),
                            label: Text(t.onTheWayCategory(c)),
                            selected: c == category,
                            onSelected: (_) {
                              ref.read(onTheWayChoicesProvider.notifier).choose(widget.trip, c);
                              _reveal(c);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s),
              ],
            ),
          ),
        ),
        ...body,
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Space.l,
            Space.s,
            Space.l,
            Space.l + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              _credit(t, category),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  String _credit(Translations t, OnTheWayCategory category) => switch (category) {
    // The prices from the national feed; the stations, their names and
    // places, from OpenStreetMap.
    OnTheWayCategory.fuel =>
      '${t.navigation.fuel.attribution}\n${t.navigation.preview.attributionOsm}',
    OnTheWayCategory.sleep => t.navigation.onTheWay.placesCredit,
    OnTheWayCategory.water =>
      '${t.navigation.onTheWay.placesCredit}\n${t.navigation.preview.attributionOsm}',
    _ => t.navigation.preview.attributionOsm,
  };

  List<Widget> _fuel(OnTheWayChoice choice) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(routeSettingsControllerProvider).value ?? const NavigationSettings();
    final vehicle = ref.watch(vehicleFuelProvider);
    final own = vehicle.fuel;
    final fuel = choice.fuel ?? own ?? FuelType.diesel;
    final query = FuelQuery(line: widget.route.line, fromM: widget.fromM, fuel: fuel);
    final offers = ref.watch(fuelOffersProvider(query));
    ref.listen(fuelOffersProvider(query), (_, next) {
      if (next.value case final shown?) {
        ref.read(shownFuelOffersProvider(widget.route.line).notifier).show(shown);
      }
    });
    final now = ref.watch(clockProvider)();
    final chips = own == null || _fuelChoice || choice.fuel != null;
    final header = <Widget>[
      if (!chips)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s,
          children: [
            Text(
              t.navigation.onTheWay.fuelOfVehicle(fuel: t.fuelType(own)),
              style: theme.textTheme.titleMedium,
            ),
            TextButton(
              onPressed: () => setState(() => _fuelChoice = true),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(t.navigation.onTheWay.otherFuel),
            ),
          ],
        )
      else ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in FuelType.values)
                Padding(
                  padding: const EdgeInsets.only(right: Space.s),
                  child: ChoiceChip(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    label: Text(t.fuelType(f)),
                    selected: f == fuel,
                    // The vehicle's own fuel chosen again is no other
                    // fuel: the next opening shows it as the vehicle's.
                    onSelected: (_) => ref
                        .read(onTheWayChoicesProvider.notifier)
                        .chooseFuel(widget.trip, f == own ? null : f),
                  ),
                ),
            ],
          ),
        ),
        if (own == null && ref.watch(vehicleProvider).value != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => unawaited(_keepFuel(fuel)),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(t.navigation.onTheWay.keepFuel),
            ),
          ),
      ],
    ];
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        sliver: SliverList.list(children: header),
      ),
      ...switch (offers) {
        AsyncData(:final value) when value.isEmpty => [
          SliverFillRemaining(
            hasScrollBody: false,
            // The prices come from France's feed: past the border the
            // stations are there, their prices are not.
            child: _Message(
              title: t.navigation.fuel.empty,
              hint: t.navigation.fuel.emptyHint,
              picture: !widget.driving,
            ),
          ),
        ],
        AsyncData(:final value) => [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            sliver: SliverList.separated(
              itemCount: value.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _OfferTile(
                offer: value[i],
                consumption: vehicle.consumptionL100 ?? defaultConsumptionL100,
                units: settings.units,
                now: now,
                onAdd: () => _add(
                  RouteStop(
                    position: value[i].position,
                    label: value[i].name ?? value[i].brand ?? t.navigation.fuel.station,
                    poiId: value[i].poiId,
                  ),
                ),
              ),
            ),
          ),
          if (value.any((o) => o.detourEstimated))
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  t.navigation.fuel.estimated,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
        AsyncError() => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              title: t.navigation.fuel.failed,
              mood: SceneMood.error,
              picture: !widget.driving,
              action: t.common.retry,
              onAction: () => ref.invalidate(fuelOffersProvider(query)),
            ),
          ),
        ],
        _ => _loading(t),
      },
    ];
  }

  /// Keeps [fuel] as the vehicle's own, which every price of the app then
  /// shows: the map's labels, the cheapest around, this list.
  Future<void> _keepFuel(FuelType fuel) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(vehicleRepositoryProvider);
    final choices = ref.read(onTheWayChoicesProvider.notifier);
    try {
      final vehicle = await ref.read(vehicleProvider.future);
      if (vehicle == null) return;
      await repository.save(vehicle.copyWith(fuel: () => fuel));
    } on Object catch (e, st) {
      _log.warning('the fuel was not kept', e, st);
      showMessage(messenger, t.navigation.onTheWay.keepFuelFailed);
      return;
    }
    choices.chooseFuel(widget.trip, null);
    if (mounted) setState(() => _fuelChoice = false);
    showMessage(messenger, t.navigation.onTheWay.fuelKept(fuel: t.fuelType(fuel)));
  }

  List<Widget> _loading(Translations t) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
        child: Text(
          t.navigation.onTheWay.loading,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ),
    SliverList.list(children: const [SkeletonTile(), SkeletonTile(), SkeletonTile()]),
  ];

  List<Widget> _list(OnTheWayCategory category) {
    final t = context.t;
    final query = OnTheWayQuery(line: widget.route.line, fromM: widget.fromM, category: category);
    _visited.add(query);
    final list = ref.watch(onTheWayListProvider(query));
    return switch (list) {
      AsyncData(:final value) => _results(category, query, value),
      AsyncError(:final error) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(
            title: switch (error) {
              GraphQLRateLimitedException() => t.navigation.onTheWay.rateLimited,
              GraphQLNetworkException() => t.navigation.onTheWay.offline,
              _ => t.navigation.onTheWay.failed,
            },
            mood: error is GraphQLNetworkException && error is! GraphQLRateLimitedException
                ? SceneMood.offline
                : SceneMood.error,
            picture: !widget.driving,
            action: t.common.retry,
            onAction: () => ref.invalidate(onTheWayListProvider(query)),
          ),
        ),
      ],
      _ => _loading(t),
    };
  }

  List<Widget> _results(OnTheWayCategory category, OnTheWayQuery query, OnTheWayResults value) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = withoutDestination(
      value.items,
      destination: widget.trip.destination,
      placeId: widget.trip.placeId,
    );
    final (:near, :further) = splitNear(
      items,
      lineStartM: value.lineStartM,
      nearM: value.search.nearM,
    );
    if (near.isEmpty && further.isEmpty && value.next == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(
            title: t.navigation.onTheWay.empty,
            hint: t.navigation.onTheWay.emptyHint,
            picture: !widget.driving,
          ),
        ),
      ];
    }
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final digests = ref.watch(placeDigestsProvider);
    final now = ref.watch(clockProvider)();
    final notifier = ref.read(onTheWayListProvider(query).notifier);
    // Nothing near: what lies further shows unfolded.
    final open = _furtherOpen == category || near.isEmpty;
    Widget row(OnTheWayItem item) => _ItemRow(
      item: item,
      route: widget.route,
      fromM: widget.fromM,
      units: units,
      now: now,
      digest: digests[item.id],
      onAdd: _add,
    );
    Widget more() => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
        child: value.loadingMore
            // The button's own height: nothing under it moves.
            ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (value.moreFailed)
                    Text(
                      t.navigation.onTheWay.moreFailed,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                    ),
                  OutlinedButton(
                    onPressed: () => unawaited(notifier.more()),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: Text(value.moreFailed ? t.common.retry : t.navigation.onTheWay.more),
                  ),
                ],
              ),
      ),
    );
    return [
      if (near.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              t.navigation.onTheWay.nearNone(distance: t.routeDistance(value.search.nearM, units)),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      SliverList.separated(
        itemCount: near.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: Space.l, endIndent: Space.l),
        itemBuilder: (context, i) => row(near[i]),
      ),
      if (further.isEmpty && value.next != null) more(),
      if (further.isNotEmpty) ...[
        SliverToBoxAdapter(
          // With nothing near, what lies further is the list itself: a
          // heading, not a fold.
          child: near.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
                  child: Semantics(
                    header: true,
                    child: Text(
                      t.navigation.onTheWay.further(n: '${further.length}'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                )
              : Semantics(
                  expanded: open,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                    minTileHeight: 48,
                    title: Text(
                      t.navigation.onTheWay.further(n: '${further.length}'),
                      style: theme.textTheme.titleMedium,
                    ),
                    trailing: Icon(open ? AppIcons.expand : AppIcons.chevron),
                    onTap: () => setState(() => _furtherOpen = open ? null : category),
                  ),
                ),
        ),
        if (open) ...[
          SliverList.separated(
            itemCount: further.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: Space.l, endIndent: Space.l),
            itemBuilder: (context, i) => row(further[i]),
          ),
          if (value.next != null) more(),
        ],
      ],
      if (items.any((i) => i.detourEstimated))
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              t.navigation.fuel.estimated,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
    ];
  }
}

/// The icon of a chip.
IconData categoryIcon(OnTheWayCategory c) => switch (c) {
  OnTheWayCategory.fuel => AppIcons.fuel,
  OnTheWayCategory.sleep => PhosphorRegular.moonStars,
  OnTheWayCategory.water => PhosphorRegular.drop,
  OnTheWayCategory.groceries => PhosphorRegular.basket,
  OnTheWayCategory.bakeries => PhosphorRegular.bread,
  OnTheWayCategory.food => PoiLook.category(PoiCategory.food),
  OnTheWayCategory.sights => PoiLook.category(PoiCategory.sights),
  OnTheWayCategory.vending => PhosphorRegular.pizza,
  OnTheWayCategory.toilets => PhosphorRegular.toilet,
  OnTheWayCategory.health => PhosphorRegular.firstAid,
  OnTheWayCategory.services => PhosphorRegular.washingMachine,
  OnTheWayCategory.charging => PhosphorRegular.plug,
  OnTheWayCategory.garages => PhosphorRegular.wrench,
};

/// The words of the sheet.
extension OnTheWayLabels on Translations {
  // Read through a name, so the translation gate sees every key used.
  Translations get _t => this;

  String onTheWayCategory(OnTheWayCategory c) => switch (c) {
    OnTheWayCategory.fuel => _t.navigation.onTheWay.categories.fuel,
    OnTheWayCategory.sleep => _t.navigation.onTheWay.categories.sleep,
    OnTheWayCategory.water => _t.navigation.onTheWay.categories.water,
    OnTheWayCategory.groceries => _t.navigation.onTheWay.categories.groceries,
    OnTheWayCategory.bakeries => _t.navigation.onTheWay.categories.bakeries,
    OnTheWayCategory.food => poiCategory(PoiCategory.food),
    OnTheWayCategory.sights => poiCategory(PoiCategory.sights),
    // The machines' own name on the map's chip: a bare "vending machines"
    // would read as cash machines, or as fuel pumps in Italian.
    OnTheWayCategory.vending => _t.poi.category.vending,
    OnTheWayCategory.toilets => _t.navigation.onTheWay.categories.toilets,
    OnTheWayCategory.health => _t.navigation.onTheWay.categories.health,
    OnTheWayCategory.services => _t.navigation.onTheWay.categories.services,
    OnTheWayCategory.charging => _t.navigation.onTheWay.categories.charging,
    OnTheWayCategory.garages => _t.navigation.onTheWay.categories.garages,
  };

  /// "Add · +4 min", or "Add · no detour" under a minute.
  String addOnTheWay(double detourS) {
    final minutes = (detourS / 60).round();
    return minutes < 1
        ? _t.navigation.onTheWay.addFree
        : _t.navigation.onTheWay.addCost(minutes: '$minutes');
  }

  /// "in 12 km · 300 m from the route": where the item is reached, from
  /// the vehicle, and how far off the road.
  String whereOnTheWay(OnTheWayItem item, double fromM, DistanceUnits units) => [
    _t.navigation.onTheWay.ahead(distance: routeDistance(item.alongM - fromM, units)),
    if (item.offM < 100)
      _t.navigation.onTheWay.byTheRoad
    else
      _t.navigation.onTheWay.offRoute(distance: routeDistance(item.offM, units)),
  ].join(' · ');

  /// Whether a point is open when the vehicle gets there; null when its
  /// hours say nothing and its kind rarely has any (water, a machine).
  String? openAtPassage(PoiOnTheWay item, DateTime? at) {
    final state = at == null ? null : item.hours.stateAt(at);
    if (at == null || state == null) {
      // A viewpoint has no hours to know; a museum does.
      if (item.kind.timeless) return null;
      return switch (item.kind.category) {
        PoiCategory.groceries ||
        PoiCategory.health ||
        PoiCategory.services ||
        PoiCategory.food ||
        PoiCategory.sights => _t.navigation.fuel.unknownHours,
        _ => null,
      };
    }
    final time = clockTime(at.toLocal());
    return switch (state) {
      OpenUntil() || OpenThroughWindow() => _t.navigation.onTheWay.openAt(time: time),
      ClosedUntil(:final opensAt) when _sameDay(opensAt, at) =>
        _t.navigation.onTheWay.closedOpensAt(time: time, opens: clockTime(opensAt.toLocal())),
      ClosedUntil() || ClosedThroughWindow() => _t.navigation.onTheWay.closedAt(time: time),
    };
  }
}

bool _sameDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// An empty, offline or failed state, without its landscape at half
/// height.
class _Message extends StatelessWidget {
  const new({
    required this.title,
    required this.picture,
    this.hint,
    this.mood = SceneMood.empty,
    this.action,
    this.onAction,
  });

  final String title;
  final String? hint;
  final SceneMood mood;
  final bool picture;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.l),
    child: MessageView(
      title: title,
      hint: hint,
      mood: mood,
      compact: true,
      picture: picture,
      action: action,
      onAction: onAction,
    ),
  );
}

/// A place or a point along the route: what it is, and the way to it.
class _ItemRow extends ConsumerWidget {
  const new({
    required this.item,
    required this.route,
    required this.fromM,
    required this.units,
    required this.now,
    required this.onAdd,
    this.digest,
  });

  final OnTheWayItem item;
  final RouteOption route;
  final double fromM;
  final DistanceUnits units;
  final DateTime now;
  final PlaceDigest? digest;
  final void Function(RouteStop stop) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (leading, details, title, stop) = switch (item) {
      final PlaceOnTheWay p => (
        _PlaceThumb(item: p),
        _placeDetails(context, p),
        t.summaryTitle(p.place),
        RouteStop(position: p.position, label: t.summaryTitle(p.place), placeId: p.id),
      ),
      final PoiOnTheWay p => (
        PoiAvatar(kind: p.kind),
        _poiDetails(context, p),
        t.poiTitle(p.name, p.kind),
        RouteStop(position: p.position, label: t.poiTitle(p.name, p.kind), poiId: p.id),
      ),
    };
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: () {
        switch (item) {
          case PlaceOnTheWay(:final id):
            unawaited(showPlaceCard(context, id));
          case final PoiOnTheWay p:
            unawaited(_showPoiCard(context, p.feature));
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 64, child: Center(child: leading)),
                const SizedBox(width: Space.ml),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: Space.xxs),
                      ...details,
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: Space.xs,
              spacing: Space.s,
              children: [
                Text(
                  t.whereOnTheWay(item, fromM, units),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                OutlinedButton.icon(
                  onPressed: () => onAdd(stop),
                  icon: const Icon(AppIcons.add, size: 18),
                  label: Text(t.addOnTheWay(item.detourS)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _placeDetails(BuildContext context, PlaceOnTheWay p) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = p.place;
    final ratings = rowRatings(place, digest);
    final price = place.priceParkingEur;
    final services = [
      for (final s in _shownServices)
        if (place.services.contains(s)) s,
    ];
    final photo = p.photo;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return [
      // The night first, in its tone, then what it is: as the lists show
      // a place.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: NightBadge(place.overnight, size: 18),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.overnightShort(place.overnight),
                    style: TextStyle(
                      color: LunaTokens.of(context).nightTone(place.overnight).label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' · ${t.kind(place.kind)}'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
        ],
      ),
      if (ratings.isNotEmpty || price != null) ...[
        const SizedBox(height: Space.xxs),
        Wrap(
          spacing: Space.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (ratings.isNotEmpty) RatingsLine(ratings: ratings),
            if (price != null)
              Text(
                price == 0
                    ? t.place.priceFree
                    : t.navigation.onTheWay.perNight(price: t.euros(price)),
                style: muted,
              ),
          ],
        ),
      ],
      if (services.isNotEmpty) ...[
        const SizedBox(height: Space.xs),
        Semantics(
          label: t.navigation.onTheWay.servicesList(
            list: [for (final s in services) t.service(s)].join(', '),
          ),
          excludeSemantics: true,
          child: Wrap(
            spacing: Space.s,
            children: [
              for (final s in services)
                Icon(AppIcons.service(s), size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ],
      if (photo != null && !isLunawayCommunity(photo.sourceId)) ...[
        const SizedBox(height: Space.xxs),
        // Beside the photo, its source, author and licence: the credit
        // its terms ask for. The external community source's licence is
        // the reference of its agreement, which means nothing to a reader:
        // the place's page leaves it out too.
        Text(
          t.navigation.onTheWay.photoFrom(
            source: [
              photoCredit(t, photo),
              if (photo.sourceId != extcomSourceId) ?p.photoLicence,
            ].join(', '),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ];
  }

  List<Widget> _poiDetails(BuildContext context, PoiOnTheWay p) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = passageAt(route, fromM, p, now);
    final open = t.openAtPassage(p, at);
    final closed = at != null && p.hours.opennessAt(at) == PoiOpenness.closed;
    // A point without a name has its kind for a title: the line under it
    // does not say again what the title says.
    final title = t.poiTitle(p.name, p.kind);
    final kind = t.poiKind(p.kind);
    final what = [if (kind != title) kind, if (p.brand case final b? when b != title) b];
    return [
      if (what.isNotEmpty)
        Text(
          what.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      if (open != null)
        Text(
          open,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: at == null
                ? scheme.onSurfaceVariant
                : (closed ? scheme.error : poiOpeningColor(scheme, p.hours, at)),
          ),
        ),
    ];
  }
}

/// The services a row of a place shows, in this order: what a motorhome
/// stops for first.
const List<Service> _shownServices = [
  Service.drinkingWater,
  Service.greyWater,
  Service.blackWater,
  Service.electricity,
  Service.toilets,
  Service.showers,
  Service.laundry,
  Service.wifi,
];

/// A place's photo, in a square whose room is kept while it loads, or its
/// mark when it has none.
class _PlaceThumb extends ConsumerWidget {
  const new({required this.item});

  final PlaceOnTheWay item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = item.photo;
    if (photo == null) {
      return PlaceAvatar(kind: item.place.kind, overnight: item.place.overnight);
    }
    final scheme = Theme.of(context).colorScheme;
    final hash = photo.thumbhash;
    final placeholder = hash == null
        ? const Skeleton(width: 64, height: 64, radius: 0)
        : Image(image: ThumbHashImage(hash), fit: BoxFit.cover, excludeFromSemantics: true);
    return ClipRRect(
      borderRadius: BorderRadius.circular(LunaTokens.radiusM),
      child: SizedBox.square(
        dimension: 64,
        child: RetryingImage(
          image: ResizeImage(
            CachedImage(photo.thumbUrl, fetcher: ref.watch(imageFetcherProvider)),
            width: 192,
          ),
          fit: BoxFit.cover,
          placeholder: placeholder,
          waiting: placeholder,
          error: hash != null
              ? placeholder
              : ColoredBox(
                  color: scheme.surfaceContainerHigh,
                  child: Icon(AppIcons.noImage, color: scheme.onSurfaceVariant),
                ),
        ),
      ),
    );
  }
}

/// The page of a point of interest over the route, in a sheet.
Future<void> _showPoiCard(BuildContext context, PoiFeature feature) => showSheet<void>(
  context,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.94,
    builder: (context, scroll) => PoiDetails(
      feature: feature,
      scrollController: scroll,
      onClose: () => Navigator.pop(context),
      // No action bar over a route: the card copies the coordinates.
      copyCoordinates: true,
    ),
  ),
);

class _OfferTile extends StatelessWidget {
  const new({
    required this.offer,
    required this.consumption,
    required this.units,
    required this.now,
    required this.onAdd,
  });

  final FuelOffer offer;
  final double consumption;
  final DistanceUnits units;
  final DateTime now;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = switch (offer.open) {
      StationOpen.open => t.navigation.fuel.open,
      StationOpen.closed => t.navigation.fuel.closed,
      StationOpen.unknown => t.navigation.fuel.unknownHours,
    };
    final effective = effectivePrice(offer, consumptionL100: consumption);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: Space.xs),
      title: Text(
        offer.name ?? offer.brand ?? t.navigation.fuel.station,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // The price leads, as on the station's sign; the rest reads under it.
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: t.litrePrice(offer.priceEur),
              style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            TextSpan(
              text: [
                ' · ${t.priceAge(offer.priceUpdatedAt, now)}',
                '${t.detour(offer.detourM, offer.detourS, units)} · $open',
                if (offer.detourM >= 100) t.litrePriceWithDetour(effective),
              ].join('\n'),
            ),
          ],
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: offer.open == StationOpen.closed ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      // One station among several: a quiet button, so the prices stay what
      // the eye compares.
      trailing: OutlinedButton(onPressed: onAdd, child: Text(t.navigation.fuel.add)),
    );
  }
}
