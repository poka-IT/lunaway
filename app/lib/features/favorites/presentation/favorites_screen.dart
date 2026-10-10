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
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/favorites/presentation/save_to_lists.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';
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
          mouseCursor: WidgetStateMouseCursor.clickable,
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
          // The places stay on the map; the points saved in this list alone
          // have nowhere else to be, which the question says.
          final items = await repo.watchFavorites(list.id).first;
          var points = 0;
          for (final e in items.whereType<FavoritePointEntry>()) {
            if ((await repo.watchListsOf(e.point.id).first).length <= 1) points++;
          }
          if (!context.mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t.favorites.deleteList),
              content: Text(
                [
                  t.favorites.deleteListConfirm(name: name),
                  if (points > 0) t.favorites.deleteListPoints(n: points),
                ].join(' '),
              ),
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

/// The places and the saved points of a list. A removal, by swipe or by the
/// row's menu, leaves the screen at once and can be undone.
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

  Future<void> _remove(Favorite e) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(favoritesRepositoryProvider);
    setState(() => _gone.add(e.key));
    final Future<void> Function()? undo;
    try {
      switch (e) {
        case FavoriteEntry():
          final removed = await repo.remove(e.listId, e.placeId);
          undo = removed == null ? null : () => repo.restore(removed);
        case FavoritePointEntry():
          final removed = await repo.removePoint(e.listId, e.point.id);
          undo = removed == null ? null : () => repo.restorePoints([removed]);
      }
    } on Object catch (error, stack) {
      // The type alone: a database error's text holds what was saved.
      _log.warning('removing a favourite failed: ${error.runtimeType}', null, stack);
      showMessage(messenger, t.common.saveFailed);
      // The swiped row must leave the tree before it comes back as new.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) setState(() => _gone.remove(e.key));
      return;
    }
    showMessage(
      messenger,
      t.favorites.removed,
      action: SnackBarAction(
        label: t.common.undo,
        onPressed: () async {
          await undo?.call();
          if (mounted) setState(() => _gone.remove(e.key));
        },
      ),
    );
  }

  Future<void> _open(Favorite e) async {
    final selection = switch (e) {
      FavoriteEntry(:final placeId) => PlaceSelection(placeId),
      FavoritePointEntry(:final point) => selectionOfSaved(point),
    };
    ref.read(selectionProvider.notifier).select(selection);
    // The map at the selection's own address: the bare map's would close it.
    context.go(MapLink.to(selection).location);
    await ref
        .read(mapControllerProvider)
        ?.moveTo(e.position, zoom: e is FavoritePointEntry ? 16 : 13);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final list = widget.list;
    final entries = ref.watch(favoriteItemsProvider(list.id));
    // A row stays hidden until the list stops holding it; then it is
    // forgotten here, so it shows again if it is saved anew.
    ref.listen(favoriteItemsProvider(list.id), (_, next) {
      final held = next.value?.map((e) => e.key).toSet();
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
      AsyncValue(:final value?) when value.where((e) => !_gone.contains(e.key)).isEmpty => ListView(
        children: [
          title,
          MessageView(mood: SceneMood.saved, title: t.favorites.empty, hint: t.favorites.emptyHint),
        ],
      ),
      AsyncValue(:final value?) => () {
        final shown = value.where((e) => !_gone.contains(e.key)).toList();
        return ListView.builder(
          padding: EdgeInsets.only(bottom: bottom + Space.l),
          itemCount: shown.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return title;
            final e = shown[i - 1];
            final distance = user == null ? null : e.position.distanceTo(user);
            return Dismissible(
              key: ValueKey('${e.listId}-${e.key}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: Space.xxl),
                color: theme.colorScheme.errorContainer,
                child: Icon(AppIcons.delete, color: theme.colorScheme.onErrorContainer),
              ),
              onDismissed: (_) => _remove(e),
              child: switch (e) {
                FavoriteEntry() => PlaceTile(
                  place: e.summary,
                  distanceM: distance,
                  onTap: () => _open(e),
                  trailing: _PlaceMenu(
                    onOpen: () => _open(e),
                    onLists: () => showSaveToLists(context, e.summary),
                    onRemove: () => _remove(e),
                  ),
                ),
                FavoritePointEntry(:final point) => _PointTile(
                  point: point,
                  onTap: () => _open(e),
                  trailing: _PointMenu(
                    onOpen: () => _open(e),
                    onRename: () => showSavePointToLists(context, point, renaming: true),
                    onRemove: () => _remove(e),
                  ),
                ),
              },
            );
          },
        );
      }(),
      AsyncError() => MessageView(mood: SceneMood.error, title: t.favorites.error),
      _ => ListView(children: const [SkeletonTile(), SkeletonTile()]),
    };
  }
}

/// The menu of a saved place's row.
class _PlaceMenu extends StatelessWidget {
  const new({required this.onOpen, required this.onLists, required this.onRemove});

  final VoidCallback onOpen;
  final VoidCallback onLists;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PopupMenuButton<VoidCallback>(
      tooltip: t.favorites.placeActions,
      icon: const Icon(AppIcons.moreVertical),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: onOpen,
          child: ListTile(leading: const Icon(AppIcons.map), title: Text(t.favorites.openOnMap)),
        ),
        PopupMenuItem(
          value: onLists,
          child: ListTile(leading: const Icon(AppIcons.lists), title: Text(t.place.chooseLists)),
        ),
        PopupMenuItem(
          value: onRemove,
          child: ListTile(leading: const Icon(AppIcons.delete), title: Text(t.favorites.remove)),
        ),
      ],
    );
  }
}

/// The menu of a saved point's row: its name, note and lists are one
/// sheet.
class _PointMenu extends StatelessWidget {
  const new({required this.onOpen, required this.onRename, required this.onRemove});

  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PopupMenuButton<VoidCallback>(
      tooltip: t.favorites.pointActions,
      icon: const Icon(AppIcons.moreVertical),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: onOpen,
          child: ListTile(leading: const Icon(AppIcons.map), title: Text(t.favorites.openOnMap)),
        ),
        PopupMenuItem(
          value: onRename,
          child: ListTile(leading: const Icon(AppIcons.rename), title: Text(t.favorites.rename)),
        ),
        PopupMenuItem(
          value: onRemove,
          child: ListTile(leading: const Icon(AppIcons.delete), title: Text(t.favorites.remove)),
        ),
      ],
    );
  }
}

/// A saved point in a list, as a place's row reads: its mark (the kind of
/// point), the name the user gave it, what it is and where, its note, and
/// its menu.
class _PointTile extends StatelessWidget {
  const new({required this.point, required this.onTap, required this.trailing});

  final SavedPoint point;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.l, Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(44 * 0.32),
              ),
              child: Icon(savedPointIcon(point), size: 23, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: Space.ml),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Space.xxs),
                  Text(
                    [savedPointKindLabel(t, point), ?point.address].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  if (point.note case final note?) ...[
                    const SizedBox(height: Space.xxs),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            trailing,
          ],
        ),
      ),
    );
  }
}
