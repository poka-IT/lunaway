import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// Copies [format] of [position] and says what went to the clipboard, with a
/// light touch the hand feels without looking.
Future<void> copyCoordinates(
  BuildContext context,
  LatLng position, {
  CoordinateFormat format = CoordinateFormat.decimal,
}) async {
  final text = format.format(position);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = context.t.place.copied(text: text);
  await Clipboard.setData(ClipboardData(text: text));
  Haptics.confirm();
  showMessage(messenger, copied);
}

/// The coordinates of a position with a one-tap copy, in the format map apps
/// accept when pasted, and the other formats one menu away. The snackbar
/// shows exactly what went to the clipboard.
class CoordinatesCard extends StatelessWidget {
  const new({required this.position, super.key});

  final LatLng position;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      ),
      child: Row(
        children: [
          Icon(AppIcons.coordinates, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.place.coordinates,
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.hair),
                SelectableText(
                  CoordinateFormat.decimal.format(position),
                  style: LunaType.number(17, weight: 440, color: scheme.onSurface),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t.place.copy,
            icon: const Icon(AppIcons.copy),
            onPressed: () => copyCoordinates(context, position),
          ),
          PopupMenuButton<CoordinateFormat>(
            tooltip: t.place.otherFormats,
            icon: const Icon(AppIcons.moreVertical),
            onSelected: (format) => copyCoordinates(context, position, format: format),
            itemBuilder: (context) => [
              for (final f in CoordinateFormat.values)
                PopupMenuItem(
                  value: f,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_label(t, f)),
                    subtitle: Text(
                      f.format(position),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _label(Translations t, CoordinateFormat f) => switch (f) {
    .decimal => t.place.formatDecimal,
    .dms => t.place.formatDms,
    .geoUri => t.place.formatGeo,
    .googleMaps => t.place.formatGoogle,
    .openStreetMap => t.place.formatOsm,
  };
}
