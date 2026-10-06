import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// One option of a [LunaSegmented].
@immutable
final class Segment<T> {
  const new({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A choice among a few options, as a pill with a sliding amber thumb. Each
/// option grows with its text, and the row wraps into a column when the text
/// is too large for one line, so no label is ever cut.
class LunaSegmented<T> extends StatelessWidget {
  const new({required this.segments, required this.selected, required this.onChanged, super.key});

  final List<Segment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelLarge;
    Widget option(Segment<T> s, {required bool expand}) {
      final on = s.value == selected;
      final child = Semantics(
        selected: on,
        button: true,
        inMutuallyExclusiveGroup: true,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.standard,
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: on ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
              onTap: on
                  ? null
                  : () {
                      Haptics.select();
                      onChanged(s.value);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.ml, vertical: Space.s),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (s.icon != null) ...[
                      Icon(
                        s.icon,
                        size: 20,
                        color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.xs),
                    ],
                    Flexible(
                      child: Text(
                        s.label,
                        textAlign: TextAlign.center,
                        style: text?.copyWith(color: on ? scheme.onPrimary : scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // One line when every label fits its share of the width; a column
        // otherwise (large text, long translations).
        final scaler = MediaQuery.textScalerOf(context);
        double needed(Segment<T> s) {
          final painter = TextPainter(
            text: TextSpan(text: s.label, style: text),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width + (s.icon == null ? 0 : 26) + Space.ml * 2;
        }

        final widest = segments.map(needed).reduce((a, b) => a > b ? a : b);
        final row = widest * segments.length <= constraints.maxWidth - 8;
        return Container(
          padding: const EdgeInsets.all(Space.xxs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(row ? LunaTokens.radiusPill : LunaTokens.radiusXl),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: row
              ? Row(children: [for (final s in segments) option(s, expand: true)])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final s in segments) option(s, expand: false)],
                ),
        );
      },
    );
  }
}
