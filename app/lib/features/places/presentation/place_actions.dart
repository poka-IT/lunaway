import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/presentation/save_to_lists.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

final _log = Logger('favorites');

/// Saves [place] in the default list, or takes it out of the default list
/// only (the other lists keep it), with an undo either way.
Future<void> toggleDefaultFavorite(BuildContext context, WidgetRef ref, PlaceSummary place) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The message outlives the place's panel: its action opens the lists from
  // the app's root, which is still there once the panel has closed.
  final root = Navigator.of(context, rootNavigator: true);
  final repo = ref.read(favoritesRepositoryProvider);
  try {
    final defaultId = await repo.defaultListId();
    final lists = await ref.read(placeListsProvider(place.id).future);
    Haptics.confirm();
    if (lists.contains(defaultId)) {
      final removed = await repo.remove(defaultId, place.id);
      showMessage(
        messenger,
        t.place.removedToast,
        action: removed == null
            ? null
            : SnackBarAction(label: t.common.undo, onPressed: () => repo.restore(removed)),
      );
    } else {
      await repo.add(defaultId, place);
      showMessage(
        messenger,
        t.place.savedToast,
        action: SnackBarAction(
          label: t.place.chooseLists,
          onPressed: () {
            if (root.mounted) unawaited(showSaveToLists(root.context, place));
          },
        ),
      );
    }
  } on Object catch (error, stack) {
    _log.warning('saving a favourite failed', error, stack);
    showMessage(messenger, t.common.saveFailed);
  }
}

/// The actions of a place, always in reach: below the details on a phone
/// (where the dock was), at the foot of the panel on wider screens.
/// "Itinéraire" leads; saving, sharing and copying the coordinates follow.
/// With large text the row splits in two, so no label is ever cut.
class PlaceActionBar extends ConsumerWidget {
  const new({required this.place, this.floating = false, super.key});

  final Place place;

  /// Over the map (phone): a floating card with a shadow.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final title = t.placeTitle(name: place.name, kind: place.kind, city: place.address?.city);
    final defaultId = ref.watch(defaultFavoriteListProvider).value;
    final lists = ref.watch(placeListsProvider(place.id)).value ?? const <int>{};
    final saved = defaultId != null && lists.contains(defaultId);

    final directions = FilledButton.icon(
      onPressed: () => openDirections(context, ref, place.position, label: title),
      onLongPress: () => openDirections(context, ref, place.position, label: title, choose: true),
      icon: const Icon(AppIcons.directions),
      label: Text(t.place.directions, maxLines: 2, textAlign: TextAlign.center),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
      ),
    );
    final others = [
      _ActionTile(
        icon: saved ? AppIcons.favoriteSelected : AppIcons.favorite,
        iconColor: saved ? scheme.primary : null,
        label: saved ? t.place.saved : t.place.save,
        hint: t.place.saveHint,
        onPressed: () => toggleDefaultFavorite(context, ref, place.summary),
        onLongPress: () => showSaveToLists(context, place.summary),
        longPressLabel: t.place.chooseLists,
      ),
      Builder(
        builder: (tileContext) => _ActionTile(
          icon: AppIcons.share,
          label: t.place.share,
          onPressed: () {
            final box = tileContext.findRenderObject() as RenderBox?;
            final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
            unawaited(
              ref
                  .read(externalActionsProvider)
                  .share(
                    [
                      title,
                      CoordinateFormat.decimal.format(place.position),
                      CoordinateFormat.openStreetMap.format(place.position),
                    ].join('\n'),
                    subject: title,
                    origin: origin,
                  ),
            );
          },
        ),
      ),
      _ActionTile(
        icon: AppIcons.copy,
        label: t.place.copyShort,
        onPressed: () => copyCoordinates(context, place.position),
      ),
    ];

    // The row needs room for "Itinéraire" beside three labelled tiles; on a
    // narrow phone or with large text it splits in two, so no label is cut.
    final bar = LayoutBuilder(
      builder: (context, constraints) {
        const tile = 68.0;
        final inner = constraints.maxWidth - Space.m * 2;
        final wide = MediaQuery.textScalerOf(context).scale(16) <= 20;
        final stacked = !wide || inner < tile * 3 + Space.xs * 3 + 148;
        return Padding(
          padding: const EdgeInsets.all(Space.m),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    directions,
                    const SizedBox(height: Space.xs),
                    Row(children: [for (final o in others) Expanded(child: o)]),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: directions),
                    for (final o in others) ...[
                      const SizedBox(width: Space.xs),
                      SizedBox(width: tile, child: o),
                    ],
                  ],
                ),
        );
      },
    );
    if (!floating) {
      return LiftsMessages(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(top: false, child: bar),
        ),
      );
    }
    return LiftsMessages(
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: Space.s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
              boxShadow: tokens.floatingShadow,
            ),
            child: Material(type: MaterialType.transparency, child: bar),
          ),
        ),
      ),
    );
  }
}

/// A secondary action: its icon over a one-line label.
class _ActionTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
    this.hint,
    this.onLongPress,
    this.longPressLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? iconColor;
  final String? hint;
  final VoidCallback? onLongPress;
  final String? longPressLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      customSemanticsActions: onLongPress == null || longPressLabel == null
          ? null
          : {CustomSemanticsAction(label: longPressLabel!): onLongPress!},
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxs, vertical: Space.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor ?? theme.colorScheme.onSurface),
                const SizedBox(height: Space.hair),
                // One word or two: shrunk to fit rather than wrapped, so a
                // long word at a large text size is never cut in the middle.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: theme.textTheme.labelMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
