import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_search.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/floating.dart';

/// The search pill over the map, with the brand mark, and its results under
/// it while there is a query. Everything is answered by the local index,
/// without network.
class MapSearch extends ConsumerStatefulWidget {
  const new({this.floating = true, super.key});

  /// Floating over the map (true) or sitting in a pane (false).
  final bool floating;

  @override
  ConsumerState<MapSearch> createState() => _MapSearchState();
}

class _MapSearchState extends ConsumerState<MapSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchQueryProvider),
  );
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).change('');
    _focus.unfocus();
  }

  Future<void> _goToTown(Municipality town) async {
    _clear();
    ref.read(selectionProvider.notifier).select(null);
    await ref.read(mapControllerProvider)?.moveTo(town.center, zoom: 12);
  }

  Future<void> _goToPoi(Poi poi) async {
    _clear();
    ref.read(selectionProvider.notifier).select(PoiSelection(poi.feature));
    final viewport = ref.read(viewportProvider);
    await ref
        .read(mapControllerProvider)
        ?.moveTo(poi.position, zoom: (viewport?.zoom ?? 0) < 15 ? 15 : null);
  }

  Future<void> _goToPlace(String id, LatLng at) async {
    _clear();
    ref.read(selectionProvider.notifier).select(PlaceSelection(id));
    final viewport = ref.read(viewportProvider);
    await ref.read(mapControllerProvider)?.moveTo(at, zoom: (viewport?.zoom ?? 0) < 13 ? 13 : null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = ref.watch(searchQueryProvider);
    final row = SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: Space.ml),
          if (widget.floating)
            const BrandMark(height: 30)
          else
            Icon(AppIcons.search, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyLarge,
              // A bare field: the pill is its box, not the theme's outline.
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: t.map.searchHint,
                hintMaxLines: 1,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              onChanged: (value) => ref.read(searchQueryProvider.notifier).change(value),
            ),
          ),
          if (query.isNotEmpty)
            IconButton(
              tooltip: t.map.clearSearch,
              icon: const Icon(AppIcons.close),
              onPressed: _clear,
            )
          else if (widget.floating)
            Padding(
              padding: const EdgeInsets.only(right: Space.ml),
              child: Icon(AppIcons.search, color: scheme.onSurfaceVariant),
            )
          else
            const SizedBox(width: Space.m),
        ],
      ),
    );
    final field = widget.floating
        ? FloatingSurface(child: row)
        : DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            ),
            child: Material(type: MaterialType.transparency, child: row),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        AnimatedSize(
          duration: Motion.of(context, Motion.emphasized),
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: query.trim().isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: _Results(
                    query: query,
                    onTown: _goToTown,
                    onPlace: _goToPlace,
                    onPoi: _goToPoi,
                  ),
                ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const new({
    required this.query,
    required this.onTown,
    required this.onPlace,
    required this.onPoi,
  });

  final String query;
  final ValueChanged<Municipality> onTown;
  final void Function(String id, LatLng at) onPlace;
  final ValueChanged<Poi> onPoi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(userLocationProvider);
    final centre = ref.read(viewportProvider)?.center;
    final near = user ?? centre;
    // The shops are ranked from the map's centre on a coarse grid: the same
    // cell keeps the same search.
    final anchor = centre == null ? null : searchAnchor(centre);
    final results = ref.watch(searchResultsProvider(query, near: near));
    // The screen's own insets: the shell's Scaffold removes the keyboard from
    // the MediaQuery below it, yet the list must end above the keyboard.
    final view = MediaQueryData.fromView(View.of(context));
    final aboveKeyboard = view.size.height - view.viewInsets.bottom - view.padding.top - 96;
    final maxHeight = math.max(120, math.min(view.size.height * 0.55, aboveKeyboard)).toDouble();
    Widget list(SearchResults value) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      children: [
        if (value.municipalities.isNotEmpty) _Header(t.search.towns),
        for (final town in value.municipalities)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: const Icon(AppIcons.town),
            ),
            title: Text(town.name),
            subtitle: Text([?town.postcode, t.search.townPlaces(n: town.placeCount)].join(' · ')),
            onTap: () => onTown(town),
          ),
        if (value.places.isNotEmpty) _Header(t.search.places),
        for (final place in value.places)
          PlaceTile(
            place: place,
            distanceM: user == null ? null : place.position.distanceTo(user),
            onTap: () => onPlace(place.id, place.position),
          ),
        PoiSearchSection(query: query, near: anchor, from: user, onTap: onPoi),
      ],
    );
    // The previous results stay while the next ones load: no flash of a
    // spinner at every keystroke.
    final body = switch (results) {
      AsyncValue(value: final value?) when value.isEmpty => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Space.s),
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(t.search.noResult(query: query.trim()), style: theme.textTheme.bodyLarge),
          ),
          PoiSearchSection(query: query, near: anchor, from: user, onTap: onPoi),
        ],
      ),
      AsyncValue(value: final value?) => list(value),
      AsyncError() => Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(t.list.error, style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error)),
      ),
      _ => const SizedBox(height: 72, child: Center(child: CircularProgressIndicator())),
    };
    return FloatingSurface(
      radius: LunaTokens.radiusXl,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: body,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new(this.text);

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
