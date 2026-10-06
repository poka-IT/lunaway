import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/luna_colors.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';

/// A place in a list: its mark, its name, the overnight status in its colour,
/// the kind and town, and the distance when the position is known.
class PlaceTile extends StatelessWidget {
  const new({
    required this.place,
    required this.onTap,
    this.distanceM,
    this.selected = false,
    super.key,
  });

  final PlaceSummary place;
  final VoidCallback onTap;
  final double? distanceM;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final colors = LunaColors.of(context);
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
      selectedColor: theme.colorScheme.onSecondaryContainer,
      leading: PlaceAvatar(kind: place.kind, overnight: place.overnight, size: 40),
      title: Text(t.summaryTitle(place), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: t.overnightLabel(place.overnight),
                  style: TextStyle(
                    color: colors.overnight(place.overnight),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' · ${[t.kind(place.kind), ?place.city].join(' · ')}'),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (place.ratingAverage case final average?) ...[
            const SizedBox(height: Space.xxs),
            RatingText(average: average, count: place.ratingCount),
          ],
        ],
      ),
      isThreeLine: place.ratingAverage != null,
      trailing: distanceM == null
          ? null
          : Text(
              t.distance(distanceM!),
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
      onTap: onTap,
    );
  }
}
