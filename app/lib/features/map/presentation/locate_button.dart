import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';

/// The map's button for the device's position. In the country's view, while
/// the app does not know where the user is (a first launch, a browser that
/// was never asked), it says what it does in words: the question at launch
/// is where to sleep near here, and a country of places does not ask it.
/// Closer, or once located, it is the round button again. It never covers
/// the map: the same corner, the same action (`locateUser`). Laid out across
/// the width of the map, aligned right; where the map leaves too little room
/// for the words, the round button stays.
class LocateButton extends ConsumerWidget {
  const new({required this.onLocate, this.underZoom = false, super.key});

  final VoidCallback onLocate;

  /// Whether the zoom's buttons stand above it. Alone in its corner, the
  /// words rise one row above the map's credit, which runs along the same
  /// bottom edge. Under the zoom's buttons they stay on the credit's row
  /// and show only where they fit beside it: rising, they would push the
  /// buttons up, and these would jump back under the mouse once the words
  /// go.
  final bool underZoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final located = ref.watch(userLocationProvider) != null;
    // Before the map reports its first camera it shows the country.
    final zoom = ref.watch(viewportProvider.select((v) => v?.zoom)) ?? initialMapZoom;
    // A device without a place and without the tiles shows the first
    // download's card in that corner instead (`SyncBanner`).
    final empty = !ref.watch(placesFromTilesProvider) && ref.watch(placeCountProvider).value == 0;
    final wanted = !located && !empty && zoom < PlaceTiles.countryZoom;
    return LayoutBuilder(
      builder: (context, box) {
        final words = t.map.aroundMe;
        final room = underZoom ? box.maxWidth - MapCredit.widthOf(context) - Space.m : box.maxWidth;
        final invite = wanted && _wordsWidth(context, words) <= room;
        final Widget button;
        if (invite) {
          final scheme = Theme.of(context).colorScheme;
          button = Padding(
            key: const ValueKey('invite'),
            padding: EdgeInsets.only(bottom: underZoom ? 0 : MapCredit.height + Space.s),
            child: FloatingSurface(
              color: scheme.primary,
              child: TextButton.icon(
                onPressed: onLocate,
                icon: const Icon(AppIcons.locate),
                label: Text(words, maxLines: 1, softWrap: false),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onPrimary,
                  // Material's button takes a notch off under the desktop's
                  // density, as the round button does.
                  minimumSize: const Size.square(48),
                  padding: const EdgeInsets.symmetric(horizontal: _padding),
                ).copyWith(side: focusRingIn(scheme.onPrimary)),
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
      },
    );
  }

  static const double _padding = Space.l;

  /// The width the button in words takes: its text in the theme's button
  /// style at the reader's text size, the icon and the paddings.
  static double _wordsWidth(BuildContext context, String words) {
    final theme = Theme.of(context);
    final style =
        theme.textButtonTheme.style?.textStyle?.resolve(const {}) ?? theme.textTheme.labelLarge;
    final painter = TextPainter(
      text: TextSpan(text: words, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 24 + Space.s + _padding * 2;
  }
}
