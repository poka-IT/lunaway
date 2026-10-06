import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';
import 'package:lunaway/shared/widgets/place_hero.dart';

/// A place in a list: its mark, its name, the night status as a moon, the
/// kind and town, the rating, and the distance when the position is known.
/// Opening it lets the mark fly to the details' header.
class PlaceTile extends StatefulWidget {
  const new({
    required this.place,
    required this.onTap,
    this.distanceM,
    this.selected = false,
    this.trailing,
    super.key,
  });

  final PlaceSummary place;
  final VoidCallback onTap;
  final double? distanceM;
  final bool selected;

  /// Replaces the distance (a menu in the favourites).
  final Widget? trailing;

  @override
  State<PlaceTile> createState() => _PlaceTileState();
}

class _PlaceTileState extends State<PlaceTile> {
  final GlobalKey<State<StatefulWidget>> _avatarKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final PlaceTile(:place, :onTap, :distanceM, :selected, :trailing) = widget;
    final avatarKey = _avatarKey;
    final tile = Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () {
          final ctx = avatarKey.currentContext;
          final rect = ctx == null ? null : PlaceHeroSource.rectOf(ctx);
          if (rect != null) {
            PlaceHero.launch(
              placeId: place.id,
              from: rect,
              kind: place.kind,
              overnight: place.overnight,
            );
          }
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.l, Space.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlaceHeroSource(
                key: avatarKey,
                child: PlaceAvatar(kind: place.kind, overnight: place.overnight),
              ),
              const SizedBox(width: Space.ml),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.summaryTitle(place),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.xxs),
                    // The night first, in its tone, then what and where: one
                    // line, so a row stays short enough to read at a glance.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: NightBadge(place.overnight, size: 18),
                        ),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: t.overnightShort(place.overnight),
                                  style: TextStyle(
                                    color: LunaTokens.of(context).nightTone(place.overnight).label,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: ' · ${[t.kind(place.kind), ?place.city].join(' · ')}',
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (place.ratingAverage case final average?) ...[
                      const SizedBox(height: Space.xxs),
                      RatingText(average: average, count: place.ratingCount),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              trailing ??
                  (distanceM == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: Space.xxs),
                          child: Text(
                            t.distance(distanceM),
                            style: LunaType.number(16, color: scheme.onSurface),
                          ),
                        )),
            ],
          ),
        ),
      ),
    );
    // The place open beside the list says so to a screen reader too.
    return Semantics(selected: selected, child: tile);
  }
}
