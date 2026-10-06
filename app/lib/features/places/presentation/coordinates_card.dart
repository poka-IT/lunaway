import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The coordinates of a position with a one-tap copy, in the format map apps
/// accept when pasted, and the other formats one menu away. The snackbar
/// shows exactly what went to the clipboard.
class CoordinatesCard extends StatelessWidget {
  const new({required this.position, super.key});

  final LatLng position;

  Future<void> _copy(BuildContext context, CoordinateFormat format) async {
    final text = format.format(position);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copied = context.t.place.copied(text: text);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.s, Space.s),
        child: Row(
          children: [
            Icon(AppIcons.locate, color: scheme.primary),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.place.coordinates,
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Space.hair),
                  SelectableText(
                    CoordinateFormat.decimal.format(position),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: t.place.copy,
              icon: const Icon(AppIcons.copy),
              onPressed: () => _copy(context, CoordinateFormat.decimal),
            ),
            PopupMenuButton<CoordinateFormat>(
              tooltip: t.place.otherFormats,
              icon: const Icon(AppIcons.more),
              onSelected: (format) => _copy(context, format),
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
