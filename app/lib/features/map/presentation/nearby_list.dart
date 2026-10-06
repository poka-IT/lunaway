import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The places of the viewed area, nearest first, kept in step with the map:
/// moving the map refreshes the list, tapping a row selects the pin.
class NearbyList extends ConsumerWidget {
  const new({this.scrollController, this.header, super.key});

  final ScrollController? scrollController;

  /// Shown above the rows, scrolling with them (a sheet's handle area).
  final Widget? header;

  /// The list query stops at this many rows; at that count the area is too
  /// wide for a useful list.
  static const limit = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final places = ref.watch(nearbyPlacesProvider);
    final user = ref.watch(userLocationProvider);
    final selection = ref.watch(selectionProvider);
    final selectedId = selection is PlaceSelection ? selection.id : null;

    Future<void> select(PlaceSummary p) async {
      ref.read(selectionProvider.notifier).select(PlaceSelection(p.id));
      final zoom = ref.read(viewportProvider)?.zoom ?? 0;
      await ref.read(mapControllerProvider)?.moveTo(p.position, zoom: zoom < 12 ? 12 : null);
    }

    final slivers = <Widget>[
      if (header != null) SliverToBoxAdapter(child: header),
      switch (places) {
        AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
          hasScrollBody: false,
          child: MessageView(
            icon: AppIcons.emptyArea,
            title: t.list.empty,
            hint: t.list.emptyHint,
            compact: true,
          ),
        ),
        AsyncData(:final value) => SliverList.builder(
          itemCount: value.length,
          itemBuilder: (context, i) {
            final p = value[i];
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
            icon: AppIcons.error,
            title: t.list.error,
            error: true,
            compact: true,
            action: t.common.retry,
            onAction: () => ref.invalidate(nearbyPlacesProvider),
          ),
        ),
        AsyncLoading() => SliverList.builder(
          itemCount: 6,
          itemBuilder: (_, _) => const SkeletonTile(),
        ),
      },
      const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
    ];
    return CustomScrollView(controller: scrollController, slivers: slivers);
  }
}

/// The count line above the list: how many places the area holds, or a hint
/// to zoom in when the area is too wide.
class NearbyCount extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final count = ref.watch(nearbyPlacesProvider).value?.length;
    final theme = Theme.of(context);
    final demo = ref.watch(appConfigProvider).demo;
    return Row(
      children: [
        Expanded(
          child: Text(
            count == null
                ? t.list.title
                // At the limit the list holds the places nearest the centre,
                // not every place in view.
                : count >= NearbyList.limit
                ? t.map.nearestPlaces(n: count)
                : t.map.placesHere(n: count),
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (demo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusS),
            ),
            child: Text(
              t.map.demoBanner,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}
