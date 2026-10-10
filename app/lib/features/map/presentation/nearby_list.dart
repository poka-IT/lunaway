import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/map/application/listed_places.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/presentation/region_names.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/sub_page.dart';

/// The places of the viewed area, nearest first or in the order the user
/// chose, kept in step with the map: moving the map refreshes the list,
/// tapping a row selects the pin. While a new area loads, the rows of the
/// previous one stay: no skeleton flashes at every pan. From the API a page
/// at a time, the next one asked as the list nears its end.
class NearbyList extends ConsumerWidget {
  const new({this.scrollController, this.header, this.bottomPadding = Space.xxl, super.key});

  final ScrollController? scrollController;

  /// Shown above the rows, scrolling with them (a sheet's handle area).
  final Widget? header;

  /// Room below the last row (the dock floats there on a phone).
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(listedPlacesProvider);
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
      const SliverToBoxAdapter(child: _MissedRegionPrompt()),
      switch (places) {
        // A view the list could not read, the network gone: said at once,
        // rather than the rows of the view before under the map that moved
        // (an error keeps the value before it).
        AsyncError(:final error) => SliverFillRemaining(
          hasScrollBody: false,
          child: _Failed(error: error),
        ),
        AsyncValue(value: ListedPage(:final page)) when page.places.isEmpty =>
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyList()),
        AsyncValue(value: ListedPage(:final page, :final digests)) => SliverList.builder(
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
              digest: digests[p.id],
              onTap: () => select(p),
            );
          },
        ),
        _ => SliverList.builder(itemCount: 6, itemBuilder: (_, _) => const SkeletonTile()),
      },
      SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
    ];
    return CustomScrollView(controller: scrollController, slivers: slivers);
  }
}

/// The list that could not be read, with the way to ask again.
class _Failed extends ConsumerWidget {
  const new({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return MessageView(
      mood: SceneMood.error,
      // The network, when it is the network: the user can do something
      // about it.
      title: _networkFailure(error) ? t.list.offline : t.list.error,
      compact: true,
      action: t.common.retry,
      onAction: () => ref.invalidate(nearbyPlacesPageProvider),
    );
  }
}

/// Whether [error] is the network's, which the user can do something about.
bool _networkFailure(Object? error) =>
    error is GraphQLNetworkException && error is! GraphQLRateLimitedException;

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
    // Offline, and the places of the view are not on the device: no
    // connection, said at once (the list's title says it), and where to
    // keep a region for next time.
    if (offlineHere(ref)) return _OfflineHere(region: ref.watch(viewRegionProvider)?.code);
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

/// Whether the list is offline where the device holds nothing of the
/// view (the region at its centre not kept, or at sea): its title then
/// says there is no connection.
bool offlineHere(WidgetRef ref) {
  if (ref.watch(placesFromTilesProvider) || ref.watch(basemapReachabilityProvider) != false) {
    return false;
  }
  return !(ref.watch(viewRegionProvider)?.held ?? false);
}

/// The list offline where the device holds nothing of the view: under its
/// title, "Pas de connexion", the way to the offline maps. The region of the view is
/// remembered, so the list offers it once the network is back
/// ([_MissedRegionPrompt]); the network is asked again every few seconds
/// while this shows, so that return is seen soon.
class _OfflineHere extends ConsumerStatefulWidget {
  const new({required this.region});

  final String? region;

  @override
  ConsumerState<_OfflineHere> createState() => _OfflineHereState();
}

class _OfflineHereState extends ConsumerState<_OfflineHere> {
  Timer? _probe;

  @override
  void initState() {
    super.initState();
    _remember();
    _probe = Timer.periodic(offlineListProbe, (_) {
      // On screen only: the app in the background asks nothing.
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      unawaited(ref.read(basemapReachabilityProvider.notifier).probe());
    });
  }

  @override
  void didUpdateWidget(_OfflineHere old) {
    super.didUpdateWidget(old);
    if (old.region != widget.region) _remember();
  }

  void _remember() {
    final code = widget.region;
    if (code == null) return;
    // After the build: a provider does not change while widgets build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(missedRegionsProvider.notifier).add(code);
    });
  }

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final maps = ref.watch(keepsPlacesProvider);
    // Words and action close under the list's title: on a phone the sheet
    // rests low over the map, and all of it shows above the dock.
    return Align(
      alignment: Alignment.topLeft,
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.list.offlineNotHere,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (maps) ...[
                const SizedBox(height: Space.s),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.offlineMaps),
                  icon: const Icon(AppIcons.map),
                  label: Text(t.offlineMaps.title),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How often the list offline asks whether the network is back.
const offlineListProbe = Duration(seconds: 10);

/// Above the list once the network is back, in a region the list found
/// missing while offline: "Bretagne n'est pas sur cet appareil", its size,
/// and "Télécharger cette région". Closed or taken, it goes.
class _MissedRegionPrompt extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(keepsPlacesProvider) || !ref.watch(placesFromTilesProvider)) {
      return const SizedBox.shrink();
    }
    final missed = ref.watch(missedRegionsProvider);
    if (missed.isEmpty) return const SizedBox.shrink();
    final here = ref.watch(viewRegionProvider);
    final region = here == null || here.kept || !missed.contains(here.code)
        ? null
        : ref.watch(regionCatalogControllerProvider).value?.byCode(here.code);
    if (region == null) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pack = region.pack;
    final name = t.regionName(region);
    final forget = ref.read(missedRegionsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xxs, Space.m),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.regions.notHere(name: name), style: theme.textTheme.titleMedium),
                  if (pack != null)
                    Text(
                      t.regions.packInfo(
                        n: pack.places,
                        count: t.number(pack.places),
                        size: t.fileSize(pack.bytes),
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: Space.s),
                  FilledButton.icon(
                    onPressed: () async {
                      forget.remove(region.code);
                      await ref.read(keptRegionsControllerProvider.notifier).add({region.code});
                    },
                    icon: const Icon(AppIcons.download),
                    label: Text(t.regions.downloadThis),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: t.common.close,
              icon: const Icon(AppIcons.close),
              onPressed: () => forget.remove(region.code),
            ),
          ],
        ),
      ),
    );
  }
}

/// The count line above the list: how many places the area holds, the
/// number in Fraunces, and the order of the list, which the user changes
/// there.
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
    final read = ref.watch(nearbyPlacesPageProvider);
    // A count only of the view shown: none while the list reads another
    // view, nor once it failed to (the count of the view before stayed
    // under a map moved offline).
    final current = !read.isLoading && !read.hasError;
    final page = stored == 0 || !current ? null : read.value;
    final count = page?.total ?? page?.places.length;
    // Offline over nothing the device holds, or a view the network did not
    // bring: the title says why the list is empty, where the sheet at rest
    // shows it first.
    final offline =
        ((page?.places.isEmpty ?? true) && offlineHere(ref)) ||
        (!read.isLoading && _networkFailure(read.error));
    // The list is sorted from the user when the map shows them, from the
    // map's centre otherwise: the title says which.
    final user = ref.watch(userLocationProvider);
    final bounds = ref.watch(viewportProvider)?.bounds;
    final fromUser = user != null && (bounds == null || bounds.contains(user));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final demo = ref.watch(appConfigProvider).demo;
    final title = offline
        ? Text(t.list.offlineTitle, style: theme.textTheme.titleLarge)
        : count == null
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
    final rankedAmong = ref.watch(listedPlacesProvider).value?.rankedAmong;
    final row = Row(
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
        const ListSortButton(),
        ?trailing,
      ],
    );
    if (rankedAmong == null) return row;
    // Ranked otherwise than by distance, the list orders the nearest it
    // read, not every place of the view: it says so.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Text(
          fromUser
              ? t.list.rankedAmongNearestYou(n: t.number(rankedAmong))
              : t.list.rankedAmongNearestCentre(n: t.number(rankedAmong)),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The order of the list beside the map: distance, rating or the newest
/// places, kept between runs.
class ListSortButton extends ConsumerWidget {
  const new({super.key});

  static String label(Translations t, ListSort sort) => switch (sort) {
    ListSort.distance => t.list.sortDistance,
    ListSort.rating => t.list.sortRating,
    ListSort.newest => t.list.sortNewest,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final sort = ref.watch(settingsProvider.select((s) => s.listSort));
    return Semantics(
      label: t.list.sortedBy(sort: label(t, sort)),
      button: true,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: () => _choose(context, ref, sort),
        icon: const Icon(AppIcons.sort, size: 20),
        label: Text(label(t, sort)),
      ),
    );
  }

  // A popup route, not an overlay: on the web the map's element under it
  // is covered while it shows, so a click on a choice never reaches it.
  Future<void> _choose(BuildContext context, WidgetRef ref, ListSort current) async {
    final t = context.t;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final chosen = await showMenu<ListSort>(
      context: context,
      position: position,
      items: [
        for (final s in ListSort.values)
          PopupMenuItem(
            value: s,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label(t, s)),
              trailing: s == current ? const Icon(AppIcons.check) : null,
            ),
          ),
      ],
    );
    if (chosen != null && context.mounted) {
      await ref.read(settingsProvider.notifier).setListSort(chosen);
    }
  }
}
