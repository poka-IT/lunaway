import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/presentation/save_to_lists.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/tab_reselect.dart';

final _log = Logger('favorites');

/// Saved places, in lists. They live on the device and keep a copy of the
/// place, so they show even offline or after the place left the data.
class FavoritesScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final lists = ref.watch(favoriteListsProvider);
    final selectedId = ref.watch(selectedFavoriteListProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ScrollsToTopOnReselect(
          tab: AppTabs.favorites,
          child: switch (lists) {
            AsyncValue(value: final lists?) when lists.isNotEmpty => _Loaded(
              lists: lists,
              selected: lists.firstWhere((l) => l.id == selectedId, orElse: () => lists.first),
            ),
            AsyncError() => MessageView(
              mood: SceneMood.error,
              title: t.favorites.error,
              action: t.common.retry,
              onAction: () => ref.invalidate(favoriteListsProvider),
            ),
            _ => ListView(children: const [SkeletonTile(), SkeletonTile(), SkeletonTile()]),
          },
        ),
      ),
    );
  }
}

String listName(Translations t, FavoriteList list) =>
    list.isDefault ? t.favorites.defaultList : (list.name ?? t.favorites.defaultList);

Future<void> _newList(BuildContext context, WidgetRef ref) async {
  final name = await askListName(context, title: context.t.favorites.newList);
  if (name == null) return;
  final id = await ref.read(favoritesRepositoryProvider).createList(name);
  ref.read(selectedFavoriteListProvider.notifier).show(id);
}

class _Loaded extends ConsumerWidget {
  const new({required this.lists, required this.selected});

  final List<FavoriteList> lists;
  final FavoriteList selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final size = WindowSize.of(context);
    final select = ref.read(selectedFavoriteListProvider.notifier);
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        size == .compact ? Space.xl : Space.xxl,
        Space.l,
        Space.m,
        Space.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A wrap: at a large text size the button goes under the title
          // rather than squeezing it.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.s,
            children: [
              Semantics(
                header: true,
                child: Text(t.favorites.title, style: theme.textTheme.headlineMedium),
              ),
              // In the header, so it is never cut at the end of the cards.
              TextButton.icon(
                onPressed: () => _newList(context, ref),
                icon: const Icon(AppIcons.add),
                label: Text(t.favorites.newList),
              ),
            ],
          ),
          const _SyncLine(),
        ],
      ),
    );
    final cards = [
      for (final list in lists)
        _ListCard(list: list, selected: list.id == selected.id, onTap: () => select.show(list.id)),
    ];
    if (size == .expanded) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: ListView(
              children: [
                header,
                for (final c in cards)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.l, Space.s),
                    child: c,
                  ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: _Entries(key: ValueKey(selected.id), list: selected),
          ),
        ],
      );
    }
    // The cards grow with the text size, so their name and count never clip.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(
          height: 64 + 52 * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: size == .compact ? Space.xl : Space.xxl),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (_, i) => SizedBox(width: 136 + 40 * scale, child: cards[i]),
          ),
        ),
        const SizedBox(height: Space.s),
        Expanded(
          child: _Entries(key: ValueKey(selected.id), list: selected),
        ),
      ],
    );
  }
}

/// Where the lists live: on this device only (with the way to keep them
/// with an account), or with the account, and when they last synced.
class _SyncLine extends ConsumerWidget {
  const new();

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(AppIcons.sync, size: 32),
        title: Text(t.favoritesSync.title),
        content: Text(t.favoritesSync.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.favoritesSync.confirm),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await ref.read(favoritesSyncControllerProvider.notifier).syncNow();
    } on Object catch (e) {
      _log.info('favourites sync not started: $e');
      showMessage(messenger, t.common.offline);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final signedIn = ref.watch(accountControllerProvider) is SignedIn;
    final status = ref.watch(favoritesSyncControllerProvider);
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    if (!signedIn) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        children: [
          Icon(AppIcons.device, size: 18, color: theme.colorScheme.onSurfaceVariant),
          Text(t.favoritesSync.local, style: muted),
          TextButton(onPressed: () => _start(context, ref), child: Text(t.favoritesSync.action)),
        ],
      );
    }
    final (icon, text) = switch (status) {
      FavoritesSynced(:final at) => (
        AppIcons.checkCircle,
        t.favoritesSync.synced(when: t.ago(at, now)),
      ),
      FavoritesSyncFailed() => (AppIcons.offline, t.favoritesSync.failed),
      _ => (AppIcons.sync, t.favoritesSync.syncing),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(text, style: muted)),
        ],
      ),
    );
  }
}

/// A list as a card: its name in Fraunces and how many places it holds.
class _ListCard extends StatelessWidget {
  const new({required this.list, required this.selected, required this.onTap});

  final FavoriteList list;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
          side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  list.isDefault ? AppIcons.defaultList : AppIcons.customList,
                  color: list.isDefault ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: Space.s),
                Text(
                  listName(t, list),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  t.favorites.count(n: list.count),
                  style: LunaType.number(14, weight: 420, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListMenu extends ConsumerWidget {
  const new({required this.list});

  final FavoriteList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final repo = ref.read(favoritesRepositoryProvider);
    return PopupMenuButton<String>(
      tooltip: t.favorites.listActions,
      icon: const Icon(AppIcons.moreVertical),
      onSelected: (action) async {
        final name = listName(t, list);
        if (action == 'rename') {
          final renamed = await askListName(context, title: t.favorites.renameList, initial: name);
          if (renamed != null) await repo.renameList(list.id, renamed);
        } else if (context.mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t.favorites.deleteList),
              content: Text(t.favorites.deleteListConfirm(name: name)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.common.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.common.delete),
                ),
              ],
            ),
          );
          if (confirmed ?? false) {
            ref.read(selectedFavoriteListProvider.notifier).show(null);
            await repo.deleteList(list.id);
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: const Icon(AppIcons.rename),
            title: Text(t.favorites.renameList),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(AppIcons.delete),
            title: Text(t.favorites.deleteList),
          ),
        ),
      ],
    );
  }
}

/// The places of a list. A removal, by swipe or by the row's menu, leaves
/// the screen at once and can be undone.
class _Entries extends ConsumerStatefulWidget {
  const new({required this.list, super.key});

  final FavoriteList list;

  @override
  ConsumerState<_Entries> createState() => _EntriesState();
}

class _EntriesState extends ConsumerState<_Entries> {
  // Removed rows, hidden at once: a dismissed row must leave the tree in the
  // same frame, before the database answers.
  final Set<String> _gone = {};

  Future<void> _remove(FavoriteEntry e) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(favoritesRepositoryProvider);
    setState(() => _gone.add(e.placeId));
    final FavoriteEntry? removed;
    try {
      removed = await repo.remove(e.listId, e.placeId);
    } on Object catch (error, stack) {
      _log.warning('removing a favourite failed', error, stack);
      showMessage(messenger, t.common.saveFailed);
      // The swiped row must leave the tree before it comes back as new.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) setState(() => _gone.remove(e.placeId));
      return;
    }
    showMessage(
      messenger,
      t.favorites.removed,
      action: SnackBarAction(
        label: t.common.undo,
        onPressed: () async {
          if (removed != null) await repo.restore(removed);
          if (mounted) setState(() => _gone.remove(e.placeId));
        },
      ),
    );
  }

  Future<void> _open(FavoriteEntry e) async {
    ref.read(selectionProvider.notifier).select(PlaceSelection(e.placeId));
    context.go(AppRoutes.map);
    await ref.read(mapControllerProvider)?.moveTo(e.position, zoom: 13);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final list = widget.list;
    final entries = ref.watch(favoriteEntriesProvider(list.id));
    // A row stays hidden until the list stops holding it; then it is
    // forgotten here, so the place shows again if it is saved anew.
    ref.listen(favoriteEntriesProvider(list.id), (_, next) {
      final held = next.value?.map((e) => e.placeId).toSet();
      if (held != null) _gone.removeWhere((id) => !held.contains(id));
    });
    final user = ref.watch(userLocationProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final title = Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.s, Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(listName(t, list), style: theme.textTheme.titleLarge)),
          if (!list.isDefault) _ListMenu(list: list),
        ],
      ),
    );
    return switch (entries) {
      AsyncValue(:final value?) when value.where((e) => !_gone.contains(e.placeId)).isEmpty =>
        ListView(
          children: [
            title,
            MessageView(
              mood: SceneMood.saved,
              title: t.favorites.empty,
              hint: t.favorites.emptyHint,
            ),
          ],
        ),
      AsyncValue(:final value?) => () {
        final shown = value.where((e) => !_gone.contains(e.placeId)).toList();
        return ListView.builder(
          padding: EdgeInsets.only(bottom: bottom + Space.l),
          itemCount: shown.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return title;
            final e = shown[i - 1];
            return Dismissible(
              key: ValueKey('${e.listId}-${e.placeId}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: Space.xxl),
                color: theme.colorScheme.errorContainer,
                child: Icon(AppIcons.delete, color: theme.colorScheme.onErrorContainer),
              ),
              onDismissed: (_) => _remove(e),
              child: PlaceTile(
                place: PlaceSummary(
                  id: e.placeId,
                  name: e.name,
                  city: e.city,
                  kind: e.kind,
                  lat: e.position.lat,
                  lon: e.position.lon,
                  overnight: e.overnight,
                ),
                distanceM: user == null ? null : e.position.distanceTo(user),
                onTap: () => _open(e),
                trailing: PopupMenuButton<String>(
                  tooltip: t.favorites.placeActions,
                  icon: const Icon(AppIcons.moreVertical),
                  onSelected: (action) async {
                    switch (action) {
                      case 'open':
                        await _open(e);
                      case 'lists':
                        await showSaveToLists(
                          context,
                          PlaceSummary(
                            id: e.placeId,
                            name: e.name,
                            city: e.city,
                            kind: e.kind,
                            lat: e.position.lat,
                            lon: e.position.lon,
                            overnight: e.overnight,
                          ),
                        );
                      case 'remove':
                        await _remove(e);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'open',
                      child: ListTile(
                        leading: const Icon(AppIcons.map),
                        title: Text(t.favorites.openOnMap),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'lists',
                      child: ListTile(
                        leading: const Icon(AppIcons.lists),
                        title: Text(t.place.chooseLists),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        leading: const Icon(AppIcons.delete),
                        title: Text(t.favorites.remove),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }(),
      AsyncError() => MessageView(mood: SceneMood.error, title: t.favorites.error),
      _ => ListView(children: const [SkeletonTile(), SkeletonTile()]),
    };
  }
}
