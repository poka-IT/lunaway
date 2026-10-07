import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/platform/system_copy_preview.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// Copies [position] and says what went to the clipboard (unless the system
/// shows it already), with a light touch the hand feels without looking.
/// Without a [format] it copies the one the user last picked from the
/// coordinates' menu; a [format] picked there becomes that choice.
Future<void> copyCoordinates(
  BuildContext context,
  WidgetRef ref,
  LatLng position, {
  CoordinateFormat? format,
}) async {
  final settings = ref.read(settingsProvider.notifier);
  if (format != null) unawaited(settings.setCopyFormat(format));
  final text = (format ?? ref.read(settingsProvider).copyFormat).format(position);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = context.t.place.copied(text: text);
  await Clipboard.setData(ClipboardData(text: text));
  Haptics.confirm();
  if (!await systemShowsCopies()) showMessage(messenger, copied);
}

/// The coordinates of a position with a one-tap copy, in the format map apps
/// accept when pasted, and the other formats one menu away. A format picked
/// in the menu stays the one the copy button copies, said under the
/// coordinates. The snackbar shows exactly what went to the clipboard.
class CoordinatesCard extends ConsumerWidget {
  const new({required this.position, super.key});

  final LatLng position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen = ref.watch(settingsProvider.select((s) => s.copyFormat));
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
                if (chosen != .decimal)
                  Text(
                    t.place.copiesAs(format: label(t, chosen)),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: chosen == .decimal ? t.place.copy : t.place.copyAs(format: label(t, chosen)),
            icon: const Icon(AppIcons.copy),
            onPressed: () => copyCoordinates(context, ref, position),
          ),
          PopupMenuButton<CoordinateFormat>(
            tooltip: t.place.otherFormats,
            icon: const Icon(AppIcons.moreVertical),
            onSelected: (format) => copyCoordinates(context, ref, position, format: format),
            itemBuilder: (context) => [
              for (final f in CoordinateFormat.values)
                PopupMenuItem(
                  value: f,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label(t, f)),
                    subtitle: Text(
                      f.format(position),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // The format the copy button copies.
                    trailing: f == chosen ? const Icon(AppIcons.check) : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The name of a format, as the menu lists it.
  static String label(Translations t, CoordinateFormat f) => switch (f) {
    .decimal => t.place.formatDecimal,
    .dms => t.place.formatDms,
    .geoUri => t.place.formatGeo,
    .googleMaps => t.place.formatGoogle,
    .openStreetMap => t.place.formatOsm,
  };
}
