import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// The Lunaway mark at [height]. The navy pin needs a lighter ground to show
/// its outline (brand/README.md): on a dark theme it stands on a cream disc
/// 1.2 times its height, as on the night splash screens.
class BrandMark extends StatelessWidget {
  const new({this.height = 28, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/brand/lunaway-mark.png',
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    if (Theme.of(context).brightness == Brightness.light) return mark;
    return Container(
      width: height * 1.2,
      height: height * 1.2,
      decoration: const BoxDecoration(color: Palette.creme, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/brand/lunaway-mark.png',
        height: height * 0.86,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// The lockup: the mark and "Lunaway" set in Fraunces, as in
/// brand/lunaway-lockup.svg, for the rail of the wide layouts.
class BrandLockup extends StatelessWidget {
  const new({this.height = 32, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.t.appTitle,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(height: height),
        SizedBox(width: height * 0.3),
        // The name never wraps: in a narrow rail or at a large text size it
        // shrinks to the space left.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              context.t.appTitle,
              maxLines: 1,
              style: LunaType.serif(
                height * 0.8,
                560,
                height: 1,
              ).copyWith(color: Theme.of(context).colorScheme.onSurface, letterSpacing: -0.4),
            ),
          ),
        ),
      ],
    ),
  );
}
