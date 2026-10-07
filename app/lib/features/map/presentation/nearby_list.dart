import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The places of the viewed area, nearest first, kept in step with the map:
/// moving the map refreshes the list, tapping a row selects the pin. While a
/// new area loads, the rows of the previous one stay: no skeleton flashes at
/// every pan. From the API a page at a time, the next one asked as the
/// list nears its end.
class NearbyList extends ConsumerWidget {
  const new({this.scrollController, this.header, this.bottomPadding = Space.xxl, super.key});

  final ScrollController? scrollController;

  /// Shown above the rows, scrolling with them (a sheet's handle area).
  final Widget? header;

  /// Room below the last row (the dock floats there on a phone).
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final places = ref.watch(nearbyPlacesPageProvider);
    final user = ref.watch(userLocationProvider);
    final selection = ref.watch(selectionProvider);
    final selectedId = selection is PlaceSelection ? selection.id : null;

    Future<void> select(PlaceSummary p) async {
      ref.read(selectionProvider.notifier).select(PlaceSelection(p.id, hint: p));
      final zoom = ref.read(viewportProvider)?.zoom ?? 0;
      await ref.read(mapControllerProvider)?.moveTo(p.position, zoom: zoom < 12 ? 12 : null);
    }

    final slivers = <Widget>[
      if (header != null) SliverToBoxAdapter(child: header),
      switch (places) {
        AsyncValue(value: final page?) when page.places.isEmpty => const SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyList(),
        ),
        AsyncValue(value: final page?) => SliverList.builder(
          itemCount: page.places.length + (page.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == page.places.length) return _More(page: page);
            // A few rows before the end, the next page is on its way.
            if (page.hasMore && !page.moreFailed && i >= page.places.length - 5) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  unawaited(ref.read(nearbyPlacesPageProvider.notifier).loadMore());
                }
              });
            }
            final p = page.places[i];
            return PlaceTile(
              key: ValueKey(p.id),
              place: p,
              selected: p.id == selectedId,
              distanceM: user == null ? null : p.position.distanceTo(user),
              onTap: () => select(p),
            );
          },
        ),
        AsyncError() => SliverFillRemaining(
          hasScrollBody: false,
          child: MessageView(
            mood: SceneMood.error,
            title: t.list.error,
            compact: true,
            action: t.common.retry,
            onAction: () => ref.invalidate(nearbyPlacesPageProvider),
          ),
        ),
        _ => SliverList.builder(itemCount: 6, itemBuilder: (_, _) => const SkeletonTile()),
      },
      SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
    ];
    return CustomScrollView(controller: scrollController, slivers: slivers);
  }
}

/// The foot of a list with more pages: the next one on its way, or a retry
/// when it failed.
class _More extends ConsumerWidget {
  const new({required this.page});

  final NearbyPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    if (page.moreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Center(
          child: TextButton(
            onPressed: () => ref.read(nearbyPlacesPageProvider.notifier).loadMore(),
            child: Text(t.list.moreFailed),
          ),
        ),
      );
    }
    return const SkeletonTile();
  }
}

/// An empty list: during the first download the places are on their way,
/// with nothing stored yet the device has to download them, and only then
/// is it the area or the filters. From the API it is the area or the
/// filters.
class _EmptyList extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    if (ref.watch(placesFromTilesProvider)) {
      return MessageView(title: t.list.empty, hint: t.list.emptyHint, compact: true);
    }
    final count = ref.watch(placeCountProvider);
    // A count that failed says nothing of a download: the list itself
    // answered, empty, so it is the area or the filters.
    if (count.hasError && !count.hasValue) {
      return MessageView(title: t.list.empty, hint: t.list.emptyHint, compact: true);
    }
    final stored = count.value;
    // Not counted yet: no message rather than a wrong one.
    if (stored == null) return const SizedBox.shrink();
    if (stored == 0) {
      final running = ref.watch(syncControllerProvider) is SyncRunning;
      return MessageView(
        title: running ? t.list.downloading : t.map.noData,
        hint: running ? t.list.downloadingHint : t.map.noDataHint,
        compact: true,
      );
    }
    return MessageView(title: t.list.empty, hint: t.list.emptyHint, compact: true);
  }
}

/// The count line above the list: how many places the area holds, the
/// number in Fraunces.
class NearbyCount extends ConsumerWidget {
  const new({this.trailing, super.key});

  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    // Nothing stored yet: no count of "0 places here" over a download. From
    // the API, the count of the whole view.
    final fromTiles = ref.watch(placesFromTilesProvider);
    final stored = fromTiles ? null : ref.watch(placeCountProvider).value;
    final page = stored == 0 ? null : ref.watch(nearbyPlacesPageProvider).value;
    final count = page?.total ?? page?.places.length;
    // The list is sorted from the user when the map shows them, from the
    // map's centre otherwise: the title says which.
    final user = ref.watch(userLocationProvider);
    final bounds = ref.watch(viewportProvider)?.bounds;
    final fromUser = user != null && (bounds == null || bounds.contains(user));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final demo = ref.watch(appConfigProvider).demo;
    final title = count == null
        ? Text(t.list.title, style: theme.textTheme.titleLarge)
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: t.number(count), style: LunaType.number(22, weight: 480)),
                TextSpan(
                  text:
                      ' ${page?.total != null
                          ? t.map.placesHereLabel(n: count)
                          : fromUser
                          ? t.map.nearestYouLabel(n: count)
                          : t.map.nearestCentreLabel(n: count)}',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            maxLines: 2,
          );
    return Row(
      children: [
        Expanded(child: Semantics(header: true, child: title)),
        if (demo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            ),
            child: Text(
              t.map.demoBanner,
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ?trailing,
      ],
    );
  }
}
