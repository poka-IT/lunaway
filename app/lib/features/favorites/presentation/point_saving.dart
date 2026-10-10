import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/save_to_lists.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

final _log = Logger('favorites');

/// What the card of a bare point, an address or a town saves: the
/// address's name and line when the search found one, else "Point du
/// 10 oct." (the day it was saved, in the user's time).
SavedPoint pointDraft(
  Translations t,
  LatLng position, {
  required DateTime now,
  AddressMatch? address,
}) {
  final town = address?.kind == AddressKind.town || address?.kind == AddressKind.postcode;
  final named = t.favorites.pointNamed(date: dayAndMonth(t, now.toLocal()));
  return SavedPoint.normalized(
    id: savedPointIdAt(position),
    kind: switch (address) {
      null => SavedPointKind.point,
      _ when town => SavedPointKind.town,
      _ => SavedPointKind.address,
    },
    name: address?.name ?? named,
    fallback: named,
    position: position,
    address: switch (address) {
      null => null,
      final a when town => a.detail,
      final a => [a.name, a.detail].where((s) => s.isNotEmpty).join(', '),
    },
  );
}

/// What the card of a shop or a service saves: its name, else its kind,
/// and its postal address when its page gave one.
SavedPoint poiDraft(Translations t, PoiFeature feature, {Address? address}) =>
    SavedPoint.normalized(
      id: savedPoiPointId(feature.id),
      kind: SavedPointKind.poi,
      name: t.poiTitle(feature.name, feature.kind),
      fallback: t.poiKind(feature.kind),
      position: feature.position,
      address: address == null
          ? null
          : [
              ?address.street,
              [?address.postcode, ?address.city].join(' '),
            ].where((s) => s.isNotEmpty).join(', '),
      poiId: feature.id,
      poiKind: feature.kind,
    );

/// What opens a saved point on the map: a shop or a service its own page,
/// any other point (and a shop whose kind this version does not know) its
/// card, which names it as saved.
MapSelection selectionOfSaved(SavedPoint point) => switch ((point.poiId, point.poiKind)) {
  (final id?, final kind?) => PoiSelection(
    PoiFeature(id: id, kind: kind, position: point.position, name: point.name),
  ),
  _ => PointSelection(point.position),
};

/// "10 oct.", in the order and the short month of the language.
String dayAndMonth(Translations t, DateTime date) => t.hours.dayOfMonth(
  day: date.day,
  month: switch (date.month) {
    1 => t.hours.months.jan,
    2 => t.hours.months.feb,
    3 => t.hours.months.mar,
    4 => t.hours.months.apr,
    5 => t.hours.months.may,
    6 => t.hours.months.jun,
    7 => t.hours.months.jul,
    8 => t.hours.months.aug,
    9 => t.hours.months.sep,
    10 => t.hours.months.oct,
    11 => t.hours.months.nov,
    _ => t.hours.months.dec,
  },
);

/// The icon of a saved point in the lists and on its card: the shop's own
/// glyph, else its nature's.
IconData savedPointIcon(SavedPoint point) => switch (point.kind) {
  SavedPointKind.poi => switch (point.poiKind) {
    final kind? => PoiLook.kind(kind),
    null => AppIcons.point,
  },
  SavedPointKind.town => AppIcons.town,
  SavedPointKind.address => AppIcons.address,
  SavedPointKind.point => AppIcons.point,
};

/// What a saved point is, in words: the shop's kind, else its nature.
String savedPointKindLabel(Translations t, SavedPoint point) => switch (point.kind) {
  SavedPointKind.poi => switch (point.poiKind) {
    final kind? => t.poiKind(kind),
    null => t.favorites.pointKind.poi,
  },
  SavedPointKind.town => t.favorites.pointKind.town,
  SavedPointKind.address => t.favorites.pointKind.address,
  SavedPointKind.point => t.favorites.pointKind.point,
};

/// Saves the point [draft] makes in the default list, or takes it out of
/// the default list only (the other lists keep it), with an undo either
/// way: the gesture of a place's "Save". A point already saved elsewhere
/// goes in with the name and note it has there.
Future<void> toggleDefaultPoint(
  BuildContext context,
  WidgetRef ref,
  SavedPoint Function() draft,
) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The message outlives the card: its action opens the sheet from the
  // app's root, which is still there once the card has closed.
  final root = Navigator.of(context, rootNavigator: true);
  final repo = ref.read(favoritesRepositoryProvider);
  try {
    final made = draft();
    final defaultId = await repo.defaultListId();
    final lists = await repo.watchListsOf(made.id).first;
    Haptics.confirm();
    if (lists.contains(defaultId)) {
      final removed = await repo.removePoint(defaultId, made.id);
      showMessage(
        messenger,
        t.place.removedToast,
        action: removed == null
            ? null
            : SnackBarAction(label: t.common.undo, onPressed: () => repo.restorePoints([removed])),
      );
    } else {
      final point = await repo.watchPoint(made.id).first ?? made;
      await repo.addPoint(defaultId, point);
      showMessage(
        messenger,
        t.place.savedToast,
        action: SnackBarAction(
          label: t.favorites.edit,
          onPressed: () {
            if (root.mounted) unawaited(showSavePointToLists(root.context, point));
          },
        ),
      );
    }
  } on Object catch (error, stack) {
    _log.warning('saving a point failed', error, stack);
    showMessage(messenger, t.common.saveFailed);
  }
}

/// Opens the sheet of the point [draft] makes: as saved when a list holds
/// it, with its name and note.
Future<void> editPoint(
  BuildContext context,
  WidgetRef ref,
  SavedPoint Function() draft, {
  bool renaming = false,
}) async {
  final made = draft();
  final saved = await ref.read(favoritesRepositoryProvider).watchPoint(made.id).first;
  if (!context.mounted) return;
  await showSavePointToLists(context, saved ?? made, renaming: renaming);
}

/// Takes the point [id] out of every list, with an undo.
Future<void> removePointEverywhere(BuildContext context, WidgetRef ref, String id) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(favoritesRepositoryProvider);
  try {
    final removed = await repo.removePointEverywhere(id);
    if (removed.isEmpty) return;
    Haptics.confirm();
    showMessage(
      messenger,
      t.favorites.removedEverywhere,
      action: SnackBarAction(label: t.common.undo, onPressed: () => repo.restorePoints(removed)),
    );
  } on Object catch (error, stack) {
    _log.warning('removing a point failed', error, stack);
    showMessage(messenger, t.common.saveFailed);
  }
}

/// The "Save" tile of a point's action bar, filled once the default list
/// holds it; a long press opens the lists, the name and the note.
class SavePointTile extends ConsumerWidget {
  const new({required this.id, required this.draft, super.key});

  /// The id the point has once saved ([savedPointIdAt], [savedPoiPointId]).
  final String id;

  /// The point as it would be saved now.
  final SavedPoint Function() draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final defaultId = ref.watch(defaultFavoriteListProvider).value;
    final lists = ref.watch(placeListsProvider(id)).value ?? const <int>{};
    final saved = defaultId != null && lists.contains(defaultId);
    return ActionTile(
      icon: saved ? AppIcons.favoriteSelected : AppIcons.favorite,
      iconColor: saved ? scheme.primary : null,
      label: saved ? t.place.saved : t.place.save,
      hint: t.place.saveHint,
      onPressed: () => toggleDefaultPoint(context, ref, draft),
      onLongPress: () => editPoint(context, ref, draft),
      longPressLabel: t.place.chooseLists,
    );
  }
}

/// What the card of a saved point adds: that it is in the favourites
/// (under which name, when the card shows another), its note, and the way
/// to rename it or take it out. Nothing for a point no list holds.
class SavedPointBlock extends ConsumerWidget {
  const new({required this.id, this.shownName, super.key});

  final String id;

  /// The name the card shows above; the block names the saved one when it
  /// differs.
  final String? shownName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedPointProvider(id)).value;
    if (saved == null) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(AppIcons.favoriteSelected, size: 18, color: scheme.primary),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      saved.name == shownName
                          ? t.favorites.inFavorites
                          : t.favorites.inFavoritesAs(name: saved.name),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              if (saved.note case final note?) ...[
                const SizedBox(height: Space.xs),
                Text(note, style: theme.textTheme.bodyMedium),
              ],
              Wrap(
                spacing: Space.xs,
                children: [
                  TextButton.icon(
                    onPressed: () => showSavePointToLists(context, saved, renaming: true),
                    icon: const Icon(AppIcons.rename, size: 20),
                    label: Text(t.favorites.rename),
                  ),
                  TextButton.icon(
                    onPressed: () => removePointEverywhere(context, ref, id),
                    icon: const Icon(AppIcons.delete, size: 20),
                    label: Text(t.favorites.removeEverywhere),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
