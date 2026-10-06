import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The name of the source a value came from, as a small tag: on reviews,
/// ratings, descriptions, photos and in the sources section.
class SourceBadge extends StatelessWidget {
  const new({required this.label, this.onPhoto = false, super.key});

  final String label;

  /// Over a photo: a translucent dark tag that stays readable on any image.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final background = onPhoto
        ? tokens.photoBackdrop.withValues(alpha: 0.72)
        : scheme.secondaryContainer;
    final foreground = onPhoto ? tokens.onPhotoBackdrop : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
