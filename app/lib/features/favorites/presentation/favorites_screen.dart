import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/presentation/save_to_lists.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// Saved places, in lists. They live on the device and keep a copy of the
/// place, so they show even offline or after the place left the data.
class FavoritesScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final lists = ref.watch(favoriteListsProvider);
    final selectedId = ref.watch(selectedFavoriteListProvider);
    final expanded = WindowSize.of(context) == .expanded;
    return switch (lists) {
      AsyncData(value: final lists) when lists.isNotEmpty => _Loaded(
        lists: lists,
        selected: lists.firstWhere((l) => l.id == selectedId, orElse: () => lists.first),
        expanded: expanded,
      ),
      AsyncError() => Scaffold(
        appBar: AppBar(title: Text(t.favorites.title)),
        body: MessageView(
          icon: AppIcons.error,
          title: t.favorites.error,
          error: true,
          action: t.common.retry,
          onAction: () => ref.invalidate(favoriteListsProvider),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: Text(t.favorites.title)),
        body: ListView(children: const [SkeletonTile(), SkeletonTile(), SkeletonTile()]),
      ),
    };
  }
}

String _listName(Translations t, FavoriteList list) =>
    list.isDefault ? t.favorites.defaultList : (list.name ?? t.favorites.defaultList);

class _Loaded extends ConsumerWidget {
  const new({required this.lists, required this.selected, required this.expanded});

  final List<FavoriteList> lists;
  final FavoriteList selected;
  final bool expanded;

  Future<void> _newList(BuildContext context, WidgetRef ref) async {
    final name = await askListName(context, title: context.t.favorites.newList);
    if (name == null) return;
    final id = await ref.read(favoritesRepositoryProvider).createList(name);
    ref.read(selectedFavoriteListProvider.notifier).show(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final select = ref.read(selectedFavoriteListProvider.notifier);
    final menu = selected.isDefault ? null : _ListMenu(list: selected);
    if (expanded) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 320,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SafeArea(
                  right: false,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: Space.l),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.l),
                        child: Text(
                          t.favorites.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      for (final list in lists)
                        ListTile(
                          selected: list.id == selected.id,
                          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                          leading: Icon(
                            list.isDefault ? AppIcons.favoriteSelected : AppIcons.customList,
                          ),
                          title: Text(_listName(t, list)),
                          trailing: Text(t.favorites.count(n: list.count)),
                          onTap: () => select.show(list.id),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                        child: OutlinedButton.icon(
                          onPressed: () => _newList(context, ref),
                          icon: const Icon(AppIcons.add),
                          label: Text(t.favorites.newList),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: AppBar(title: Text(_listName(t, selected)), actions: [?menu]),
                body: _Entries(list: selected),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t.favorites.title), actions: [?menu]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xxs, Space.l, Space.s),
            child: Row(
              children: [
                for (final list in lists)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: ChoiceChip(
                      label: Text('${_listName(t, list)} · ${list.count}'),
                      selected: list.id == selected.id,
                      onSelected: (_) => select.show(list.id),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(AppIcons.add),
                  label: Text(t.favorites.newList),
                  onPressed: () => _newList(context, ref),
                ),
              ],
            ),
          ),
          Expanded(child: _Entries(list: selected)),
        ],
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
      tooltip: t.common.more,
      onSelected: (action) async {
        final name = _listName(t, list);
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
        PopupMenuItem(value: 'rename', child: Text(t.favorites.renameList)),
        PopupMenuItem(value: 'delete', child: Text(t.favorites.deleteList)),
      ],
    );
  }
}

class _Entries extends ConsumerWidget {
  const new({required this.list});

  final FavoriteList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final entries = ref.watch(favoriteEntriesProvider(list.id));
    final user = ref.watch(userLocationProvider);
    return switch (entries) {
      AsyncData(:final value) when value.isEmpty => MessageView(
        icon: AppIcons.favorite,
        title: t.favorites.empty,
        hint: t.favorites.emptyHint,
      ),
      AsyncData(:final value) => ListView.builder(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        itemCount: value.length,
        itemBuilder: (context, i) {
          final e = value[i];
          return Dismissible(
            key: ValueKey('${e.listId}-${e.placeId}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: Space.xxl),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Icon(AppIcons.delete, color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            onDismissed: (_) async {
              final messenger = ScaffoldMessenger.of(context);
              final repo = ref.read(favoritesRepositoryProvider);
              await repo.remove(e.listId, e.placeId);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(t.favorites.removed),
                    action: SnackBarAction(label: t.common.undo, onPressed: () => repo.restore(e)),
                  ),
                );
            },
            child: ListTile(
              leading: PlaceAvatar(kind: e.kind, size: 40),
              title: Text(
                t.placeTitle(name: e.name, kind: e.kind),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(t.kind(e.kind)),
              trailing: user == null
                  ? const Icon(AppIcons.chevron)
                  : Text(
                      t.distance(e.position.distanceTo(user)),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
              onTap: () async {
                ref.read(selectionProvider.notifier).select(PlaceSelection(e.placeId));
                context.go(AppRoutes.map);
                await ref.read(mapControllerProvider)?.moveTo(e.position, zoom: 13);
              },
            ),
          );
        },
      ),
      AsyncError() => MessageView(icon: AppIcons.error, title: t.favorites.error, error: true),
      AsyncLoading() => ListView(children: const [SkeletonTile(), SkeletonTile()]),
    };
  }
}
