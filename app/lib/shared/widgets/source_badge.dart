import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The name of the source a value came from, as a small tag: on reviews,
/// ratings, descriptions, photos and in the sources section.
class SourceBadge extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusS),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w700),
      ),
    );
  }
}
