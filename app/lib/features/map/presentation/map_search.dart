import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/address_results.dart';
import 'package:lunaway/features/places/presentation/locality_line.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_search.dart';
import 'package:lunaway/features/poi/presentation/poi_search.dart';
import 'package:lunaway/features/search/application/search_history_providers.dart';
import 'package:lunaway/features/search/data/search_history_store.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';
import 'package:lunaway/features/search/presentation/recent_searches.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/floating.dart';

/// The search pill over the map, with the brand mark, and its results under
/// it while there is a query: the places for motorhomes first, the device's
/// own index or the API's; then the towns and the addresses the server's
/// geocoders find, and the shops, services and other points the API finds
/// in the same request, before the towns when the text asks for a kind or
/// names one of them ([poisFirst]). The entries of the history the text
/// matches come first, under a clock.
///
/// The field focused and empty, the history shows under it instead
/// ([RecentSearchesList]): the results opened and the texts searched
/// before, which open again without a search. It stays on the device.
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

  /// The focus of the field and of what shows under it: the history stays
  /// while the keyboard goes from the field to its entries and crosses.
  final FocusNode _region = FocusNode(skipTraversal: true, canRequestFocus: false);
  final GlobalKey _pill = GlobalKey();

  /// Read once at the start: [dispose] closes the history and may no
  /// longer read a provider then.
  late final SearchHistoryOpen _historyOpen;

  /// The text the user validated, kept in the history until a result of it
  /// opens: then the result takes its place.
  RecentText? _validated;

  /// Where the pill ends on the screen, as the last frame laid it out: the
  /// list of results starts under it and runs to the bottom of the room
  /// left. Null before the first frame.
  double? _pillBottom;

  @override
  void initState() {
    super.initState();
    _historyOpen = ref.read(searchHistoryOpenProvider.notifier);
    _region.addListener(_followFocus);
  }

  @override
  void dispose() {
    _region.removeListener(_followFocus);
    // The history leaves with its field (another layout's field takes over
    // unfocused): told after the frame, as the tree may be building.
    final open = _historyOpen;
    unawaited(Future.microtask(() => open.set(open: false)));
    _controller.dispose();
    _focus.dispose();
    _region.dispose();
    super.dispose();
  }

  /// The history shows while the field, or an entry of the history, has
  /// the focus, and the field no text.
  void _followFocus() {
    if (!mounted) return;
    _historyOpen.set(open: _region.hasFocus && _controller.text.trim().isEmpty);
  }

  /// The focus leaves the search, wherever in it it stood.
  void _letGo() {
    if (_region.hasFocus) FocusManager.instance.primaryFocus?.unfocus();
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

  SearchHistoryStore get _history => ref.read(searchHistoryStoreProvider);

  /// [entry] opened: it heads the history, and the text validated before
  /// it leaves when this result answers that same text; a text validated
  /// before another search stays.
  void _remember(RecentSearch entry) {
    final history = _history;
    final validated = _validated;
    _validated = null;
    final answered = validated != null && validated.key == RecentText(_controller.text.trim()).key;
    unawaited(() async {
      if (answered) await history.remove(validated.key);
      await history.record(entry);
    }());
  }

  /// The text of the field validated (the keyboard's search key, Enter):
  /// kept in the history as a text searched, until a result of it opens.
  void _validate(String text) {
    final query = text.trim();
    if (query.length < 2) return;
    final entry = RecentText(query);
    _validated = entry;
    unawaited(_history.record(entry));
  }

  Future<void> _goToTown(Municipality town) async {
    _remember(RecentTown(town));
    _clear();
    _flow.select(null);
    await ref.read(mapControllerProvider)?.moveTo(town.center, zoom: 12);
  }

  Future<void> _goToAddress(AddressMatch address) async {
    _remember(RecentAddress(address));
    _clear();
    _flow.select(PointSelection(address.position, address: address));
    await ref.read(mapControllerProvider)?.moveTo(address.position, zoom: address.kind.zoom);
  }

  Future<void> _goToPoi(Poi poi) async {
    _remember(RecentPoi.of(poi));
    await _showPoi(poi.feature);
  }

  Future<void> _showPoi(PoiFeature feature) async {
    _clear();
    _flow.select(PoiSelection(feature));
    final viewport = ref.read(viewportProvider);
    await ref
        .read(mapControllerProvider)
        ?.moveTo(feature.position, zoom: (viewport?.zoom ?? 0) < 15 ? 15 : null);
  }

  Future<void> _goToPlace(PlaceSummary place) async {
    _remember(RecentPlace(place));
    await _showPlace(place);
  }

  Future<void> _showPlace(PlaceSummary place) async {
    _clear();
    _flow.select(PlaceSelection(place.id, hint: place));
    final viewport = ref.read(viewportProvider);
    await ref
        .read(mapControllerProvider)
        ?.moveTo(place.position, zoom: (viewport?.zoom ?? 0) < 13 ? 13 : null);
  }

  /// An entry of the history touched: its result opens again without a
  /// search (a place or a point read by its id, a town or an address at
  /// its position), its text is searched again. A place or a point the
  /// map no longer holds leaves the history, and a message says so. The
  /// read by id comes late on a slow network: when the user opened
  /// something else meanwhile, the entry opens nothing ([MapFlow.stands]).
  Future<void> _reopen(RecentSearch entry) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final goneText = context.t.search.recentGone(name: recentTitle(context.t, entry));
    final history = _history;
    final flow = _flow;
    switch (entry) {
      case RecentText(:final text):
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        ref.read(searchQueryProvider.notifier).change(text);
        _validated = entry;
        _historyOpen.set(open: false);
        unawaited(history.record(entry));
      case RecentTown(:final town):
        await _goToTown(town);
      case RecentAddress(:final address):
        await _goToAddress(address);
      case RecentPlace(:final place):
        final asked = ref.read(mapFlowProvider).revision;
        final reader = ref.read(placeReaderProvider);
        _letGo();
        if (await _gone(() => reader.read(place.id))) {
          await history.remove(entry.key);
          showMessage(messenger, goneText);
          return;
        }
        if (!mounted || !flow.stands(asked)) return;
        _remember(entry);
        await _showPlace(place);
      case RecentPoi(:final id, :final feature):
        final asked = ref.read(mapFlowProvider).revision;
        final points = ref.read(poiRepositoryProvider);
        _letGo();
        if (await _gone(() async => (await points.watchPage(id).first).value)) {
          await history.remove(entry.key);
          showMessage(messenger, goneText);
          return;
        }
        if (!mounted || !flow.stands(asked)) return;
        _remember(entry);
        await _showPoi(feature);
    }
  }

  /// Whether [read], the read by id of what an entry opens, says it is no
  /// longer there. Offline, late or failed, it is taken to be there: its
  /// page then says what it can. Offline, a device knows only the places
  /// of its regions, and the others are not gone for that.
  Future<bool> _gone(Future<Object?> Function() read) async {
    if (!ref.read(placesFromTilesProvider)) return false;
    try {
      return await read().timeout(const Duration(seconds: 4)) == null;
    } on Object {
      return false;
    }
  }

  /// Empties the history; the message that says so takes it back.
  Future<void> _clearHistory() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = context.t;
    final history = _history;
    final removed = ref.read(recentSearchesProvider).value ?? const <RecentSearch>[];
    await history.clear();
    showMessage(
      messenger,
      t.search.historyCleared,
      action: SnackBarAction(
        label: t.common.undo,
        // The oldest first, so the most recent heads it again.
        onPressed: () => unawaited(() async {
          for (final entry in removed.reversed) {
            await history.record(entry);
          }
        }()),
      ),
    );
    // The field keeps the focus, for a search typed next.
    if (mounted) _focus.requestFocus();
  }

  /// A touch outside the field and its lists: the history closes, on a
  /// phone too; with a text, as the platform does (a phone keeps its
  /// keyboard, a computer and a browser let go of the field).
  void _tappedOutside(PointerDownEvent event) {
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
      _ => false,
    };
    if (_controller.text.trim().isEmpty || kIsWeb || desktop) _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = ref.watch(searchQueryProvider);
    final historyOpen = ref.watch(searchHistoryOpenProvider);
    // A query cleared from elsewhere (the system back) empties the field too.
    ref.listen(searchQueryProvider, (_, next) {
      if (next.isEmpty && _controller.text.isNotEmpty) {
        _controller.clear();
        _focus.unfocus();
      }
    });
    // The history closed from elsewhere (the system back, Escape, a pin
    // tapped): the field lets go of the focus with it.
    ref.listen(searchHistoryOpenProvider, (_, open) {
      if (!open && _controller.text.trim().isEmpty) _letGo();
    });
    ref.listen(selectionProvider, (_, next) {
      if (next != null && _controller.text.trim().isEmpty) _letGo();
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
                // Narrowed by the list's panel or a large text, the hint
                // gets a little smaller rather than end in "une com...".
                hint: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    t.map.searchHint,
                    maxLines: 1,
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).change(value);
                _followFocus();
              },
              onSubmitted: _validate,
              onTapOutside: _tappedOutside,
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
    final history = !searching && historyOpen
        ? ref.watch(recentSearchesProvider).value ?? const <RecentSearch>[]
        : const <RecentSearch>[];
    // The list's room depends on where the pill sits, which only a laid out
    // frame tells: measured after each frame while results show, the list
    // follows the next one.
    if (searching || history.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measurePill());
    }
    final top = _pillBottom == null ? null : _pillBottom! + Space.s;
    final Widget results;
    if (searching) {
      results = Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: _Results(
          query: query,
          top: top,
          onTown: _goToTown,
          onPlace: _goToPlace,
          onAddress: _goToAddress,
          onPoi: _goToPoi,
          onRecent: _reopen,
        ),
      );
    } else if (history.isNotEmpty) {
      results = Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: _Panel(
          top: top,
          child: RecentSearchesList(
            entries: history,
            onOpen: _reopen,
            onRemove: (entry) {
              // The focus back in the field: the cross a key pressed goes
              // with its entry, and the history stays.
              if (!_focus.hasFocus) _focus.requestFocus();
              unawaited(_history.remove(entry.key));
            },
            onClear: _clearHistory,
          ),
        ),
      );
    } else {
      results = const SizedBox(width: double.infinity);
    }
    // The field and what shows under it are one region: a touch in the
    // history or the results is no touch outside the field.
    return Focus(
      focusNode: _region,
      // No semantics of its own: its annotation took the field's node in
      // while the field stood alone, and gave it up when the clear button
      // and the results came, so the field's node changed at the first
      // keys typed. A browser with its semantics on (a screen reader, the
      // web journeys) types into an input element made from that node: a
      // new node is a new, empty input, and the keys typed before it were
      // lost ("ing-car Park Viviers", 2026-10-10).
      includeSemantics: false,
      // Escape closes the history, from the field or from an entry; with a
      // text, the screen's own Escape goes on as before.
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.escape ||
            _controller.text.trim().isNotEmpty) {
          return KeyEventResult.ignored;
        }
        _letGo();
        return KeyEventResult.handled;
      },
      child: TextFieldTapRegion(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            // In a pane the list under the search comes back as the results
            // go: a collapse in steps would push it past the pane's foot.
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
        ),
      ),
    );
  }
}

/// The surface of what shows under the search, the results or the history,
/// down to the keyboard or the foot of the window and no further.
class _Panel extends StatelessWidget {
  const new({required this.top, required this.child});

  /// Where the panel starts on the screen; null before it is known.
  final double? top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
    return FloatingSurface(
      radius: LunaTokens.radiusXl,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: child,
      ),
    );
  }
}

class _Results extends ConsumerStatefulWidget {
  const new({
    required this.query,
    required this.top,
    required this.onTown,
    required this.onPlace,
    required this.onAddress,
    required this.onPoi,
    required this.onRecent,
  });

  final String query;

  /// Where the list starts on the screen; null before it is known.
  final double? top;
  final ValueChanged<Municipality> onTown;
  final ValueChanged<PlaceSummary> onPlace;
  final ValueChanged<AddressMatch> onAddress;
  final ValueChanged<Poi> onPoi;

  /// An entry of the history the text matches, touched.
  final ValueChanged<RecentSearch> onRecent;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  /// The points the order of the sections follows while the next ones
  /// load: the section does not jump at every keystroke.
  PoiResults _ordering = PoiResults.none;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = widget.query;
    final user = ref.watch(userLocationProvider);
    final centre = ref.read(viewportProvider)?.center;
    final near = user ?? centre;
    // One family key for both: on the web they are one request.
    final language = t.$meta.locale.languageCode;
    final results = ref.watch(
      searchResultsProvider(query, near: near, language: language, pois: true),
    );
    // No address nor point is asked under three characters: no line saying
    // one is on its way. Offline, the device's places alone answer, and
    // the points say they need a network.
    final online = query.trim().length < 3
        ? const AsyncData(OnlineMatches.none)
        : !ref.watch(placesFromTilesProvider)
        ? const AsyncData(OnlineMatches.unreachable)
        : ref.watch(onlineSearchProvider(query, near: near, language: language, pois: true));
    if (online.value case final matches?) _ordering = matches.pois;
    final addresses = online.whenData((o) => o.addresses);
    Widget addressSection(List<Municipality> towns) => AddressResults(
      // Its list stays while the next one loads, whatever comes and
      // goes above it.
      key: const ValueKey('addresses'),
      addresses: addresses,
      towns: towns,
      from: user,
      onTap: widget.onAddress,
    );
    // The same: it keeps its list as it moves above the towns or below.
    // A kind sought near here is listed from the user when the map shows
    // them, as the list beside the map; from elsewhere on the map, in the
    // server's order, from the map's centre.
    final bounds = ref.read(viewportProvider)?.bounds;
    final poiSection = PoiSearchSection(
      key: const ValueKey('pois'),
      query: query,
      results: online,
      from: user,
      orderFrom: user != null && (bounds?.contains(user) ?? false) ? user : null,
      onTap: widget.onPoi,
    );
    // What the history holds that the text names, a few, at the head of
    // the results under a clock: a text searched again is not one of them.
    final typed = RecentText(query.trim()).key;
    final recent = [
      for (final entry in ref.watch(recentSearchesProvider).value ?? const <RecentSearch>[])
        if (entry.key != typed && entry.matches(query))
          RecentSearchTile(
            key: ValueKey('recent ${entry.key}'),
            entry: entry,
            onTap: () => widget.onRecent(entry),
          ),
    ].take(_recentAmongResults).toList();
    Widget list(SearchResults value) {
      final towns = [for (final m in value.municipalities) m.name];
      final first = poisFirst(_ordering, query, towns);
      // A text that is a town's name asks for the town: it heads the list,
      // before the places that bear its name or lie in it ("Annecy", the
      // town's journey of the web app, 2026-10-10).
      final townFirst = townNamed(query, towns);
      final townSection = [
        if (value.municipalities.isNotEmpty) SearchHeader(t.search.towns),
        for (final town in value.municipalities)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: const Icon(AppIcons.town),
            ),
            title: Text(town.name),
            subtitle: Text(townDetail(t, town, home: homeCountry(ref))),
            // Saved from here: the tap shows its places and opens no card.
            trailing: SaveTownButton(town: town),
            onTap: () => widget.onTown(town),
          ),
      ];
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        children: [
          // The API out of reach: what follows comes from the regions kept.
          if (value.deviceOnly) const _DeviceOnlyNote(),
          ...recent,
          // Only once every section is done and none found anything: above
          // the addresses a section did find, it read as if nothing had.
          if (value.isEmpty && _foundNothing(online))
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(t.search.noResult(query: query.trim()), style: theme.textTheme.bodyLarge),
            ),
          if (townFirst) ...townSection,
          // The places for motorhomes come next, before any establishment.
          if (value.places.isNotEmpty) SearchHeader(t.search.places),
          for (final place in value.places)
            PlaceTile(
              place: place,
              distanceM: user == null ? null : place.position.distanceTo(user),
              onTap: () => widget.onPlace(place),
            ),
          if (first) poiSection,
          if (!townFirst) ...townSection,
          addressSection(value.municipalities),
          if (!first) poiSection,
        ],
      );
    }

    // The previous results stay while the next ones load: no flash of a
    // spinner at every keystroke.
    Widget withRecent(Widget state) => recent.isEmpty
        ? state
        : ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            children: [...recent, state],
          );
    final body = switch (results) {
      AsyncValue(value: final value?) => list(value),
      // Not tried again by itself (it would turn for half a minute): the
      // user asks again, once the network is back.
      AsyncError(:final error) => withRecent(
        Padding(
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
                onPressed: () => ref.invalidate(
                  searchResultsProvider(query, near: near, language: language, pois: true),
                ),
                child: Text(t.common.retry),
              ),
            ],
          ),
        ),
      ),
      _ => withRecent(
        const SizedBox(height: 72, child: Center(child: CircularProgressIndicator())),
      ),
    };
    return _Panel(top: widget.top, child: body);
  }
}

/// The most entries of the history the results start with.
const _recentAmongResults = 3;

/// The search limited to the regions the device keeps, the API out of
/// reach: said at the top of the results.
class _DeviceOnlyNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
      child: Row(
        children: [
          Icon(AppIcons.offline, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              context.t.search.deviceOnly,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// What stands above the list of results under the top of the window, the
/// pill and its margins, until a frame has measured it.
const double _aboveResults = 96;

/// Whether the addresses and the points are done and found nothing: a
/// failure says so in its own section, and finds nothing either.
bool _foundNothing(AsyncValue<OnlineMatches> online) => switch (online) {
  AsyncData(:final value) => value.addresses.isEmpty && value.pois.pois.isEmpty,
  AsyncError() => true,
  _ => false,
};

/// The line under a town: where it lies ([townWhere]: "Commune · Drôme (26)"),
/// then how many places it holds.
String townDetail(Translations t, Municipality town, {required String home}) =>
    [townWhere(t, town, home: home), t.search.townPlaces(n: town.placeCount)].join(' · ');
