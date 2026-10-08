import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

/// Lets the user tick the lists a place belongs to, and create one.
Future<void> showSaveToLists(BuildContext context, PlaceSummary place) => showSheet<void>(
  context,
  // Above the dock and the panels: the shell holds the branches.
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => _SaveToLists(place: place),
);

class _SaveToLists extends ConsumerWidget {
  const new({required this.place});

  final PlaceSummary place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final lists = ref.watch(favoriteListsProvider).value ?? const <FavoriteList>[];
    final member = ref.watch(placeListsProvider(place.id)).value ?? const <int>{};
    final repo = ref.read(favoritesRepositoryProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.s),
            child: Text(t.place.saveTo, style: Theme.of(context).textTheme.titleLarge),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final list in lists)
                  CheckboxListTile(
                    value: member.contains(list.id),
                    title: Text(list.isDefault ? t.favorites.defaultList : (list.name ?? '')),
                    subtitle: Text(t.favorites.count(n: list.count)),
                    onChanged: (checked) => checked ?? false
                        ? repo.add(list.id, place)
                        : repo.remove(list.id, place.id),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(AppIcons.add),
            title: Text(t.favorites.newList),
            onTap: () async {
              final name = await askListName(context, title: t.favorites.newList);
              if (name == null) return;
              final id = await repo.createList(name);
              await repo.add(id, place);
            },
          ),
          const SizedBox(height: Space.s),
        ],
      ),
    );
  }
}

/// Asks for a list name; null when cancelled or empty.
Future<String?> askListName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _ListNameDialog(title: title, initial: initial),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Owns its text controller, so the field outlives the closing animation.
class _ListNameDialog extends StatefulWidget {
  const new({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: t.favorites.listName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.common.cancel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: Text(t.common.save),
        ),
      ],
    );
  }
}
