import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';

/// The mark of a place in lists and headers, like its map pin: the family
/// colour, the kind's glyph, and the night status as a moon at the corner.
class PlaceAvatar extends StatelessWidget {
  const new({required this.kind, this.overnight, this.size = 44, super.key});

  final PlaceKind kind;
  final OvernightStatus? overnight;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.48;
    final ring = Theme.of(context).colorScheme.surface;
    return SizedBox.square(
      dimension: size + badge * 0.22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: LunaTokens.familyFill(kind.family),
                // A rounded square, not a disc: the lists read as a column
                // of tiles, the pins on the map as drops.
                borderRadius: BorderRadius.circular(size * 0.32),
              ),
              alignment: Alignment.center,
              child: Icon(AppIcons.kind(kind), size: size * 0.52, color: LunaTokens.pinGlyph),
            ),
          ),
          if (overnight case final status?)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                child: NightBadge(status, size: badge),
              ),
            ),
        ],
      ),
    );
  }
}
