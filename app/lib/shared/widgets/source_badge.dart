import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The name of the source a value came from, as a small tag: on reviews,
/// ratings, descriptions, photos and in the sources section.
class SourceBadge extends StatelessWidget {
  const new({required this.label, this.onPhoto = false, this.maxLines = 1, super.key});

  final String label;

  /// Lines the name may take before it is cut: more than one where the
  /// whole name must stay readable at a large text size.
  final int maxLines;

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
        // A pill on one line; a name that wraps gets rounded corners, not
        // the oval a pill radius would make of it (14 is past half the
        // height of one line, so a single line still reads as a pill).
        borderRadius: BorderRadius.circular(
          maxLines == 1 ? LunaTokens.radiusPill : LunaTokens.radiusM,
        ),
      ),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
