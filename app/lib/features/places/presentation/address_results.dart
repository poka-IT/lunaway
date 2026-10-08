import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/address_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The title of a section of search results.
class SearchHeader extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.xxs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// The addresses the server's geocoders found, under the places: the
/// previous list stays while the next one loads; the first one says it is
/// on its way, a failure says so, and the geocoders are credited under the
/// list. The towns listed above are left out. The map's search and the
/// choice of a route's start show them alike.
class AddressResults extends StatefulWidget {
  const new({
    required this.addresses,
    required this.towns,
    required this.onTap,
    this.from,
    super.key,
  });

  final AsyncValue<List<AddressMatch>> addresses;

  /// The towns listed above, left out of the addresses.
  final List<Municipality> towns;

  /// The user's position, for the distances.
  final LatLng? from;
  final ValueChanged<AddressMatch> onTap;

  @override
  State<AddressResults> createState() => _AddressResultsState();
}

class _AddressResultsState extends State<AddressResults> {
  List<AddressMatch> _shown = const [];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
    switch (widget.addresses) {
      case AsyncValue(value: final list?):
        _shown = list;
      case AsyncError():
        _shown = const [];
        return note(t.search.addressesFailed);
      case _ when _shown.isEmpty:
        return note(t.search.addressesSearching);
      case _:
        break;
    }
    final list = withoutShownTowns(_shown, widget.towns);
    if (list.isEmpty) return const SizedBox.shrink();
    final from = widget.from;
    final sources = {for (final a in list) a.attribution}.join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchHeader(t.search.addresses),
        for (final address in list)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.tertiaryContainer,
              foregroundColor: scheme.onTertiaryContainer,
              child: Icon(addressIcon(address.kind)),
            ),
            title: Text(address.name, maxLines: 2),
            subtitle: Text(
              [
                if (address.detail.isEmpty) addressKindLabel(t, address.kind) else address.detail,
                if (from != null) t.distance(address.position.distanceTo(from)),
              ].join(' · '),
              maxLines: 2,
            ),
            onTap: () => widget.onTap(address),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxs, Space.xl, Space.s),
          child: Text(
            t.search.addressSources(sources: sources),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
