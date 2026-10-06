import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/theme/luna_colors.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The round mark of a place in lists and headers: the family colour and
/// glyph, with the overnight status as a small badge, like the map pin.
class PlaceAvatar extends StatelessWidget {
  const new({required this.kind, this.overnight, this.size = 44, super.key});

  final PlaceKind kind;
  final OvernightStatus? overnight;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final family = kind.family;
    final color = LunaColors.pinFamily(family);
    final badgeColor = overnight == null ? null : LunaColors.pinOvernight(overnight!);
    final badge = size * 0.42;
    return SizedBox.square(
      dimension: size + badge * 0.25,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: LunaIcon(
                LunaIcons.family(family),
                size: size * 0.56,
                color: LunaTokens.of(context).onAccent,
              ),
            ),
          ),
          if (badgeColor != null)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: LunaIcon(
                  LunaIcons.overnight(overnight!),
                  size: badge * 0.66,
                  color: LunaTokens.of(context).onAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
