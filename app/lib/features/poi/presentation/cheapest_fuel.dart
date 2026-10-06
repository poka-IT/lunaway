import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/poi/application/fuel_feed_providers.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// "Cheapest around me", in place of the list of places while the fuel chip
/// is on: the stations of the view that sell the chosen fuel, cheapest
/// first, then nearest, each with its price, how fresh the price is, how
/// far, whether it is open, and the feed's shortages. The fuel switches in
/// the header; the vehicle's is the first one.
class CheapestFuelList extends ConsumerWidget {
  const new({
    this.scrollController,
    this.trailing,
    this.topPadding = 0,
    this.bottomPadding = Space.xxl,
    super.key,
  });

  final ScrollController? scrollController;

  /// Beside the title (a panel's close button).
  final Widget? trailing;
  final double topPadding;

  /// Room below the last row (the dock floats there on a phone).
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final zoom = ref.watch(viewportProvider)?.zoom ?? 0;
    final inView = ref.watch(cheapestFuelProvider);
    // Too many stations to read them all, or a view far out: the server's
    // search around the user ranks the stations instead. Against an API
    // without that search, the list asks to come closer.
    final around =
        zoom < fuelStationsMinZoom || (!inView.hasError && inView.hasValue && inView.value == null);
    final offers = around ? ref.watch(nearbyFuelProvider) : inView;
    final prices = [
      for (final o in offers.value ?? const <FuelOffer>[])
        if (o.shortage == null) o.price.priceEur,
    ];
    final tooMany = !offers.hasError && offers.hasValue && offers.value == null;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: _Header(
            // A failed read would date and credit the view before.
            offers: offers.hasError ? null : offers.value,
            now: now,
            trailing: trailing,
          ),
        ),
      ),
      if (tooMany)
        SliverFillRemaining(
          hasScrollBody: false,
          child: MessageView(title: t.poi.cheapest.zoomIn, compact: true),
        )
      else
        switch (offers) {
          // First: a failure keeps the stations of the view before, which
          // would show as this one's.
          AsyncError() => SliverFillRemaining(
            hasScrollBody: false,
            child: MessageView(
              mood: SceneMood.error,
              title: t.poi.cheapest.error,
              action: t.common.retry,
              onAction: () => ref.invalidate(around ? nearbyFuelProvider : fuelStationsProvider),
              compact: true,
            ),
          ),
          AsyncValue(:final value, hasValue: true) when value?.isEmpty ?? true =>
            SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(
                title: t.poi.cheapest.none,
                hint: t.poi.cheapest.noneHint,
                compact: true,
              ),
            ),
          AsyncValue(:final List<FuelOffer> value) => SliverList.builder(
            itemCount: value.length,
            itemBuilder: (context, i) => _OfferRow(
              key: ValueKey(value[i].station.id),
              offer: value[i],
              rank: value[i].shortage == null ? priceRank(value[i].price.priceEur, prices) : null,
              now: now,
            ),
          ),
          _ => SliverList.list(children: const [SkeletonTile(), SkeletonTile(), SkeletonTile()]),
        },
      SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
    ];
    return CustomScrollView(controller: scrollController, slivers: slivers);
  }
}

/// The title, the fuel shown and the switch to another, and when the feed
/// was read.
class _Header extends ConsumerWidget {
  const new({required this.offers, required this.now, this.trailing});

  final List<FuelOffer>? offers;
  final DateTime now;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen = ref.watch(chosenFuelProvider);
    final read = offers
        ?.map((o) => o.station.fuel?.fetchedAt)
        .nonNulls
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.s, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t.poi.cheapest.title, style: theme.textTheme.titleLarge),
                ),
              ),
              ?trailing,
            ],
          ),
          if (read != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.poi.feedRead(when: t.agoFine(read, now)),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: Space.s),
                SourceBadge(label: sourceName(t, fuelSourceId)),
                const SizedBox(width: Space.s),
              ],
            ),
          const SizedBox(height: Space.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final fuel in FuelType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: ChoiceChip(
                      label: Text(t.fuelType(fuel)),
                      selected: chosen == fuel,
                      onSelected: (_) {
                        Haptics.select();
                        ref.read(chosenFuelProvider.notifier).choose(fuel);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferRow extends ConsumerWidget {
  const new({required this.offer, required this.now, this.rank, super.key});

  final FuelOffer offer;
  final DateTime now;

  /// Where its price sits among those of the view, for its colour; null for
  /// a station out of the fuel.
  final double? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final station = offer.station;
    final rank = this.rank;
    final priceColor = rank == null
        ? scheme.onSurfaceVariant
        : PoiLook.price(rank, dark: theme.brightness == Brightness.dark);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final known = station.hours.opennessAt(now) != PoiOpenness.unknown;
    return InkWell(
      onTap: () {
        // A station no point of interest describes has no sheet: the map
        // goes to it.
        if (!station.id.startsWith('fuel-station:')) {
          ref.read(selectionProvider.notifier).select(PoiSelection(station.feature));
        }
        final zoom = ref.read(viewportProvider)?.zoom ?? 0;
        unawaited(
          ref.read(mapControllerProvider)?.moveTo(station.position, zoom: zoom < 14 ? 14 : null),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.s),
          child: Row(
            children: [
              PoiAvatar(kind: station.kind, size: 40, faded: offer.shortage != null),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.poiTitle(station.name, station.kind),
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${t.distance(offer.distanceM)} · '
                      '${t.poi.priceUpdated(when: t.agoFine(offer.price.updatedAt, now))}',
                      style: muted,
                    ),
                    if (known && offer.shortage == null)
                      Text(
                        t.poiOpening(station.hours, now),
                        style: muted?.copyWith(color: poiOpeningColor(scheme, station.hours, now)),
                      ),
                    if (offer.shortage != null)
                      Text(
                        t.poi.shortageTemporary,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              Text(
                t.pricePerLitre(offer.price.priceEur),
                style: theme.textTheme.titleMedium?.copyWith(color: priceColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
