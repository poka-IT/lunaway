import 'package:flutter/widgets.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';

/// "On the way": a route with a magnifying glass on its free corner, the
/// button of the sheet that looks along the route for fuel, a night, water
/// or a shop. The route's glyph leaves its lower right corner empty, where
/// the glass sits without a halo, in the colour of the button.
class OnTheWayIcon extends StatelessWidget {
  const new({this.size, super.key});

  /// The side of the square; the theme's icon size by default.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: side,
      child: Stack(
        children: [
          Icon(PhosphorRegular.path, size: side * 0.86),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(PhosphorFill.magnifyingGlass, size: side * 0.52),
          ),
        ],
      ),
    );
  }
}
