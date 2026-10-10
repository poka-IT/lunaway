import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/french_departments.dart';
import 'package:lunaway/features/places/presentation/address_results.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_search.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/floating.dart';

/// The search pill over the map, with the brand mark, and its results under
/// it while there is a query: the places and towns (the device's own index,
/// else the API), then the addresses the server's geocoders find, then the
/// shops and services.
class MapSearch extends ConsumerStatefulWidget {
  const new({this.floating = true, this.brand = true, super.key});

  /// Floating over the map (true) or sitting in a pane (false).
  final bool floating;

  /// The brand mark at the start of a floating pill; a rail that already
  /// shows the brand leaves it out.
  final bool brand;

  /// The pill's height to a finger; 8 less to a mouse.
  static const double touchHeight = 56;

  /// The pill's height: 56 to a finger, 48 to a mouse.
  static double heightOf(BuildContext context) => controlHeight(context, touchHeight);

  @override
  ConsumerState<MapSearch> createState() => _MapSearchState();
}

class _MapSearchState extends ConsumerState<MapSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchQueryProvider),
  );
  final FocusNode _focus = FocusNode();
  final GlobalKey _pill = GlobalKey();

  /// Where the pill ends on the screen, as the last frame laid it out: the
  /// list of results starts under it and runs to the bottom of the room
  /// left. Null before the first frame.
  double? _pillBottom;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _measurePill() {
    if (!mounted) return;
    final box = _pill.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    if (_pillBottom == null || (bottom - _pillBottom!).abs() > 0.5) {
      setState(() => _pillBottom = bottom);
    }
  }

  void _clear() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).change('');
    _focus.unfocus();
  }

  MapFlow get _flow => ref.read(mapFlowProvider.notifier);

  Future<void> _goToTown(Municipality town) async {
    _clear();
    _flow.select(null);
    await ref.read(mapControllerProvider)?.moveTo(town.center, zoom: 12);
  }

  Future<void> _goToAddress(AddressMatch address) async {
    _clear();
    _flow.select(PointSelection(address.position, address: address));
    await ref.read(mapControllerProvider)?.moveTo(address.position, zoom: address.kind.zoom);
  }

  Future<void> _goToPoi(Poi poi) async {
    _clear();
    _flow.select(PoiSelection(poi.feature));
    final viewport = ref.read(viewportProvider);
    await ref
        .read(mapControllerProvider)
        ?.moveTo(poi.position, zoom: (viewport?.zoom ?? 0) < 15 ? 15 : null);
  }

  Future<void> _goToPlace(String id, LatLng at) async {
    _clear();
    _flow.select(PlaceSelection(id));
    final viewport = ref.read(viewportProvider);
    await ref.read(mapControllerProvider)?.moveTo(at, zoom: (viewport?.zoom ?? 0) < 13 ? 13 : null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = ref.watch(searchQueryProvider);
    // A query cleared from elsewhere (the system back) empties the field too.
    ref.listen(searchQueryProvider, (_, next) {
      if (next.isEmpty && _controller.text.isNotEmpty) {
        _controller.clear();
        _focus.unfocus();
      }
    });
    final row = SizedBox(
      height: MapSearch.heightOf(context),
      child: Row(
        children: [
          const SizedBox(width: Space.ml),
          if (widget.floating && widget.brand)
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
          else if (widget.floating && widget.brand)
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
        ? FloatingSurface(key: _pill, child: row)
        : DecoratedBox(
            key: _pill,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            ),
            child: Material(type: MaterialType.transparency, child: row),
          );
    final searching = query.trim().isNotEmpty;
    // The list's room depends on where the pill sits, which only a laid out
    // frame tells: measured after each frame while results show, the list
    // follows the next one.
    if (searching) WidgetsBinding.instance.addPostFrameCallback((_) => _measurePill());
    final results = !searching
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: _Results(
              query: query,
              top: _pillBottom == null ? null : _pillBottom! + Space.s,
              onTown: _goToTown,
              onPlace: _goToPlace,
              onAddress: _goToAddress,
              onPoi: _goToPoi,
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        // In a pane the list under the search comes back as the results go:
        // a collapse in steps would push it past the pane's foot.
        if (widget.floating)
          AnimatedSize(
            duration: Motion.of(context, Motion.emphasized),
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: results,
          )
        else
          results,
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const new({
    required this.query,
    required this.top,
    required this.onTown,
    required this.onPlace,
    required this.onAddress,
    required this.onPoi,
  });

  final String query;

  /// Where the list starts on the screen; null before it is known.
  final double? top;
  final ValueChanged<Municipality> onTown;
  final void Function(String id, LatLng at) onPlace;
  final ValueChanged<AddressMatch> onAddress;
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
    // One family key for both: on the web they are one request.
    final language = t.$meta.locale.languageCode;
    final results = ref.watch(searchResultsProvider(query, near: near, language: language));
    // No address is asked offline nor under three characters: no line
    // saying one is on its way.
    final addresses = query.trim().length < 3 || !ref.watch(placesFromTilesProvider)
        ? const AsyncData(<AddressMatch>[])
        : ref.watch(addressSearchProvider(query, near: near, language: language));
    // The same family member the shops' section reads: no second request.
    final pois = query.trim().length < 3
        ? const AsyncData(<Poi>[])
        : ref.watch(poiSearchProvider(query, near: anchor));
    Widget addressSection(List<Municipality> towns) => AddressResults(
      // Its list stays while the next one loads, whatever comes and
      // goes above it.
      key: const ValueKey('addresses'),
      addresses: addresses,
      towns: towns,
      from: user,
      onTap: onAddress,
    );
    // The screen's own insets: the shell's Scaffold removes the keyboard from
    // the MediaQuery below it, yet the list must end above the keyboard;
    // with the keyboard closed it ends above the dock and the system's bar,
    // which the shell's padding holds (its body runs under the dock). The
    // list takes all of that room: the map behind waits for a choice.
    // The window's size from the MediaQuery, so a resized window lays the
    // list out again; its insets from the view, which no Scaffold or
    // SafeArea above has taken away: the keyboard, the system's bars.
    final height = MediaQuery.sizeOf(context).height;
    final view = MediaQueryData.fromView(View.of(context));
    final below = [
      view.viewInsets.bottom,
      view.padding.bottom,
      MediaQuery.paddingOf(context).bottom,
    ].reduce(math.max);
    final start = top ?? view.padding.top + _aboveResults;
    final maxHeight = math.max(120, height - below - start - Space.m).toDouble();
    Widget list(SearchResults value) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      children: [
        if (value.municipalities.isNotEmpty) SearchHeader(t.search.towns),
        for (final town in value.municipalities)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: const Icon(AppIcons.town),
            ),
            title: Text(town.name),
            subtitle: Text(townDetail(t, town)),
            onTap: () => onTown(town),
          ),
        if (value.places.isNotEmpty) SearchHeader(t.search.places),
        for (final place in value.places)
          PlaceTile(
            place: place,
            distanceM: user == null ? null : place.position.distanceTo(user),
            onTap: () => onPlace(place.id, place.position),
          ),
        addressSection(value.municipalities),
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
          // Only once every section is done and none found anything: above
          // the addresses a section did find, it read as if nothing had.
          if (_foundNothing(addresses, pois))
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(t.search.noResult(query: query.trim()), style: theme.textTheme.bodyLarge),
            ),
          addressSection(const []),
          PoiSearchSection(query: query, near: anchor, from: user, onTap: onPoi),
        ],
      ),
      AsyncValue(value: final value?) => list(value),
      // Not tried again by itself (it would turn for half a minute): the
      // user asks again, once the network is back.
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error is GraphQLNetworkException && error is! GraphQLRateLimitedException
                  ? t.search.offline
                  : t.list.error,
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(searchResultsProvider(query, near: near, language: language)),
              child: Text(t.common.retry),
            ),
          ],
        ),
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

/// What stands above the list of results under the top of the window, the
/// pill and its margins, until a frame has measured it.
const double _aboveResults = 96;

/// Whether the addresses and the shops are done and found nothing: a
/// failure says so in its own section, and finds nothing either.
bool _foundNothing(AsyncValue<List<AddressMatch>> addresses, AsyncValue<List<Poi>> pois) {
  bool nothing<T>(AsyncValue<List<T>> v) => switch (v) {
    AsyncData(:final value) => value.isEmpty,
    AsyncError() => true,
    _ => false,
  };
  return nothing(addresses) && nothing(pois);
}

/// The line under a town: its postcode, then its department in France (the
/// homonyms of two departments read apart) or its country elsewhere, then
/// how many places it holds.
@visibleForTesting
String townDetail(Translations t, Municipality town) {
  final department = frenchDepartments[town.department];
  final country = town.countryCode;
  return [
    ?town.postcode,
    if (department != null)
      department
    else if (country != null && country != 'FR')
      t.countryName(country),
    t.search.townPlaces(n: town.placeCount),
  ].join(' · ');
}
