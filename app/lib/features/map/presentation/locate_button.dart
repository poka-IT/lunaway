import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';

/// The map's button for the device's position. In the country's view, while
/// the app does not know where the user is (a first launch, a browser that
/// was never asked), it says what it does in words: the question at launch
/// is where to sleep near here, and a country of places does not ask it.
/// Closer, or once located, it is the round button again. It never covers
/// the map: the same corner, the same action (`locateUser`).
class LocateButton extends ConsumerWidget {
  const new({required this.onLocate, super.key});

  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final located = ref.watch(userLocationProvider) != null;
    // Before the map reports its first camera it shows the country.
    final zoom = ref.watch(viewportProvider.select((v) => v?.zoom)) ?? initialMapZoom;
    // A device without a place and without the tiles shows the first
    // download's card in that corner instead (`SyncBanner`).
    final empty = !ref.watch(placesFromTilesProvider) && ref.watch(placeCountProvider).value == 0;
    final invite = !located && !empty && zoom < PlaceTiles.countryZoom;
    final Widget button;
    if (invite) {
      final scheme = Theme.of(context).colorScheme;
      // On a phone the map's credit runs along the same bottom edge: the
      // words stand one row higher, clear of it.
      final lift = WindowSize.of(context) == WindowSize.compact ? 48.0 + Space.s : 0.0;
      button = Padding(
        key: const ValueKey('invite'),
        padding: EdgeInsets.only(bottom: lift),
        child: FloatingSurface(
          color: scheme.primary,
          child: TextButton.icon(
            onPressed: onLocate,
            icon: const Icon(AppIcons.locate),
            label: Text(t.map.aroundMe),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onPrimary,
              // Material's button takes a notch off under the desktop's
              // density, as the round button does.
              minimumSize: const Size.square(48),
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
      );
    } else {
      button = MapButton(
        key: const ValueKey('locate'),
        icon: located ? AppIcons.locateActive : AppIcons.locate,
        tooltip: t.map.locateMe,
        onPressed: onLocate,
        size: 48,
      );
    }
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.bottomRight, children: [...previous, ?current]),
      child: button,
    );
  }
}
