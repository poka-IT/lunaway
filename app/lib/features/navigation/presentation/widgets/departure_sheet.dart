import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/address_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

/// Where the preview's routes start: the device's position, or a town, a
/// place or an address the search finds, as the map's search finds them.
Future<void> showDepartureSheet(BuildContext context) => showSheet<void>(
  context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => const DepartureSearch(),
);

/// The search of [showDepartureSheet].
class DepartureSearch extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DepartureSearch> createState() => _DepartureSearchState();
}

class _DepartureSearchState extends ConsumerState<DepartureSearch> {
  final _text = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _choose(RouteDeparture? departure) {
    final chosen = ref.read(chosenDepartureProvider.notifier);
    if (departure == null) {
      chosen.clear();
    } else {
      chosen.choose(departure);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(userLocationProvider);
    final near = user ?? ref.read(viewportProvider)?.center;
    final language = t.$meta.locale.languageCode;
    final query = _query.trim();
    final results = query.isEmpty
        ? null
        : ref.watch(searchResultsProvider(query, near: near, language: language));
    // As the map's search: no address is asked offline nor under three
    // characters.
    final addresses = query.length < 3 || !ref.watch(placesFromTilesProvider)
        ? null
        : ref.watch(addressSearchProvider(query, near: near, language: language));
    final found = results?.value;
    final towns = found?.municipalities ?? const [];
    final places = found?.places ?? const [];
    final streets = addresses?.value ?? const <AddressMatch>[];
    final waiting = (results?.isLoading ?? false) || (addresses?.isLoading ?? false);
    Widget icon(IconData data) => CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Icon(data),
    );
    return Padding(
      // Above the keyboard, which the field opens.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Semantics(
              header: true,
              child: Text(t.navigation.preview.departure.title, style: theme.textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.navigation.preview.departure.searchHint,
                prefixIcon: const Icon(AppIcons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (waiting) const LinearProgressIndicator() else const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.m),
              children: [
                ListTile(
                  leading: icon(AppIcons.locate),
                  title: Text(t.navigation.preview.departure.myPositionChoice),
                  onTap: () => _choose(null),
                ),
                for (final town in towns)
                  ListTile(
                    leading: icon(AppIcons.town),
                    title: Text(town.name),
                    subtitle: town.postcode == null ? null : Text(town.postcode!),
                    onTap: () => _choose(RouteDeparture(position: town.center, label: town.name)),
                  ),
                for (final place in places)
                  ListTile(
                    leading: icon(AppIcons.point),
                    title: Text(t.summaryTitle(place)),
                    subtitle: Text([t.kind(place.kind), ?place.city].join(' · ')),
                    onTap: () => _choose(
                      RouteDeparture(
                        position: LatLng(place.lat, place.lon),
                        label: t.summaryTitle(place),
                      ),
                    ),
                  ),
                for (final address in streets)
                  ListTile(
                    leading: icon(addressIcon(address.kind)),
                    title: Text(address.name),
                    subtitle: Text(
                      [
                        ?address.postcode,
                        ?address.city,
                      ].join(' ').ifEmpty(addressKindLabel(t, address.kind)),
                    ),
                    onTap: () => _choose(
                      RouteDeparture(
                        position: address.position,
                        label: [address.name, ?address.city].join(', '),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
