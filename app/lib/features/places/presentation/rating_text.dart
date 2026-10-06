import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// "4,3 (128)" after an amber star: the rating and how many reviews it
/// rests on, the figures in Fraunces.
class RatingText extends StatelessWidget {
  const new({required this.average, required this.count, this.size = 15, super.key});

  final double average;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${t.place.stars(rating: t.ratingValue(average))}, ${t.place.reviewsCount(n: count)}',
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
                  TextSpan(
                    text: ' ($count)',
                    style: LunaType.number(size, weight: 400, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
