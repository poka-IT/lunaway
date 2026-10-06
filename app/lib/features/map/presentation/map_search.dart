import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The search field over the map, and its results under it while there is a
/// query. Everything is answered by the local index, without network.
class MapSearch extends ConsumerStatefulWidget {
  const new({this.trailing, this.elevated = true, super.key});

  /// A button at the end of the field (the filters on a phone).
  final Widget? trailing;

  /// Floating over the map (true) or sitting in a pane (false).
  final bool elevated;

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

  Future<void> _goToPlace(String id, double lat, double lon) async {
    _clear();
    ref.read(selectionProvider.notifier).select(PlaceSelection(id));
    final viewport = ref.read(viewportProvider);
    await ref
        .read(mapControllerProvider)
        ?.moveTo(LatLng(lat, lon), zoom: (viewport?.zoom ?? 0) < 13 ? 13 : null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final query = ref.watch(searchQueryProvider);
    final field = Material(
      elevation: widget.elevated ? 3 : 0,
      shadowColor: LunaTokens.of(context).shadow,
      color: widget.elevated
          ? theme.colorScheme.surfaceContainerHigh
          : theme.colorScheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: Space.lx),
            Icon(AppIcons.search, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.m),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration.collapsed(
                  hintText: t.map.searchHint,
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
            else
              const SizedBox(width: Space.s),
            ?widget.trailing,
            if (widget.trailing != null) const SizedBox(width: Space.xxs),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        AnimatedSize(
          duration: Motion.emphasized,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: query.trim().isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: _Results(query: query, onTown: _goToTown, onPlace: _goToPlace),
                ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const new({required this.query, required this.onTown, required this.onPlace});

  final String query;
  final ValueChanged<Municipality> onTown;
  final void Function(String id, double lat, double lon) onPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final user = ref.watch(userLocationProvider);
    final near = user ?? ref.read(viewportProvider)?.center;
    final results = ref.watch(searchResultsProvider(query, near: near));
    // The screen's own insets: the shell's Scaffold removes the keyboard from
    // the MediaQuery below it, yet the list must end above the keyboard.
    final view = MediaQueryData.fromView(View.of(context));
    final aboveKeyboard = view.size.height - view.viewInsets.bottom - view.padding.top - 96;
    final maxHeight = math.max(120, math.min(view.size.height * 0.55, aboveKeyboard)).toDouble();
    final body = switch (results) {
      AsyncData(:final value) when value.isEmpty => Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(t.search.noResult(query: query.trim()), style: theme.textTheme.bodyLarge),
      ),
      AsyncData(:final value) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        children: [
          if (value.municipalities.isNotEmpty) _Header(t.search.towns),
          for (final town in value.municipalities)
            ListTile(
              leading: const CircleAvatar(child: Icon(AppIcons.town)),
              title: Text(town.name),
              subtitle: Text([?town.postcode, t.search.townPlaces(n: town.placeCount)].join(' · ')),
              onTap: () => onTown(town),
            ),
          if (value.places.isNotEmpty) _Header(t.search.places),
          for (final place in value.places)
            PlaceTile(
              place: place,
              distanceM: user == null ? null : place.position.distanceTo(user),
              onTap: () => onPlace(place.id, place.lat, place.lon),
            ),
        ],
      ),
      AsyncError() => Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(
          t.list.error,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
        ),
      ),
      AsyncLoading() => const SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      ),
    };
    return Material(
      elevation: LunaTokens.of(context).floatingElevation,
      shadowColor: LunaTokens.of(context).shadow,
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusXl),
      clipBehavior: Clip.antiAlias,
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
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
