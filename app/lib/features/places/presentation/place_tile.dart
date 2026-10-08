import 'package:flutter/material.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';
import 'package:lunaway/shared/widgets/place_hero.dart';

/// A place in a list: its mark, its name, the night status as a moon, the
/// kind and town, the rating, the opening of its description, and the
/// distance when the position is known. The rating is Lunaway users' when
/// they rated the place, else the external source's, said so in the count.
/// Opening it lets the mark fly to the details' header.
class PlaceTile extends StatefulWidget {
  const new({
    required this.place,
    required this.onTap,
    this.distanceM,
    this.selected = false,
    this.trailing,
    this.digest,
    super.key,
  });

  final PlaceSummary place;
  final VoidCallback onTap;
  final double? distanceM;
  final bool selected;

  /// Replaces the distance (a menu in the favourites).
  final Widget? trailing;

  /// What the API adds to the summary: the ratings by source and the
  /// opening of the description; null while it has not answered.
  final PlaceDigest? digest;

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
    final PlaceTile(:place, :onTap, :distanceM, :selected, :trailing, :digest) = widget;
    final rating = rowRating(place, digest);
    // In the reader's language only: a text in another one is noise in a
    // row, and the card shows it with its language named.
    final excerpt = switch (digest?.excerpt) {
      final e? when e.lang == t.$meta.locale.languageCode || e.lang == 'und' => e,
      _ => null,
    };
    final avatarKey = _avatarKey;
    final tile = Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
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
                    if (rating != null) ...[
                      const SizedBox(height: Space.xxs),
                      RatingText(
                        average: rating.average,
                        count: rating.count,
                        externalSource: isLunawayCommunity(rating.sourceId)
                            ? null
                            : sourceName(t, rating.sourceId),
                      ),
                    ],
                    if (excerpt != null) ...[
                      const SizedBox(height: Space.xxs),
                      // Its source first, short, so a cut text never
                      // loses it: the card names it in full, and so does a
                      // screen reader.
                      Semantics(
                        label: t.place.excerptFrom(
                          source: sourceName(t, excerpt.sourceId),
                          text: excerpt.text,
                        ),
                        excludeSemantics: true,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${excerptSource(t, excerpt.sourceId)} · ',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: excerpt.text),
                            ],
                          ),
                          // One line on a phone, where the rows must stay
                          // short; two beside the map on a wider screen.
                          maxLines: WindowSize.of(context) == WindowSize.compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
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
