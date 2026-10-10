import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// "4,3 (128)" after an amber star: the rating and how many reviews it
/// rests on, the figures in Fraunces. A rating of another community than
/// Lunaway's ([externalSource], its name) says so in the count: "3,3 (246
/// avis externes)"; Lunaway users' says so too when [namedLunaway], beside
/// another source's: "4,0 (1 avis Lunaway)".
class RatingText extends StatelessWidget {
  const new({
    required this.average,
    required this.count,
    this.size = 15,
    this.externalSource,
    this.namedLunaway = false,
    super.key,
  });

  final double average;
  final int count;
  final double size;

  /// The name of the other community the rating comes from; null for
  /// Lunaway's.
  final String? externalSource;

  /// Whether Lunaway users' rating names Lunaway in its count, so that it
  /// reads apart from another source's shown beside it.
  final bool namedLunaway;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final muted = LunaType.number(size, weight: 400, color: scheme.onSurfaceVariant);
    final label = switch (externalSource) {
      _? => t.place.externalRatingsLabel(n: count),
      null when namedLunaway => t.place.lunawayRatingsLabel(n: count),
      null => null,
    };
    return Semantics(
      label: [
        t.place.stars(rating: t.ratingValue(average)),
        t.place.reviewsCount(n: count),
        externalSource ?? (namedLunaway ? t.appTitle : null),
      ].nonNulls.join(', '),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.star, size: size + 2, color: scheme.primary),
          const SizedBox(width: 3),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.ratingValue(average),
                    style: LunaType.number(size, weight: 540, color: scheme.onSurface),
                  ),
                  if (label != null) ...[
                    TextSpan(text: ' (', style: muted),
                    TextSpan(text: '$count', style: muted),
                    TextSpan(
                      text: ' $label)',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ] else
                    TextSpan(text: ' ($count)', style: muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ratings a place shows ([shownRatings]) side by side: Lunaway users'
/// first, named when another source's stands beside it, which says it is
/// external. Nothing when [ratings] is empty.
class RatingsLine extends StatelessWidget {
  const new({required this.ratings, this.size = 15, this.anotherToCome = false, super.key});

  final List<RowRating> ratings;
  final double size;

  /// Whether another source's rating is being read to stand beside
  /// Lunaway users': theirs is named already, so its words stay the same
  /// when that one shows.
  final bool anotherToCome;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final both = ratings.length > 1 || anotherToCome;
    return Wrap(
      spacing: Space.m,
      runSpacing: Space.hair,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in ratings)
          RatingText(
            average: r.average,
            count: r.count,
            size: size,
            externalSource: isLunawayCommunity(r.sourceId) ? null : sourceName(t, r.sourceId),
            namedLunaway: both && isLunawayCommunity(r.sourceId),
          ),
      ],
    );
  }
}
