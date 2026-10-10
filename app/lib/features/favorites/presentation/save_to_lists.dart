import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

final _log = Logger('favorites');

/// Lets the user tick the lists a place belongs to, and create one. Each
/// tick saves at once; "Done" closes the sheet, which otherwise stays open
/// for a second list.
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
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.s),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.done),
            ),
          ),
        ],
      ),
    );
  }
}

/// The same sheet for a point outside the places (an address, a town, a
/// bare point, a shop): its name and a short note above the lists. The
/// name and the note go to every list that holds the point when the sheet
/// closes, however it closes; a tick saves the point at once as it reads
/// then. [renaming] puts the cursor in the name, selected.
Future<void> showSavePointToLists(
  BuildContext context,
  SavedPoint point, {
  bool renaming = false,
}) => showSheet<void>(
  context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => _SavePointToLists(point: point, renaming: renaming),
);

class _SavePointToLists extends ConsumerStatefulWidget {
  const new({required this.point, required this.renaming});

  /// The point as saved, or as it would be.
  final SavedPoint point;
  final bool renaming;

  @override
  ConsumerState<_SavePointToLists> createState() => _SavePointToListsState();
}

class _SavePointToListsState extends ConsumerState<_SavePointToLists> {
  // Read at once: dispose writes the name through it, when ref is gone.
  late final FavoritesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(favoritesRepositoryProvider);
  }

  late final TextEditingController _name = TextEditingController(text: widget.point.name)
    ..selection = widget.renaming
        ? TextSelection(baseOffset: 0, extentOffset: widget.point.name.length)
        : TextSelection.collapsed(offset: widget.point.name.length);
  late final TextEditingController _note = TextEditingController(text: widget.point.note ?? '');

  /// The point with the name and note as typed; an empty name keeps the
  /// one it had.
  SavedPoint get _current => widget.point.renamed(_name.text, _note.text);

  @override
  void dispose() {
    final current = _current;
    if (current != widget.point) {
      // The repository outlives the sheet: the edit lands after it closed.
      unawaited(
        _repo
            .updatePoint(current)
            .catchError((Object e, StackTrace s) => _log.warning('renaming a point failed', e, s)),
      );
    }
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lists = ref.watch(favoriteListsProvider).value ?? const <FavoriteList>[];
    final member = ref.watch(placeListsProvider(widget.point.id)).value ?? const <int>{};
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.s),
              child: Text(t.place.saveTo, style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.s),
              child: TextField(
                key: const Key('point-name'),
                controller: _name,
                autofocus: widget.renaming,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(SavedPoint.maxName)],
                decoration: InputDecoration(labelText: t.favorites.name),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.s),
              child: TextField(
                key: const Key('point-note'),
                controller: _note,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(SavedPoint.maxNote)],
                decoration: InputDecoration(labelText: t.favorites.note),
              ),
            ),
            for (final list in lists)
              CheckboxListTile(
                value: member.contains(list.id),
                title: Text(list.isDefault ? t.favorites.defaultList : (list.name ?? '')),
                subtitle: Text(t.favorites.count(n: list.count)),
                onChanged: (checked) => checked ?? false
                    ? _repo.addPoint(list.id, _current)
                    : _repo.removePoint(list.id, widget.point.id),
              ),
            ListTile(
              leading: const Icon(AppIcons.add),
              title: Text(t.favorites.newList),
              onTap: () async {
                final name = await askListName(context, title: t.favorites.newList);
                if (name == null) return;
                final id = await _repo.createList(name);
                await _repo.addPoint(id, _current);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.s),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.common.done),
              ),
            ),
          ],
        ),
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
