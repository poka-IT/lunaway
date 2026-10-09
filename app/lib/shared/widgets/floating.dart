import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// A surface floating over the map: the search pill, the map buttons, the
/// chips. A soft navy shadow separates it from a basemap of any colour,
/// where a tonal surface alone would not.
class FloatingSurface extends StatelessWidget {
  const new({
    required this.child,
    this.radius = LunaTokens.radiusPill,
    this.color,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final double radius;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = LunaTokens.of(context);
    return OverMap(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? tokens.floatingSurface,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: tokens.floatingShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A round button floating over the map: locate, zoom, the list.
class MapButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 52,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Drawn in the accent, for a mode that is on (following the position).
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FloatingSurface(
      color: active ? scheme.primary : null,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 24,
        style: IconButton.styleFrom(
          minimumSize: Size.square(size),
          foregroundColor: active ? scheme.onPrimary : scheme.onSurface,
        ).copyWith(side: focusRingIn(active ? scheme.onPrimary : scheme.onSurface)),
        icon: Icon(icon),
      ),
    );
  }
}
