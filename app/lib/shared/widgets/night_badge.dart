import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The overnight status as a moon phase on its disc: the same mark in the
/// sheet, the list, the filters and on the map pins.
class NightBadge extends StatelessWidget {
  const new(this.status, {this.size = 22, this.semantic = false, super.key});

  final OvernightStatus status;
  final double size;

  /// Read the status aloud (when no label stands next to the badge).
  final bool semantic;

  @override
  Widget build(BuildContext context) {
    final tone = LunaTokens.of(context).nightTone(status);
    final unknown = status == OvernightStatus.unknown;
    final glyph = LunaIcon(
      LunaIcons.night(status),
      size: unknown ? size : size * 0.72,
      color: tone.glyph,
      semanticLabel: semantic ? context.t.overnightShort(status) : null,
    );
    if (unknown) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: glyph),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.disc,
        shape: BoxShape.circle,
        border: tone.ring == null ? null : Border.all(color: tone.ring!),
      ),
      alignment: Alignment.center,
      child: glyph,
    );
  }
}

/// The badge and the status in words, as list rows and cards show it.
class NightLabel extends StatelessWidget {
  const new(this.status, {this.style, this.badgeSize = 20, super.key});

  final OvernightStatus status;
  final TextStyle? style;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    final tone = LunaTokens.of(context).nightTone(status);
    final text = style ?? Theme.of(context).textTheme.labelLarge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NightBadge(status, size: badgeSize),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            context.t.overnightShort(status),
            style: text?.copyWith(color: tone.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
