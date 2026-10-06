import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
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
/// every pan.
class NearbyList extends ConsumerWidget {
  const new({this.scrollController, this.header, this.bottomPadding = Space.xxl, super.key});

  final ScrollController? scrollController;

  /// Shown above the rows, scrolling with them (a sheet's handle area).
  final Widget? header;

  /// Room below the last row (the dock floats there on a phone).
  final double bottomPadding;

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
        AsyncValue(value: final value?) when value.isEmpty => SliverFillRemaining(
          hasScrollBody: false,
          child: MessageView(title: t.list.empty, hint: t.list.emptyHint, compact: true),
        ),
        AsyncValue(value: final value?) => SliverList.builder(
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
            mood: SceneMood.error,
            title: t.list.error,
            compact: true,
            action: t.common.retry,
            onAction: () => ref.invalidate(nearbyPlacesProvider),
          ),
        ),
        _ => SliverList.builder(itemCount: 6, itemBuilder: (_, _) => const SkeletonTile()),
      },
      SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
    ];
    return CustomScrollView(controller: scrollController, slivers: slivers);
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
    final count = ref.watch(nearbyPlacesProvider).value?.length;
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
                      ' ${count >= NearbyList.limit ? t.map.nearestPlacesLabel(n: count) : t.map.placesHereLabel(n: count)}',
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
