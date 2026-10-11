import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/home_views.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

/// "Partir d'ici": a trip prepared from [position], the routes previewed
/// next start from this point rather than from the device's position,
/// named [label] when it has a name.
void startFrom(BuildContext context, WidgetRef ref, LatLng position, {String? label}) {
  ref
      .read(chosenDepartureProvider.notifier)
      .choose(RouteDeparture(position: position, label: label));
  showMessage(ScaffoldMessenger.maybeOf(context), context.t.map.departureChosen);
}

/// "Partir d'ici" as an entry of a card's menu of other actions, holding
/// [value]. A restaurant, a place or an address is seldom where a trip
/// starts: the entry stays out of the row of actions and out of the card's
/// body (the PO's rule of 2026-10-10), and the preview keeps its own choice
/// of the start ("Partir de…").
PopupMenuItem<T> startHereEntry<T>(BuildContext context, T value) => PopupMenuItem<T>(
  value: value,
  child: ListTile(leading: const Icon(AppIcons.departure), title: Text(context.t.map.startHere)),
);

/// The menu of other actions of a card that has no other: "…" in its
/// header, beside the close, as a place's card has it (`PlaceMoreMenu`):
/// "Partir d'ici", and "Définir comme domicile" when the card says what
/// the point would be as a home ([home]).
class StartHereMenu extends ConsumerWidget {
  const new({required this.position, this.label, this.home, super.key});

  final LatLng position;

  /// The start's name in the preview; none for a point of the map.
  final String? label;

  /// The point as the home would keep it; none where no home is offered.
  final SavedPoint Function()? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final home = this.home;
    final isHome = home != null && isHomeId(ref, home().id);
    return PopupMenuButton<String>(
      tooltip: context.t.contribute.more,
      icon: const Icon(AppIcons.moreVertical),
      style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
      onSelected: (action) async {
        switch (action) {
          case 'start':
            startFrom(context, ref, position, label: label);
          case 'home' when home != null:
            await toggleHome(context, ref, home());
        }
      },
      itemBuilder: (context) => [
        startHereEntry(context, 'start'),
        if (home != null) homeEntry(context, 'home', isHome: isHome),
      ],
    );
  }
}
