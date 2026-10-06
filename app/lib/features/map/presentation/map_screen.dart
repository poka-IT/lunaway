import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/map/presentation/sync_banner.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// The map of places, in the three layouts: on a phone the map fills the
/// screen with the list and the details in sheets; on a tablet the details
/// open in a side panel; on a desktop the list, the map and the details sit
/// side by side.
class MapScreen extends ConsumerStatefulWidget {
  const new({this.placeId, super.key});

  /// A place to open on arrival, from a link.
  final String? placeId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _listOpen = false;

  @override
  void initState() {
    super.initState();
    // The first sync, or a refresh of an old one, starts with the map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(syncControllerProvider.notifier).syncIfStale());
      unawaited(_openLinkedPlace());
    });
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    // After the build: a provider cannot change while widgets are updated.
    if (widget.placeId != old.placeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openLinkedPlace());
      });
    }
  }

  /// Selects the place a link names and, once the map is ready, shows it.
  Future<void> _openLinkedPlace() async {
    final id = widget.placeId;
    if (id == null) return;
    ref.read(selectionProvider.notifier).select(PlaceSelection(id));
    final place = await ref.read(placesRepositoryProvider).watchPlace(id).first;
    if (!mounted || place == null) return;
    // The map is ready once it reports its first camera: its style is loaded
    // and its size settled. A move sent before (the web map exists before it
    // is laid out) can land off centre.
    bool ready() => ref.read(mapControllerProvider) != null && ref.read(viewportProvider) != null;
    for (var i = 0; !ready() && i < 50 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    await ref.read(mapControllerProvider)?.moveTo(place.position, zoom: 13);
  }

  void _clearSelection() => ref.read(selectionProvider.notifier).select(null);

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final unavailable = context.t.map.locationUnavailable;
    final controller = ref.read(mapControllerProvider);
    final position = await controller?.locateUser();
    if (!mounted) return;
    if (position == null) {
      messenger?.showSnackBar(SnackBar(content: Text(unavailable)));
      return;
    }
    ref.read(userLocationProvider.notifier).update(position);
    await controller?.moveTo(position, zoom: 12);
  }

  @override
  Widget build(BuildContext context) {
    final size = WindowSize.of(context);
    final selection = ref.watch(selectionProvider);
    final body = switch (size) {
      .compact => _CompactLayout(
        selection: selection,
        onLocate: _locate,
        onCloseSelection: _clearSelection,
      ),
      .medium => _MediumLayout(
        selection: selection,
        listOpen: _listOpen,
        onToggleList: () => setState(() => _listOpen = !_listOpen),
        onLocate: _locate,
        onCloseSelection: _clearSelection,
      ),
      .expanded => _ExpandedLayout(
        selection: selection,
        onLocate: _locate,
        onCloseSelection: _clearSelection,
      ),
    };
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clearSelection},
      child: Focus(autofocus: true, child: Scaffold(body: body)),
    );
  }
}

/// The map itself, fed from the providers.
class _Map extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final viewport = ref.read(viewportProvider);
    final places = ref.watch(mapPlacesProvider).value ?? const [];
    final selection = ref.watch(selectionProvider);
    final select = ref.read(selectionProvider.notifier);
    return ref.watch(lunaMapBuilderProvider)(
      context,
      LunaMapProps(
        styleUrl: dark ? config.basemapDark : config.basemapLight,
        initialCenter: viewport?.center ?? initialMapCenter,
        initialZoom: viewport?.zoom ?? initialMapZoom,
        places: places,
        selectedId: selection is PlaceSelection ? selection.id : null,
        markedPoint: selection is PointSelection ? selection.position : null,
        onPlaceTap: (id) => select.select(PlaceSelection(id)),
        onLongPress: (p) {
          select.select(PointSelection(p));
          // The sheet or panel that opens may cover the point: bring it into
          // the part of the map left free, at the same zoom.
          unawaited(ref.read(mapControllerProvider)?.moveTo(p));
        },
        onViewportChanged: (v) => ref.read(viewportProvider.notifier).update(v),
        onMapReady: (c) => ref.read(mapControllerProvider.notifier).attach(c),
        padding: padding,
      ),
    );
  }
}

/// The details of what is selected, for a sheet or a panel.
class _SelectionDetails extends StatelessWidget {
  const new({required this.selection, required this.onClose, this.scrollController, super.key});

  final MapSelection selection;
  final VoidCallback onClose;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => switch (selection) {
    PlaceSelection(:final id) => PlaceDetails(
      placeId: id,
      scrollController: scrollController,
      onClose: onClose,
    ),
    PointSelection(:final position) => PointDetails(
      position: position,
      scrollController: scrollController,
      onClose: onClose,
    ),
  };
}

class _LocateButton extends StatelessWidget {
  const new({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OverMap(
    child: FloatingActionButton(
      heroTag: 'locate',
      tooltip: context.t.map.locateMe,
      onPressed: onPressed,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      foregroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(AppIcons.locate),
    ),
  );
}

/// Phone: the map fills the screen; the list rests in a sheet at the bottom,
/// and a selection replaces it with its details.
class _CompactLayout extends ConsumerStatefulWidget {
  const new({required this.selection, required this.onLocate, required this.onCloseSelection});

  final MapSelection? selection;
  final VoidCallback onLocate;
  final VoidCallback onCloseSelection;

  @override
  ConsumerState<_CompactLayout> createState() => _CompactLayoutState();
}

class _CompactLayoutState extends ConsumerState<_CompactLayout> {
  static const _listPeek = 0.16;
  static const _detailsInitial = 0.46;
  // The height of the search field and the filter chips over the map.
  static const _overlayHeight = 140.0;
  double _sheet = _listPeek;

  @override
  void didUpdateWidget(_CompactLayout old) {
    super.didUpdateWidget(old);
    // Every selection opens a new sheet at its initial size (the sheet is
    // keyed by the selection), which reports no extent until it is dragged.
    if (old.selection != widget.selection) {
      _sheet = widget.selection == null ? _listPeek : _detailsInitial;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height;
    final selection = widget.selection;
    final sheetTop = height * _sheet;
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    // The search results must cover the sheet and the locate button, so the
    // search sits on top; it fades away when the sheet is dragged over it.
    final sheetCoversSearch = height - sheetTop < media.padding.top + _overlayHeight;
    return Stack(
      children: [
        Positioned.fill(
          child: _Map(
            padding: EdgeInsets.only(bottom: sheetTop, top: _overlayHeight),
          ),
        ),
        const Positioned(
          left: 12,
          right: 12,
          top: 0,
          bottom: 0,
          child: Center(child: SyncBanner()),
        ),
        if (!searching)
          AnimatedPositioned(
            duration: Motion.short,
            right: 16,
            bottom: sheetTop + 16,
            child: _LocateButton(onPressed: widget.onLocate),
          ),
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            if ((n.extent - _sheet).abs() > 0.005) setState(() => _sheet = n.extent);
            return false;
          },
          child: AnimatedSwitcher(
            duration: Motion.emphasized,
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: selection == null
                ? _Sheet(
                    key: const ValueKey('list'),
                    initial: _listPeek,
                    min: _listPeek,
                    snaps: const [0.5],
                    builder: (controller) => NearbyList(
                      scrollController: controller,
                      header: const Padding(
                        padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
                        child: NearbyCount(),
                      ),
                    ),
                  )
                : _Sheet(
                    key: ValueKey(selection),
                    initial: _detailsInitial,
                    min: 0.2,
                    snaps: const [_detailsInitial],
                    builder: (controller) => _SelectionDetails(
                      selection: selection,
                      scrollController: controller,
                      onClose: widget.onCloseSelection,
                    ),
                  ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            ignoring: sheetCoversSearch,
            child: AnimatedOpacity(
              duration: Motion.short,
              opacity: sheetCoversSearch ? 0 : 1,
              child: const SafeArea(
                bottom: false,
                child: OverMap(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
                        child: MapSearch(),
                      ),
                      QuickFilters(
                        padding: EdgeInsets.fromLTRB(Space.m, Space.sm, Space.xxs, Space.xxs),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A bottom sheet resting over the map, dragged by its handle or its content.
class _Sheet extends StatelessWidget {
  const new({
    required this.initial,
    required this.min,
    required this.builder,
    this.snaps = const [],
    super.key,
  });

  final double initial;
  final double min;
  final List<double> snaps;
  final Widget Function(ScrollController controller) builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: initial,
      minChildSize: min,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: snaps,
      builder: (context, controller) => OverMap(
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          elevation: LunaTokens.of(context).sheetElevation,
          shadowColor: LunaTokens.of(context).shadowStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(LunaTokens.of(context).radiusSheet),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // The handle drags the sheet even where the content does not
              // scroll.
              SingleChildScrollView(
                controller: controller,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  height: 28,
                  width: double.infinity,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusXs),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: builder(controller)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tablet: the map with the rail; the list and the details open in a panel
/// on the right.
class _MediumLayout extends ConsumerWidget {
  const new({
    required this.selection,
    required this.listOpen,
    required this.onToggleList,
    required this.onLocate,
    required this.onCloseSelection,
  });

  final MapSelection? selection;
  final bool listOpen;
  final VoidCallback onToggleList;
  final VoidCallback onLocate;
  final VoidCallback onCloseSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final panelOpen = selection != null || listOpen;
    const panelWidth = 380.0;
    return Stack(
      children: [
        Positioned.fill(
          child: _Map(
            padding: EdgeInsets.only(right: panelOpen ? panelWidth + Space.xxl : 0, top: 140),
          ),
        ),
        const Positioned(
          left: 16,
          right: 16,
          top: 0,
          bottom: 0,
          child: Center(child: SyncBanner()),
        ),
        Positioned(
          right: panelOpen ? panelWidth + 32 : 16,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _LocateButton(onPressed: onLocate),
              const SizedBox(height: Space.m),
              OverMap(
                child: FloatingActionButton.extended(
                  heroTag: 'list',
                  onPressed: onToggleList,
                  icon: Icon(listOpen ? AppIcons.map : AppIcons.list),
                  label: Text(listOpen ? t.map.showMap : t.map.showList),
                ),
              ),
            ],
          ),
        ),
        // Above the buttons: the search results cover them.
        Positioned(
          left: 16,
          top: 0,
          right: panelOpen ? panelWidth + 32 : 16,
          child: SafeArea(
            bottom: false,
            child: OverMap(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Space.m),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: const MapSearch(),
                  ),
                  const QuickFilters(
                    padding: EdgeInsets.only(top: Space.sm, bottom: Space.xxs),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: Motion.emphasized,
          curve: Motion.enter,
          top: 0,
          bottom: 0,
          right: panelOpen ? 0 : -panelWidth - 24,
          width: panelWidth + 16,
          child: SafeArea(
            left: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, Space.m, Space.m, Space.m),
              child: OverMap(
                child: _Panel(
                  child: selection != null
                      ? _SelectionDetails(
                          key: ValueKey(selection),
                          selection: selection!,
                          onClose: onCloseSelection,
                        )
                      : NearbyList(
                          header: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.xl,
                              Space.xl,
                              Space.xl,
                              Space.s,
                            ),
                            child: Row(
                              children: [
                                const Expanded(child: NearbyCount()),
                                IconButton(
                                  tooltip: t.common.close,
                                  icon: const Icon(AppIcons.close),
                                  onPressed: onToggleList,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A floating rounded surface beside the map.
class _Panel extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    elevation: LunaTokens.of(context).floatingElevation,
    shadowColor: LunaTokens.of(context).shadowStrong,
    borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusSheet),
    clipBehavior: Clip.antiAlias,
    child: AnimatedSwitcher(duration: Motion.medium, child: child),
  );
}

/// Desktop: the list pane, the map, and the details pane side by side.
class _ExpandedLayout extends ConsumerWidget {
  const new({required this.selection, required this.onLocate, required this.onCloseSelection});

  final MapSelection? selection;
  final VoidCallback onLocate;
  final VoidCallback onCloseSelection;

  /// From this width the list stays beside the details; narrower, the
  /// details take the list's place so the map keeps room.
  static const threePanesFrom = 1500.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final paneWidth = width >= 1280 ? 420.0 : 380.0;
    final threePanes = width >= threePanesFrom;
    final selection = this.selection;
    final details = selection == null
        ? null
        : _SelectionDetails(
            key: ValueKey(selection),
            selection: selection,
            onClose: onCloseSelection,
          );
    const list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
          child: MapSearch(elevated: false),
        ),
        QuickFilters(
          padding: EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.s),
          floating: false,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.xxs),
          child: NearbyCount(),
        ),
        Divider(),
        Expanded(child: NearbyList()),
      ],
    );
    Widget pane(Widget child) => SizedBox(
      width: paneWidth,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: SafeArea(child: child),
      ),
    );
    return Row(
      children: [
        pane(
          AnimatedSwitcher(
            duration: Motion.medium,
            child: details != null && !threePanes
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.m),
                    child: details,
                  )
                : list,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: _Map()),
              const Positioned(
                left: Space.l,
                right: Space.l,
                top: 0,
                bottom: 0,
                child: Center(child: SyncBanner()),
              ),
              Positioned(
                right: Space.l,
                bottom: Space.l,
                child: _LocateButton(onPressed: onLocate),
              ),
            ],
          ),
        ),
        if (threePanes)
          AnimatedSize(
            duration: Motion.emphasized,
            curve: Motion.enter,
            alignment: Alignment.centerLeft,
            child: details == null
                ? const SizedBox(height: double.infinity)
                : Row(
                    children: [
                      const VerticalDivider(width: 1),
                      pane(
                        Padding(
                          padding: const EdgeInsets.only(top: Space.m),
                          child: AnimatedSwitcher(duration: Motion.medium, child: details),
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
