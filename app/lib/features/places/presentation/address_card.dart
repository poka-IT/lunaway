import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunaway/core/platform/system_copy_preview.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The postal address of [place] with a one-tap copy, as one line a
/// navigation or a delivery app accepts when pasted ("12 Rue de la Gare,
/// 07220 Viviers"), and the source it came from: a source of the place,
/// or OpenStreetMap through Lunaway's own reverse geocoding when no
/// source gave a street. Nothing when the place has no street, town nor
/// postcode; a private host has its town only (the server never gives its
/// street).
class AddressCard extends StatelessWidget {
  const new({required this.place, super.key});

  final Place place;

  /// The two lines of [address]: the street, then the postcode and town.
  static List<String> linesOf(Address address) => [
    if (address.street case final street? when street.trim().isNotEmpty) street.trim(),
    if ([address.postcode, address.city].nonNulls.where((s) => s.trim().isNotEmpty).join(' ')
        case final town when town.isNotEmpty)
      town,
  ];

  /// What [place] shows of its address: a private host never its street,
  /// whatever a copy kept on the device holds.
  static Address shownOf(Place place) => switch ((place.kind, place.address)) {
    (_, null) => const Address(),
    (PlaceKind.homestay, final a?) => Address(
      postcode: a.postcode,
      city: a.city,
      countryCode: a.countryCode,
    ),
    (_, final a?) => a,
  };

  /// Whether [place] has an address to show.
  static bool shows(Place place) => linesOf(shownOf(place)).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final lines = linesOf(shownOf(place));
    if (lines.isEmpty) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final copied = lines.join(', ');
    final source = place.provenance.where((p) => p.field == 'address').firstOrNull;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      ),
      child: Row(
        children: [
          Icon(AppIcons.street, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.place.address,
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.hair),
                SelectableText(
                  lines.join('\n'),
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
                ),
                if (source != null)
                  Text(
                    t.place.addressSource(source: _sourceLabel(t, source.sourceId)),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: t.place.copyAddress,
            icon: const Icon(AppIcons.copy),
            onPressed: () => _copy(context, copied),
          ),
        ],
      ),
    );
  }

  /// OpenStreetMap by the credit its licence asks for (the reverse
  /// geocoding gives an address no source of the place listed), any
  /// other source by its name.
  String _sourceLabel(Translations t, String sourceId) => sourceId == 'osm'
      ? t.navigation.preview.attributionOsm
      : sourceName(t, sourceId, sources: place.sources);

  Future<void> _copy(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copied = context.t.place.copied(text: text);
    await Clipboard.setData(ClipboardData(text: text));
    Haptics.confirm();
    if (!await systemShowsCopies()) showMessage(messenger, copied);
  }
}
